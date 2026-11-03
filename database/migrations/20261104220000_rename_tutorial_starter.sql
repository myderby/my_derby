CREATE OR REPLACE FUNCTION my_derby.rename_tutorial_starter(
  p_horse_id uuid,
  p_name text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_user uuid:=auth.uid();
  v_world uuid;
  v_stage integer;
  v_horse my_derby.horses%rowtype;
  v_expected_type text;
  v_name text:=btrim(coalesce(p_name,''));
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING errcode='42501'; END IF;
  IF p_horse_id IS NULL OR char_length(v_name)<2 OR char_length(v_name)>20
    OR v_name ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'INVALID_HORSE_NAME' USING errcode='22023';
  END IF;

  SELECT p.world_id INTO v_world FROM my_derby.profiles p
    WHERE p.user_id=v_user AND p.initial_setup_complete FOR UPDATE;
  IF v_world IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING errcode='42501'; END IF;
  SELECT t.story_stage INTO v_stage FROM my_derby.player_tutorial_progress t
    WHERE t.user_id=v_user FOR UPDATE;
  v_expected_type:=CASE v_stage WHEN 0 THEN 'YOUNG' WHEN 1 THEN 'GRADE6'
    WHEN 2 THEN 'US_GRADE4' ELSE NULL END;
  IF v_expected_type IS NULL THEN RAISE EXCEPTION 'TUTORIAL_RENAME_NOT_AVAILABLE'; END IF;

  SELECT * INTO v_horse FROM my_derby.horses h
    WHERE h.id=p_horse_id AND h.world_id=v_world AND h.owner_user_id=v_user
      AND h.tutorial_starter_type=v_expected_type FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TUTORIAL_RENAME_NOT_AVAILABLE'; END IF;
  IF EXISTS(SELECT 1 FROM my_derby.horses h WHERE h.world_id=v_world
    AND h.id<>p_horse_id AND h.name=v_name) THEN
    RAISE EXCEPTION 'TUTORIAL_HORSE_NAME_TAKEN' USING errcode='23505';
  END IF;

  UPDATE my_derby.horses SET name=v_name WHERE id=p_horse_id;
  UPDATE my_derby.horse_source_profiles SET horse_name=v_name WHERE horse_id=p_horse_id;
  RETURN jsonb_build_object('horseId',p_horse_id,'name',v_name);
END
$function$;
REVOKE ALL ON FUNCTION my_derby.rename_tutorial_starter(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION my_derby.rename_tutorial_starter(uuid,text) TO authenticated;

NOTIFY pgrst,'reload schema';
