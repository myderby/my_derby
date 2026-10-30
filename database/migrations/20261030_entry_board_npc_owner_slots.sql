CREATE OR REPLACE FUNCTION my_derby.player_race_board(p_week integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_user uuid := auth.uid();
 v_world uuid;
 v_clock jsonb;
 v_current integer;
 v_week integer;
 v_races jsonb;
 v_horses jsonb;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT world_id INTO v_world FROM my_derby.profiles
 WHERE user_id=v_user AND initial_setup_complete;
 IF v_world IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501'; END IF;
 v_clock:=my_derby.world_clock(v_world);
 v_current:=(v_clock->>'week')::integer;
 v_week:=coalesce(p_week,v_current);
 IF v_week < v_current OR v_week>52 THEN RAISE EXCEPTION 'WEEK_OUT_OF_RANGE'; END IF;

 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',r.id,'track',r.track,'grade',r.class_name,'gradeNo',r.prize_policy->>'grade_no',
  'sourceMeet',r.prize_policy->>'source_meet',
  'distance',r.distance_m,'raceDay',r.race_day,'status',r.status,
  'startTime',to_char(r.start_time,'HH24:MI'),
  'entryDeadline',to_char(r.entry_deadline,'HH24:MI'),
  'kstDate',r.prize_policy->>'kst_date',
  'raceNo',r.prize_policy->>'source_rc_no','capacity',r.target_runner_count,
  'confirmedCount',(select count(*) from my_derby.race_entries e where e.race_id=r.id and e.status='CONFIRMED'),
  'npcReplaceableCount',(select count(*) from my_derby.race_entries e where e.race_id=r.id
   and e.status='CONFIRMED' and e.owner_user_id is null and e.snapshot->>'entry_source' IN ('NPC_AUTOFILL_DUSU_V1','NPC_OWNER_APPLICATION_V1')),
  'myEntries',coalesce((select jsonb_agg(jsonb_build_object(
   'horseId',e.horse_id,'status',e.status,'gateNo',e.gate_no,
   'jockeyId',e.jockey_id,'jockeyName',j.name))
   from my_derby.race_entries e left join my_derby.npc_jockeys j on j.id=e.jockey_id
   where e.race_id=r.id and e.owner_user_id=v_user and e.status in ('APPLIED','CONFIRMED','COMPLETED')),'[]'::jsonb)
 ) ORDER BY r.start_time,r.track,r.race_no),'[]'::jsonb) INTO v_races
 FROM my_derby.races r
 WHERE r.world_id=v_world AND r.race_day=(v_week-1)*7+1
  AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2';

 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'id',h.id,'name',h.name,'sex',h.sex,'age',h.age_years,
 'sourceMeet',h.source_meet,'gradeNo',h.source_grade_no,
 'lifeStage',h.life_stage,'health',h.health_state,'fatigue',h.fatigue,
 'condition',h.condition_score,'retired',h.racing_retired_permanently,
 'breedingRetired',h.breeding_retired_at IS NOT NULL,
 'saleState',h.sale_state) ORDER BY h.name),'[]'::jsonb) INTO v_horses
 FROM my_derby.horses h WHERE h.world_id=v_world AND h.owner_user_id=v_user;

 RETURN jsonb_build_object('currentWeek',v_current,'week',v_week,
  'worldStatus',v_clock->>'status','races',v_races,'horses',v_horses);
END $function$;