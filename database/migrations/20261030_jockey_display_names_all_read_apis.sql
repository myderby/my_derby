-- Every publicly displayed source jockey uses canonical 2025 roster name;
-- internal unique name and original jkNo are retained.
-- apply_player_jockey
CREATE OR REPLACE FUNCTION my_derby.apply_player_jockey(p_race_id uuid, p_horse_id uuid, p_jockey_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_user uuid:=auth.uid();
 v_r my_derby.races%rowtype;
 v_entry my_derby.race_entries%rowtype;
 v_j my_derby.npc_jockeys%rowtype;
 v_kst timestamp:=now() AT TIME ZONE 'Asia/Seoul';
 v_rides integer;
 v_chance numeric;v_roll numeric;v_preference text;v_existing text;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_r FROM my_derby.races WHERE id=p_race_id FOR UPDATE;
 IF NOT FOUND OR v_r.status<>'OPEN' THEN RAISE EXCEPTION 'RACE_NOT_OPEN'; END IF;
 IF (v_r.prize_policy->>'kst_date')::date<v_kst::date OR
  ((v_r.prize_policy->>'kst_date')::date=v_kst::date AND
    v_kst::time>=coalesce(v_r.entry_deadline,v_r.start_time-interval '10 minutes')) THEN
  RAISE EXCEPTION 'ENTRY_DEADLINE_PASSED';
 END IF;
 SELECT * INTO v_entry FROM my_derby.race_entries
 WHERE race_id=p_race_id AND horse_id=p_horse_id AND owner_user_id=v_user AND status='CONFIRMED'
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'OWN_CONFIRMED_ENTRY_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_j FROM my_derby.npc_jockeys
 WHERE id=p_jockey_id AND world_id=v_r.world_id AND home_track=v_r.track AND is_active FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'JOCKEY_NOT_ELIGIBLE'; END IF;
 IF EXISTS(SELECT 1 FROM my_derby.race_entries e
    WHERE e.race_id=p_race_id AND e.jockey_id=p_jockey_id AND e.horse_id<>p_horse_id
    AND e.status IN ('APPLIED','CONFIRMED','COMPLETED')) THEN
   RAISE EXCEPTION 'JOCKEY_ALREADY_BOOKED_FOR_RACE';
 END IF;
 SELECT count(*) INTO v_rides FROM my_derby.race_entries e
  JOIN my_derby.races rr ON rr.id=e.race_id
  WHERE rr.world_id=v_r.world_id AND rr.race_day=v_r.race_day AND rr.status<>'CANCELLED'
   AND e.jockey_id=p_jockey_id AND e.status IN ('APPLIED','CONFIRMED','COMPLETED')
   AND e.id<>v_entry.id;
 IF v_rides>=v_j.max_daily_rides THEN RAISE EXCEPTION 'JOCKEY_DAILY_LIMIT'; END IF;

 SELECT status INTO v_existing FROM my_derby.jockey_applications
  WHERE race_id=p_race_id AND horse_id=p_horse_id AND jockey_id=p_jockey_id;
 IF v_existing='REJECTED' THEN
  RETURN jsonb_build_object('status','REJECTED','jockeyId',p_jockey_id,
    'jockeyName',coalesce(v_j.display_name,v_j.name),'reason','ALREADY_DECLINED_THIS_RACE');
 END IF;
 IF v_existing='ACCEPTED' THEN
  RETURN jsonb_build_object('status','ALREADY_ACCEPTED','jockeyId',p_jockey_id,
    'jockeyName',coalesce(v_j.display_name,v_j.name),'dailyRidesAfter',v_rides+1,
    'maxDailyRides',v_j.max_daily_rides);
 END IF;
 -- Each NPC jockey has a stable, deterministic preference.
 v_preference:=CASE (('x'||substr(md5(v_j.id::text),1,2))::bit(8)::int%3)
   WHEN 0 THEN 'PRUDENT' WHEN 1 THEN 'BALANCED' ELSE 'CHALLENGER' END;
 v_chance:=least(96,greatest(55,CASE v_preference
    WHEN 'PRUDENT' THEN 73 WHEN 'CHALLENGER' THEN 89 ELSE 83 END
    -v_rides*3
    +CASE WHEN v_r.track=v_j.home_track THEN 4 ELSE -15 END
    +CASE WHEN (SELECT source_grade_no FROM my_derby.horses
      WHERE id=p_horse_id)<=3 THEN 5 ELSE 0 END
    +CASE WHEN (v_j.skill_stats->>'judgment')::numeric>=82 THEN -4 ELSE 0 END));
 v_roll:=(('x'||substr(md5(p_race_id::text||p_horse_id::text||
   p_jockey_id::text||':ACCEPT_V1'),1,8))::bit(32)::bigint%10000)::numeric/100;
 IF v_roll>=v_chance THEN
  INSERT INTO my_derby.jockey_applications(race_id,horse_id,owner_user_id,jockey_id,status)
  VALUES(p_race_id,p_horse_id,v_user,p_jockey_id,'REJECTED')
  ON CONFLICT(race_id,horse_id,jockey_id) DO UPDATE SET status='REJECTED';
  UPDATE my_derby.jockey_applications
  SET decision_snapshot=jsonb_build_object('chance',v_chance,'roll',v_roll,
    'preference',v_preference,'reason','NPC_JOCKEY_DECLINED')
  WHERE race_id=p_race_id AND horse_id=p_horse_id AND jockey_id=p_jockey_id;
  RETURN jsonb_build_object('status','REJECTED','jockeyName',coalesce(v_j.display_name,v_j.name),
    'reason','NPC_JOCKEY_DECLINED','acceptanceChance',v_chance,
    'jockeyPreference',v_preference);
 END IF;
  UPDATE my_derby.jockey_applications SET status='WITHDRAWN'
 WHERE race_id=p_race_id AND horse_id=p_horse_id AND owner_user_id=v_user
  AND status IN ('PENDING','ACCEPTED','AUTO_ASSIGNED') AND jockey_id<>p_jockey_id;
 INSERT INTO my_derby.jockey_applications(race_id,horse_id,owner_user_id,jockey_id,status)
 VALUES(p_race_id,p_horse_id,v_user,p_jockey_id,'ACCEPTED')
 ON CONFLICT(race_id,horse_id,jockey_id) DO UPDATE SET status='ACCEPTED';
 UPDATE my_derby.jockey_applications
  SET decision_snapshot=jsonb_build_object('chance',v_chance,'roll',v_roll,
    'preference',v_preference,'reason','NPC_JOCKEY_ACCEPTED')
  WHERE race_id=p_race_id AND horse_id=p_horse_id AND jockey_id=p_jockey_id;
 UPDATE my_derby.race_entries SET jockey_id=p_jockey_id,
  snapshot=jsonb_set(snapshot,'{autoAssignedJockey}','false'::jsonb,true)
 WHERE id=v_entry.id;
 RETURN jsonb_build_object('status','ACCEPTED','raceId',p_race_id,
  'horseId',p_horse_id,'jockeyId',p_jockey_id,'jockeyName',coalesce(v_j.display_name,v_j.name),
  'dailyRidesAfter',v_rides+1,'maxDailyRides',v_j.max_daily_rides,
  'acceptanceChance',v_chance,'jockeyPreference',v_preference);
END $function$;

-- official_public_race_detail
CREATE OR REPLACE FUNCTION my_derby.official_public_race_detail(p_race_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  r my_derby.races%rowtype;
  public_result jsonb;
  runners jsonb;
BEGIN
  SELECT * INTO r FROM my_derby.races WHERE id=p_race_id;
  IF NOT FOUND OR r.prize_policy->>'schedule_version' IS DISTINCT FROM 'csv2025_rank_sttime_v2'
  THEN RETURN NULL; END IF;
  public_result:=my_derby.official_public_race_result(p_race_id);
  IF public_result IS NULL THEN RETURN NULL; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'horseId',h.id,
    'number',e.gate_no,
    'name',h.name,
    'age',h.age_years,
    'sex',h.sex,
    'jockeyName',coalesce(j.display_name,j.name),
    'weightKg',e.weight_kg,
    'entryStatus',e.status
  ) ORDER BY e.gate_no NULLS LAST,h.name),'[]'::jsonb)
  INTO runners
  FROM my_derby.race_entries e
  JOIN my_derby.horses h ON h.id=e.horse_id
  LEFT JOIN my_derby.npc_jockeys j ON j.id=e.jockey_id
  WHERE e.race_id=p_race_id AND e.status IN ('APPLIED','CONFIRMED','COMPLETED');

  RETURN public_result||jsonb_build_object(
    'raceNo',coalesce((r.prize_policy->>'source_rc_no')::integer,r.race_no),
    'gameRaceNo',r.race_no,
    'raceDay',r.race_day,
    'kstDate',r.prize_policy->>'kst_date',
    'startTime',to_char(r.start_time,'HH24:MI'),
    'resultTime',r.prize_policy->>'result_kst_time',
    'targetRunnerCount',r.target_runner_count,
    'entryDeadline',to_char(r.entry_deadline,'HH24:MI'),
    'sourceMeet',r.prize_policy->>'source_meet',
    'sourceRaceNo',r.prize_policy->>'source_rc_no',
    'entries',runners
  );
END;
$function$;

-- player_race_board
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
   'jockeyId',e.jockey_id,'jockeyName',coalesce(j.display_name,j.name)))
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

-- player_race_jockey_options
CREATE OR REPLACE FUNCTION my_derby.player_race_jockey_options(p_race_id uuid, p_horse_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_user uuid:=auth.uid();
 v_r my_derby.races%rowtype;
 v_entry my_derby.race_entries%rowtype;
 v_choices jsonb;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_entry FROM my_derby.race_entries
  WHERE race_id=p_race_id AND horse_id=p_horse_id AND owner_user_id=v_user
   AND status='CONFIRMED';
 IF NOT FOUND THEN RAISE EXCEPTION 'OWN_CONFIRMED_ENTRY_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_r FROM my_derby.races WHERE id=p_race_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'RACE_NOT_FOUND'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',j.id,'name',coalesce(j.display_name,j.name),'track',j.home_track,
  'maxDailyRides',j.max_daily_rides,'dailyRides',(
    SELECT count(*) FROM my_derby.race_entries e JOIN my_derby.races rr ON rr.id=e.race_id
    WHERE rr.world_id=v_r.world_id AND rr.race_day=v_r.race_day
      AND rr.status<>'CANCELLED' AND e.jockey_id=j.id AND e.status IN ('APPLIED','CONFIRMED','COMPLETED')),
  'busyInRace',EXISTS(SELECT 1 FROM my_derby.race_entries e WHERE e.race_id=p_race_id
    AND e.jockey_id=j.id AND e.horse_id<>p_horse_id AND e.status IN ('APPLIED','CONFIRMED')),
  'selected',v_entry.jockey_id=j.id,'stats',j.skill_stats,'specialties',j.specialties
 ) ORDER BY coalesce(j.display_name,j.name)),'[]'::jsonb) INTO v_choices
 FROM my_derby.npc_jockeys j WHERE j.world_id=v_r.world_id
   AND j.home_track=v_r.track AND j.is_active;
 RETURN jsonb_build_object('raceId',p_race_id,'horseId',p_horse_id,'jockeys',v_choices);
END $function$;

-- world_jockey_directory
CREATE OR REPLACE FUNCTION my_derby.world_jockey_directory(p_search text DEFAULT NULL::text, p_track text DEFAULT NULL::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 24, p_sort text DEFAULT 'name'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_world uuid;v_day integer;v_recent_day integer;
 v_search text:=nullif(trim(coalesce(p_search,'')),'');
 v_track text:=nullif(trim(coalesce(p_track,'')),'');
 v_page integer:=coalesce(p_page,1);
 v_size integer:=coalesce(p_page_size,24);
 v_sort text:=coalesce(p_sort,'name');
 v_count integer;v_items jsonb;
BEGIN
 IF v_page NOT BETWEEN 1 AND 10000 OR v_size NOT BETWEEN 1 AND 50
  OR length(coalesce(v_search,''))>50
  OR v_sort NOT IN('name','rides','wins')
  OR (v_track IS NOT NULL AND v_track NOT IN('서울','부산','영천'))
 THEN RAISE EXCEPTION 'DIRECTORY_FILTER_INVALID';END IF;
 SELECT id INTO v_world FROM my_derby.worlds
 WHERE world_key='kra_roster_v1' AND status='ACTIVE' LIMIT 1;
 IF v_world IS NULL THEN RAISE EXCEPTION 'WORLD_NOT_ACTIVE'; END IF;
 v_day:=(my_derby.world_clock(v_world)->>'gameDayStart')::integer+6;
 v_recent_day:=greatest(1,v_day-363);
 SELECT count(*) INTO v_count FROM my_derby.npc_jockeys j
 WHERE j.world_id=v_world AND (v_search IS NULL OR coalesce(j.display_name,j.name) ILIKE '%'||v_search||'%')
 AND (v_track IS NULL OR j.home_track=v_track);
 WITH summary AS (
  SELECT e.jockey_id,
   count(*)::integer starts,
   count(*) FILTER(WHERE rr.finishing_rank=1)::integer wins,
   count(*) FILTER(WHERE rr.finishing_rank=2)::integer seconds,
   count(*) FILTER(WHERE rr.finishing_rank=3)::integer thirds,
   count(*) FILTER(WHERE race.race_day BETWEEN v_recent_day AND v_day)::integer year_starts,
   count(*) FILTER(WHERE rr.finishing_rank=1 AND
    race.race_day BETWEEN v_recent_day AND v_day)::integer year_wins,
   count(*) FILTER(WHERE rr.finishing_rank=2 AND
    race.race_day BETWEEN v_recent_day AND v_day)::integer year_seconds,
   count(*) FILTER(WHERE rr.finishing_rank=3 AND
    race.race_day BETWEEN v_recent_day AND v_day)::integer year_thirds
  FROM my_derby.race_results rr
  JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
  JOIN my_derby.races race ON race.id=run.race_id AND
    race.status='FINISHED' AND race.world_id=v_world
  JOIN my_derby.race_entries e ON e.race_id=race.id AND
    e.horse_id=rr.horse_id
  GROUP BY e.jockey_id
 ), filtered AS (
  SELECT j.id,coalesce(j.display_name,j.name) AS name,j.home_track,j.is_active,j.max_daily_rides,
   j.skill_stats,j.specialties,
   coalesce(s.starts,0) starts,coalesce(s.wins,0) wins,
   coalesce(s.seconds,0) seconds,coalesce(s.thirds,0) thirds,
   coalesce(s.year_starts,0) year_starts,coalesce(s.year_wins,0) year_wins,
   coalesce(s.year_seconds,0) year_seconds,coalesce(s.year_thirds,0) year_thirds
  FROM my_derby.npc_jockeys j LEFT JOIN summary s ON s.jockey_id=j.id
  WHERE j.world_id=v_world
   AND (v_search IS NULL OR coalesce(j.display_name,j.name) ILIKE '%'||v_search||'%')
   AND (v_track IS NULL OR j.home_track=v_track)
 ), paged AS (
   SELECT * FROM filtered f
   ORDER BY CASE WHEN v_sort='rides' THEN f.starts END DESC NULLS LAST,
    CASE WHEN v_sort='wins' THEN f.wins END DESC NULLS LAST,
    f.name ASC,f.id ASC
   LIMIT v_size OFFSET (v_page-1)*v_size
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',k.id,'name',k.name,'track',k.home_track,'active',k.is_active,
  'maxDailyRides',k.max_daily_rides,
  'skills',k.skill_stats,'specialties',to_jsonb(k.specialties),
  'career',jsonb_build_object('starts',k.starts,'wins',k.wins,
   'second',k.seconds,'third',k.thirds),
  'recentYear',jsonb_build_object('starts',k.year_starts,
   'wins',k.year_wins,'second',k.year_seconds,'third',k.year_thirds)
  ) ORDER BY
    CASE WHEN v_sort='rides' THEN k.starts END DESC NULLS LAST,
    CASE WHEN v_sort='wins' THEN k.wins END DESC NULLS LAST,
    k.name ASC,k.id ASC),'[]'::jsonb) INTO v_items FROM paged k;
 RETURN jsonb_build_object('total',v_count,'page',v_page,'pageSize',v_size,
   'pages',ceil(v_count::numeric/v_size)::integer,
   'gameDay',v_day,'yearStartDay',v_recent_day,
   'recordBasis','MY_DERBY_FINISHED_OFFICIAL_RACES',
   'yearBasis','LAST_364_GAME_DAYS','items',v_items);
END $function$;
