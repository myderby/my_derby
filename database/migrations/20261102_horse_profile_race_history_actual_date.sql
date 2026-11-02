-- Add recent official race rows to horse details; intervals use KST calendar dates.
CREATE OR REPLACE FUNCTION my_derby.world_horse_profile(p_horse_id uuid DEFAULT NULL::uuid, p_source_meet text DEFAULT NULL::text, p_source_hr_no text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_h my_derby.horses%rowtype;v_p my_derby.horse_source_profiles%rowtype;
 v_ability jsonb;v_day integer;v_world uuid;v_game_total jsonb;v_game_year jsonb;v_recent_starts jsonb;
BEGIN
 IF p_horse_id IS NULL AND (p_source_meet IS NULL OR p_source_hr_no IS NULL)
 THEN RAISE EXCEPTION 'HORSE_ID_OR_SOURCE_REQUIRED';END IF;
 IF p_horse_id IS NOT NULL THEN
  SELECT * INTO v_h FROM my_derby.horses WHERE id=p_horse_id;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','NOT_FOUND');END IF;
  SELECT * INTO v_p FROM my_derby.horse_source_profiles WHERE horse_id=v_h.id LIMIT 1;
 ELSE
  IF p_source_meet NOT IN('서울','영남','제주') OR length(p_source_hr_no)>24
  THEN RAISE EXCEPTION 'INVALID_SOURCE_ID';END IF;
  SELECT * INTO v_p FROM my_derby.horse_source_profiles
  WHERE source_meet=p_source_meet AND source_hr_no=p_source_hr_no;
  IF v_p.source_hr_no IS NULL THEN RETURN jsonb_build_object('status','NOT_FOUND');END IF;
  IF v_p.horse_id IS NOT NULL THEN
   SELECT * INTO v_h FROM my_derby.horses WHERE id=v_p.horse_id;
  END IF;
 END IF;
 v_world:=coalesce(v_h.world_id,(SELECT id FROM my_derby.worlds
  WHERE world_key='kra_roster_v1' LIMIT 1));
 v_day:=(my_derby.world_clock(v_world)->>'gameDayStart')::integer+6;
 IF v_h.id IS NOT NULL THEN
  SELECT CASE WHEN auth.uid() IS NOT NULL AND v_h.owner_user_id=auth.uid()
   THEN my_derby.player_horse_insight(v_h.id) ELSE NULL END INTO v_ability;
  SELECT jsonb_build_object('starts',count(*),'wins',count(*) FILTER(WHERE rr.finishing_rank=1),
   'second',count(*) FILTER(WHERE rr.finishing_rank=2),
   'third',count(*) FILTER(WHERE rr.finishing_rank=3)),
   jsonb_build_object('starts',count(*) FILTER(WHERE race.race_day BETWEEN greatest(1,v_day-363) AND v_day),
   'wins',count(*) FILTER(WHERE race.race_day BETWEEN greatest(1,v_day-363) AND v_day AND rr.finishing_rank=1),
   'second',count(*) FILTER(WHERE race.race_day BETWEEN greatest(1,v_day-363) AND v_day AND rr.finishing_rank=2),
   'third',count(*) FILTER(WHERE race.race_day BETWEEN greatest(1,v_day-363) AND v_day AND rr.finishing_rank=3))
  INTO v_game_total,v_game_year
  FROM my_derby.race_results rr
  JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
  JOIN my_derby.races race ON race.id=run.race_id AND race.status='FINISHED'
  WHERE rr.horse_id=v_h.id;
  WITH ranked AS (
   SELECT r.id,r.race_day,(r.prize_policy->>'kst_date')::date race_date,
    r.start_time,r.race_no,r.class_name,r.track,r.distance_m,
    e.gate_no,e.weight_kg,rr.finishing_rank,rr.finish_time_sec,j.name jockey_name,
    count(*) OVER(PARTITION BY r.id) field_size,
    lag((r.prize_policy->>'kst_date')::date) OVER(
     ORDER BY (r.prize_policy->>'kst_date')::date,r.start_time,r.id) previous_race_date
   FROM my_derby.race_results rr
   JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
   JOIN my_derby.races r ON r.id=run.race_id AND r.status='FINISHED'
    AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   JOIN my_derby.race_entries e ON e.race_id=r.id AND e.horse_id=rr.horse_id
   LEFT JOIN my_derby.npc_jockeys j ON j.id=e.jockey_id
   WHERE rr.horse_id=v_h.id
    AND r.prize_policy->>'kst_date' ~ '^\\d{4}-\\d{2}-\\d{2}
 RETURN jsonb_build_object(
  'status','OK','gameHorseId',v_h.id,'sourceAvailable',v_p.source_hr_no IS NOT NULL,
  'name',coalesce(v_h.name,v_p.horse_name),
  'horseNo',coalesce(v_p.source_hr_no,v_h.source_hr_no),
  'track',CASE coalesce(v_h.source_meet,v_p.source_meet)
    WHEN '부산경남' THEN '부산' WHEN '영남' THEN '부산'
    WHEN '제주' THEN '영천' ELSE coalesce(v_h.source_meet,v_p.source_meet) END,
  'sex',v_h.sex,'sourceSex',v_p.source_sex,
  'age',v_h.age_years,'birthDate',coalesce(v_p.birth_date,v_h.source_birth_date),
  'grade',v_h.source_grade_no,'sourceRank',v_p.source_rank,
  'rating',v_h.domestic_rating,'sourceRating',v_p.source_rating,
  'stage',v_h.life_stage,'condition',v_h.condition_score,'fatigue',v_h.fatigue,
  'health',v_h.health_state,'retired',v_h.racing_retired_permanently,
  'ratingPending',v_h.rating_pending_grade,
  'abilities','{}'::jsonb,'discovery',v_ability,
  'gameTrainer',(select jsonb_build_object('id',n.id,'name',n.name)
   from my_derby.trainer_contracts c join my_derby.npc_trainers n on n.id=c.trainer_id
   where c.horse_id=v_h.id and c.status='ACTIVE'
   order by c.start_game_day desc,c.id desc limit 1),
  'source',CASE WHEN v_p.source_hr_no IS NULL THEN NULL ELSE jsonb_build_object(
    'meet',v_p.source_meet,'horseNo',v_p.source_hr_no,'horseName',v_p.horse_name,
    'country',v_p.country,
    'fatherName',v_p.father_name,'fatherNo',v_p.father_no,
    'motherName',v_p.mother_name,'motherNo',v_p.mother_no,
    'ownerName',v_p.owner_name,'trainerName',v_p.trainer_name,
    'career',jsonb_build_object('starts',v_p.starts_total,
      'wins',v_p.wins_total,'second',v_p.seconds_total,'third',v_p.thirds_total),
    'recentYear',jsonb_build_object('starts',v_p.starts_year,
      'wins',v_p.wins_year,'second',v_p.seconds_year,'third',v_p.thirds_year),
    'sourceLabel','USER_CSV_QUERY_56','yearBasis','USER_PROVIDED_ONE_YEAR_SNAPSHOT'
   ) END,
  'game',jsonb_build_object('career',v_game_total,'recentYear',v_game_year,
   'recentStarts',coalesce(v_recent_starts,'[]'::jsonb),
   'yearBasis','LAST_364_GAME_DAYS','recordsAvailable',v_h.id IS NOT NULL)
 );
END $function$

  ), recent AS (
   SELECT * FROM ranked ORDER BY race_date DESC,start_time DESC,id LIMIT 20
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
   'raceId',id,'date',to_char(race_date,'YYYY-MM-DD'),
   'weekday',extract(dow FROM race_date)::integer,
   'raceNo',race_no,'gateNo',gate_no,'grade',class_name,'track',track,
   'distanceM',distance_m,'weightKg',weight_kg,'rank',finishing_rank,
   'fieldSize',field_size,'timeSec',finish_time_sec,'jockeyName',jockey_name,
   'intervalDays',CASE WHEN previous_race_date IS NULL THEN NULL
    ELSE race_date-previous_race_date END
  ) ORDER BY race_date DESC,start_time DESC,id),'[]'::jsonb)
  INTO v_recent_starts FROM recent;
 END IF;
 RETURN jsonb_build_object(
  'status','OK','gameHorseId',v_h.id,'sourceAvailable',v_p.source_hr_no IS NOT NULL,
  'name',coalesce(v_h.name,v_p.horse_name),
  'horseNo',coalesce(v_p.source_hr_no,v_h.source_hr_no),
  'track',CASE coalesce(v_h.source_meet,v_p.source_meet)
    WHEN '부산경남' THEN '부산' WHEN '영남' THEN '부산'
    WHEN '제주' THEN '영천' ELSE coalesce(v_h.source_meet,v_p.source_meet) END,
  'sex',v_h.sex,'sourceSex',v_p.source_sex,
  'age',v_h.age_years,'birthDate',coalesce(v_p.birth_date,v_h.source_birth_date),
  'grade',v_h.source_grade_no,'sourceRank',v_p.source_rank,
  'rating',v_h.domestic_rating,'sourceRating',v_p.source_rating,
  'stage',v_h.life_stage,'condition',v_h.condition_score,'fatigue',v_h.fatigue,
  'health',v_h.health_state,'retired',v_h.racing_retired_permanently,
  'ratingPending',v_h.rating_pending_grade,
  'abilities','{}'::jsonb,'discovery',v_ability,
  'gameTrainer',(select jsonb_build_object('id',n.id,'name',n.name)
   from my_derby.trainer_contracts c join my_derby.npc_trainers n on n.id=c.trainer_id
   where c.horse_id=v_h.id and c.status='ACTIVE'
   order by c.start_game_day desc,c.id desc limit 1),
  'source',CASE WHEN v_p.source_hr_no IS NULL THEN NULL ELSE jsonb_build_object(
    'meet',v_p.source_meet,'horseNo',v_p.source_hr_no,'horseName',v_p.horse_name,
    'country',v_p.country,
    'fatherName',v_p.father_name,'fatherNo',v_p.father_no,
    'motherName',v_p.mother_name,'motherNo',v_p.mother_no,
    'ownerName',v_p.owner_name,'trainerName',v_p.trainer_name,
    'career',jsonb_build_object('starts',v_p.starts_total,
      'wins',v_p.wins_total,'second',v_p.seconds_total,'third',v_p.thirds_total),
    'recentYear',jsonb_build_object('starts',v_p.starts_year,
      'wins',v_p.wins_year,'second',v_p.seconds_year,'third',v_p.thirds_year),
    'sourceLabel','USER_CSV_QUERY_56','yearBasis','USER_PROVIDED_ONE_YEAR_SNAPSHOT'
   ) END,
  'game',jsonb_build_object('career',v_game_total,'recentYear',v_game_year,
   'yearBasis','LAST_364_GAME_DAYS','recordsAvailable',v_h.id IS NOT NULL)
 );
END $function$

REVOKE ALL ON FUNCTION my_derby.world_horse_profile(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.world_horse_profile(uuid,text,text) TO anon,authenticated;
NOTIFY pgrst, 'reload schema';
