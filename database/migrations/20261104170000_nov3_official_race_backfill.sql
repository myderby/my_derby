-- Narrow backfill path for the official races missed on 2026-11-03.
-- The date is fixed in the claim routine; finished and cancelled races are excluded.

UPDATE my_derby.races
SET weather_code=NULL,track_condition=NULL
WHERE status='OPEN'
  AND prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  AND prize_policy->>'kst_date'='2026-11-03'
  AND (weather_code IS NULL OR track_condition IS NULL);

CREATE OR REPLACE FUNCTION my_derby.secure_backfill_claim_nov3(p_secret text,p_slot integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_race my_derby.races%rowtype;
 v_run my_derby.race_runs%rowtype;
 v_world my_derby.worlds%rowtype;
 v_input jsonb;
 v_runners jsonb;
 v_count integer;
 v_seed integer;
BEGIN
 IF p_secret IS NULL OR p_secret IS DISTINCT FROM
   (SELECT secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner')
   THEN RAISE EXCEPTION 'OFFICIAL_AUTH_REQUIRED' USING errcode='42501'; END IF;
 IF p_slot NOT BETWEEN 0 AND 2 THEN RAISE EXCEPTION 'INVALID_SLOT'; END IF;
 SELECT * INTO v_world FROM my_derby.worlds WHERE world_key='kra_roster_v1';
 IF v_world.status<>'ACTIVE' OR NOT v_world.automatic_processing_enabled
   THEN RETURN jsonb_build_object('status','WORLD_NOT_PROCESSING'); END IF;

 -- Resume a previously claimed Nov 3 race if the request was interrupted before finalizing it.
 SELECT r.* INTO v_race
 FROM my_derby.races r
 JOIN my_derby.race_runs rr ON rr.race_id=r.id AND rr.status='RUNNING'
 WHERE r.world_id=v_world.id AND r.status='RUNNING'
   AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND r.prize_policy->>'kst_date'='2026-11-03'
   AND (r.prize_policy->>'slot_index')::integer=p_slot
   AND NOT EXISTS(SELECT 1 FROM my_derby_private.race_pending_results p WHERE p.race_id=r.id)
 ORDER BY r.start_time,r.track,r.race_no LIMIT 1 FOR UPDATE OF r SKIP LOCKED;
 IF FOUND THEN
   SELECT * INTO v_run FROM my_derby.race_runs WHERE race_id=v_race.id AND status='RUNNING';
   RETURN jsonb_build_object('status','CLAIMED','raceId',v_race.id,'runId',v_run.id,
     'rank',v_race.class_name,'startTime',v_race.start_time,'input',v_run.race_input);
 END IF;

 SELECT * INTO v_race FROM my_derby.races r
 WHERE r.world_id=v_world.id AND r.status='OPEN'
   AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND r.prize_policy->>'kst_date'='2026-11-03'
   AND (r.prize_policy->>'slot_index')::integer=p_slot
   AND r.target_runner_count BETWEEN 2 AND 16
   AND (SELECT count(*) FROM my_derby.race_entries e WHERE e.race_id=r.id AND e.status='CONFIRMED')=r.target_runner_count
 ORDER BY r.start_time,r.track,r.race_no LIMIT 1 FOR UPDATE OF r SKIP LOCKED;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','WAITING','slot',p_slot); END IF;

 IF v_race.weather_code IS NULL OR v_race.track_condition IS NULL
   THEN RAISE EXCEPTION 'BACKFILL_RACE_ENVIRONMENT_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM my_derby.race_entries e JOIN my_derby.horses h ON h.id=e.horse_id
   WHERE e.race_id=v_race.id AND e.status='CONFIRMED'
     AND (h.life_stage<>'RACING' OR h.racing_retired_permanently OR h.breeding_retired_at IS NOT NULL
       OR h.source_meet IS DISTINCT FROM (v_race.prize_policy->>'source_meet')
       OR h.source_grade_no IS DISTINCT FROM (v_race.prize_policy->>'grade_no')::smallint))
   THEN RAISE EXCEPTION 'ENTRY_INELIGIBLE_BY_REGION_GRADE_OR_RETIREMENT'; END IF;
 PERFORM my_derby_private.recalculate_official_handicap_race(v_race.id);
 SELECT count(*) INTO v_count FROM my_derby.race_entries e
   WHERE e.race_id=v_race.id AND e.status='CONFIRMED';
 SELECT jsonb_agg(jsonb_build_object(
   'id',h.id::text,'number',e.gate_no,'name',h.name,'gate',e.gate_no,
   'horse',a.current_stats,
   'trackAdaptation',my_derby_private.track_adaptation_from_hidden_traits(a.hidden_traits),
   'jockey',my_derby_private.apply_jockey_hidden_traits(j.id,j.skill_stats,v_race.distance_m,v_race.class_name,
     coalesce(e.snapshot->'strategies','["FREE"]'::jsonb)),
   'strategies',coalesce(e.snapshot->'strategies','["FREE"]'::jsonb),
   'condition',h.condition_score,'fatigue',h.fatigue,'weightKg',e.weight_kg,
   'distanceFit',coalesce(nullif(a.distance_affinity->>(v_race.distance_m::text),'')::numeric,75),
   'trainerReadiness',coalesce((e.snapshot->>'trainerReadiness')::numeric,75)
 ) ORDER BY e.gate_no) INTO v_runners
 FROM my_derby.race_entries e
 JOIN my_derby.horses h ON h.id=e.horse_id
 JOIN my_derby.horse_abilities a ON a.horse_id=h.id
 JOIN my_derby.npc_jockeys j ON j.id=e.jockey_id AND j.is_active
 WHERE e.race_id=v_race.id AND e.status='CONFIRMED' AND e.gate_no IS NOT NULL AND e.weight_kg IS NOT NULL;
 IF v_runners IS NULL OR jsonb_array_length(v_runners)<>v_count OR v_count<>v_race.target_runner_count
   THEN RAISE EXCEPTION 'ENTRY_ABILITY_JOCKEY_MISSING'; END IF;
 v_seed:=floor(random()*2147483646)::integer+1;
 v_input:=jsonb_build_object('raceId',v_race.id,'track',v_race.track,'distanceM',v_race.distance_m,
   'seed',v_seed,'weather',v_race.weather_code,'trackCondition',v_race.track_condition,'runners',v_runners);
 INSERT INTO my_derby.race_runs(race_id,race_input,random_seed,balance_version,tick_seconds,status,claimed_at,engine_version)
 VALUES(v_race.id,v_input,v_seed,v_world.balance_version,0.2,'RUNNING',now(),'0.2.0')
 ON CONFLICT(race_id) DO NOTHING RETURNING * INTO v_run;
 IF NOT FOUND THEN RAISE EXCEPTION 'BACKFILL_RUN_ALREADY_EXISTS'; END IF;
 UPDATE my_derby.races SET status='RUNNING' WHERE id=v_race.id;
 INSERT INTO my_derby.official_race_process_audit(race_id,slot_time,action,event_detail)
 VALUES(v_race.id,v_race.start_time,'BACKFILL_CLAIM',jsonb_build_object('runId',v_run.id,'date','2026-11-03'));
 RETURN jsonb_build_object('status','CLAIMED','raceId',v_race.id,'runId',v_run.id,
   'rank',v_race.class_name,'startTime',v_race.start_time,'input',v_input);
END;
$function$;

REVOKE ALL ON FUNCTION my_derby.secure_backfill_claim_nov3(text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.secure_backfill_claim_nov3(text,integer) TO anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.send_nov3_race_backfill()
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_secret text;v_request bigint;
BEGIN
 SELECT secret INTO v_secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner';
 IF v_secret IS NULL THEN RAISE EXCEPTION 'DISPATCH_SECRET_MISSING'; END IF;
 SELECT net.http_get(
   url:='https://my-derby.vercel.app/api/cron/race/backfill-nov3',
   headers:=jsonb_build_object('Authorization','Bearer '||v_secret),
   timeout_milliseconds:=45000
 ) INTO v_request;
 RETURN v_request;
END;
$function$;

REVOKE ALL ON FUNCTION my_derby_private.send_nov3_race_backfill() FROM PUBLIC,anon,authenticated;
