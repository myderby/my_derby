
-- Game-wide horse information page, with separate source historical records
-- and actual My Derby official-game records. No made-up source results.
CREATE OR REPLACE FUNCTION my_derby.world_horse_profile(
 p_horse_id uuid DEFAULT NULL,
 p_source_meet text DEFAULT NULL,
 p_source_hr_no text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_h my_derby.horses%rowtype;v_p my_derby.horse_source_profiles%rowtype;
 v_ability jsonb;v_day integer;v_world uuid;v_game_total jsonb;v_game_year jsonb;
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
  SELECT jsonb_build_object('current',current_stats,'distanceAffinity',distance_affinity)
    INTO v_ability FROM my_derby.horse_abilities WHERE horse_id=v_h.id;
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
  'abilities',coalesce(v_ability,'{}'::jsonb),
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
END $fn$;

-- Source-first directory: all 4,060 rows including horses that have no
-- fictional player/NPC owner or estimated game skills yet.
CREATE OR REPLACE FUNCTION my_derby.world_uploaded_horse_directory(
 p_search text DEFAULT NULL,p_track text DEFAULT NULL,
 p_grade integer DEFAULT NULL,p_sex text DEFAULT NULL,
 p_page integer DEFAULT 1,p_page_size integer DEFAULT 24,
 p_sort text DEFAULT 'name'
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_search text:=nullif(trim(coalesce(p_search,'')),'');
 v_track text:=nullif(p_track,'');v_sex text:=nullif(p_sex,'');
 v_page int:=coalesce(p_page,1);v_size int:=coalesce(p_page_size,24);
 v_sort text:=coalesce(p_sort,'name');v_total int;v_items jsonb;
BEGIN
 IF v_page NOT BETWEEN 1 AND 10000 OR v_size NOT BETWEEN 1 AND 50
 OR length(coalesce(v_search,''))>50
 OR v_sort NOT IN ('name','rating','age','grade','wins','starts')
 OR (p_grade IS NOT NULL AND p_grade NOT BETWEEN 1 AND 6)
 OR (v_track IS NOT NULL AND v_track NOT IN('서울','부산','영천'))
 OR (v_sex IS NOT NULL AND v_sex NOT IN('MALE','FEMALE','GELDING'))
 THEN RAISE EXCEPTION 'DIRECTORY_FILTER_INVALID';END IF;
 WITH filtered AS(
  SELECT p.*,h.age_years,h.sex,h.domestic_rating,h.source_grade_no,h.life_stage,
   h.rating_pending_grade,h.rating_derived_grade,
   CASE p.source_meet WHEN '영남' THEN '부산'
   WHEN '제주' THEN '영천' ELSE '서울' END track,
   CASE p.source_sex WHEN '수' THEN 'MALE' WHEN '암' THEN 'FEMALE'
   WHEN '거' THEN 'GELDING' END normalized_sex,
   substring(p.source_rank from '[1-6]')::integer source_grade
  FROM my_derby.horse_source_profiles p
  LEFT JOIN my_derby.horses h ON h.id=p.horse_id
 )
 SELECT count(*) INTO v_total FROM filtered p
 WHERE (v_search IS NULL OR p.horse_name ILIKE '%'||v_search||'%'
  OR p.source_hr_no ILIKE '%'||v_search||'%')
 AND (v_track IS NULL OR p.track=v_track)
 AND (p_grade IS NULL OR coalesce(p.source_grade_no,p.source_grade)=p_grade)
 AND (v_sex IS NULL OR p.normalized_sex=v_sex);
 WITH filtered AS(
  SELECT p.*,h.age_years,h.sex,h.domestic_rating,h.source_grade_no,h.life_stage,
   h.rating_pending_grade,h.rating_derived_grade,
   CASE p.source_meet WHEN '영남' THEN '부산'
   WHEN '제주' THEN '영천' ELSE '서울' END track,
   CASE p.source_sex WHEN '수' THEN 'MALE' WHEN '암' THEN 'FEMALE'
   WHEN '거' THEN 'GELDING' END normalized_sex,
   substring(p.source_rank from '[1-6]')::integer source_grade
  FROM my_derby.horse_source_profiles p
  LEFT JOIN my_derby.horses h ON h.id=p.horse_id
 ), paged AS(
  SELECT * FROM filtered p
  WHERE (v_search IS NULL OR p.horse_name ILIKE '%'||v_search||'%'
   OR p.source_hr_no ILIKE '%'||v_search||'%')
  AND (v_track IS NULL OR p.track=v_track)
  AND (p_grade IS NULL OR coalesce(p.source_grade_no,p.source_grade)=p_grade)
  AND (v_sex IS NULL OR p.normalized_sex=v_sex)
  ORDER BY CASE WHEN v_sort='name' THEN p.horse_name END ASC,
   CASE WHEN v_sort='rating' THEN p.domestic_rating END DESC NULLS LAST,
   CASE WHEN v_sort='age' THEN p.age_years END DESC NULLS LAST,
   CASE WHEN v_sort='grade' THEN coalesce(p.source_grade_no,p.source_grade) END ASC NULLS LAST,
   CASE WHEN v_sort='wins' THEN p.wins_total END DESC,
   CASE WHEN v_sort='starts' THEN p.starts_total END DESC,
   p.horse_name,p.source_hr_no,p.source_meet
  LIMIT v_size OFFSET(v_page-1)*v_size
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',coalesce(p.horse_id::text,p.source_meet||':'||p.source_hr_no),
  'gameHorseId',p.horse_id,'name',p.horse_name,
  'horseNo',p.source_hr_no,'sourceMeet',p.source_meet,'track',p.track,
  'grade',coalesce(p.source_grade_no,p.source_grade),
  'sourceRank',p.source_rank,'rating',p.domestic_rating,
  'age',p.age_years,'birthDate',p.birth_date,'sex',p.normalized_sex,
  'stage',coalesce(p.life_stage,'SOURCE_ONLY'),
  'ratingPending',p.rating_pending_grade,
  'ratingProposedGrade',p.rating_derived_grade,
  'career',jsonb_build_object('starts',p.starts_total,'wins',p.wins_total,
    'second',p.seconds_total,'third',p.thirds_total),
  'recentYear',jsonb_build_object('starts',p.starts_year,'wins',p.wins_year,
    'second',p.seconds_year,'third',p.thirds_year),
  'gameLinked',p.horse_id IS NOT NULL,
  'sourceRecordCount',p.starts_total
 ) ORDER BY CASE WHEN v_sort='name' THEN p.horse_name END ASC,
  CASE WHEN v_sort='rating' THEN p.domestic_rating END DESC NULLS LAST,
  CASE WHEN v_sort='age' THEN p.age_years END DESC NULLS LAST,
  CASE WHEN v_sort='grade' THEN coalesce(p.source_grade_no,p.source_grade) END ASC NULLS LAST,
  CASE WHEN v_sort='wins' THEN p.wins_total END DESC,
  CASE WHEN v_sort='starts' THEN p.starts_total END DESC,
  p.horse_name,p.source_hr_no,p.source_meet),'[]'::jsonb)
 INTO v_items FROM paged p;
 RETURN jsonb_build_object('page',v_page,'pageSize',v_size,
  'total',v_total,'pages',ceil(v_total::numeric/v_size)::integer,
  'recordBasis','USER_CSV_QUERY_56','yearBasis','USER_PROVIDED_ONE_YEAR_SNAPSHOT',
  'items',v_items);
END $fn$;
REVOKE ALL ON FUNCTION my_derby.world_horse_profile(uuid,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.world_uploaded_horse_directory(text,text,integer,text,integer,integer,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.world_horse_profile(uuid,text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.world_uploaded_horse_directory(text,text,integer,text,integer,integer,text)
 TO anon,authenticated;
