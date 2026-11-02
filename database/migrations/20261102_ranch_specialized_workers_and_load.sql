-- Ranch worker specialities, candidate hiring, manual facility assignment, and staffing-load effects.
ALTER TABLE my_derby.ranch_workers
  ADD COLUMN IF NOT EXISTS specialty text NOT NULL DEFAULT 'PASTURE_CARETAKER',
  ADD COLUMN IF NOT EXISTS assigned_facility_id uuid;

ALTER TABLE my_derby.ranch_workers DROP CONSTRAINT IF EXISTS ranch_workers_specialty_check;
ALTER TABLE my_derby.ranch_workers ADD CONSTRAINT ranch_workers_specialty_check
 CHECK (specialty = ANY (ARRAY[
  'PASTURE_CARETAKER','RECOVERY_CARETAKER','REHAB_CARETAKER','VET','YOUNG_HORSE_CARETAKER'
 ]));
ALTER TABLE my_derby.ranch_workers DROP CONSTRAINT IF EXISTS ranch_workers_assigned_facility_id_fkey;
ALTER TABLE my_derby.ranch_workers ADD CONSTRAINT ranch_workers_assigned_facility_id_fkey
 FOREIGN KEY (assigned_facility_id) REFERENCES my_derby.ranch_facilities(id) ON DELETE SET NULL;
ALTER TABLE my_derby.ranch_workers DROP CONSTRAINT IF EXISTS ranch_workers_assignment_role_check;
ALTER TABLE my_derby.ranch_workers ADD CONSTRAINT ranch_workers_assignment_role_check
 CHECK (role = 'VET' AND specialty = 'VET' OR role = 'CARETAKER' AND specialty <> 'VET');

WITH ranked AS (
 SELECT id, row_number() OVER (PARTITION BY ranch_id ORDER BY
   CASE grade WHEN 'S' THEN 0 WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END, id) AS rn
 FROM my_derby.ranch_workers WHERE role='CARETAKER'
)
UPDATE my_derby.ranch_workers rw SET specialty=CASE ranked.rn
 WHEN 1 THEN 'PASTURE_CARETAKER' WHEN 2 THEN 'RECOVERY_CARETAKER'
 WHEN 3 THEN 'REHAB_CARETAKER' WHEN 4 THEN 'YOUNG_HORSE_CARETAKER'
 ELSE 'PASTURE_CARETAKER' END
FROM ranked WHERE ranked.id=rw.id;
UPDATE my_derby.ranch_workers SET specialty='VET' WHERE role='VET';

UPDATE my_derby.ranch_facilities
 SET capacity=2 + greatest(level-1,0)*2
 WHERE capacity IS DISTINCT FROM 2 + greatest(level-1,0)*2;

CREATE OR REPLACE FUNCTION my_derby.create_initial_ranch_facilities()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $fn$
BEGIN
 INSERT INTO my_derby.ranch_facilities(ranch_id,facility_type,level,capacity)
 SELECT NEW.id,facility_type,1,2
 FROM unnest(ARRAY['PASTURE','RECOVERY_STABLE','REHAB_TRACK','VET_CLINIC','YOUNG_HORSE_AREA']) facility_type
 ON CONFLICT(ranch_id,facility_type) DO NOTHING;
 RETURN NEW;
END
$fn$;

CREATE TABLE IF NOT EXISTS my_derby.ranch_worker_candidates(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ranch_id uuid NOT NULL REFERENCES my_derby.ranches(id) ON DELETE CASCADE,
 specialty text NOT NULL CHECK (specialty = ANY (ARRAY[
  'PASTURE_CARETAKER','RECOVERY_CARETAKER','REHAB_CARETAKER','VET','YOUNG_HORSE_CARETAKER'
 ])),
 name text NOT NULL,
 grade text NOT NULL CHECK (grade = ANY (ARRAY['C','B','A','S'])),
 skills jsonb NOT NULL DEFAULT '{}'::jsonb,
 salary_per_game_day integer NOT NULL CHECK (salary_per_game_day > 0),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ranch_worker_candidates_ranch_specialty_idx
 ON my_derby.ranch_worker_candidates(ranch_id,specialty,created_at);
ALTER TABLE my_derby.ranch_worker_candidates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.ranch_worker_candidates FROM anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_ranch_worker_candidates(p_specialty text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();v_ranch uuid;v_count int;v_id uuid;v_score int;
 v_grade text;v_bonus int;v_label text;v_salary int;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 IF p_specialty NOT IN ('PASTURE_CARETAKER','RECOVERY_CARETAKER','REHAB_CARETAKER','VET','YOUNG_HORSE_CARETAKER')
 THEN RAISE EXCEPTION 'INVALID_WORKER_SPECIALTY';END IF;
 SELECT id INTO v_ranch FROM my_derby.ranches WHERE owner_user_id=u FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RANCH_NOT_FOUND';END IF;
 SELECT count(*) INTO v_count FROM my_derby.ranch_worker_candidates
  WHERE ranch_id=v_ranch AND specialty=p_specialty;
 IF v_count<>3 THEN
  DELETE FROM my_derby.ranch_worker_candidates WHERE ranch_id=v_ranch AND specialty=p_specialty;
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
 END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'specialty',specialty,
  'name',name,'grade',grade,'skills',skills,'salary',salary_per_game_day)
  ORDER BY CASE grade WHEN 'S' THEN 0 WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END,id)
  FROM my_derby.ranch_worker_candidates
  WHERE ranch_id=v_ranch AND specialty=p_specialty),'[]'::jsonb);
END
$fn$;

CREATE OR REPLACE FUNCTION my_derby.player_ranch_management_board()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();r my_derby.ranches%rowtype;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT * INTO r FROM my_derby.ranches WHERE owner_user_id=u;
 IF NOT FOUND THEN RAISE EXCEPTION 'RANCH_NOT_FOUND';END IF;
 RETURN jsonb_build_object('ranchId',r.id,'name',r.name,'level',r.level,
  'horseCapacity',8+(r.level-1)*4,
  'horses',(SELECT count(*) FROM my_derby.horses h WHERE h.owner_user_id=u AND h.location='OWNER_RANCH'),
  'staff',r.staff_count,'vets',r.veterinarian_count,
  'staffMax',10+r.level*5,'vetMax',3+r.level*2,
  'workers',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'id',rw.id,'name',rw.name,'role',rw.role,'specialty',rw.specialty,
    'assignedFacilityId',rw.assigned_facility_id,'grade',rw.grade,
    'skills',rw.skills,'salary',rw.salary_per_game_day,'active',rw.is_active)
    ORDER BY rw.specialty,CASE rw.grade WHEN 'S' THEN 0 WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END,rw.name)
    FROM my_derby.ranch_workers rw WHERE rw.ranch_id=r.id AND rw.is_active),'[]'::jsonb),
  'prices',jsonb_build_object('expand',100000*r.level*r.level,'hireStaff',5000,'hireVet',15000),
  'facilities',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'id',f.id,'type',f.facility_type,'level',f.level,'capacity',f.capacity,
    'upgradePrice',(CASE f.facility_type WHEN 'PASTURE' THEN 80000
      WHEN 'RECOVERY_STABLE' THEN 100000 WHEN 'REHAB_TRACK' THEN 140000
      WHEN 'VET_CLINIC' THEN 180000 ELSE 90000 END)*(f.level+1)*(f.level+1))
    ORDER BY f.facility_type) FROM my_derby.ranch_facilities f WHERE f.ranch_id=r.id),'[]'::jsonb),
  'pricesProvisional',true);
END
$fn$;

CREATE OR REPLACE FUNCTION my_derby.player_ranch_worker_manage(
 p_action text,p_request_id uuid,p_candidate_id uuid DEFAULT NULL,
 p_worker_id uuid DEFAULT NULL,p_facility_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();r my_derby.ranches%rowtype;w my_derby.ranch_workers%rowtype;
 c my_derby.ranch_worker_candidates%rowtype;f my_derby.ranch_facilities%rowtype;
 v_world uuid;v_day int;v_price bigint:=0;v_operation text;v_role text;
 v_expected_facility text;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO v_world FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF v_world IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 SELECT * INTO r FROM my_derby.ranches WHERE owner_user_id=u FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RANCH_NOT_FOUND';END IF;
 v_day:=(my_derby.world_clock(v_world)->>'gameDayStart')::int;
 IF p_action IN ('HIRE_WORKER','FIRE_WORKER') THEN
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'REQUEST_ID_REQUIRED';END IF;
  IF EXISTS(SELECT 1 FROM my_derby.ranch_management_events
    WHERE request_id=p_request_id AND owner_user_id=u)
  THEN RETURN jsonb_build_object('status','ALREADY_APPLIED');END IF;
 END IF;
 IF p_action='HIRE_WORKER' THEN
  SELECT * INTO c FROM my_derby.ranch_worker_candidates
   WHERE id=p_candidate_id AND ranch_id=r.id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WORKER_CANDIDATE_EXPIRED';END IF;
  v_role:=CASE WHEN c.specialty='VET' THEN 'VET' ELSE 'CARETAKER' END;
  IF (v_role='VET' AND r.veterinarian_count>=3+r.level*2)
    OR (v_role='CARETAKER' AND r.staff_count>=10+r.level*5)
  THEN RAISE EXCEPTION 'STAFF_CAPACITY_REACHED';END IF;
  v_price:=CASE WHEN v_role='VET' THEN 15000 ELSE 5000 END;
  PERFORM my_derby_private.wallet_mutate(u,v_world,v_day,-v_price,
   'RANCH_MANAGEMENT','RANCH_MANAGEMENT',p_request_id);
  INSERT INTO my_derby.ranch_workers(ranch_id,role,specialty,name,grade,skills,
    salary_per_game_day,is_active)
  VALUES(r.id,v_role,c.specialty,c.name,c.grade,c.skills,c.salary_per_game_day,true)
  RETURNING * INTO w;
  DELETE FROM my_derby.ranch_worker_candidates WHERE id=c.id;
  IF v_role='VET' THEN
   UPDATE my_derby.ranches SET veterinarian_count=veterinarian_count+1 WHERE id=r.id;
   v_operation:='HIRE_VET';
  ELSE
   UPDATE my_derby.ranches SET staff_count=staff_count+1 WHERE id=r.id;
   v_operation:='HIRE_STAFF';
  END IF;
  INSERT INTO my_derby.ranch_management_events(request_id,owner_user_id,ranch_id,
   game_day,operation,amount)
  VALUES(p_request_id,u,r.id,v_day,v_operation,v_price);
  RETURN jsonb_build_object('status','APPLIED','workerId',w.id,'paid',v_price);
 ELSIF p_action='FIRE_WORKER' THEN
  SELECT * INTO w FROM my_derby.ranch_workers
   WHERE id=p_worker_id AND ranch_id=r.id AND is_active FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WORKER_NOT_FOUND';END IF;
  UPDATE my_derby.ranch_workers SET is_active=false,assigned_facility_id=NULL WHERE id=w.id;
  IF w.role='VET' THEN
   UPDATE my_derby.ranches SET veterinarian_count=greatest(0,veterinarian_count-1) WHERE id=r.id;
   v_operation:='FIRE_VET';
  ELSE
   UPDATE my_derby.ranches SET staff_count=greatest(0,staff_count-1) WHERE id=r.id;
   v_operation:='FIRE_STAFF';
  END IF;
  INSERT INTO my_derby.ranch_management_events(request_id,owner_user_id,ranch_id,
   game_day,operation,amount)
  VALUES(p_request_id,u,r.id,v_day,v_operation,0);
  RETURN jsonb_build_object('status','APPLIED','workerId',w.id);
 ELSIF p_action='ASSIGN_WORKER' THEN
  SELECT * INTO w FROM my_derby.ranch_workers
   WHERE id=p_worker_id AND ranch_id=r.id AND is_active FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'WORKER_NOT_FOUND';END IF;
  IF p_facility_id IS NULL THEN
   UPDATE my_derby.ranch_workers SET assigned_facility_id=NULL WHERE id=w.id;
   RETURN jsonb_build_object('status','APPLIED','workerId',w.id,'facilityId',NULL);
  END IF;
  SELECT * INTO f FROM my_derby.ranch_facilities
   WHERE id=p_facility_id AND ranch_id=r.id;
  IF NOT FOUND THEN RAISE EXCEPTION 'FACILITY_NOT_FOUND';END IF;
  v_expected_facility:=CASE w.specialty
   WHEN 'PASTURE_CARETAKER' THEN 'PASTURE'
   WHEN 'RECOVERY_CARETAKER' THEN 'RECOVERY_STABLE'
   WHEN 'REHAB_CARETAKER' THEN 'REHAB_TRACK'
   WHEN 'VET' THEN 'VET_CLINIC'
   WHEN 'YOUNG_HORSE_CARETAKER' THEN 'YOUNG_HORSE_AREA' END;
  IF f.facility_type<>v_expected_facility THEN RAISE EXCEPTION 'FACILITY_SPECIALTY_MISMATCH';END IF;
  UPDATE my_derby.ranch_workers SET assigned_facility_id=f.id WHERE id=w.id;
  RETURN jsonb_build_object('status','APPLIED','workerId',w.id,'facilityId',f.id);
 ELSE
  RAISE EXCEPTION 'INVALID_WORKER_ACTION';
 END IF;
END
$fn$;

CREATE OR REPLACE FUNCTION my_derby_private.finish_due_ranch_courses()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE rec record;h my_derby.horses%rowtype;a my_derby.horse_abilities%rowtype;
 v_stats jsonb;v_k text;v_curr numeric;v_lim numeric;v_gain numeric;
 v_n int:=0;v_boost numeric;v_skill text;v_worker_count int;v_horse_count int;
 v_effective_skill numeric;
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
  v_skill:=CASE rec.course_type WHEN 'REHAB' THEN 'medical'
    WHEN 'YOUNG_BASIC' THEN 'growth' ELSE 'care' END;
  SELECT count(*) INTO v_horse_count FROM my_derby.horses
   WHERE owner_user_id=rec.owner_user_id AND location='OWNER_RANCH';
  SELECT count(*),avg((rw.skills->>v_skill)::numeric)
   INTO v_worker_count,v_effective_skill
  FROM my_derby.ranch_workers rw
  JOIN my_derby.ranch_facilities f ON f.id=rw.assigned_facility_id
  WHERE rw.ranch_id=rec.ranch_id AND rw.is_active
   AND (
    (rec.course_type='REST_3D' AND rw.specialty='PASTURE_CARETAKER' AND f.facility_type='PASTURE')
    OR (rec.course_type='RECOVERY_7D' AND rw.specialty='RECOVERY_CARETAKER' AND f.facility_type='RECOVERY_STABLE')
    OR (rec.course_type='REHAB' AND (
       (rw.specialty='REHAB_CARETAKER' AND f.facility_type='REHAB_TRACK')
       OR (rw.specialty='VET' AND f.facility_type='VET_CLINIC')))
    OR (rec.course_type='YOUNG_BASIC' AND rw.specialty='YOUNG_HORSE_CARETAKER' AND f.facility_type='YOUNG_HORSE_AREA')
   );
  IF v_worker_count=0 THEN
   v_boost:=1;
  ELSE
   v_effective_skill:=greatest(0,coalesce(v_effective_skill,50)
    - greatest(0,v_horse_count-(2*v_worker_count))*5);
   v_boost:=1+least(0.15,greatest(0,v_effective_skill-50)/300);
  END IF;
  IF rec.course_type='REST_3D' THEN
   UPDATE my_derby.horses SET fatigue=greatest(0,fatigue-25*v_boost),
     condition_score=least(100,condition_score+12*v_boost) WHERE id=h.id;
  ELSIF rec.course_type='RECOVERY_7D' THEN
   UPDATE my_derby.horses SET fatigue=greatest(0,fatigue-45*v_boost),
     condition_score=least(100,condition_score+20*v_boost) WHERE id=h.id;
  ELSIF rec.course_type='REHAB' THEN
   UPDATE my_derby.horses SET fatigue=greatest(0,fatigue-15*v_boost),
     condition_score=least(100,condition_score+18*v_boost),
     health_state=CASE WHEN health_state='INJURED' THEN 'RECOVERING' ELSE health_state END
    WHERE id=h.id;
  ELSIF rec.course_type='YOUNG_BASIC' THEN
   SELECT * INTO a FROM my_derby.horse_abilities WHERE horse_id=h.id FOR UPDATE;
   IF FOUND THEN
    v_stats:=a.current_stats;
    FOREACH v_k IN ARRAY ARRAY['stability','recovery','stamina'] LOOP
     v_curr:=coalesce((v_stats->>v_k)::numeric,0);
     v_lim:=coalesce((a.potential_stats->>v_k)::numeric,v_curr);
     v_gain:=(CASE WHEN v_k='stamina' THEN 1 ELSE 2 END)*v_boost;
     v_stats:=jsonb_set(v_stats,ARRAY[v_k],to_jsonb(least(v_lim,v_curr+v_gain)),true);
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
END
$fn$;

REVOKE ALL ON FUNCTION my_derby.player_ranch_worker_candidates(text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_ranch_worker_manage(text,uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_ranch_management_board() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.finish_due_ranch_courses() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_ranch_worker_candidates(text) TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_ranch_worker_manage(text,uuid,uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_ranch_management_board() TO authenticated;
