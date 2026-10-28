
-- MY DERBY: irreversible breeding retirement. Only for eligible owned horses.
-- Existing historical results are retained; no seasonal/history reset.

ALTER TABLE my_derby.horses
  ADD COLUMN IF NOT EXISTS breeding_retired_at timestamptz;

COMMENT ON COLUMN my_derby.horses.breeding_retired_at IS
  'Permanently records entering breeding career. Once non-null, never returns to racing.';

-- Backfill any pre-existing stallions/broodmares, including NPC horses.
UPDATE my_derby.horses SET breeding_retired_at = now()
WHERE life_stage IN ('STALLION','BROODMARE') AND breeding_retired_at IS NULL;

ALTER TABLE my_derby.horses
  DROP CONSTRAINT IF EXISTS breeding_retirement_no_racing;
ALTER TABLE my_derby.horses
  ADD CONSTRAINT breeding_retirement_no_racing
  CHECK (breeding_retired_at IS NULL OR life_stage NOT IN ('RACING','FOAL','YEARLING'));

CREATE OR REPLACE FUNCTION my_derby.enforce_breeding_career_lock()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.breeding_retired_at IS NOT NULL
     AND NEW.breeding_retired_at IS DISTINCT FROM OLD.breeding_retired_at THEN
    RAISE EXCEPTION 'BREEDING_RETIREMENT_PERMANENT: retirement marker cannot be changed'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.life_stage = 'STALLION' AND NEW.sex <> 'MALE' THEN
    RAISE EXCEPTION 'BREEDING_SEX_MISMATCH: stallion must be male' USING ERRCODE='23514';
  ELSIF NEW.life_stage = 'BROODMARE' AND NEW.sex <> 'FEMALE' THEN
    RAISE EXCEPTION 'BREEDING_SEX_MISMATCH: broodmare must be female' USING ERRCODE='23514';
  END IF;

  IF NEW.life_stage IN ('STALLION','BROODMARE') THEN
    IF NEW.breeding_retired_at IS NULL THEN
      NEW.breeding_retired_at := now();
    END IF;
    IF NEW.race_entry_state IN ('APPLIED','CONFIRMED') THEN
      RAISE EXCEPTION 'BREEDING_HORSE_ACTIVE_ENTRY: finish or withdraw race application before retirement'
        USING ERRCODE='23514';
    END IF;
  END IF;

  IF NEW.breeding_retired_at IS NOT NULL THEN
    IF NEW.life_stage IN ('RACING','FOAL','YEARLING') THEN
      RAISE EXCEPTION 'BREEDING_RETIREMENT_PERMANENT: racing return prohibited'
        USING ERRCODE='23514';
    END IF;
    IF NEW.race_entry_state IN ('APPLIED','CONFIRMED') THEN
      RAISE EXCEPTION 'BREEDING_RETIREMENT_PERMANENT: cannot register a breeding horse'
        USING ERRCODE='23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_breeding_career_lock ON my_derby.horses;
CREATE TRIGGER trg_enforce_breeding_career_lock
BEFORE INSERT OR UPDATE ON my_derby.horses
FOR EACH ROW EXECUTE FUNCTION my_derby.enforce_breeding_career_lock();

-- Reject direct inserts/updates of race_entries as well as application-layer requests.
CREATE OR REPLACE FUNCTION my_derby.check_breeding_retirement_race_entry()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE
  v_stage text;
  v_retired timestamptz;
BEGIN
  IF NEW.status IN ('APPLIED','CONFIRMED') THEN
    SELECT h.life_stage,h.breeding_retired_at INTO v_stage,v_retired
    FROM my_derby.horses h WHERE h.id=NEW.horse_id FOR SHARE;

    IF NOT FOUND OR v_retired IS NOT NULL OR v_stage <> 'RACING' THEN
      RAISE EXCEPTION 'NOT_RACING_ELIGIBLE: breeding/retired horses cannot enter races'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_breeding_retirement_race_entry ON my_derby.race_entries;
CREATE TRIGGER trg_breeding_retirement_race_entry
BEFORE INSERT OR UPDATE OF horse_id,status ON my_derby.race_entries
FOR EACH ROW EXECUTE FUNCTION my_derby.check_breeding_retirement_race_entry();

-- Direct breeding requests must require breeding retirement of BOTH parents.
CREATE OR REPLACE FUNCTION my_derby.check_retired_breeding_pair()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE
  v_mare my_derby.horses%ROWTYPE;
  v_sire my_derby.horses%ROWTYPE;
BEGIN
  IF NEW.mare_id = NEW.sire_id THEN
    RAISE EXCEPTION 'BREEDING_INVALID_PAIR: mare and sire must differ' USING ERRCODE='23514';
  END IF;

  SELECT * INTO v_mare FROM my_derby.horses WHERE id = NEW.mare_id FOR SHARE;
  SELECT * INTO v_sire FROM my_derby.horses WHERE id = NEW.sire_id FOR SHARE;

  IF v_mare.id IS NULL OR v_sire.id IS NULL
     OR v_mare.life_stage <> 'BROODMARE' OR v_mare.breeding_retired_at IS NULL
     OR v_sire.life_stage <> 'STALLION' OR v_sire.breeding_retired_at IS NULL
     OR v_mare.age_years NOT BETWEEN 4 AND 18
     OR v_mare.breeding_state <> 'AVAILABLE'
     OR v_sire.breeding_state <> 'AVAILABLE'
     OR v_mare.world_id <> v_sire.world_id THEN
    RAISE EXCEPTION 'BREEDING_ELIGIBILITY: both parents must be retired breeding horses'
      USING ERRCODE='23514';
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_breeding_retirement_pair ON my_derby.breeding_requests;
CREATE TRIGGER trg_breeding_retirement_pair
BEFORE INSERT OR UPDATE OF mare_id,sire_id ON my_derby.breeding_requests
FOR EACH ROW EXECUTE FUNCTION my_derby.check_retired_breeding_pair();

DROP POLICY IF EXISTS own_breeding_insert ON my_derby.breeding_requests;
CREATE POLICY own_breeding_insert ON my_derby.breeding_requests FOR INSERT TO authenticated
WITH CHECK (
  owner_user_id=(SELECT auth.uid())
  AND EXISTS (
    SELECT 1 FROM my_derby.horses h
    WHERE h.id=mare_id
      AND h.owner_user_id=(SELECT auth.uid())
      AND h.sex='FEMALE'
      AND h.life_stage='BROODMARE'
      AND h.breeding_retired_at IS NOT NULL
      AND h.age_years BETWEEN 4 AND 18
      AND h.breeding_state='AVAILABLE'
  )
  AND EXISTS (
    SELECT 1 FROM my_derby.horses h
    WHERE h.id=sire_id
      AND h.sex='MALE'
      AND h.life_stage='STALLION'
      AND h.breeding_retired_at IS NOT NULL
      AND h.breeding_state='AVAILABLE'
  )
);

-- Authorized user RPC, safe without a server-side secret. Does not allow arbitrary horse updates.
CREATE OR REPLACE FUNCTION my_derby.retire_horse_for_breeding(p_horse_id uuid)
RETURNS TABLE(horse_id uuid,life_stage text,breeding_retired_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_horse my_derby.horses%ROWTYPE;
  v_target text;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_horse FROM my_derby.horses
  WHERE id=p_horse_id AND owner_user_id=(SELECT auth.uid())
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'HORSE_NOT_OWNED' USING ERRCODE='42501';
  END IF;

  IF v_horse.breeding_retired_at IS NOT NULL THEN
    RAISE EXCEPTION 'ALREADY_PERMANENTLY_RETIRED' USING ERRCODE='23514';
  END IF;

  IF v_horse.sex = 'MALE' AND v_horse.age_years >= 2 THEN
    v_target := 'STALLION';
  ELSIF v_horse.sex = 'FEMALE' AND v_horse.age_years BETWEEN 4 AND 18 THEN
    v_target := 'BROODMARE';
  ELSE
    RAISE EXCEPTION 'BREEDING_AGE_OR_SEX_INELIGIBLE' USING ERRCODE='23514';
  END IF;

  IF v_horse.life_stage NOT IN ('RACING','RETIRED') THEN
    RAISE EXCEPTION 'NOT_READY_FOR_BREEDING_RETIREMENT' USING ERRCODE='23514';
  END IF;

  IF EXISTS (
    SELECT 1 FROM my_derby.race_entries e
    JOIN my_derby.races r ON r.id=e.race_id
    WHERE e.horse_id=p_horse_id
      AND e.status IN ('APPLIED','CONFIRMED')
      AND r.status IN ('OPEN','CLOSED','RUNNING')
  ) THEN
    RAISE EXCEPTION 'ACTIVE_RACE_ENTRY: withdraw from upcoming race before retiring'
      USING ERRCODE='23514';
  END IF;

  UPDATE my_derby.horses h SET
    life_stage=v_target,
    location='OWNER_RANCH',
    race_entry_state='NONE'
  WHERE h.id=p_horse_id
  RETURNING h.id,h.life_stage,h.breeding_retired_at
  INTO horse_id,life_stage,breeding_retired_at;

  RETURN NEXT;
END;
$$;
REVOKE ALL ON FUNCTION my_derby.retire_horse_for_breeding(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION my_derby.retire_horse_for_breeding(uuid) TO authenticated;

COMMENT ON FUNCTION my_derby.retire_horse_for_breeding(uuid) IS
  'Irreversible owner-authorized transition into STALLION/BROODMARE; return to racing forbidden.';

NOTIFY pgrst,'reload schema';
