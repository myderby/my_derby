-- A player horse must have an active trainer contract before entering a race.
DO $patch$
DECLARE
  v_definition text;
  v_anchor text := ' -- Ordinary racing: exact grade. OPEN/special: verified source ageCond.';
  v_insert text := $insert$ IF NOT EXISTS (
   SELECT 1
   FROM my_derby.trainer_contracts tc
   JOIN my_derby.npc_trainers nt ON nt.id=tc.trainer_id AND nt.is_active
   WHERE tc.horse_id=v_h.id AND tc.status='ACTIVE'
 ) THEN
  RAISE EXCEPTION 'TRAINER_REQUIRED';
 END IF;
 -- Ordinary racing: exact grade. OPEN/special: verified source ageCond.$insert$;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'my_derby.apply_player_race_entry(uuid,uuid)'::regprocedure
  ) INTO v_definition;
  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'apply_player_race_entry was not found';
  END IF;
  IF position('TRAINER_REQUIRED' IN v_definition)>0 THEN
    RETURN;
  END IF;
  IF position(v_anchor IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely add active trainer requirement';
  END IF;
  v_definition:=replace(v_definition,v_anchor,v_insert);
  EXECUTE v_definition;
END;
$patch$;
