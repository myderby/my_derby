-- Tutorial starters must arrive with an active trainer contract. Pick the
-- least-loaded active trainer at the horse's home track, preferring trainers
-- who still have capacity. A tutorial horse cannot be left without a trainer.
CREATE OR REPLACE FUNCTION my_derby_private.assign_tutorial_starter_trainer()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_track text;
  v_trainer_id uuid;
  v_game_day integer;
BEGIN
  IF NEW.owner_user_id IS NULL OR NEW.tutorial_starter_type IS NULL THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1 FROM my_derby.trainer_contracts c
    WHERE c.horse_id=NEW.id AND c.status='ACTIVE'
  ) THEN
    RETURN NEW;
  END IF;

  v_track:=CASE NEW.source_meet
    WHEN '부산경남' THEN '부산'
    WHEN '제주' THEN '영천'
    ELSE NEW.source_meet
  END;
  SELECT nt.id INTO v_trainer_id
  FROM my_derby.npc_trainers nt
  JOIN my_derby.npc_stables stable ON stable.id=nt.stable_id
  LEFT JOIN LATERAL (
    SELECT count(*)::integer AS horse_count
    FROM my_derby.trainer_contracts c
    WHERE c.trainer_id=nt.id AND c.status='ACTIVE'
  ) load ON true
  WHERE stable.world_id=NEW.world_id
    AND stable.track=v_track
    AND nt.is_active
  ORDER BY (load.horse_count>=nt.capacity),load.horse_count,nt.name,nt.id
  LIMIT 1
  FOR UPDATE OF nt SKIP LOCKED;

  IF v_trainer_id IS NULL THEN
    RAISE EXCEPTION 'TUTORIAL_TRAINER_UNAVAILABLE';
  END IF;
  v_game_day:=coalesce((my_derby.world_clock(NEW.world_id)->>'gameDayStart')::integer,1);
  INSERT INTO my_derby.trainer_contracts
    (horse_id,trainer_id,start_game_day,familiarity,status)
  VALUES(NEW.id,v_trainer_id,v_game_day,0,'ACTIVE');
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION my_derby_private.assign_tutorial_starter_trainer()
  FROM PUBLIC,anon,authenticated;

DO $trigger$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='my_derby.horses'::regclass
      AND t.tgname='trg_tutorial_horse_trainer_auto_assign'
      AND NOT t.tgisinternal
  ) THEN
    CREATE TRIGGER trg_tutorial_horse_trainer_auto_assign
    AFTER INSERT OR UPDATE OF owner_user_id,tutorial_starter_type ON my_derby.horses
    FOR EACH ROW EXECUTE FUNCTION my_derby_private.assign_tutorial_starter_trainer();
  END IF;
END
$trigger$;

-- Repair tutorial horses already issued before this automatic assignment was
-- enabled. The trigger performs the same per-horse least-loaded selection.
DO $backfill$
DECLARE
  v_horse record;
BEGIN
  FOR v_horse IN
    SELECT h.id
    FROM my_derby.horses h
    WHERE h.owner_user_id IS NOT NULL
      AND h.tutorial_starter_type IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM my_derby.trainer_contracts c
        WHERE c.horse_id=h.id AND c.status='ACTIVE'
      )
    ORDER BY h.created_at,h.id
  LOOP
    UPDATE my_derby.horses
    SET tutorial_starter_type=tutorial_starter_type
    WHERE id=v_horse.id;
  END LOOP;
END
$backfill$;

NOTIFY pgrst,'reload schema';
