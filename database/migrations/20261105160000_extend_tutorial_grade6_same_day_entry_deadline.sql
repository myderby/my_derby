-- Keep the first-time tutorial Grade 6 exception open until 18:00 KST.
DO $migration$
DECLARE
  v_definition text;
  v_before text := $old$IF v_now::time >= time '08:00' THEN$old$;
  v_after text := $new$IF v_now::time >= time '18:00' THEN$new$;
BEGIN
  SELECT pg_get_functiondef('my_derby.apply_player_race_entry(uuid,uuid)'::regprocedure)
    INTO v_definition;
  IF position(v_before in v_definition)=0 THEN
    RAISE EXCEPTION 'Could not locate tutorial same-day entry deadline';
  END IF;
  EXECUTE replace(v_definition,v_before,v_after);
END
$migration$;
