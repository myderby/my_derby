-- Keep horses currently assigned to an active personal-ranch course out of
-- the entry board and reject stale/direct entry requests for those horses.
DO $patch$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  v_definition := pg_catalog.pg_get_functiondef(
    'my_derby.player_race_board(integer)'::regprocedure
  );

  v_old := $old$      r.class_name,r.prize_policy->>'source_rc_name',r.prize_policy->>'ageCond',h.birth_hemisphere)
  ),'[]'::jsonb),$old$;
  v_new := $new$      r.class_name,r.prize_policy->>'source_rc_name',r.prize_policy->>'ageCond',h.birth_hemisphere)
      AND NOT EXISTS (
        SELECT 1 FROM my_derby.ranch_course_requests rc
        WHERE rc.horse_id=h.id AND rc.owner_user_id=v_user AND rc.status='ACTIVE'
      )
  ),'[]'::jsonb),$new$;
  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not patch race-board eligible horse list';
  END IF;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := 'FROM my_derby.horses h WHERE h.world_id=v_world AND h.owner_user_id=v_user;';
  v_new := 'FROM my_derby.horses h WHERE h.world_id=v_world AND h.owner_user_id=v_user'
    || E'\n' || ' AND NOT EXISTS (SELECT 1 FROM my_derby.ranch_course_requests rc'
    || E'\n' || '  WHERE rc.horse_id=h.id AND rc.owner_user_id=v_user AND rc.status=''ACTIVE'');';
  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not patch race-board horse details';
  END IF;
  v_definition := replace(v_definition,v_old,v_new);
  EXECUTE v_definition;

  v_definition := pg_catalog.pg_get_functiondef(
    'my_derby.apply_player_race_entry(uuid,uuid)'::regprocedure
  );
  v_old := ' IF NOT FOUND OR v_h.owner_user_id IS DISTINCT FROM v_user THEN RAISE EXCEPTION ''NOT_YOUR_HORSE'' USING ERRCODE=''42501''; END IF;';
  v_new := v_old || E'\n' ||
    ' IF EXISTS (SELECT 1 FROM my_derby.ranch_course_requests rc' || E'\n' ||
    '   WHERE rc.horse_id=v_h.id AND rc.owner_user_id=v_user AND rc.status=''ACTIVE'') THEN' || E'\n' ||
    '  RAISE EXCEPTION ''HORSE_IN_PERSONAL_RANCH'';' || E'\n' ||
    ' END IF;';
  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not patch race-entry ranch eligibility';
  END IF;
  v_definition := replace(v_definition,v_old,v_new);
  EXECUTE v_definition;
END;
$patch$;

NOTIFY pgrst,'reload schema';
