-- Mailbox staff notes, operator gifts, and player inventory.
CREATE TABLE IF NOT EXISTS my_derby.operator_gifts(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 sent_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 item_code text NOT NULL CHECK(item_code ~ '^[A-Z0-9_]{2,40}$'),
 item_name text NOT NULL CHECK(char_length(btrim(item_name)) BETWEEN 1 AND 60),
 item_description text NOT NULL DEFAULT '' CHECK(char_length(item_description)<=160),
 quantity integer NOT NULL CHECK(quantity BETWEEN 1 AND 99),
 operator_message text NOT NULL DEFAULT '' CHECK(char_length(operator_message)<=300),
 created_at timestamptz NOT NULL DEFAULT now(),
 claimed_at timestamptz
);
CREATE INDEX IF NOT EXISTS operator_gifts_owner_unclaimed_idx
 ON my_derby.operator_gifts(owner_user_id,created_at DESC) WHERE claimed_at IS NULL;
ALTER TABLE my_derby.operator_gifts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.operator_gifts FROM PUBLIC,anon,authenticated;

CREATE TABLE IF NOT EXISTS my_derby.player_inventory(
 owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 item_code text NOT NULL CHECK(item_code ~ '^[A-Z0-9_]{2,40}$'),
 item_name text NOT NULL CHECK(char_length(btrim(item_name)) BETWEEN 1 AND 60),
 item_description text NOT NULL DEFAULT '' CHECK(char_length(item_description)<=160),
 quantity integer NOT NULL CHECK(quantity>0),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(owner_user_id,item_code)
);
ALTER TABLE my_derby.player_inventory ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.player_inventory FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby.operator_mail_recipients(p_search text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE q text:=btrim(coalesce(p_search,''));
BEGIN
 IF coalesce(auth.jwt()->'app_metadata'->>'role','') NOT IN ('operator','admin')
 THEN RAISE EXCEPTION 'OPERATOR_REQUIRED' USING ERRCODE='42501';END IF;
 IF char_length(q)>40 THEN RAISE EXCEPTION 'SEARCH_TOO_LONG';END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object(
   'userId',p.user_id,'nickname',p.nickname) ORDER BY p.nickname,p.user_id)
  FROM (SELECT user_id,nickname FROM my_derby.profiles
   WHERE initial_setup_complete AND (q='' OR nickname ILIKE '%'||q||'%')
   ORDER BY nickname,user_id LIMIT 40) p),'[]'::jsonb);
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.operator_mail_recipients(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.operator_mail_recipients(text) TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.operator_send_gift(
 p_user_id uuid,p_item_code text,p_item_name text,p_item_description text,
 p_quantity integer,p_message text DEFAULT ''
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();v_gift bigint;v_nickname text;
BEGIN
 IF u IS NULL OR coalesce(auth.jwt()->'app_metadata'->>'role','') NOT IN ('operator','admin')
 THEN RAISE EXCEPTION 'OPERATOR_REQUIRED' USING ERRCODE='42501';END IF;
 IF p_item_code IS NULL OR p_item_code !~ '^[A-Z0-9_]{2,40}$'
  OR p_item_name IS NULL OR char_length(btrim(p_item_name)) NOT BETWEEN 1 AND 60
  OR char_length(coalesce(p_item_description,''))>160
  OR p_quantity NOT BETWEEN 1 AND 99 OR char_length(coalesce(p_message,''))>300
 THEN RAISE EXCEPTION 'GIFT_FIELDS_INVALID';END IF;
 SELECT nickname INTO v_nickname FROM my_derby.profiles
 WHERE user_id=p_user_id AND initial_setup_complete;
 IF NOT FOUND THEN RAISE EXCEPTION 'RECIPIENT_NOT_FOUND';END IF;
 INSERT INTO my_derby.operator_gifts(owner_user_id,sent_by,item_code,item_name,
  item_description,quantity,operator_message)
 VALUES(p_user_id,u,p_item_code,btrim(p_item_name),coalesce(p_item_description,''),
  p_quantity,btrim(coalesce(p_message,''))) RETURNING id INTO v_gift;
 INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
 VALUES(p_user_id,'OPERATOR_GIFT','운영자 선물이 도착했습니다',
  CASE WHEN btrim(coalesce(p_message,''))<>'' THEN btrim(p_message)
   ELSE '운영자가 '||btrim(p_item_name)||' '||p_quantity||'개를 보냈습니다. 우편함에서 수령해주세요.' END,
  jsonb_build_object('senderType','OPERATOR','senderName','MY DERBY 운영팀',
   'giftId',v_gift,'itemCode',p_item_code,'itemName',btrim(p_item_name),
   'quantity',p_quantity));
 RETURN jsonb_build_object('status','SENT','giftId',v_gift,'recipientNickname',v_nickname);
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.operator_send_gift(uuid,text,text,text,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.operator_send_gift(uuid,text,text,text,integer,text) TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_claim_gift(p_gift_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();g my_derby.operator_gifts%rowtype;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT * INTO g FROM my_derby.operator_gifts WHERE id=p_gift_id AND owner_user_id=u FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'GIFT_NOT_FOUND' USING ERRCODE='42501';END IF;
 IF g.claimed_at IS NOT NULL THEN RAISE EXCEPTION 'GIFT_ALREADY_CLAIMED';END IF;
 INSERT INTO my_derby.player_inventory(owner_user_id,item_code,item_name,item_description,quantity,updated_at)
 VALUES(u,g.item_code,g.item_name,g.item_description,g.quantity,now())
 ON CONFLICT(owner_user_id,item_code) DO UPDATE SET
  item_name=excluded.item_name,item_description=excluded.item_description,
  quantity=my_derby.player_inventory.quantity+excluded.quantity,updated_at=now();
 UPDATE my_derby.operator_gifts SET claimed_at=now() WHERE id=g.id;
 UPDATE my_derby.notifications SET read_at=coalesce(read_at,now())
 WHERE owner_user_id=u AND category='OPERATOR_GIFT' AND payload->>'giftId'=g.id::text;
 RETURN jsonb_build_object('status','CLAIMED','giftId',g.id,'itemCode',g.item_code,
  'itemName',g.item_name,'quantity',g.quantity);
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_claim_gift(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_claim_gift(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_inventory()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('items',coalesce((SELECT jsonb_agg(jsonb_build_object(
  'code',item_code,'name',item_name,'description',item_description,'quantity',quantity,
  'updatedAt',updated_at) ORDER BY item_name,item_code)
  FROM my_derby.player_inventory WHERE owner_user_id=u),'[]'::jsonb));
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_inventory() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_inventory() TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_inbox()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object(
  'unread',(SELECT count(*) FROM my_derby.notifications n
    WHERE n.owner_user_id=u AND n.read_at IS NULL),
  'items',coalesce((SELECT jsonb_agg(x.item ORDER BY x.id DESC) FROM (
    SELECT n.id,jsonb_build_object('id',n.id,'category',n.category,
     'title',n.title,'body',n.body,'createdAt',n.created_at,
     'readAt',n.read_at,'payload',n.payload,
     'senderName',n.payload->>'senderName','senderType',n.payload->>'senderType',
     'gift',CASE WHEN g.id IS NULL THEN NULL ELSE jsonb_build_object(
       'id',g.id,'itemCode',g.item_code,'itemName',g.item_name,
       'description',g.item_description,'quantity',g.quantity,
       'claimedAt',g.claimed_at) END) item
    FROM my_derby.notifications n
    LEFT JOIN my_derby.operator_gifts g
      ON n.category='OPERATOR_GIFT' AND n.payload->>'giftId'=g.id::text
     AND g.owner_user_id=n.owner_user_id
    WHERE n.owner_user_id=u ORDER BY n.id DESC LIMIT 100) x),'[]'::jsonb),
  'inventory',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'code',i.item_code,'name',i.item_name,'description',i.item_description,
    'quantity',i.quantity,'updatedAt',i.updated_at) ORDER BY i.item_name,i.item_code)
   FROM my_derby.player_inventory i WHERE i.owner_user_id=u),'[]'::jsonb));
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_inbox() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_inbox() TO authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.send_training_weekly_mail(p_horse_id uuid,p_week_start integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE h my_derby.horses%rowtype;v_manager text;v_staff text;v_staff_type text;
 v_reports integer;v_latest text;v_fatigue numeric;v_condition numeric;v_key text;v_game_week integer;
BEGIN
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id;
 IF h.id IS NULL OR h.owner_user_id IS NULL THEN RETURN;END IF;
 SELECT count(*), (array_agg(tr.report_text ORDER BY tr.game_day DESC,tr.id DESC))[1]
 INTO v_reports,v_latest FROM my_derby.training_reports tr
 WHERE tr.horse_id=h.id AND tr.game_day BETWEEN p_week_start AND p_week_start+6;
 IF v_reports=0 THEN RETURN;END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('training-mail:'||h.id::text||':'||p_week_start::text,0));
 v_game_week:=((p_week_start-1)/7)+1;
 SELECT rw.name INTO v_manager FROM my_derby.ranches r
 JOIN my_derby.ranch_workers rw ON rw.ranch_id=r.id AND rw.is_active AND rw.role='CARETAKER'
 WHERE r.owner_user_id=h.owner_user_id
 ORDER BY CASE rw.grade WHEN 'S' THEN 0 WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END,rw.name LIMIT 1;
 IF v_manager IS NOT NULL THEN
  v_key:='RANCH_WEEK:'||h.id::text||':'||p_week_start::text;
  IF NOT EXISTS(SELECT 1 FROM my_derby.notifications n
    WHERE n.owner_user_id=h.owner_user_id AND n.payload->>'mailEventKey'=v_key) THEN
   INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
   VALUES(h.owner_user_id,'RANCH_MESSAGE','목장 관리사의 주간 소식',
    v_manager||' 관리사입니다. 이번 주 '||h.name||'의 훈련 기록 '||v_reports||
    '건을 확인했습니다. 현재 피로도 '||round(h.fatigue,1)||'점, 컨디션 '||
    round(h.condition_score,1)||'점입니다. 목장에서 계속 살펴보겠습니다.',
    jsonb_build_object('senderType','RANCH_MANAGER','senderName',v_manager||' 관리사',
     'horseId',h.id,'horseName',h.name,'gameWeek',v_game_week,'mailEventKey',v_key));
  END IF;
 END IF;
 v_staff:=NULL;v_staff_type:=NULL;
 SELECT t.name INTO v_staff FROM my_derby.training_reports tr
 JOIN my_derby.npc_trainers t ON t.id=tr.trainer_id
 WHERE tr.horse_id=h.id AND tr.game_day BETWEEN p_week_start AND p_week_start+6
  AND tr.trainer_id IS NOT NULL ORDER BY tr.game_day DESC,tr.id DESC LIMIT 1;
 IF v_staff IS NOT NULL THEN v_staff_type:='TRAINER';
 ELSE
  SELECT coalesce(j.display_name,j.name) INTO v_staff FROM my_derby.race_entries e
  JOIN my_derby.races r ON r.id=e.race_id
  JOIN my_derby.npc_jockeys j ON j.id=e.jockey_id
  WHERE e.horse_id=h.id AND e.jockey_id IS NOT NULL
  ORDER BY r.race_day DESC,r.race_no DESC,e.id DESC LIMIT 1;
  IF v_staff IS NOT NULL THEN v_staff_type:='JOCKEY';END IF;
 END IF;
 IF v_staff IS NOT NULL THEN
  v_key:='STAFF_TRAINING:'||h.id::text||':'||p_week_start::text;
  IF NOT EXISTS(SELECT 1 FROM my_derby.notifications n
    WHERE n.owner_user_id=h.owner_user_id AND n.payload->>'mailEventKey'=v_key) THEN
   INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
   VALUES(h.owner_user_id,'TRAINING_MESSAGE',h.name||' 훈련 보고',
    v_staff||CASE WHEN v_staff_type='TRAINER' THEN ' 조교사' ELSE ' 기수' END||
    '입니다. 이번 주 훈련을 확인했습니다. '||coalesce(v_latest,'훈련 기록을 정리했습니다.')||
    ' 말의 상태를 살피며 다음 훈련도 준비하겠습니다.',
    jsonb_build_object('senderType',v_staff_type,'senderName',v_staff||
     CASE WHEN v_staff_type='TRAINER' THEN ' 조교사' ELSE ' 기수' END,
     'horseId',h.id,'horseName',h.name,'gameWeek',v_game_week,
     'trainingReportCount',v_reports,'mailEventKey',v_key));
  END IF;
 END IF;
END
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.send_training_weekly_mail(uuid,integer) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.process_training_for_horse_week(p_horse_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_day int;v_first int;v_item jsonb;v_done int:=0;v_items jsonb:='[]'::jsonb;
BEGIN
 SELECT (my_derby.world_clock(h.world_id)->>'gameDayStart')::int INTO v_first
 FROM my_derby.horses h WHERE h.id=p_horse_id;
 IF v_first IS NULL THEN RAISE EXCEPTION 'HORSE_NOT_FOUND';END IF;
 FOR v_day IN v_first..v_first+6 LOOP
  v_item:=my_derby_private.process_training_for_horse_day(p_horse_id,v_day);
  v_items:=v_items||jsonb_build_array(v_item);
  IF v_item->>'status' IN('TRAINED','RECOVERY','INELIGIBLE_REST','RACE_DAY_REST','RANCH_STAY_REST')
  THEN v_done:=v_done+1;END IF;
 END LOOP;
 IF v_done>0 THEN PERFORM my_derby_private.send_training_weekly_mail(p_horse_id,v_first);END IF;
 RETURN jsonb_build_object('horseId',p_horse_id,'processedDays',v_done,
  'weekStart',v_first,'items',v_items);
END
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.process_training_for_horse_week(uuid) FROM PUBLIC,anon,authenticated;
NOTIFY pgrst,'reload schema';
