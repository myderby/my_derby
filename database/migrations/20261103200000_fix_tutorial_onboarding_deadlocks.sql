-- Treat the first accepted ranch course for the tutorial's young starter as
-- completion of the first story action. This prevents an accidental default
-- course choice from leaving the player unable to progress.
CREATE OR REPLACE FUNCTION my_derby_private.award_tutorial_grade6_after_course()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_world uuid;
  v_horse uuid;
BEGIN
  IF NEW.status<>'ACTIVE' THEN RETURN NEW; END IF;
  IF NOT EXISTS(SELECT 1 FROM my_derby.horses h
    WHERE h.id=NEW.horse_id AND h.owner_user_id=NEW.owner_user_id
      AND h.tutorial_starter_type='YOUNG') THEN RETURN NEW; END IF;

  SELECT p.world_id INTO v_world FROM my_derby.profiles p
    WHERE p.user_id=NEW.owner_user_id AND p.initial_setup_complete;
  IF v_world IS NULL THEN RETURN NEW; END IF;
  IF NOT EXISTS(SELECT 1 FROM my_derby.player_tutorial_progress t
    WHERE t.user_id=NEW.owner_user_id AND t.story_stage=0) THEN RETURN NEW; END IF;

  SELECT h.id INTO v_horse
  FROM my_derby.horses h
  WHERE h.world_id=v_world AND h.owner_user_id IS NULL AND h.npc_owner_id IS NULL
    AND h.source_model_version='kra_v1' AND h.life_stage='RACING'
    AND h.racing_retired_permanently=false AND h.breeding_retired_at IS NULL
    AND h.age_years=3 AND h.source_grade_no=6
  ORDER BY h.id LIMIT 1 FOR UPDATE OF h;
  -- Keep the ranch request committed if the finite starter pool is depleted.
  -- A later valid tutorial-course request can retry the award.
  IF v_horse IS NULL THEN RETURN NEW; END IF;

  UPDATE my_derby.horses SET owner_user_id=NEW.owner_user_id,
    location='NPC_STABLE',tutorial_starter_type='GRADE6',tutorial_entry_fee_waived=true
    WHERE id=v_horse;
  UPDATE my_derby.player_tutorial_progress SET story_stage=1,completed=false,updated_at=now()
    WHERE user_id=NEW.owner_user_id AND story_stage=0;
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION my_derby_private.award_tutorial_grade6_after_course() FROM PUBLIC,anon,authenticated;

-- Repair players who already started any ranch course with their tutorial
-- young horse before this migration was applied.
DO $backfill$
DECLARE
  v_user uuid;
  v_world uuid;
  v_horse uuid;
BEGIN
  FOR v_user,v_world IN
    SELECT t.user_id,p.world_id
    FROM my_derby.player_tutorial_progress t
    JOIN my_derby.profiles p ON p.user_id=t.user_id AND p.initial_setup_complete
    JOIN my_derby.horses y ON y.owner_user_id=t.user_id AND y.tutorial_starter_type='YOUNG'
    JOIN my_derby.ranch_course_requests c ON c.owner_user_id=t.user_id AND c.horse_id=y.id
      AND c.status IN ('ACTIVE','DONE')
    WHERE t.story_stage=0
    GROUP BY t.user_id,p.world_id
  LOOP
    SELECT h.id INTO v_horse
    FROM my_derby.horses h
    WHERE h.world_id=v_world AND h.owner_user_id IS NULL AND h.npc_owner_id IS NULL
      AND h.source_model_version='kra_v1' AND h.life_stage='RACING'
      AND h.racing_retired_permanently=false AND h.breeding_retired_at IS NULL
      AND h.age_years=3 AND h.source_grade_no=6
    ORDER BY h.id LIMIT 1 FOR UPDATE OF h;
    IF v_horse IS NOT NULL THEN
      UPDATE my_derby.horses SET owner_user_id=v_user,location='NPC_STABLE',
        tutorial_starter_type='GRADE6',tutorial_entry_fee_waived=true
        WHERE id=v_horse;
      UPDATE my_derby.player_tutorial_progress SET story_stage=1,completed=false,updated_at=now()
        WHERE user_id=v_user AND story_stage=0;
    END IF;
  END LOOP;
END
$backfill$;

NOTIFY pgrst,'reload schema';
