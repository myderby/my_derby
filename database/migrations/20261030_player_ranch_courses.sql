
-- Personal ranch core: paid courses, real recovery and young-horse foundation.
CREATE OR REPLACE FUNCTION my_derby.player_ranch_board()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid; c jsonb; v_ranch jsonb;v_horses jsonb;v_courses jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 c:=my_derby.world_clock(w);
 SELECT jsonb_build_object('id',r.id,'name',r.name,'staff',r.staff_count,
  'veterinarians',r.veterinarian_count,
  'facilities',coalesce((SELECT jsonb_agg(jsonb_build_object(
   'id',f.id,'type',f.facility_type,'level',f.level,'capacity',f.capacity) ORDER BY f.facility_type)
   FROM my_derby.ranch_facilities f WHERE f.ranch_id=r.id),'[]'::jsonb))
 INTO v_ranch FROM my_derby.ranches r WHERE r.owner_user_id=u;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',h.id,'name',h.name,'age',h.age_years,
   'stage',h.life_stage,'health',h.health_state,'fatigue',h.fatigue,
   'condition',h.condition_score,'grade',h.source_grade_no,'location',h.location)
   ORDER BY h.name),'[]'::jsonb) INTO v_horses
 FROM my_derby.horses h WHERE h.world_id=w AND h.owner_user_id=u;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',cr.id,'horseId',cr.horse_id,
   'horseName',h.name,'courseType',cr.course_type,'status',cr.status,
   'startDay',cr.start_game_day,'endDay',cr.end_game_day)
 ORDER BY cr.start_game_day DESC),'[]'::jsonb) INTO v_courses
 FROM my_derby.ranch_course_requests cr JOIN my_derby.horses h ON h.id=cr.horse_id
 WHERE cr.owner_user_id=u AND cr.status IN ('ACTIVE','DONE') AND
  cr.start_game_day>=(c->>'gameDayStart')::int-35;
 RETURN jsonb_build_object('world',c,'ranch',v_ranch,'horses',v_horses,
  'courses',v_courses,'balance',my_derby_private.wallet_initialise(u,w,(c->>'gameDayStart')::int));
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_ranch_apply(
 p_horse uuid,p_course text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();h my_derby.horses%rowtype;
 ranch my_derby.ranches%rowtype;f my_derby.ranch_facilities%rowtype;
 v_course_type text;v_days int; v_price bigint;v_factor numeric;
 v_day int;v_cost bigint; v_id uuid; v_world uuid;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO v_world FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF v_world IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse AND world_id=v_world FOR UPDATE;
 IF NOT FOUND OR h.owner_user_id IS DISTINCT FROM u THEN RAISE EXCEPTION 'NOT_YOUR_HORSE' USING ERRCODE='42501'; END IF;
 SELECT * INTO ranch FROM my_derby.ranches WHERE owner_user_id=u FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RANCH_NOT_AVAILABLE';END IF;
 v_course_type:=CASE p_course WHEN 'REST_3D' THEN 'PASTURE'
 WHEN 'RECOVERY_7D' THEN 'RECOVERY_STABLE' WHEN 'REHAB' THEN 'REHAB_TRACK'
 WHEN 'YOUNG_BASIC' THEN 'YOUNG_HORSE_AREA' ELSE null END;
 IF v_course_type IS NULL THEN RAISE EXCEPTION 'UNKNOWN_RANCH_COURSE';END IF;
 v_days:=CASE p_course WHEN 'REST_3D' THEN 3 ELSE 7 END;
 v_price:=CASE p_course WHEN 'REST_3D' THEN 5000 WHEN 'RECOVERY_7D' THEN 5000
 WHEN 'REHAB' THEN 20000 ELSE 10000 END;
 IF h.sale_state<>'NOT_LISTED' OR h.life_stage='DECEASED'
 OR h.injury_prognosis='RACING_UNFIT' THEN RAISE EXCEPTION 'HORSE_NOT_RANCH_ELIGIBLE'; END IF;
 IF (p_course='YOUNG_BASIC' AND h.age_years>1) OR
    (p_course<>'YOUNG_BASIC' AND h.age_years<2)
 THEN RAISE EXCEPTION 'RANCH_COURSE_AGE_MISMATCH'; END IF;
 IF p_course='REHAB' AND h.health_state='HEALTHY' THEN
  RAISE EXCEPTION 'REHAB_REQUIRES_INJURY';END IF;
 IF EXISTS(SELECT 1 FROM my_derby.ranch_course_requests c
  WHERE c.horse_id=h.id AND c.status='ACTIVE') THEN RAISE EXCEPTION 'RANCH_COURSE_ALREADY_ACTIVE';END IF;
 v_day:=(my_derby.world_clock(v_world)->>'gameDayStart')::int;
 IF EXISTS(SELECT 1 FROM my_derby.race_entries e
  JOIN my_derby.races r ON r.id=e.race_id
  WHERE e.horse_id=h.id AND e.status IN ('APPLIED','CONFIRMED')
    AND r.status IN('OPEN','CLOSED','RUNNING')
    AND r.race_day BETWEEN v_day AND v_day+v_days-1)
 THEN RAISE EXCEPTION 'RANCH_RACE_CONFLICT';END IF;
 SELECT * INTO f FROM my_derby.ranch_facilities
  WHERE ranch_id=ranch.id AND facility_type=v_course_type FOR UPDATE;
 IF NOT FOUND OR f.capacity<1 THEN RAISE EXCEPTION 'RANCH_FACILITY_NOT_READY';END IF;
 IF (SELECT count(*) FROM my_derby.ranch_course_requests c
  WHERE c.ranch_id=ranch.id AND c.status='ACTIVE'
   AND c.course_type=p_course)>=f.capacity THEN
  RAISE EXCEPTION 'RANCH_FACILITY_FULL';END IF;
 v_factor:=CASE h.source_grade_no WHEN 5 THEN 1.2 WHEN 4 THEN 1.5 WHEN 3 THEN 2.0
 WHEN 2 THEN 2.8 WHEN 1 THEN 4.0 ELSE 1 END;
 v_cost:=round(v_price*v_factor*v_days)::bigint;
 INSERT INTO my_derby.ranch_course_requests(ranch_id,horse_id,owner_user_id,
  course_type,status,start_game_day,end_game_day)
 VALUES(ranch.id,h.id,u,p_course,'ACTIVE',v_day,v_day+v_days-1)
 RETURNING id INTO v_id;
 PERFORM my_derby_private.wallet_mutate(u,v_world,v_day,-v_cost,
  'RANCH_COURSE_FEE','RANCH_COURSE',v_id);
 UPDATE my_derby.horses SET location='OWNER_RANCH' WHERE id=h.id;
 RETURN jsonb_build_object('status','ACTIVE','courseId',v_id,
  'horseId',h.id,'startGameDay',v_day,'endGameDay',v_day+v_days-1,'fee',v_cost);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.finish_due_ranch_courses()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE rec record;h my_derby.horses%rowtype;
 a my_derby.horse_abilities%rowtype;v_stats jsonb;v_k text;v_curr numeric;v_lim numeric;
 v_gain numeric;v_n int:=0;v_end int;
BEGIN
 FOR rec IN SELECT cr.*,r.owner_user_id pr_owner,h.world_id
  FROM my_derby.ranch_course_requests cr
  JOIN my_derby.ranches r ON r.id=cr.ranch_id
  JOIN my_derby.horses h ON h.id=cr.horse_id
  JOIN my_derby.worlds w ON w.id=h.world_id
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
REVOKE ALL ON FUNCTION my_derby.player_ranch_board() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_ranch_apply(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.finish_due_ranch_courses() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_ranch_board() TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_ranch_apply(uuid,text) TO authenticated;
SELECT cron.schedule('my-derby-ranch-courses','50 13 * * *',
 'select my_derby_private.finish_due_ranch_courses();');
