-- If a player completed the tutorial Grade 6 entry before the story trigger
-- advanced their stage, repair the story and award the next tutorial starter.
DO $repair$
DECLARE
  v_player record;
BEGIN
  FOR v_player IN
    SELECT t.user_id,p.world_id,p.starting_region
    FROM my_derby.player_tutorial_progress t
    JOIN my_derby.profiles p ON p.user_id=t.user_id AND p.initial_setup_complete
    WHERE t.story_stage=1
      AND EXISTS (
        SELECT 1
        FROM my_derby.horses h
        JOIN my_derby.race_entries e ON e.horse_id=h.id
        WHERE h.owner_user_id=t.user_id
          AND h.tutorial_starter_type='GRADE6'
          AND e.owner_user_id=t.user_id
          AND e.status IN ('CONFIRMED','COMPLETED')
      )
    ORDER BY t.updated_at,t.user_id
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM my_derby.horses h
      WHERE h.owner_user_id=v_player.user_id
        AND h.tutorial_starter_type='US_GRADE4'
    ) THEN
      PERFORM my_derby_private.create_tutorial_starter(
        v_player.user_id,v_player.world_id,'US_GRADE4',v_player.starting_region);
    END IF;
    UPDATE my_derby.player_tutorial_progress
    SET story_stage=2,completed=false,updated_at=now()
    WHERE user_id=v_player.user_id AND story_stage=1;
  END LOOP;
END
$repair$;
