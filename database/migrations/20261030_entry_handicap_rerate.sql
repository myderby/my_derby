CREATE OR REPLACE FUNCTION my_derby.apply_player_race_entry(p_race_id uuid, p_horse_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_user uuid := auth.uid();
 v_world uuid;
 v_r my_derby.races%rowtype;
 v_h my_derby.horses%rowtype;
 v_entry my_derby.race_entries%rowtype;
 v_stat jsonb;
 v_now timestamp := now() AT TIME ZONE 'Asia/Seoul';
 v_date date;
 v_count integer;
 v_gate smallint;
 v_jockey uuid;
 v_strategies jsonb;
 v_replaced boolean := false;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT world_id INTO v_world FROM my_derby.profiles
  WHERE user_id=v_user AND initial_setup_complete;
 IF v_world IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_r FROM my_derby.races WHERE id=p_race_id AND world_id=v_world FOR UPDATE;
 IF NOT FOUND OR v_r.status<>'OPEN' OR v_r.prize_policy->>'schedule_version'<>'csv2025_rank_sttime_v2' THEN
  RAISE EXCEPTION 'RACE_NOT_OPEN';
 END IF;
 v_date:=(v_r.prize_policy->>'kst_date')::date;
 IF v_date IS NULL OR v_date < v_now::date OR
  (v_date=v_now::date AND v_now::time>=coalesce(v_r.entry_deadline,v_r.start_time - interval '10 minutes')) THEN
  RAISE EXCEPTION 'ENTRY_DEADLINE_PASSED';
 END IF;
 IF v_r.target_runner_count NOT BETWEEN 2 AND 16 THEN RAISE EXCEPTION 'INVALID_RACE_CAPACITY'; END IF;

 SELECT * INTO v_h FROM my_derby.horses WHERE id=p_horse_id AND world_id=v_world FOR UPDATE;
 IF NOT FOUND OR v_h.owner_user_id IS DISTINCT FROM v_user THEN RAISE EXCEPTION 'NOT_YOUR_HORSE' USING ERRCODE='42501'; END IF;
 IF v_h.life_stage<>'RACING' OR v_h.racing_retired_permanently OR v_h.breeding_retired_at IS NOT NULL
  OR v_h.health_state<>'HEALTHY' OR v_h.age_years NOT BETWEEN 2 AND 10
  OR v_h.sale_state<>'NOT_LISTED'
  OR v_h.condition_score<50 OR v_h.fatigue>=80 THEN
  RAISE EXCEPTION 'HORSE_NOT_RACE_ELIGIBLE';
 END IF;
 IF v_h.source_meet IS DISTINCT FROM v_r.prize_policy->>'source_meet'
  OR v_h.source_grade_no::text IS DISTINCT FROM v_r.prize_policy->>'grade_no' THEN
  RAISE EXCEPTION 'REGION_OR_GRADE_MISMATCH';
 END IF;
 SELECT current_stats INTO v_stat FROM my_derby.horse_abilities WHERE horse_id=p_horse_id;
 IF v_stat IS NULL OR v_stat='{}'::jsonb THEN RAISE EXCEPTION 'HORSE_ABILITY_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM my_derby.race_entries e
    JOIN my_derby.races rr ON rr.id=e.race_id
    WHERE e.horse_id=p_horse_id AND rr.world_id=v_world AND rr.race_day=v_r.race_day
    AND rr.status<>'CANCELLED' AND e.status IN ('APPLIED','CONFIRMED','COMPLETED')) THEN
   IF EXISTS(SELECT 1 FROM my_derby.race_entries e WHERE e.race_id=p_race_id AND e.horse_id=p_horse_id
     AND e.owner_user_id=v_user AND e.status='CONFIRMED') THEN
    RETURN jsonb_build_object('status','ALREADY_CONFIRMED','raceId',p_race_id,'horseId',p_horse_id);
   END IF;
   RAISE EXCEPTION 'HORSE_ALREADY_ENTERED_THIS_DAY';
 END IF;

 v_strategies:=CASE WHEN coalesce((v_stat->>'start')::numeric,0)>coalesce((v_stat->>'finishing')::numeric,0)
  THEN '["FRONT","PRESS","SAVE"]'::jsonb ELSE '["SAVE","MOVE","CLOSER"]'::jsonb END;
 SELECT count(*) INTO v_count FROM my_derby.race_entries
   WHERE race_id=p_race_id AND status IN ('APPLIED','CONFIRMED');
 IF v_count>=v_r.target_runner_count THEN
  -- Existing NPC-only slots were auto-filled to the requested starter count.
  -- Preserve the gate and existing safe jockey assignment; replace one NPC.
  SELECT * INTO v_entry FROM my_derby.race_entries e
   WHERE e.race_id=p_race_id AND e.status='CONFIRMED' AND e.owner_user_id IS NULL
    AND e.snapshot->>'entry_source' IN ('NPC_AUTOFILL_DUSU_V1','NPC_OWNER_APPLICATION_V1')
   ORDER BY e.gate_no DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RACE_FULL_NO_NPC_SLOT'; END IF;
  v_replaced:=true;
  UPDATE my_derby.race_entries SET
    horse_id=p_horse_id,owner_user_id=v_user,status='CONFIRMED',weight_kg=54,
    snapshot=jsonb_build_object(
      'entry_source','PLAYER_APPLICATION_V1','strategies',v_strategies,
      'trainerReadiness',75,'originalNpcHorseId',v_entry.horse_id,
      'autoAssignedJockey',true)
   WHERE id=v_entry.id;
  v_gate:=v_entry.gate_no;
  v_jockey:=v_entry.jockey_id;
 ELSE
  SELECT min(g)::smallint INTO v_gate FROM generate_series(1,v_r.target_runner_count) g
   WHERE NOT EXISTS(SELECT 1 FROM my_derby.race_entries e WHERE e.race_id=p_race_id AND e.gate_no=g);
  IF v_gate IS NULL THEN RAISE EXCEPTION 'NO_GATE_AVAILABLE'; END IF;
  SELECT j.id INTO v_jockey FROM my_derby.npc_jockeys j
   WHERE j.world_id=v_world AND j.home_track=v_r.track AND j.is_active
    AND NOT EXISTS(SELECT 1 FROM my_derby.race_entries e
      WHERE e.race_id=p_race_id AND e.jockey_id=j.id AND e.status IN ('APPLIED','CONFIRMED'))
    AND (SELECT count(*) FROM my_derby.race_entries e
     JOIN my_derby.races rr ON rr.id=e.race_id
     WHERE rr.race_day=v_r.race_day AND rr.world_id=v_world AND rr.status<>'CANCELLED'
      AND e.jockey_id=j.id AND e.status IN ('APPLIED','CONFIRMED','COMPLETED'))<j.max_daily_rides
   ORDER BY j.name LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF v_jockey IS NULL THEN RAISE EXCEPTION 'NO_JOCKEY_AVAILABLE'; END IF;
  INSERT INTO my_derby.race_entries
  (race_id,horse_id,owner_user_id,jockey_id,gate_no,weight_kg,status,snapshot)
  VALUES(p_race_id,p_horse_id,v_user,v_jockey,v_gate,54,'CONFIRMED',
   jsonb_build_object('entry_source','PLAYER_APPLICATION_V1',
    'strategies',v_strategies,'trainerReadiness',75,'autoAssignedJockey',true));
 END IF;
 -- Economy_v2 general race entry fee (2% of grade prize pool);
 -- per horse+racing event reference prevents duplicate or missing payments.
 PERFORM my_derby_private.wallet_mutate(
   v_user,v_world,v_r.race_day,
   -floor(my_derby_private.economy_grade_pool((v_r.prize_policy->>'grade_no')::int)
     * (SELECT amount FROM my_derby.economy_config
        WHERE key='ENTRY_FEE_BASIS_POINTS')/10000.0)::bigint,
   'RACE_ENTRY_FEE','RACE_ENTRY',md5(p_race_id::text||':'||p_horse_id::text)::uuid);
 UPDATE my_derby.races SET prize_policy=prize_policy||jsonb_build_object(
   'actual_starters',(SELECT count(*) FROM my_derby.race_entries e
      WHERE e.race_id=p_race_id AND e.status='CONFIRMED'),
   'player_entry_enabled',true) WHERE id=p_race_id;
 PERFORM my_derby_private.recalculate_official_handicap_race(p_race_id);
 RETURN jsonb_build_object('status','CONFIRMED','raceId',p_race_id,
   'horseId',p_horse_id,'gateNo',v_gate,'jockeyId',v_jockey,'replacedNpc',v_replaced);
END $function$;