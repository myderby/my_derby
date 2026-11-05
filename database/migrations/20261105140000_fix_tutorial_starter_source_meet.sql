DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
  v_old_map text;
  v_new_map text;
  v_old_insert text;
  v_new_insert text;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'my_derby_private.create_tutorial_starter(uuid,uuid,text,text)'::regprocedure
  ) INTO v_definition;

  v_old := '  v_meet text;';
  v_new := E'  v_meet text;\n  v_source_meet text;';
  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely locate tutorial starter meet variable';
  END IF;
  v_definition := replace(v_definition,v_old,v_new);

  v_old_map := $old$  v_meet:=CASE p_starting_region
    WHEN 'SEOUL' THEN '서울' WHEN 'BUSAN' THEN '부산경남' ELSE '영천' END;$old$;
  v_new_map := $new$  v_meet:=CASE p_starting_region
    WHEN 'SEOUL' THEN '서울' WHEN 'BUSAN' THEN '부산경남' ELSE '영천' END;
  v_source_meet:=CASE p_starting_region WHEN 'SEOUL' THEN '서울' ELSE '영남' END;$new$;
  IF position(v_old_map IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely locate tutorial starter meet mapping';
  END IF;
  v_definition := replace(v_definition,v_old_map,v_new_map);

  v_old_insert := $old$    v_meet,v_source_hr_no,v_id,v_name,v_grade::text||'등급',$old$;
  v_new_insert := $new$    v_source_meet,v_source_hr_no,v_id,v_name,v_grade::text||'등급',$new$;
  IF position(v_old_insert IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely locate tutorial source profile insert';
  END IF;
  v_definition := replace(v_definition,v_old_insert,v_new_insert);

  EXECUTE v_definition;
END;
$migration$;
