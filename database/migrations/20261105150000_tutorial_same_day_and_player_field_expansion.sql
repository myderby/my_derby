-- Same-day Grade 6 entry is a first-time tutorial benefit. If a standard
-- 12-runner field has no NPC entries left to replace, player horses may fill
-- the remaining gates up to 16.
DO $migration$
DECLARE
  v_definition text;
  v_before text;
  v_after text;
BEGIN
  SELECT pg_get_functiondef('my_derby.apply_player_race_entry(uuid,uuid)'::regprocedure)
    INTO v_definition;

  v_before := $old$IF coalesce((v_r.prize_policy->>'grade_no')::integer,0)<>6
     OR my_derby_private.player_is_special_race(v_r.class_name,v_r.prize_policy->>'source_rc_name') THEN$old$;
  v_after := $new$IF coalesce((v_r.prize_policy->>'grade_no')::integer,0)<>6
     OR my_derby_private.player_is_special_race(v_r.class_name,v_r.prize_policy->>'source_rc_name')
     OR NOT EXISTS (
       SELECT 1 FROM my_derby.horses tutorial_horse
       WHERE tutorial_horse.id=p_horse_id
         AND tutorial_horse.owner_user_id=v_user
         AND tutorial_horse.tutorial_starter_type='GRADE6'
     ) THEN$new$;
  IF position(v_before in v_definition)=0 THEN
    RAISE EXCEPTION 'Could not locate same-day Grade 6 entry guard';
  END IF;
  v_definition := replace(v_definition,v_before,v_after);

  v_before := $old$SELECT count(*) INTO v_count FROM my_derby.race_entries
   WHERE race_id=p_race_id AND status IN ('APPLIED','CONFIRMED');
 IF v_count>=v_r.target_runner_count THEN$old$;
  v_after := $new$SELECT count(*) INTO v_count FROM my_derby.race_entries
   WHERE race_id=p_race_id AND status IN ('APPLIED','CONFIRMED');
 -- Extend only a standard field that is already full and contains no NPCs.
 IF v_r.target_runner_count=12 AND v_count>=12 AND v_count<16
    AND NOT EXISTS (
      SELECT 1 FROM my_derby.race_entries field_entry
      WHERE field_entry.race_id=p_race_id
        AND field_entry.status IN ('APPLIED','CONFIRMED')
        AND field_entry.owner_user_id IS NULL
    ) THEN
   v_r.target_runner_count := 16;
 END IF;
 IF v_count>=v_r.target_runner_count THEN$new$;
  IF position(v_before in v_definition)=0 THEN
    RAISE EXCEPTION 'Could not locate race field capacity guard';
  END IF;
  v_definition := replace(v_definition,v_before,v_after);
  EXECUTE v_definition;
END
$migration$;
