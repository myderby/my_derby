-- Show only current active source-file jockeys after 89-row roster restriction.
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
 WHERE j.world_id=v_world AND j.is_active AND (v_search IS NULL OR coalesce(j.display_name,j.name) ILIKE '%'||v_search||'%')
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
  WHERE j.world_id=v_world AND j.is_active
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
