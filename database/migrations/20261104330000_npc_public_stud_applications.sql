-- NPC owners may apply their eligible broodmares to public player and
-- association stallions. Public listings are treated as consent to accept
-- NPC applications; pair outcomes, reviews and fees are processed by the
-- existing NPC breeding cron.
ALTER TABLE my_derby.npc_breeding_cycles
  ADD COLUMN IF NOT EXISTS application_source text NOT NULL DEFAULT 'NPC_INTERNAL',
  ADD COLUMN IF NOT EXISTS stud_fee_g bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS decision_detail jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE my_derby.npc_breeding_cycles
  DROP CONSTRAINT IF EXISTS npc_breeding_cycles_status_check;
ALTER TABLE my_derby.npc_breeding_cycles
  ADD CONSTRAINT npc_breeding_cycles_status_check
  CHECK(status IN ('PREGNANT','FAILED','BORN','DENIED'));
ALTER TABLE my_derby.npc_breeding_cycles
  DROP CONSTRAINT IF EXISTS npc_breeding_cycles_application_source_check;
ALTER TABLE my_derby.npc_breeding_cycles
  ADD CONSTRAINT npc_breeding_cycles_application_source_check
  CHECK(application_source IN ('NPC_INTERNAL','PLAYER_PUBLIC_STUD','ASSOCIATION_PUBLIC_STUD'));
ALTER TABLE my_derby.npc_breeding_cycles
  DROP CONSTRAINT IF EXISTS npc_breeding_cycles_stud_fee_g_check;
ALTER TABLE my_derby.npc_breeding_cycles
  ADD CONSTRAINT npc_breeding_cycles_stud_fee_g_check CHECK(stud_fee_g>=0);

CREATE INDEX IF NOT EXISTS ix_npc_breeding_cycles_sire_season
 ON my_derby.npc_breeding_cycles(sire_id,season_number)
 WHERE status<>'DENIED';

CREATE OR REPLACE FUNCTION my_derby_private.stud_booked_slots(p_sire_id uuid,p_season int)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 SELECT
  (SELECT count(*)::integer FROM my_derby.breeding_requests br
   WHERE br.sire_id=p_sire_id AND br.season_number=p_season
    AND coalesce(br.decision_detail->>'approvalState','APPROVED')<>'DENIED')
  +
  (SELECT count(*)::integer FROM my_derby.npc_breeding_cycles bc
   WHERE bc.sire_id=p_sire_id AND bc.season_number=p_season AND bc.status<>'DENIED');
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.stud_booked_slots(uuid,integer) FROM PUBLIC,anon,authenticated;

-- Make both NPC and player booking paths share the same seasonal 200-service cap.
DO $patch$
DECLARE v_definition text;v_original text;v_updated text;v_function regprocedure;
BEGIN
 v_function:='my_derby_private.review_breeding_pair(uuid,uuid,integer)'::regprocedure;
 v_definition:=pg_catalog.pg_get_functiondef(v_function);
 v_original:=$sql$SELECT count(*) INTO v_booked FROM my_derby.breeding_requests
  WHERE sire_id=sire.id AND season_number=p_season
    AND coalesce(decision_detail->>'approvalState','APPROVED')<>'DENIED';$sql$;
 v_updated:='v_booked:=my_derby_private.stud_booked_slots(sire.id,p_season);';
 IF position(v_original IN v_definition)>0 THEN
  EXECUTE replace(v_definition,v_original,v_updated);
 ELSIF position(v_updated IN v_definition)=0 THEN
  RAISE EXCEPTION 'Could not safely update breeding review capacity count';
 END IF;

 v_function:='my_derby.player_breeding_pair_preview(uuid,uuid)'::regprocedure;
 v_definition:=pg_catalog.pg_get_functiondef(v_function);
 v_original:=$sql$SELECT count(*) INTO v_booked FROM my_derby.breeding_requests br
 WHERE br.sire_id=sire.id AND br.season_number=(c->>'season')::int
  AND coalesce(br.decision_detail->>'approvalState','APPROVED')<>'DENIED';$sql$;
 v_updated:='v_booked:=my_derby_private.stud_booked_slots(sire.id,(c->>''season'')::int);';
 IF position(v_original IN v_definition)>0 THEN
  EXECUTE replace(v_definition,v_original,v_updated);
 ELSIF position(v_updated IN v_definition)=0 THEN
  RAISE EXCEPTION 'Could not safely update breeding preview capacity count';
 END IF;

 v_function:='my_derby.player_apply_breeding(uuid,uuid)'::regprocedure;
 v_definition:=pg_catalog.pg_get_functiondef(v_function);
 v_original:=$sql$SELECT count(*) INTO v_booked FROM my_derby.breeding_requests br
 WHERE br.sire_id=sire.id AND br.season_number=v_season
  AND coalesce(br.decision_detail->>'approvalState','APPROVED')<>'DENIED';$sql$;
 v_updated:='v_booked:=my_derby_private.stud_booked_slots(sire.id,v_season);';
 IF position(v_original IN v_definition)>0 THEN
  EXECUTE replace(v_definition,v_original,v_updated);
 ELSIF position(v_updated IN v_definition)=0 THEN
  RAISE EXCEPTION 'Could not safely update player breeding capacity count';
 END IF;
END;
$patch$;

CREATE OR REPLACE FUNCTION my_derby_private.process_npc_breeding_pairs()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 mare record;
 sire my_derby.horses%rowtype;
 v_season int;
 v_day int;
 v_assessment jsonb;
 v_review jsonb;
 v_review_denied boolean;
 v_roll numeric;
 v_chance numeric;
 v_conceived boolean;
 v_source text;
 v_fee bigint;
 v_cycle uuid;
 v_wallet_update int;
 v_count int:=0;
 v_applied int:=0;
 v_denied int:=0;
 v_pregnant int:=0;
 v_failed int:=0;
BEGIN
 FOR mare IN
  SELECT h.id,h.world_id,h.npc_owner_id,
    (my_derby.world_clock(h.world_id)->>'season')::int AS season,
    (my_derby.world_clock(h.world_id)->>'gameDayStart')::int AS game_day
  FROM my_derby.horses h
  JOIN my_derby.npc_owners o ON o.id=h.npc_owner_id
  JOIN my_derby.worlds w ON w.id=h.world_id
  WHERE w.status='ACTIVE' AND w.automatic_processing_enabled
   AND o.policy->>'active'='true'
   AND h.sex='FEMALE' AND h.age_years BETWEEN 4 AND 18
   AND h.life_stage='BROODMARE' AND h.breeding_retired_at IS NOT NULL
   AND h.health_state='HEALTHY' AND h.sale_state='NOT_LISTED'
   AND h.breeding_state IN ('AVAILABLE','COOLDOWN')
   AND NOT EXISTS(
    SELECT 1 FROM my_derby.npc_breeding_cycles bc
    WHERE bc.mare_id=h.id
      AND bc.season_number=(my_derby.world_clock(h.world_id)->>'season')::int
   )
  ORDER BY h.id FOR UPDATE OF h SKIP LOCKED
 LOOP
  v_season:=mare.season;
  v_day:=mare.game_day;
  v_review:=NULL;
  v_review_denied:=false;
  v_fee:=0;
  v_cycle:=gen_random_uuid();

  SELECT h.* INTO sire
  FROM my_derby.horses h
  WHERE h.world_id=mare.world_id
   AND h.sex='MALE' AND h.age_years BETWEEN 4 AND 25
   AND h.life_stage='STALLION' AND h.breeding_retired_at IS NOT NULL
   AND h.racing_retired_permanently AND h.health_state='HEALTHY'
   AND h.sale_state='NOT_LISTED'
   AND (
    (h.owner_user_id IS NOT NULL AND EXISTS(
      SELECT 1 FROM my_derby_private.breeding_stud_offerings o
      WHERE o.horse_id=h.id AND o.owner_user_id=h.owner_user_id
    ))
    OR h.source_model_version='MY_DERBY_ASSOCIATION_STUD_V1'
    OR (h.npc_owner_id IS NOT NULL AND EXISTS(
      SELECT 1 FROM my_derby.npc_retirement_decisions dec
      WHERE dec.horse_id=h.id AND dec.converted_to='STALLION'
    ))
    OR (h.npc_owner_id IS NOT NULL AND h.source_model_version='MY_DERBY_SYSTEM_STUD_V1')
   )
   AND my_derby_private.stud_booked_slots(h.id,v_season)<200
   AND (
    (h.owner_user_id IS NULL AND h.source_model_version<>'MY_DERBY_ASSOCIATION_STUD_V1')
    OR coalesce((SELECT nw.balance FROM my_derby.npc_owner_wallets nw
      WHERE nw.npc_owner_id=mare.npc_owner_id),0)
      >=(my_derby_private.stud_fee_quote(h.id)->>'feeG')::bigint
   )
  ORDER BY CASE
    WHEN h.owner_user_id IS NOT NULL OR h.source_model_version='MY_DERBY_ASSOCIATION_STUD_V1' THEN 0
    ELSE 1 END,
    md5(mare.id::text||h.id::text||v_season::text)
  LIMIT 1 FOR UPDATE OF h SKIP LOCKED;
  IF sire.id IS NULL THEN CONTINUE; END IF;

  v_source:=CASE
    WHEN sire.owner_user_id IS NOT NULL THEN 'PLAYER_PUBLIC_STUD'
    WHEN sire.source_model_version='MY_DERBY_ASSOCIATION_STUD_V1' THEN 'ASSOCIATION_PUBLIC_STUD'
    ELSE 'NPC_INTERNAL'
  END;
  v_assessment:=my_derby.breeding_pair_assessment(mare.id,sire.id);
  v_chance:=(v_assessment->>'chance')::numeric;
  v_count:=my_derby_private.stud_booked_slots(sire.id,v_season);
  IF v_count>=150 THEN
   v_review:=my_derby_private.review_breeding_pair(mare.id,sire.id,v_season);
   v_review_denied:=v_review->>'decision'='DENIED';
  END IF;
  IF v_source<>'NPC_INTERNAL' AND NOT v_review_denied THEN
   v_fee:=(my_derby_private.stud_fee_quote(sire.id)->>'feeG')::bigint;
  END IF;

  v_roll:=((('x'||substr(md5(mare.id::text||sire.id::text||v_season::text),1,8))
     ::bit(32)::bigint % 10000)::numeric)/100;
  v_conceived:=NOT v_review_denied AND v_roll<v_chance;
  INSERT INTO my_derby.npc_breeding_cycles
   (id,world_id,npc_owner_id,mare_id,sire_id,season_number,conceived_game_day,
    due_game_day,conception_chance,status,application_source,stud_fee_g,decision_detail)
  VALUES(v_cycle,mare.world_id,mare.npc_owner_id,mare.id,sire.id,v_season,v_day,
    CASE WHEN v_conceived THEN v_day+330 ELSE NULL END,
    v_chance,CASE WHEN v_review_denied THEN 'DENIED'
      WHEN v_conceived THEN 'PREGNANT' ELSE 'FAILED' END,
    v_source,v_fee,jsonb_build_object(
      'pregnant',v_conceived,
      'approvalState',CASE WHEN v_review_denied THEN 'DENIED' ELSE 'APPROVED' END,
      'review',v_review,
      'studFeeG',v_fee,
      'applicationSource',v_source,
      'pedigreeIncomplete',v_assessment->'pedigreeIncomplete'
    ))
  ON CONFLICT(mare_id,season_number) DO NOTHING;
  IF NOT FOUND THEN CONTINUE; END IF;

  IF v_fee>0 THEN
   UPDATE my_derby.npc_owner_wallets
    SET balance=balance-v_fee,updated_at=now()
    WHERE npc_owner_id=mare.npc_owner_id AND balance>=v_fee;
   GET DIAGNOSTICS v_wallet_update=ROW_COUNT;
   IF v_wallet_update=0 THEN
    RAISE EXCEPTION 'NPC_STUD_FEE_FUNDS_CHANGED';
   END IF;
   IF sire.owner_user_id IS NOT NULL THEN
    PERFORM my_derby_private.wallet_mutate(sire.owner_user_id,mare.world_id,v_day,
      v_fee,'STUD_FEE_INCOME','NPC_BREEDING_CYCLE',v_cycle);
    INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
    VALUES(sire.owner_user_id,'BREEDING',
      CASE WHEN v_review_denied THEN 'NPC 마주 교배 신청 심사 불허'
       WHEN v_conceived THEN 'NPC 마주 교배 신청 · 임신 성공'
       ELSE 'NPC 마주 교배 신청 · 임신 실패' END,
      (SELECT owner.name||' 마주의 암말 '||mare_horse.name||'이(가) '||
        sire_horse.name||' 씨수말과 교배했습니다. '||
        CASE WHEN v_review_denied THEN '심사 불허되어 교배료가 청구되지 않았습니다.'
         WHEN v_conceived THEN '임신에 성공했고 교배료 '||v_fee||'G가 정산되었습니다.'
         ELSE '임신은 실패했지만 교배료 '||v_fee||'G가 정산되었습니다.' END
       FROM my_derby.npc_owners owner
       JOIN my_derby.horses mare_horse ON mare_horse.id=mare.id
       JOIN my_derby.horses sire_horse ON sire_horse.id=sire.id
       WHERE owner.id=mare.npc_owner_id),
      jsonb_build_object('source','NPC_PUBLIC_STUD_APPLICATION','cycleId',v_cycle,
       'mareId',mare.id,'sireId',sire.id,'status',CASE WHEN v_review_denied THEN 'DENIED'
        WHEN v_conceived THEN 'PREGNANT' ELSE 'FAILED' END,
       'studFeeG',v_fee,'review',v_review));
   ELSE
    INSERT INTO my_derby.npc_owner_wallets(npc_owner_id)
    VALUES(sire.npc_owner_id) ON CONFLICT(npc_owner_id) DO NOTHING;
    UPDATE my_derby.npc_owner_wallets SET balance=balance+v_fee,updated_at=now()
    WHERE npc_owner_id=sire.npc_owner_id;
   END IF;
  ELSIF v_source='PLAYER_PUBLIC_STUD' THEN
   INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
   VALUES(sire.owner_user_id,'BREEDING','NPC 마주 교배 신청 심사 불허',
     '공개 씨수말 교배 신청이 혼잡 심사에서 불허되었습니다. 교배료는 정산되지 않았습니다.',
     jsonb_build_object('source','NPC_PUBLIC_STUD_APPLICATION','cycleId',v_cycle,
       'mareId',mare.id,'sireId',sire.id,'status','DENIED','studFeeG',0,'review',v_review));
  END IF;

  UPDATE my_derby.horses
   SET breeding_state=CASE WHEN v_conceived THEN 'PREGNANT' ELSE 'COOLDOWN' END
   WHERE id=mare.id;
  v_applied:=v_applied+1;
  IF v_review_denied THEN v_denied:=v_denied+1;
  ELSIF v_conceived THEN v_pregnant:=v_pregnant+1;
  ELSE v_failed:=v_failed+1; END IF;
 END LOOP;
 RETURN jsonb_build_object('status','OK','paired',v_applied,'applications',v_applied,
   'reviewDenied',v_denied,'pregnancies',v_pregnant,'failed',v_failed);
END
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.process_npc_breeding_pairs() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_npc_breeding_applications()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;result jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'id',bc.id,'mareId',mare.id,'mareName',mare.name,
   'npcOwnerName',owner.name,'sireId',sire.id,'sireName',sire.name,
   'season',bc.season_number,'status',bc.status,'createdAt',bc.created_at,
   'conceptionChance',bc.conception_chance,'studFeeG',bc.stud_fee_g,
   'decisionDetail',bc.decision_detail,'dueGameDay',bc.due_game_day,
   'foalId',bc.foal_id,'applicationSource',bc.application_source
  ) ORDER BY bc.created_at DESC),'[]'::jsonb)
 INTO result
 FROM my_derby.npc_breeding_cycles bc
 JOIN my_derby.horses sire ON sire.id=bc.sire_id
 JOIN my_derby.horses mare ON mare.id=bc.mare_id
 JOIN my_derby.npc_owners owner ON owner.id=bc.npc_owner_id
 WHERE sire.world_id=w AND sire.owner_user_id=u
   AND bc.application_source='PLAYER_PUBLIC_STUD';
 RETURN result;
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_npc_breeding_applications() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_npc_breeding_applications() TO authenticated;
NOTIFY pgrst,'reload schema';
