-- Generate three fresh worker candidates every time the hire list is opened.
CREATE OR REPLACE FUNCTION my_derby.player_ranch_worker_candidates(p_specialty text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE u uuid:=auth.uid();v_ranch uuid;v_count int;v_id uuid;v_score int;
 v_grade text;v_bonus int;v_label text;v_salary int;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 IF p_specialty NOT IN ('PASTURE_CARETAKER','RECOVERY_CARETAKER','REHAB_CARETAKER','VET','YOUNG_HORSE_CARETAKER')
 THEN RAISE EXCEPTION 'INVALID_WORKER_SPECIALTY';END IF;
 SELECT id INTO v_ranch FROM my_derby.ranches WHERE owner_user_id=u FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RANCH_NOT_FOUND';END IF;
 DELETE FROM my_derby.ranch_worker_candidates
  WHERE ranch_id=v_ranch AND specialty=p_specialty;
  v_label:=CASE p_specialty WHEN 'PASTURE_CARETAKER' THEN '방목지 관리사'
   WHEN 'RECOVERY_CARETAKER' THEN '회복 관리사' WHEN 'REHAB_CARETAKER' THEN '재활 관리사'
   WHEN 'VET' THEN '수의사' ELSE '육성 관리사' END;
  FOR v_count IN 1..3 LOOP
   v_id:=gen_random_uuid();v_score:=floor(random()*100)::int;
   v_grade:=CASE WHEN v_score<43 THEN 'C' WHEN v_score<77 THEN 'B'
    WHEN v_score<96 THEN 'A' ELSE 'S' END;
   v_bonus:=CASE v_grade WHEN 'S' THEN 38 WHEN 'A' THEN 25 WHEN 'B' THEN 12 ELSE 0 END;
   v_salary:=CASE v_grade WHEN 'S' THEN 2400 WHEN 'A' THEN 1600 WHEN 'B' THEN 1200 ELSE 1000 END;
   INSERT INTO my_derby.ranch_worker_candidates
    (id,ranch_id,specialty,name,grade,skills,salary_per_game_day)
   VALUES(v_id,v_ranch,p_specialty,v_label||' '||substr(replace(v_id::text,'-',''),1,4),
    v_grade,jsonb_build_object(
     'care',least(96,35+v_bonus+floor(random()*21)::int),
     'medical',least(96,35+v_bonus+floor(random()*21)::int),
     'growth',least(96,35+v_bonus+floor(random()*21)::int),
     'stability',least(96,35+v_bonus+floor(random()*21)::int)),v_salary);
  END LOOP;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'specialty',specialty,
  'name',name,'grade',grade,'skills',skills,'salary',salary_per_game_day)
  ORDER BY CASE grade WHEN 'S' THEN 0 WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END,id)
  FROM my_derby.ranch_worker_candidates
  WHERE ranch_id=v_ranch AND specialty=p_specialty),'[]'::jsonb);
END
$function$

