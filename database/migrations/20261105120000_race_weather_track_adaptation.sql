-- Persist randomly generated race-day weather and track conditions, and apply
-- hidden track aptitude in the official race simulation.
ALTER TABLE my_derby.races
  ADD COLUMN IF NOT EXISTS weather_code text,
  ADD COLUMN IF NOT EXISTS track_condition text;

DO $constraints$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='races_weather_code_check') THEN
    ALTER TABLE my_derby.races ADD CONSTRAINT races_weather_code_check
      CHECK (weather_code IS NULL OR weather_code IN ('CLEAR','CLOUDY','RAIN','SNOW'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='races_track_condition_check') THEN
    ALTER TABLE my_derby.races ADD CONSTRAINT races_track_condition_check
      CHECK (track_condition IS NULL OR track_condition IN ('FIRM','GOOD','YIELDING','SOFT','HEAVY'));
  END IF;
END
$constraints$;

CREATE OR REPLACE FUNCTION my_derby_private.race_environment_roll(p_key text, p_salt text)
RETURNS numeric
LANGUAGE sql IMMUTABLE STRICT
SET search_path TO ''
AS $function$
  SELECT mod(('x'||substr(md5(p_key||':'||p_salt),1,7))::bit(28)::int,10000)::numeric/10000;
$function$;

CREATE OR REPLACE FUNCTION my_derby_private.generate_race_environment(p_key text, p_month integer)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE STRICT
SET search_path TO ''
AS $function$
DECLARE
  v_weather_roll numeric := my_derby_private.race_environment_roll(p_key,'weather');
  v_track_roll numeric := my_derby_private.race_environment_roll(p_key,'track');
  v_snow numeric := CASE WHEN p_month IN (12,1,2) THEN 0.28 ELSE 0 END;
  v_rain numeric := CASE WHEN p_month IN (6,7,8,9) THEN 0.30 ELSE 0.16 END;
  v_weather text;
  v_condition text;
BEGIN
  v_weather := CASE
    WHEN v_weather_roll < v_snow THEN 'SNOW'
    WHEN v_weather_roll < v_snow+v_rain THEN 'RAIN'
    WHEN v_weather_roll < v_snow+v_rain+0.24 THEN 'CLOUDY'
    ELSE 'CLEAR' END;
  v_condition := CASE v_weather
    WHEN 'SNOW' THEN CASE WHEN v_track_roll<0.10 THEN 'FIRM' WHEN v_track_roll<0.24 THEN 'GOOD'
      WHEN v_track_roll<0.45 THEN 'YIELDING' WHEN v_track_roll<0.76 THEN 'SOFT' ELSE 'HEAVY' END
    WHEN 'RAIN' THEN CASE WHEN v_track_roll<0.04 THEN 'FIRM' WHEN v_track_roll<0.25 THEN 'GOOD'
      WHEN v_track_roll<0.56 THEN 'YIELDING' WHEN v_track_roll<0.86 THEN 'SOFT' ELSE 'HEAVY' END
    ELSE CASE WHEN v_track_roll<0.37 THEN 'FIRM' WHEN v_track_roll<0.86 THEN 'GOOD'
      WHEN v_track_roll<0.96 THEN 'YIELDING' WHEN v_track_roll<0.99 THEN 'SOFT' ELSE 'HEAVY' END
  END;
  RETURN jsonb_build_object('weather',v_weather,'trackCondition',v_condition);
END;
$function$;

CREATE OR REPLACE FUNCTION my_derby_private.assign_race_environment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_slot integer;
  v_date date;
  v_environment jsonb;
  v_key text;
BEGIN
  IF NEW.weather_code IS NOT NULL AND NEW.track_condition IS NOT NULL THEN RETURN NEW; END IF;
  v_slot := coalesce(nullif(NEW.prize_policy->>'slot_index','')::integer,
    CASE WHEN NEW.slot_hour BETWEEN 19 AND 21 THEN NEW.slot_hour-19
      WHEN extract(hour from NEW.start_time)::integer BETWEEN 19 AND 21 THEN extract(hour from NEW.start_time)::integer-19
      ELSE 0 END);
  v_date := coalesce(nullif(NEW.prize_policy->>'kst_date','')::date,(now() at time zone 'Asia/Seoul')::date);
  v_key := concat_ws(':',NEW.world_id::text,NEW.race_day::text,NEW.track,v_slot::text);
  v_environment := my_derby_private.generate_race_environment(v_key,extract(month from v_date)::integer);
  NEW.weather_code := coalesce(NEW.weather_code,v_environment->>'weather');
  NEW.track_condition := coalesce(NEW.track_condition,v_environment->>'trackCondition');
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS races_assign_environment ON my_derby.races;
CREATE TRIGGER races_assign_environment
BEFORE INSERT OR UPDATE OF weather_code,track_condition ON my_derby.races
FOR EACH ROW EXECUTE FUNCTION my_derby_private.assign_race_environment();

CREATE OR REPLACE FUNCTION my_derby_private.ensure_track_affinity(p_horse_id uuid,p_traits jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SET search_path TO ''
AS $function$
DECLARE
  v_traits jsonb := CASE WHEN jsonb_typeof(p_traits)='object' THEN p_traits ELSE '{}'::jsonb END;
  v_tags jsonb := CASE WHEN jsonb_typeof(p_traits->'tags')='array' THEN p_traits->'tags' ELSE '[]'::jsonb END;
  v_states text[] := ARRAY['FIRM','GOOD','YIELDING','SOFT','HEAVY'];
  v_state text;
BEGIN
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_tags) tag WHERE tag->>'code' LIKE 'TRACK_AFFINITY_%') THEN
    RETURN v_traits;
  END IF;
  v_state := v_states[1+floor(random()*array_length(v_states,1))::integer];
  RETURN jsonb_set(v_traits,'{tags}',v_tags||jsonb_build_array(jsonb_build_object(
    'code','TRACK_AFFINITY_'||v_state,
    'score',50+floor(random()*51)::integer,
    'evidence','무작위 주로 적응 특성'
  )),true);
END;
$function$;

CREATE OR REPLACE FUNCTION my_derby_private.track_adaptation_from_hidden_traits(p_traits jsonb)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT substring(tag->>'code' from '^TRACK_AFFINITY_(FIRM|GOOD|YIELDING|SOFT|HEAVY)$')
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_traits->'tags')='array' THEN p_traits->'tags' ELSE '[]'::jsonb END) tag
  WHERE tag->>'code' LIKE 'TRACK_AFFINITY_%'
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION my_derby_private.ensure_horse_track_affinity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  NEW.hidden_traits := my_derby_private.ensure_track_affinity(NEW.horse_id,NEW.hidden_traits);
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS horse_abilities_track_affinity ON my_derby.horse_abilities;
CREATE TRIGGER horse_abilities_track_affinity
BEFORE INSERT OR UPDATE OF hidden_traits ON my_derby.horse_abilities
FOR EACH ROW EXECUTE FUNCTION my_derby_private.ensure_horse_track_affinity();

UPDATE my_derby.horse_abilities
SET hidden_traits=my_derby_private.ensure_track_affinity(horse_id,hidden_traits)
WHERE my_derby_private.track_adaptation_from_hidden_traits(hidden_traits) IS NULL;

UPDATE my_derby.races
SET weather_code=NULL,track_condition=NULL
WHERE status IN ('OPEN','CLOSED')
  AND prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  AND nullif(prize_policy->>'kst_date','')::date >= (now() at time zone 'Asia/Seoul')::date
  AND (weather_code IS NULL OR track_condition IS NULL);

CREATE OR REPLACE FUNCTION my_derby.secure_program_preview_race(p_secret text, p_race_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  r my_derby.races%rowtype;
  input_runners jsonb;
  n integer;
  seed integer;
BEGIN
  IF p_secret IS NULL OR p_secret IS DISTINCT FROM
    (SELECT secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner')
    THEN RAISE EXCEPTION 'OFFICIAL_AUTH_REQUIRED' USING errcode='42501'; END IF;
  SELECT * INTO r FROM my_derby.races WHERE id=p_race_id;
  IF NOT FOUND OR r.status='CANCELLED' OR r.prize_policy->>'schedule_version'<>'csv2025_rank_sttime_v2'
    THEN RAISE EXCEPTION 'NEW_PROGRAM_RACE_NOT_FOUND'; END IF;
  IF (r.prize_policy->>'kst_date')::date<>((now() at time zone 'Asia/Seoul')::date)
    THEN RAISE EXCEPTION 'NOT_TODAY_PROGRAM'; END IF;
  SELECT count(*) INTO n FROM my_derby.race_entries e WHERE e.race_id=p_race_id AND e.status IN ('CONFIRMED','COMPLETED');
  IF r.target_runner_count IS NULL OR n<>r.target_runner_count OR n<2 OR n>16
    THEN RAISE EXCEPTION 'DUSU_STARTERS_MISMATCH: required %, actual %',r.target_runner_count,n USING errcode='23514'; END IF;
  IF EXISTS(SELECT 1 FROM my_derby.race_entries e JOIN my_derby.horses h ON h.id=e.horse_id
    WHERE e.race_id=p_race_id AND e.status IN ('CONFIRMED','COMPLETED')
      AND (h.life_stage<>'RACING' OR h.racing_retired_permanently OR h.breeding_retired_at IS NOT NULL
        OR h.source_meet IS DISTINCT FROM (r.prize_policy->>'source_meet')
        OR h.source_grade_no IS DISTINCT FROM (r.prize_policy->>'grade_no')::smallint))
    THEN RAISE EXCEPTION 'ENTRY_INELIGIBLE_BY_REGION_GRADE_OR_RETIREMENT'; END IF;
  SELECT jsonb_agg(jsonb_build_object(
    'id',h.id::text,'number',e.gate_no,'name',h.name,'gate',e.gate_no,
    'horse',a.current_stats,
    'trackAdaptation',my_derby_private.track_adaptation_from_hidden_traits(a.hidden_traits),
    'jockey',my_derby_private.apply_jockey_hidden_traits(j.id,j.skill_stats,r.distance_m,r.class_name,
      coalesce(e.snapshot->'strategies','["FREE"]'::jsonb)),
    'strategies',coalesce(e.snapshot->'strategies','["FREE"]'::jsonb),
    'condition',h.condition_score,'fatigue',h.fatigue,'weightKg',e.weight_kg,
    'distanceFit',coalesce(nullif(a.distance_affinity->>(r.distance_m::text),'')::numeric,75),
    'trainerReadiness',coalesce((e.snapshot->>'trainerReadiness')::numeric,75)
  ) ORDER BY e.gate_no) INTO input_runners
  FROM my_derby.race_entries e
  JOIN my_derby.horses h ON h.id=e.horse_id
  JOIN my_derby.horse_abilities a ON a.horse_id=h.id
  JOIN my_derby.npc_jockeys j ON j.id=e.jockey_id AND j.is_active
  WHERE e.race_id=p_race_id AND e.status IN ('CONFIRMED','COMPLETED') AND e.gate_no IS NOT NULL AND e.weight_kg IS NOT NULL;
  IF input_runners IS NULL OR jsonb_array_length(input_runners)<>n THEN RAISE EXCEPTION 'ENTRY_ABILITY_JOCKEY_MISSING'; END IF;
  seed:=floor(random()*2147483646)::int+1;
  RETURN jsonb_build_object('status','PREVIEW','raceId',r.id,
    'displayRaceNo',r.prize_policy->>'source_rc_no','startTime',to_char(r.start_time,'HH24:MI'),
    'resultTime',r.prize_policy->>'result_kst_time','rank',r.class_name,
    'input',jsonb_build_object('raceId',r.id,'track',r.track,'distanceM',r.distance_m,'seed',seed,
      'weather',coalesce(r.weather_code,'CLEAR'),'trackCondition',coalesce(r.track_condition,'GOOD'),'runners',input_runners));
END;
$function$;

CREATE OR REPLACE FUNCTION my_derby.secure_program_claim_next(p_secret text, p_slot integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 r my_derby.races%rowtype; v_data jsonb; v_input jsonb; v_run my_derby.race_runs%rowtype;
 v_world my_derby.worlds%rowtype; v_today date;
BEGIN
 IF p_secret IS NULL OR p_secret IS DISTINCT FROM
   (SELECT secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner')
   THEN RAISE EXCEPTION 'OFFICIAL_AUTH_REQUIRED' USING errcode='42501'; END IF;
 IF p_slot NOT BETWEEN 0 AND 2 THEN RAISE EXCEPTION 'INVALID_SLOT'; END IF;
 SELECT * INTO v_world FROM my_derby.worlds WHERE world_key='kra_roster_v1';
 IF v_world.status<>'ACTIVE' OR NOT v_world.automatic_processing_enabled
   THEN RETURN jsonb_build_object('status','WORLD_NOT_PROCESSING'); END IF;
 v_today:=(now() at time zone 'Asia/Seoul')::date;
 SELECT * INTO r FROM my_derby.races ra
 WHERE ra.world_id=v_world.id AND ra.status='OPEN'
  AND ra.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  AND ra.prize_policy->>'kst_date'=v_today::text
  AND (ra.prize_policy->>'slot_index')::int=p_slot
  AND ra.start_time<=(now() at time zone 'Asia/Seoul')::time
  AND ra.target_runner_count BETWEEN 2 AND 16
  AND (SELECT count(*) FROM my_derby.race_entries e WHERE e.race_id=ra.id AND e.status='CONFIRMED')=ra.target_runner_count
 ORDER BY ra.start_time,ra.track,ra.race_no LIMIT 1 FOR UPDATE OF ra SKIP LOCKED;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','WAITING','slot',p_slot); END IF;
 PERFORM my_derby_private.recalculate_official_handicap_race(r.id);
 v_data:=my_derby.secure_program_preview_race(p_secret,r.id);
 v_input:=v_data->'input';
 INSERT INTO my_derby.race_runs(race_id,race_input,random_seed,balance_version,tick_seconds,status,claimed_at,engine_version)
 VALUES(r.id,v_input,(v_input->>'seed')::bigint,v_world.balance_version,0.2,'RUNNING',now(),'0.2.0')
 ON CONFLICT(race_id) DO NOTHING RETURNING * INTO v_run;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','ALREADY_RUNNING','raceId',r.id); END IF;
 UPDATE my_derby.races SET status='RUNNING' WHERE id=r.id;
 INSERT INTO my_derby.official_race_process_audit(race_id,slot_time,action,event_detail)
 VALUES(r.id,r.start_time,'SCHEDULE_V2_CLAIM',jsonb_build_object('runId',v_run.id,'grade',r.class_name));
 RETURN jsonb_build_object('status','CLAIMED','raceId',r.id,'runId',v_run.id,'rank',r.class_name,
   'startTime',r.start_time,'input',v_input);
END;
$function$;

CREATE OR REPLACE FUNCTION my_derby.secure_official_race_finalize(p_secret text,p_run_id uuid,p_result jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_run my_derby.race_runs%rowtype; v_race my_derby.races%rowtype;
 v_count int; v_different int; v_sections int; v_event_count int;
BEGIN
 IF p_secret IS NULL OR p_secret IS DISTINCT FROM
   (SELECT secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner')
   THEN RAISE EXCEPTION 'OFFICIAL_AUTH_REQUIRED' USING errcode='42501'; END IF;
 SELECT * INTO v_run FROM my_derby.race_runs WHERE id=p_run_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RUN_NOT_FOUND'; END IF;
 IF v_run.status='FINISHED' THEN RETURN jsonb_build_object('status','ALREADY_FINISHED','raceId',v_run.race_id); END IF;
 IF v_run.status<>'RUNNING' THEN RAISE EXCEPTION 'RUN_NOT_CLAIMED'; END IF;
 SELECT * INTO v_race FROM my_derby.races WHERE id=v_run.race_id FOR UPDATE;
 IF v_race.status<>'RUNNING' THEN RAISE EXCEPTION 'RACE_NOT_RUNNING'; END IF;
 IF p_result->>'raceId' IS DISTINCT FROM v_race.id::text OR
    (p_result->>'seed')::integer IS DISTINCT FROM v_run.random_seed OR
    p_result->>'version' IS NULL OR p_result->>'version' NOT IN ('0.1.0','0.2.0') OR (p_result->>'tickSeconds')::numeric<>0.2 OR
    (p_result->>'version'='0.2.0' AND (
      p_result->>'weather' IS DISTINCT FROM v_race.weather_code OR
      p_result->>'trackCondition' IS DISTINCT FROM v_race.track_condition OR
      p_result->>'weather' IS DISTINCT FROM v_run.race_input->>'weather' OR
      p_result->>'trackCondition' IS DISTINCT FROM v_run.race_input->>'trackCondition'))
   THEN RAISE EXCEPTION 'ENGINE_SNAPSHOT_MISMATCH'; END IF;
 IF jsonb_typeof(p_result->'results')<>'array' OR jsonb_typeof(p_result->'sections')<>'array' OR jsonb_typeof(p_result->'events')<>'array'
   THEN RAISE EXCEPTION 'RESULT_ARRAYS_INVALID'; END IF;
 SELECT count(*)::int INTO v_count FROM my_derby.race_entries WHERE race_id=v_race.id AND status='CONFIRMED';
 IF jsonb_array_length(p_result->'results')<>v_count OR v_count<2 OR v_count>16 OR
    (v_race.target_runner_count IS NOT NULL AND v_count<>v_race.target_runner_count)
   THEN RAISE EXCEPTION 'FINISHER_COUNT_MISMATCH'; END IF;
 SELECT count(*)::int INTO v_different FROM jsonb_array_elements(p_result->'results') f
 WHERE NOT EXISTS(SELECT 1 FROM my_derby.race_entries e WHERE e.race_id=v_race.id AND e.horse_id=(f->>'horseId')::uuid)
   OR (f->>'timeSec')::numeric<=0 OR (f->>'rank')::int NOT BETWEEN 1 AND v_count;
 IF v_different>0 THEN RAISE EXCEPTION 'INVALID_FINISHER'; END IF;
 IF (SELECT count(DISTINCT f->>'horseId') FROM jsonb_array_elements(p_result->'results') f)<>v_count OR
    (SELECT count(DISTINCT (f->>'rank')::int) FROM jsonb_array_elements(p_result->'results') f)<>v_count
   THEN RAISE EXCEPTION 'DUPLICATE_FINISHER_OR_RANK'; END IF;
 SELECT jsonb_array_length(p_result->'sections'),jsonb_array_length(p_result->'events') INTO v_sections,v_event_count;
 IF v_sections>20 OR v_event_count>650 THEN RAISE EXCEPTION 'RESULT_TOO_LARGE'; END IF;
 INSERT INTO my_derby.race_results(race_run_id,horse_id,finishing_rank,finish_time_sec,prize_amount,change_snapshot)
 SELECT v_run.id,(f->>'horseId')::uuid,(f->>'rank')::smallint,(f->>'timeSec')::numeric,0,
   jsonb_build_object('engine_version',p_result->>'version','prize_settlement','PENDING_ECONOMY_V2','final_stamina',f->>'finalStamina')
 FROM jsonb_array_elements(p_result->'results') f;
 INSERT INTO my_derby.race_section_ranks(race_run_id,horse_id,distance_m,ranking,gap_m,pace)
 SELECT v_run.id,(ranked.r->>'horseId')::uuid,(sec.s->>'distanceM')::int,(ranked.r->>'rank')::smallint,
   (ranked.r->>'gapM')::numeric,ranked.r->>'strategy'
 FROM jsonb_array_elements(p_result->'sections') sec(s) CROSS JOIN LATERAL jsonb_array_elements(sec.s->'ranks') ranked(r);
 INSERT INTO my_derby.race_event_logs(race_run_id,seq,time_sec,distance_m,horse_id,event_type,reason_code,params,importance)
 SELECT v_run.id,(e->>'seq')::int,(e->>'timeSec')::numeric,(e->>'distanceM')::numeric,
   nullif(e->>'horseId','')::uuid,e->>'eventType',e->>'reasonCode',coalesce(e->'params','{}'::jsonb)||jsonb_build_object('text',e->>'text'),
   coalesce((e->>'importance')::smallint,1) FROM jsonb_array_elements(p_result->'events') e;
 UPDATE my_derby.race_entries SET status='COMPLETED' WHERE race_id=v_race.id AND status='CONFIRMED';
 UPDATE my_derby.races SET status='FINISHED',prize_policy=prize_policy||'{"prize_status":"PENDING_ECONOMY_V2"}'::jsonb WHERE id=v_race.id;
 UPDATE my_derby.race_runs SET status='FINISHED',engine_version=p_result->>'version',result_applied_at=now() WHERE id=v_run.id;
 INSERT INTO my_derby.official_race_process_audit(race_id,slot_time,action,event_detail)
 VALUES(v_race.id,v_race.start_time,'FINISHED',jsonb_build_object('runId',v_run.id,'finishers',v_count,'events',v_event_count,'sections',v_sections));
 PERFORM my_derby_private.apply_official_race_aftercare(v_race.id);
 RETURN jsonb_build_object('status','FINISHED','raceId',v_race.id,'runId',v_run.id,
   'winner',p_result->'results'->0->>'name','finishers',v_count,'prizeSettlement','ECONOMY_V2_SETTLED');
END;
$function$;

CREATE OR REPLACE FUNCTION my_derby.official_public_race_detail(p_race_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  r my_derby.races%rowtype; public_result jsonb; runners jsonb;
BEGIN
  SELECT * INTO r FROM my_derby.races WHERE id=p_race_id;
  IF NOT FOUND OR r.prize_policy->>'schedule_version' IS DISTINCT FROM 'csv2025_rank_sttime_v2' THEN RETURN NULL; END IF;
  public_result:=my_derby.official_public_race_result(p_race_id);
  IF public_result IS NULL THEN RETURN NULL; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'horseId',h.id,'number',e.gate_no,'name',h.name,'age',h.age_years,'rating',h.domestic_rating,
    'origin',h.source_meet,'sex',h.sex,'jockeyId',e.jockey_id,'jockeyName',coalesce(j.display_name,j.name),
    'trainerName',coalesce(trainer.trainer_name,'미계약'),'trainerId',trainer.trainer_id,'weightKg',e.weight_kg,
    'entryStatus',e.status,'lastRaceDate',coalesce(last_run.last_date,h.source_last_race_date::text),
    'lastRaceOrigin',case when last_run.last_day is not null then 'GAME' when h.source_last_race_date is not null then 'IMPORTED' else null end,
    'raceIntervalWeeks',case when last_run.last_day is not null then round(greatest(0,r.race_day-last_run.last_day)::numeric/7,1)
      when h.source_last_race_date is not null and h.source_last_race_date<=(r.prize_policy->>'kst_date')::date
      then round(((r.prize_policy->>'kst_date')::date-h.source_last_race_date)::numeric/7,1) else null end,
    'firstStart',last_run.last_day is null AND h.source_last_race_date is null AND coalesce(h.source_record_count,0)=0
  ) ORDER BY e.gate_no NULLS LAST,h.name),'[]'::jsonb) INTO runners
  FROM my_derby.race_entries e JOIN my_derby.horses h ON h.id=e.horse_id
  LEFT JOIN my_derby.npc_jockeys j ON j.id=e.jockey_id
  LEFT JOIN LATERAL (
    SELECT t.id AS trainer_id,t.name AS trainer_name FROM my_derby.trainer_contracts tc
    JOIN my_derby.npc_trainers t ON t.id=tc.trainer_id JOIN my_derby.npc_stables s ON s.id=t.stable_id
    WHERE tc.horse_id=e.horse_id AND tc.start_game_day<=r.race_day
      AND (tc.end_game_day IS NULL OR tc.end_game_day>=r.race_day) AND s.track=r.track
    ORDER BY tc.start_game_day DESC,tc.id DESC LIMIT 1
  ) trainer ON TRUE
  LEFT JOIN LATERAL (
    SELECT previous.race_day AS last_day,previous.prize_policy->>'kst_date' AS last_date
    FROM my_derby.race_results result JOIN my_derby.race_runs run ON run.id=result.race_run_id
      AND run.status='FINISHED' AND run.result_applied_at IS NOT NULL
    JOIN my_derby.races previous ON previous.id=run.race_id AND previous.world_id=r.world_id
      AND previous.race_day<r.race_day AND previous.status='FINISHED'
    WHERE result.horse_id=h.id ORDER BY previous.race_day DESC,previous.start_time DESC LIMIT 1
  ) last_run ON TRUE
  WHERE e.race_id=p_race_id AND e.status IN ('APPLIED','CONFIRMED','COMPLETED');
  RETURN public_result||jsonb_build_object(
    'raceNo',r.race_no,'gameRaceNo',r.race_no,'raceDay',r.race_day,'kstDate',r.prize_policy->>'kst_date',
    'startTime',to_char(r.start_time,'HH24:MI'),'resultTime',r.prize_policy->>'result_kst_time',
    'targetRunnerCount',r.target_runner_count,'entryDeadline',to_char(r.entry_deadline,'HH24:MI'),
    'bettingResults',my_derby.public_race_final_dividends(p_race_id),
    'entryAnnouncementAt',(r.prize_policy->>'kst_date')||' 08:00 KST',
    'entryAnnouncementPending',(r.status='OPEN' AND (now() at time zone 'Asia/Seoul')<(r.prize_policy->>'kst_date')::timestamp+interval '8 hours'),
    'weatherCode',r.weather_code,'trackCondition',r.track_condition,
    'entries',case when r.status='OPEN' and (now() at time zone 'Asia/Seoul')<(r.prize_policy->>'kst_date')::timestamp+interval '8 hours'
      then '[]'::jsonb else runners end
  );
END;
$function$;

REVOKE ALL ON FUNCTION my_derby.official_public_race_detail(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.official_public_race_detail(uuid) TO anon,authenticated,service_role;
