-- Return the latest official start and the next registered race for each owned horse.
CREATE OR REPLACE FUNCTION my_derby.player_horse_race_schedule()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid:=auth.uid();
  v_horses jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTHENTICATION_REQUIRED'; END IF;

  SELECT coalesce(jsonb_object_agg(h.id::text,jsonb_build_object(
    'lastStart',last_start.info,
    'nextStart',next_start.info
  )),'{}'::jsonb)
  INTO v_horses
  FROM my_derby.horses h
  LEFT JOIN LATERAL (
    SELECT jsonb_build_object(
      'date',r.prize_policy->>'kst_date',
      'gameDay',r.race_day,
      'track',r.track,
      'raceNo',r.race_no,
      'distanceM',r.distance_m,
      'className',r.class_name,
      'rank',rr.finishing_rank
    ) AS info
    FROM my_derby.race_results rr
    JOIN my_derby.race_runs run
      ON run.id=rr.race_run_id
     AND run.status='FINISHED'
     AND run.result_applied_at IS NOT NULL
    JOIN my_derby.races r
      ON r.id=run.race_id
     AND r.world_id=h.world_id
     AND r.status='FINISHED'
    WHERE rr.horse_id=h.id
    ORDER BY run.result_applied_at DESC,run.id DESC
    LIMIT 1
  ) last_start ON true
  LEFT JOIN LATERAL (
    SELECT jsonb_build_object(
      'date',r.prize_policy->>'kst_date',
      'gameDay',r.race_day,
      'track',r.track,
      'raceNo',r.race_no,
      'distanceM',r.distance_m,
      'className',r.class_name,
      'entryStatus',e.status
    ) AS info
    FROM my_derby.race_entries e
    JOIN my_derby.races r
      ON r.id=e.race_id
     AND r.world_id=h.world_id
    WHERE e.horse_id=h.id
      AND e.owner_user_id=v_user
      AND e.status IN ('APPLIED','CONFIRMED')
      AND r.status IN ('OPEN','CLOSED','RUNNING')
      AND r.race_day >= coalesce(
        (my_derby.world_clock(h.world_id)->>'gameDayStart')::integer,1)
    ORDER BY r.race_day,r.start_time,r.id
    LIMIT 1
  ) next_start ON true
  WHERE h.owner_user_id=v_user;

  RETURN jsonb_build_object('horses',v_horses);
END
$function$;

REVOKE ALL ON FUNCTION my_derby.player_horse_race_schedule() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_horse_race_schedule() TO authenticated;
NOTIFY pgrst,'reload schema';
