
-- Distinguish northern- and southern-hemisphere foaling conditions.
-- Never infer foaling hemisphere from race venue (e.g. Jeju -> Yeongcheon),
-- nationality or horse name. Unknown birthplace is fail-closed.
ALTER TABLE my_derby.horses ADD COLUMN IF NOT EXISTS birth_hemisphere text;
ALTER TABLE my_derby.horses DROP CONSTRAINT IF EXISTS valid_birth_hemisphere;
ALTER TABLE my_derby.horses ADD CONSTRAINT valid_birth_hemisphere
  CHECK (birth_hemisphere IS NULL OR birth_hemisphere IN ('NORTH','SOUTH'));

CREATE OR REPLACE FUNCTION my_derby_private.player_age_cond_valid(p_age_cond text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO ''
AS $fn$
DECLARE c text:=regexp_replace(coalesce(p_age_cond,''),'[[:space:]]+','','g');
BEGIN
 IF c IN('남4이하/북3','남3/북2','연령오픈','전연령','전체','무제한')
 THEN RETURN true;END IF;
 RETURN c ~ '^[0-9]{1,2}세$'
  OR c ~ '^[0-9]{1,2}세(이상|이하)$'
  OR c ~ '^[0-9]{1,2}세[~-][0-9]{1,2}세$'
  OR c ~ '^[0-9]{1,2}[~-][0-9]{1,2}세$'
  OR c ~ '^[0-9]{1,2}세이상[0-9]{1,2}세이하$';
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.player_age_cond_matches(
 p_age integer,p_cond text,p_birth_hemisphere text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO ''
AS $fn$
DECLARE c text:=regexp_replace(coalesce(p_cond,''),'[[:space:]]+','','g');
BEGIN
 IF p_age IS NULL OR p_age<0 THEN RETURN false; END IF;
 IF c='남4이하/북3' THEN RETURN CASE p_birth_hemisphere
  WHEN 'SOUTH' THEN p_age<=4
  WHEN 'NORTH' THEN p_age=3 ELSE false END;END IF;
 IF c='남3/북2' THEN RETURN CASE p_birth_hemisphere
  WHEN 'SOUTH' THEN p_age=3
  WHEN 'NORTH' THEN p_age=2 ELSE false END;END IF;
 RETURN my_derby_private.player_age_cond_matches(p_age,p_cond);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.player_race_grade_age_eligible(
 p_horse_grade integer,p_horse_age integer,p_race_grade integer,
 p_class_name text,p_source_name text,p_age_cond text,p_birth_hemisphere text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $fn$
 SELECT CASE WHEN my_derby_private.player_is_special_race(p_class_name,p_source_name)
  THEN my_derby_private.player_age_cond_matches(p_horse_age,p_age_cond,p_birth_hemisphere)
  ELSE my_derby_private.player_horse_grade_can_enter(p_horse_grade,p_race_grade) END
$fn$;

REVOKE ALL ON FUNCTION my_derby_private.player_age_cond_matches(integer,text,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.player_age_cond_valid(text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.player_race_grade_age_eligible(
 integer,integer,integer,text,text,text,text) FROM PUBLIC,anon,authenticated;

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
 IF v_date IS NULL OR v_date<v_now::date THEN
  RAISE EXCEPTION 'ENTRY_DEADLINE_PASSED';
 END IF;
 IF v_date=v_now::date THEN
  RAISE EXCEPTION 'ENTRY_RACE_DAY_BLOCKED';
 END IF;
 -- Entry window opens at 00:00 Asia/Seoul, four calendar days before
 -- an OPEN-class race, otherwise two calendar days before.
 IF v_now::date < my_derby_private.player_entry_open_date(
   v_date,v_r.class_name,v_r.prize_policy->>'source_rc_name') THEN
  RAISE EXCEPTION 'ENTRY_NOT_OPEN_YET';
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
 -- Ordinary racing: exact grade. OPEN/special: verified source ageCond.
 -- Existing region and medical checks apply to both classes.
 IF v_h.source_meet IS DISTINCT FROM v_r.prize_policy->>'source_meet' THEN
  RAISE EXCEPTION 'REGION_MISMATCH';
 END IF;
 IF my_derby_private.player_is_special_race(
      v_r.class_name,v_r.prize_policy->>'source_rc_name') THEN
  IF NOT my_derby_private.player_age_cond_valid(v_r.prize_policy->>'ageCond') THEN
   RAISE EXCEPTION 'AGE_COND_UNAVAILABLE';
  END IF;
  IF v_r.prize_policy->>'ageCond' IN('남4이하/북3','남3/북2')
    AND v_h.birth_hemisphere IS NULL THEN
   RAISE EXCEPTION 'HORSE_BIRTH_HEMISPHERE_REQUIRED';
  END IF;
  IF NOT my_derby_private.player_age_cond_matches(v_h.age_years,
      v_r.prize_policy->>'ageCond',v_h.birth_hemisphere) THEN
   RAISE EXCEPTION 'AGE_COND_NOT_ELIGIBLE';
  END IF;
 ELSIF NOT my_derby_private.player_horse_grade_can_enter(
     v_h.source_grade_no,(v_r.prize_policy->>'grade_no')::integer) THEN
  RAISE EXCEPTION 'GRADE_ENTRY_NOT_ALLOWED';
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
      'autoAssignedJockey',true,
      'horseGradeAtEntry',v_h.source_grade_no,
      'raceGradeAtEntry',(v_r.prize_policy->>'grade_no')::integer,
      'higherGradeChallenge',false,
      'specialRaceEntry',my_derby_private.player_is_special_race(
        v_r.class_name,v_r.prize_policy->>'source_rc_name'),
      'ageCondAtEntry',v_r.prize_policy->>'ageCond',
      'birthHemisphereAtEntry',v_h.birth_hemisphere)
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
    'strategies',v_strategies,'trainerReadiness',75,'autoAssignedJockey',true,
      'horseGradeAtEntry',v_h.source_grade_no,
      'raceGradeAtEntry',(v_r.prize_policy->>'grade_no')::integer,
      'higherGradeChallenge',false,
      'specialRaceEntry',my_derby_private.player_is_special_race(
       v_r.class_name,v_r.prize_policy->>'source_rc_name'),
      'ageCondAtEntry',v_r.prize_policy->>'ageCond',
      'birthHemisphereAtEntry',v_h.birth_hemisphere));
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
   'horseId',p_horse_id,'gateNo',v_gate,'jockeyId',v_jockey,'replacedNpc',v_replaced,
   'horseGrade',v_h.source_grade_no,
   'raceGrade',(v_r.prize_policy->>'grade_no')::integer,
   'higherGradeChallenge',false,
   'specialRaceEntry',my_derby_private.player_is_special_race(
     v_r.class_name,v_r.prize_policy->>'source_rc_name'),
   'ageCond',v_r.prize_policy->>'ageCond',
   'birthHemisphere',v_h.birth_hemisphere);
END $function$;
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
  'entryOpenDays',CASE WHEN my_derby_private.player_is_special_race(
    r.class_name,r.prize_policy->>'source_rc_name') THEN 4 ELSE 2 END,
  'isSpecialRace',my_derby_private.player_is_special_race(
    r.class_name,r.prize_policy->>'source_rc_name'),
  'ageCond',r.prize_policy->>'ageCond',
  'ageCondValid',my_derby_private.player_age_cond_valid(
    r.prize_policy->>'ageCond'),
  'ageCondRequiresBirthHemisphere',r.prize_policy->>'ageCond'
    IN('남4이하/북3','남3/북2'),
  'eligibleHorseIds',coalesce((
    SELECT jsonb_agg(h.id)
    FROM my_derby.horses h WHERE h.world_id=v_world AND h.owner_user_id=v_user
    AND h.source_meet=r.prize_policy->>'source_meet'
    AND my_derby_private.player_race_grade_age_eligible(
      h.source_grade_no,h.age_years,(r.prize_policy->>'grade_no')::integer,
      r.class_name,r.prize_policy->>'source_rc_name',r.prize_policy->>'ageCond',h.birth_hemisphere)
  ),'[]'::jsonb),
  'entryOpenDate',to_char(
     (r.prize_policy->>'kst_date')::date-
       CASE WHEN my_derby_private.player_is_special_race(
        r.class_name,r.prize_policy->>'source_rc_name') THEN 4 ELSE 2 END,
     'YYYY-MM-DD'),
  'isOpenGrade',my_derby_private.player_is_special_race(
    r.class_name,r.prize_policy->>'source_rc_name'),
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
 'sourceMeet',h.source_meet,'gradeNo',h.source_grade_no,'birthHemisphere',h.birth_hemisphere,
 'lifeStage',h.life_stage,'health',h.health_state,'fatigue',h.fatigue,
 'condition',h.condition_score,'retired',h.racing_retired_permanently,
 'breedingRetired',h.breeding_retired_at IS NOT NULL,
 'saleState',h.sale_state) ORDER BY h.name),'[]'::jsonb) INTO v_horses
 FROM my_derby.horses h WHERE h.world_id=v_world AND h.owner_user_id=v_user;

 RETURN jsonb_build_object('currentWeek',v_current,'week',v_week,
  'worldStatus',v_clock->>'status','races',v_races,'horses',v_horses);
END $function$;
