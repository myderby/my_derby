-- Expose only the My Derby race number in public race detail, retain source provenance in DB.
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
    'raceNo',r.race_no,
    'gameRaceNo',r.race_no,
    'raceDay',r.race_day,
    'kstDate',r.prize_policy->>'kst_date',
    'startTime',to_char(r.start_time,'HH24:MI'),
    'resultTime',r.prize_policy->>'result_kst_time',
    'targetRunnerCount',r.target_runner_count,
    'entryDeadline',to_char(r.entry_deadline,'HH24:MI'),
    'entries',runners
  );
END;
$function$;
