-- Move only unstarted stage-zero accounts off the old shared-pool horse.
-- Accounts that raced, started a ranch course, or progressed further keep all
-- horse records and history unchanged.
DO $refresh$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT p.user_id,p.world_id,p.starting_region,y.id AS old_horse_id
    FROM my_derby.player_tutorial_progress t
    JOIN my_derby.profiles p ON p.user_id=t.user_id AND p.initial_setup_complete
    JOIN my_derby.horses y ON y.owner_user_id=p.user_id AND y.tutorial_starter_type='YOUNG'
    WHERE t.story_stage=0
      AND NOT EXISTS(SELECT 1 FROM my_derby.ranch_course_requests c
        WHERE c.owner_user_id=p.user_id AND c.horse_id=y.id)
      AND NOT EXISTS(SELECT 1 FROM my_derby.race_entries e
        WHERE e.owner_user_id=p.user_id AND e.horse_id=y.id)
  LOOP
    UPDATE my_derby.horses SET owner_user_id=NULL,location='NPC_STABLE',
      tutorial_starter_type=NULL,tutorial_entry_fee_waived=false
      WHERE id=r.old_horse_id AND owner_user_id=r.user_id;
    PERFORM my_derby_private.create_tutorial_starter(
      r.user_id,r.world_id,'YOUNG',r.starting_region);
  END LOOP;
END
$refresh$;
