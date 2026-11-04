CREATE OR REPLACE FUNCTION my_derby.player_upcoming_race_news()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH upcoming AS (
    SELECT r.id AS race_id,
      e.horse_id,
      h.name AS horse_name,
      r.track,
      r.race_no,
      r.prize_policy->>'kst_date' AS race_date,
      to_char(r.start_time,'HH24:MI') AS start_time,
      r.class_name,
      r.distance_m,
      e.gate_no,
      e.status AS entry_status,
      e.jockey_id,
      coalesce(nullif(j.display_name,''),j.name,'미배정') AS jockey_name,
      trainer.trainer_name
    FROM my_derby.race_entries e
    JOIN my_derby.races r ON r.id=e.race_id
    JOIN my_derby.horses h ON h.id=e.horse_id
    LEFT JOIN my_derby.npc_jockeys j ON j.id=e.jockey_id
    LEFT JOIN LATERAL (
      SELECT n.name AS trainer_name
      FROM my_derby.trainer_contracts tc
      JOIN my_derby.npc_trainers n ON n.id=tc.trainer_id
      JOIN my_derby.npc_stables st ON st.id=n.stable_id
      WHERE tc.horse_id=e.horse_id
        AND tc.start_game_day<=r.race_day
        AND (tc.end_game_day IS NULL OR tc.end_game_day>=r.race_day)
        AND st.track=r.track
      ORDER BY tc.start_game_day DESC,tc.id DESC
      LIMIT 1
    ) trainer ON TRUE
    WHERE auth.uid() IS NOT NULL
      AND e.owner_user_id=auth.uid()
      AND e.status IN ('APPLIED','CONFIRMED')
      AND r.status IN ('OPEN','CLOSED','RUNNING')
      AND r.world_id=(SELECT p.world_id FROM my_derby.profiles p WHERE p.user_id=auth.uid())
      AND nullif(r.prize_policy->>'kst_date','')::date >= (now() at time zone 'Asia/Seoul')::date
    ORDER BY r.prize_policy->>'kst_date',r.start_time,r.track,r.race_no,e.gate_no
    LIMIT 50
  )
  SELECT coalesce(jsonb_agg(to_jsonb(upcoming)
    ORDER BY upcoming.race_date,upcoming.start_time,upcoming.track,upcoming.race_no,upcoming.gate_no),'[]'::jsonb)
  FROM upcoming;
$function$;

REVOKE ALL ON FUNCTION my_derby.player_upcoming_race_news() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_upcoming_race_news() TO authenticated;
NOTIFY pgrst,'reload schema';
