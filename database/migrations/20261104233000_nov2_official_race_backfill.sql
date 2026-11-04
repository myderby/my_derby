-- Narrow backfill path for the official races missed on 2026-11-02.
-- The date is fixed in the claim routine; finished and cancelled races are excluded.

UPDATE my_derby.races
SET weather_code=NULL,track_condition=NULL
WHERE status='OPEN'
  AND prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  AND prize_policy->>'kst_date'='2026-11-02'
  AND (weather_code IS NULL OR track_condition IS NULL);

CREATE OR REPLACE FUNCTION my_derby.secure_backfill_claim_nov2(p_secret text,p_slot integer)
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

 -- Resume a previously claimed Nov 2 race if the request was interrupted before finalizing it.
 SELECT r.* INTO v_race
 FROM my_derby.races r
 JOIN my_derby.race_runs rr ON rr.race_id=r.id AND rr.status='RUNNING'
 WHERE r.world_id=v_world.id AND r.status='RUNNING'
   AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND r.prize_policy->>'kst_date'='2026-11-02'
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
   AND r.prize_policy->>'kst_date'='2026-11-02'
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
 VALUES(v_race.id,v_race.start_time,'BACKFILL_CLAIM',jsonb_build_object('runId',v_run.id,'date','2026-11-02'));
 RETURN jsonb_build_object('status','CLAIMED','raceId',v_race.id,'runId',v_run.id,
   'rank',v_race.class_name,'startTime',v_race.start_time,'input',v_input);
END;
$function$;

REVOKE ALL ON FUNCTION my_derby.secure_backfill_claim_nov2(text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.secure_backfill_claim_nov2(text,integer) TO anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.send_nov2_race_backfill()
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_secret text;v_request bigint;
BEGIN
 SELECT secret INTO v_secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner';
 IF v_secret IS NULL THEN RAISE EXCEPTION 'DISPATCH_SECRET_MISSING'; END IF;
 SELECT net.http_get(
   url:='https://my-derby.vercel.app/api/cron/race/backfill-nov2',
   headers:=jsonb_build_object('Authorization','Bearer '||v_secret),
   timeout_milliseconds:=45000
 ) INTO v_request;
 RETURN v_request;
END;
$function$;

REVOKE ALL ON FUNCTION my_derby_private.send_nov2_race_backfill() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby.secure_backfill_finalize_pending_nov2(p_secret text,p_slot integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_row record;
 v_result jsonb;
 v_n integer:=0;
 v_ids jsonb:='[]'::jsonb;
BEGIN
 IF p_secret IS NULL OR p_secret IS DISTINCT FROM
   (SELECT secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner')
   THEN RAISE EXCEPTION 'OFFICIAL_AUTH_REQUIRED' USING errcode='42501'; END IF;
 IF p_slot NOT BETWEEN 0 AND 2 THEN RAISE EXCEPTION 'INVALID_SLOT'; END IF;
 FOR v_row IN
   SELECT p.race_id,p.run_id,p.result
   FROM my_derby_private.race_pending_results p
   JOIN my_derby.races r ON r.id=p.race_id
   WHERE p.due_at<=now() AND r.status='RUNNING'
     AND r.prize_policy->>'kst_date'='2026-11-02'
     AND (r.prize_policy->>'slot_index')::integer=p_slot
   ORDER BY p.due_at LIMIT 4 FOR UPDATE OF p SKIP LOCKED
 LOOP
   v_result:=my_derby.secure_official_race_finalize(p_secret,v_row.run_id,v_row.result);
   DELETE FROM my_derby_private.race_pending_results WHERE race_id=v_row.race_id;
   v_ids:=v_ids||jsonb_build_array(jsonb_build_object('raceId',v_row.race_id,'result',v_result));
   v_n:=v_n+1;
 END LOOP;
 RETURN jsonb_build_object('status',CASE WHEN v_n>0 THEN 'PUBLISHED' ELSE 'WAITING' END,
   'count',v_n,'results',v_ids);
END;
$function$;

REVOKE ALL ON FUNCTION my_derby.secure_backfill_finalize_pending_nov2(text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.secure_backfill_finalize_pending_nov2(text,integer) TO anon,authenticated;

ALTER FUNCTION my_derby.secure_backfill_claim_nov2(text,integer)
  SET statement_timeout TO '30s';
ALTER FUNCTION my_derby.secure_backfill_finalize_pending_nov2(text,integer)
  SET statement_timeout TO '30s';

CREATE OR REPLACE FUNCTION my_derby.secure_backfill_finalize_race_nov2(
  p_secret text,p_run_id uuid,p_result jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
SET statement_timeout TO '30s'
AS $function$
DECLARE v_race_date text;
BEGIN
 IF p_secret IS NULL OR p_secret IS DISTINCT FROM
   (SELECT secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner')
   THEN RAISE EXCEPTION 'OFFICIAL_AUTH_REQUIRED' USING errcode='42501'; END IF;
 SELECT r.prize_policy->>'kst_date' INTO v_race_date
 FROM my_derby.race_runs rr JOIN my_derby.races r ON r.id=rr.race_id
 WHERE rr.id=p_run_id AND rr.status='RUNNING' AND r.status='RUNNING';
 IF v_race_date IS DISTINCT FROM '2026-11-02'
   THEN RAISE EXCEPTION 'BACKFILL_DATE_NOT_ALLOWED' USING errcode='42501'; END IF;
 RETURN my_derby.secure_official_race_finalize(p_secret,p_run_id,p_result);
END;
$function$;

REVOKE ALL ON FUNCTION my_derby.secure_backfill_finalize_race_nov2(text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.secure_backfill_finalize_race_nov2(text,uuid,jsonb) TO anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby.secure_log_race_processing_error(
  p_secret text,p_race_id uuid,p_slot integer,p_phase text,p_message text,
  p_error_code text,p_details text,p_hint text,p_context jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
SET statement_timeout TO '3s'
AS $function$
DECLARE
 v_date text;
 v_slot_time time;
 v_id bigint;
BEGIN
 IF p_secret IS NULL OR p_secret IS DISTINCT FROM
   (SELECT secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner')
   THEN RAISE EXCEPTION 'OFFICIAL_AUTH_REQUIRED' USING errcode='42501'; END IF;
 IF p_slot IS NOT NULL AND p_slot NOT BETWEEN 0 AND 2 THEN RAISE EXCEPTION 'INVALID_SLOT'; END IF;
 IF p_race_id IS NOT NULL THEN
   SELECT r.prize_policy->>'kst_date',r.start_time INTO v_date,v_slot_time
   FROM my_derby.races r WHERE r.id=p_race_id;
 END IF;
 v_date:=coalesce(v_date,p_context->>'kstDate',(now() at time zone 'Asia/Seoul')::date::text);
 INSERT INTO my_derby.official_race_process_audit(race_id,slot_time,action,event_detail)
 VALUES(p_race_id,v_slot_time,'PROCESS_ERROR',jsonb_build_object(
   'date',v_date,'slot',p_slot,'phase',left(coalesce(p_phase,'unknown'),80),
   'message',left(regexp_replace(coalesce(p_message,'Unknown error'),'Bearer [^[:space:]]+','Bearer [REDACTED]','gi'),1200),
   'code',left(coalesce(p_error_code,''),100),
   'details',left(regexp_replace(coalesce(p_details,''),'Bearer [^[:space:]]+','Bearer [REDACTED]','gi'),800),
   'hint',left(regexp_replace(coalesce(p_hint,''),'Bearer [^[:space:]]+','Bearer [REDACTED]','gi'),800),
   'context',coalesce(p_context,'{}'::jsonb),'loggedAt',now()
 )) RETURNING id INTO v_id;
 RETURN jsonb_build_object('status','LOGGED','auditId',v_id,'raceId',p_race_id,'phase',p_phase);
END;
$function$;

REVOKE ALL ON FUNCTION my_derby.secure_log_race_processing_error(text,uuid,integer,text,text,text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.secure_log_race_processing_error(text,uuid,integer,text,text,text,text,text,jsonb) TO anon,authenticated;
NOTIFY pgrst,'reload schema';
