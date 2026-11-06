-- Progress tutorial when a confirmed player Grade 6 starter replaces a confirmed NPC entry.
CREATE OR REPLACE FUNCTION my_derby_private.award_tutorial_foreign_horse_after_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_region text;
  v_world uuid;
BEGIN
  IF NEW.status<>'CONFIRMED' OR NEW.owner_user_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND OLD.status='CONFIRMED' AND OLD.owner_user_id IS NOT DISTINCT FROM NEW.owner_user_id AND OLD.horse_id=NEW.horse_id THEN RETURN NEW; END IF;
  SELECT p.world_id,p.starting_region INTO v_world,v_region FROM my_derby.profiles p
    WHERE p.user_id=NEW.owner_user_id AND p.initial_setup_complete;
  IF v_world IS NULL OR NOT EXISTS(SELECT 1 FROM my_derby.player_tutorial_progress t
    WHERE t.user_id=NEW.owner_user_id AND t.story_stage=1) THEN RETURN NEW; END IF;
  IF NOT EXISTS(SELECT 1 FROM my_derby.horses h WHERE h.id=NEW.horse_id
    AND h.owner_user_id=NEW.owner_user_id AND h.tutorial_starter_type='GRADE6') THEN RETURN NEW; END IF;

  PERFORM my_derby_private.create_tutorial_starter(
    NEW.owner_user_id,v_world,'US_GRADE4',v_region);
  UPDATE my_derby.player_tutorial_progress SET story_stage=2,completed=false,updated_at=now()
    WHERE user_id=NEW.owner_user_id AND story_stage=1;
  RETURN NEW;
END
$function$

