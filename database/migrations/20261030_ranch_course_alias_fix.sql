CREATE OR REPLACE FUNCTION my_derby_private.finish_due_ranch_courses()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE rec record;h my_derby.horses%rowtype;
 a my_derby.horse_abilities%rowtype;v_stats jsonb;v_k text;v_curr numeric;v_lim numeric;
 v_gain numeric;v_n int:=0;v_end int;
BEGIN
 FOR rec IN SELECT cr.*,r.owner_user_id pr_owner,horse.world_id
  FROM my_derby.ranch_course_requests cr
  JOIN my_derby.ranches r ON r.id=cr.ranch_id
  JOIN my_derby.horses horse ON horse.id=cr.horse_id
  JOIN my_derby.worlds w ON w.id=horse.world_id
  WHERE cr.status='ACTIVE' AND w.status='ACTIVE'
   AND cr.end_game_day<=(my_derby.world_clock(w.id)->>'gameDayStart')::int+6
  ORDER BY cr.end_game_day,cr.id FOR UPDATE OF cr SKIP LOCKED
 LOOP
  SELECT * INTO h FROM my_derby.horses WHERE id=rec.horse_id FOR UPDATE;
  IF NOT FOUND OR h.owner_user_id IS DISTINCT FROM rec.owner_user_id THEN CONTINUE;END IF;
  IF rec.course_type='REST_3D' THEN
   UPDATE my_derby.horses SET fatigue=greatest(0,fatigue-25),
      condition_score=least(100,condition_score+12) WHERE id=h.id;
  ELSIF rec.course_type='RECOVERY_7D' THEN
   UPDATE my_derby.horses SET fatigue=greatest(0,fatigue-45),
     condition_score=least(100,condition_score+20) WHERE id=h.id;
  ELSIF rec.course_type='REHAB' THEN
   UPDATE my_derby.horses SET fatigue=greatest(0,fatigue-15),
     condition_score=least(100,condition_score+18),
     health_state=CASE WHEN health_state='INJURED' THEN 'RECOVERING' ELSE health_state END
     WHERE id=h.id;
  ELSIF rec.course_type='YOUNG_BASIC' THEN
   SELECT * INTO a FROM my_derby.horse_abilities WHERE horse_id=h.id FOR UPDATE;
   IF FOUND THEN
    v_stats:=a.current_stats;
    FOREACH v_k IN ARRAY ARRAY['stability','recovery','stamina'] LOOP
     v_curr:=coalesce((v_stats->>v_k)::numeric,0);
     v_lim:=coalesce((a.potential_stats->>v_k)::numeric,v_curr);
     v_gain:=CASE WHEN v_k='stamina' THEN 1 ELSE 2 END;
     v_stats:=jsonb_set(v_stats,ARRAY[v_k],
       to_jsonb(least(v_lim,v_curr+v_gain)),true);
    END LOOP;
    UPDATE my_derby.horse_abilities SET current_stats=v_stats,updated_at=now()
      WHERE horse_id=h.id;
   END IF;
  END IF;
  UPDATE my_derby.ranch_course_requests SET status='DONE' WHERE id=rec.id;
  INSERT INTO my_derby.horse_state_history(horse_id,game_day,event_code,old_state,new_state)
   VALUES(h.id,rec.end_game_day,'RANCH_COURSE_COMPLETED',
    jsonb_build_object('fatigue',h.fatigue,'condition',h.condition_score,'health',h.health_state),
    jsonb_build_object('course',rec.course_type,'completed',true));
  v_n:=v_n+1;
 END LOOP;
 RETURN jsonb_build_object('status','OK','completedCourses',v_n);
END $fn$;