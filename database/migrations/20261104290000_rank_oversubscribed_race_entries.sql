-- When a race with at least 12 places is oversubscribed, rank player
-- applications by lifetime prize money, rating, then fewer completed starts.
CREATE OR REPLACE FUNCTION my_derby_private.player_race_entry_better(
  p_candidate_horse_id uuid,
  p_incumbent_horse_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
WITH score AS (
  SELECT h.id,
    coalesce(sum(rr.prize_amount) FILTER (WHERE race.id IS NOT NULL),0)::bigint AS earnings,
    coalesce(h.domestic_rating,0)::integer AS rating,
    count(rr.id) FILTER (WHERE race.id IS NOT NULL)::bigint AS starts
  FROM my_derby.horses h
  LEFT JOIN my_derby.race_results rr ON rr.horse_id=h.id
  LEFT JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
  LEFT JOIN my_derby.races race ON race.id=run.race_id AND race.world_id=h.world_id
  WHERE h.id IN (p_candidate_horse_id,p_incumbent_horse_id)
  GROUP BY h.id,h.domestic_rating
)
SELECT candidate.earnings > incumbent.earnings
  OR (candidate.earnings = incumbent.earnings AND candidate.rating > incumbent.rating)
  OR (candidate.earnings = incumbent.earnings AND candidate.rating = incumbent.rating
      AND candidate.starts < incumbent.starts)
  OR (candidate.earnings = incumbent.earnings AND candidate.rating = incumbent.rating
      AND candidate.starts = incumbent.starts AND candidate.id < incumbent.id)
FROM score candidate
JOIN score incumbent ON incumbent.id=p_incumbent_horse_id
WHERE candidate.id=p_candidate_horse_id;
$function$;

REVOKE ALL ON FUNCTION my_derby_private.player_race_entry_better(uuid,uuid)
  FROM PUBLIC,anon,authenticated;

DO $patch$
DECLARE
  v_definition text;
  v_old text := '  IF NOT FOUND THEN RAISE EXCEPTION ''RACE_FULL_NO_NPC_SLOT''; END IF;';
  v_new text := $replacement$  IF NOT FOUND THEN
    -- Keep the scheduled field size; performance selection applies to
    -- oversubscribed races whose configured capacity is 12 or more.
    IF v_r.target_runner_count < 12 THEN
      RAISE EXCEPTION 'RACE_FULL_NO_NPC_SLOT';
    END IF;
    SELECT e.* INTO v_entry
    FROM my_derby.race_entries e
    WHERE e.race_id=p_race_id AND e.status='CONFIRMED'
      AND e.owner_user_id IS NOT NULL
      AND e.snapshot->>'entry_source'='PLAYER_APPLICATION_V1'
    ORDER BY
      coalesce((SELECT sum(rr.prize_amount)::bigint
        FROM my_derby.race_results rr
        JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
        JOIN my_derby.races race ON race.id=run.race_id AND race.world_id=v_world
        WHERE rr.horse_id=e.horse_id),0) ASC,
      coalesce((SELECT h.domestic_rating FROM my_derby.horses h
        WHERE h.id=e.horse_id),0) ASC,
      (SELECT count(*) FROM my_derby.race_results rr
        JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
        JOIN my_derby.races race ON race.id=run.race_id AND race.world_id=v_world
        WHERE rr.horse_id=e.horse_id) DESC,
      e.horse_id DESC
    LIMIT 1 FOR UPDATE;
    IF NOT FOUND OR NOT my_derby_private.player_race_entry_better(p_horse_id,v_entry.horse_id) THEN
      RAISE EXCEPTION 'RACE_ENTRY_NOT_SELECTED';
    END IF;
  END IF;$replacement$;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'my_derby.apply_player_race_entry(uuid,uuid)'::regprocedure
  ) INTO v_definition;
  IF v_definition IS NULL OR position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely patch apply_player_race_entry selection block';
  END IF;
  v_definition:=replace(v_definition,v_old,v_new);
  v_definition:=replace(v_definition,'''originalNpcHorseId'',v_entry.horse_id',
    '''replacedHorseId'',v_entry.horse_id');
  EXECUTE v_definition;
END;
$patch$;
