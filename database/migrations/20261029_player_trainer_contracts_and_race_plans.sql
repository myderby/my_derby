
-- NPC trainer offers and player 1/2/3 strategy config, live official race engine input.
CREATE OR REPLACE FUNCTION my_derby.player_stable_board()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid(); w uuid; v_h jsonb;v_t jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',h.id,'name',h.name,'age',h.age_years,'sourceMeet',h.source_meet,
  'health',h.health_state,'stage',h.life_stage,'fatigue',h.fatigue,
  'trainerId',tr.trainer_id,'trainerName',nt.name,'familiarity',tr.familiarity)
  ORDER BY h.name),'[]'::jsonb) INTO v_h
 FROM my_derby.horses h
 LEFT JOIN my_derby.trainer_contracts tr ON tr.horse_id=h.id AND tr.status='ACTIVE'
 LEFT JOIN my_derby.npc_trainers nt ON nt.id=tr.trainer_id
 WHERE h.owner_user_id=u AND h.world_id=w;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',n.id,'name',n.name,'track',s.track,
  'capacity',n.capacity,'occupied',(SELECT count(*) FROM my_derby.trainer_contracts t
    WHERE t.trainer_id=n.id AND t.status='ACTIVE'),
  'skills',n.skill_stats,'specialties',n.specialties)
 ORDER BY s.track,n.name),'[]'::jsonb) INTO v_t
 FROM my_derby.npc_trainers n JOIN my_derby.npc_stables s ON s.id=n.stable_id
 WHERE s.world_id=w AND n.is_active;
 RETURN jsonb_build_object('horses',v_h,'trainers',v_t);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_apply_trainer(p_horse_id uuid,p_trainer_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;h my_derby.horses%rowtype;n my_derby.npc_trainers%rowtype;
 s my_derby.npc_stables%rowtype; v_track text; v_busy int;v_chance numeric;
 v_roll numeric; v_day int; v_reason text; v_app uuid;v_prev uuid;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id AND world_id=w FOR UPDATE;
 IF NOT FOUND OR h.owner_user_id IS DISTINCT FROM u THEN
  RAISE EXCEPTION 'NOT_YOUR_HORSE' USING ERRCODE='42501';END IF;
 IF h.life_stage<>'RACING' OR h.racing_retired_permanently OR h.health_state='INJURED'
  THEN RAISE EXCEPTION 'HORSE_NOT_TRAINABLE';END IF;
 SELECT * INTO n FROM my_derby.npc_trainers WHERE id=p_trainer_id FOR UPDATE;
 IF NOT FOUND OR NOT n.is_active THEN RAISE EXCEPTION 'TRAINER_UNAVAILABLE';END IF;
 SELECT * INTO s FROM my_derby.npc_stables WHERE id=n.stable_id;
 v_track:=CASE h.source_meet WHEN '부산경남' THEN '부산'
  WHEN '제주' THEN '영천' ELSE h.source_meet END;
 IF s.world_id IS DISTINCT FROM w OR s.track IS DISTINCT FROM v_track
  THEN RAISE EXCEPTION 'TRAINER_TRACK_MISMATCH';END IF;
 SELECT trainer_id INTO v_prev FROM my_derby.trainer_contracts
  WHERE horse_id=h.id AND status='ACTIVE' LIMIT 1;
 IF v_prev=n.id THEN RETURN jsonb_build_object('status','ALREADY_CONTRACTED','trainerName',n.name);END IF;
 v_day:=(my_derby.world_clock(w)->>'gameDayStart')::int;
 IF EXISTS (SELECT 1 FROM my_derby.trainer_applications a WHERE
  a.horse_id=h.id AND a.trainer_id=n.id AND a.status='REJECTED'
  AND a.created_at::date=(now() AT TIME ZONE 'Asia/Seoul')::date)
 THEN RETURN jsonb_build_object('status','ALREADY_REJECTED_TODAY','trainerName',n.name);END IF;
 SELECT count(*) INTO v_busy FROM my_derby.trainer_contracts
  WHERE trainer_id=n.id AND status='ACTIVE';
 IF v_busy>=n.capacity THEN RAISE EXCEPTION 'TRAINER_AT_CAPACITY';END IF;
 v_chance:=least(99,greatest(60,86+(n.capacity-v_busy)*0.6-
   greatest(0,v_busy-30)*0.6));
 v_roll:=(('x'||substr(md5(h.id::text||n.id::text||v_day::text),1,8))::bit(32)::bigint % 10000)::numeric/100;
 IF v_roll>v_chance THEN
  INSERT INTO my_derby.trainer_applications(horse_id,owner_user_id,trainer_id,preference_rank,status,response_reason)
  VALUES(h.id,u,n.id,1,'REJECTED','NPC_TRAINER_DECLINED') RETURNING id INTO v_app;
  RETURN jsonb_build_object('status','REJECTED','trainerName',n.name);
 END IF;
 UPDATE my_derby.trainer_contracts SET status='ENDED',end_game_day=v_day
  WHERE horse_id=h.id AND status='ACTIVE';
 INSERT INTO my_derby.trainer_contracts(horse_id,trainer_id,start_game_day,familiarity,status)
 VALUES(h.id,n.id,v_day,0,'ACTIVE');
 INSERT INTO my_derby.trainer_applications(horse_id,owner_user_id,trainer_id,preference_rank,status,response_reason)
 VALUES(h.id,u,n.id,1,'ACCEPTED','NPC_TRAINER_ACCEPTED') RETURNING id INTO v_app;
 RETURN jsonb_build_object('status','ACCEPTED','trainerName',n.name,'horseId',h.id,
 'capacity',n.capacity,'occupiedAfter',v_busy+1,'applicationId',v_app);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_save_race_strategies(
 p_race_id uuid,p_horse_id uuid,p_codes text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();v_world uuid;r my_derby.races%rowtype;
 e my_derby.race_entries%rowtype; v_time timestamp:=now() at time zone 'Asia/Seoul';
 v_date date; idx int;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO v_world FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF v_world IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 IF array_length(p_codes,1)<>3 OR EXISTS(SELECT 1 FROM unnest(p_codes) c
    WHERE c NOT IN ('FRONT','PRESS','SAVE','MOVE','CLOSER','FREE'))
 THEN RAISE EXCEPTION 'STRATEGY_INVALID';END IF;
 SELECT * INTO r FROM my_derby.races WHERE id=p_race_id AND world_id=v_world FOR UPDATE;
 IF NOT FOUND OR r.status<>'OPEN' THEN RAISE EXCEPTION 'RACE_NOT_OPEN';END IF;
 v_date:=(r.prize_policy->>'kst_date')::date;
 IF v_date IS NULL OR v_date<v_time::date OR
  (v_date=v_time::date AND v_time::time>=coalesce(r.entry_deadline,r.start_time-interval '10 minutes'))
 THEN RAISE EXCEPTION 'ENTRY_DEADLINE_PASSED';END IF;
 SELECT * INTO e FROM my_derby.race_entries
  WHERE race_id=r.id AND horse_id=p_horse_id AND owner_user_id=u
   AND status='CONFIRMED' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'OWN_CONFIRMED_ENTRY_REQUIRED';END IF;
 FOR idx IN 1..3 LOOP
  INSERT INTO my_derby.race_strategies(race_entry_id,owner_user_id,plan_no,strategy_code)
  VALUES(e.id,u,idx,p_codes[idx])
  ON CONFLICT(race_entry_id,plan_no) DO UPDATE SET
   strategy_code=excluded.strategy_code,owner_user_id=excluded.owner_user_id,updated_at=now();
 END LOOP;
 UPDATE my_derby.race_entries SET snapshot=snapshot||
   jsonb_build_object('strategies',to_jsonb(p_codes),'strategy_source','PLAYER_PLAN_1_2_3')
 WHERE id=e.id;
 RETURN jsonb_build_object('status','SAVED','raceId',p_race_id,'horseId',p_horse_id,
   'strategies',to_jsonb(p_codes),'officialEngineSnapshotUpdated',true);
END $fn$;
REVOKE ALL ON FUNCTION my_derby.player_stable_board() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_apply_trainer(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_save_race_strategies(uuid,uuid,text[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_stable_board() TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_apply_trainer(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_save_race_strategies(uuid,uuid,text[]) TO authenticated;
