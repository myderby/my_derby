-- Player ranch expansion, facilities and staffing with audited game-money costs.
ALTER TABLE my_derby.ranches ADD COLUMN IF NOT EXISTS level integer NOT NULL DEFAULT 1;
ALTER TABLE my_derby.ranches DROP CONSTRAINT IF EXISTS ranch_level_limit;
ALTER TABLE my_derby.ranches ADD CONSTRAINT ranch_level_limit CHECK(level BETWEEN 1 AND 10);
CREATE TABLE IF NOT EXISTS my_derby.ranch_management_events(
 request_id uuid PRIMARY KEY,
 owner_user_id uuid NOT NULL REFERENCES auth.users(id),
 ranch_id uuid NOT NULL REFERENCES my_derby.ranches(id),
 game_day integer NOT NULL,
 operation text NOT NULL CHECK(operation IN
 ('EXPAND','UPGRADE_FACILITY','HIRE_STAFF','FIRE_STAFF','HIRE_VET','FIRE_VET')),
 facility_id uuid REFERENCES my_derby.ranch_facilities(id),
 amount bigint NOT NULL DEFAULT 0,
 new_level integer,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE my_derby.ranch_management_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.ranch_management_events FROM anon,authenticated;
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
   'horses',(SELECT count(*) FROM my_derby.horses h
       WHERE h.owner_user_id=u AND h.location='OWNER_RANCH'),
   'staff',r.staff_count,'vets',r.veterinarian_count,
   'staffMax',10+r.level*5,'vetMax',3+r.level*2,
   'prices',jsonb_build_object('expand',100000*r.level*r.level,
    'hireStaff',5000,'hireVet',15000),
   'facilities',coalesce((SELECT jsonb_agg(jsonb_build_object(
       'id',f.id,'type',f.facility_type,'level',f.level,'capacity',f.capacity,
       'upgradePrice',(CASE f.facility_type
        WHEN 'PASTURE' THEN 80000 WHEN 'RECOVERY_STABLE' THEN 100000
        WHEN 'REHAB_TRACK' THEN 140000 WHEN 'VET_CLINIC' THEN 180000
        ELSE 90000 END)*(f.level+1)*(f.level+1)) ORDER BY f.facility_type)
      FROM my_derby.ranch_facilities f WHERE f.ranch_id=r.id),'[]'::jsonb),
   'pricesProvisional',true);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_ranch_manage(
 p_operation text,p_request_id uuid,p_facility uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();r my_derby.ranches%rowtype;f my_derby.ranch_facilities%rowtype;
 w uuid;v_day int;v_price bigint:=0;v_new_lvl integer;
 v_fac uuid;v_prev uuid;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'REQUEST_ID_REQUIRED';END IF;
 SELECT world_id INTO w FROM my_derby.profiles
 WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST';END IF;
 SELECT * INTO r FROM my_derby.ranches WHERE owner_user_id=u FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RANCH_NOT_FOUND';END IF;
 IF EXISTS(SELECT 1 FROM my_derby.ranch_management_events
    WHERE request_id=p_request_id AND owner_user_id=u)
 THEN RETURN jsonb_build_object('status','ALREADY_APPLIED');END IF;
 v_day:=(my_derby.world_clock(w)->>'gameDayStart')::int;
 IF p_operation='EXPAND' THEN
  IF r.level>=10 THEN RAISE EXCEPTION 'RANCH_AT_MAX_LEVEL';END IF;
  v_price:=100000*r.level*r.level;v_new_lvl:=r.level+1;
 ELSIF p_operation='UPGRADE_FACILITY' THEN
  SELECT * INTO f FROM my_derby.ranch_facilities
    WHERE id=p_facility AND ranch_id=r.id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_YOUR_FACILITY';END IF;
  IF f.level>=10 THEN RAISE EXCEPTION 'FACILITY_AT_MAX_LEVEL';END IF;
  v_price:=(CASE f.facility_type WHEN 'PASTURE' THEN 80000
    WHEN 'RECOVERY_STABLE' THEN 100000 WHEN 'REHAB_TRACK' THEN 140000
    WHEN 'VET_CLINIC' THEN 180000 ELSE 90000 END)*(f.level+1)*(f.level+1);
  v_new_lvl:=f.level+1;v_fac:=f.id;
 ELSIF p_operation='HIRE_STAFF' THEN
  IF r.staff_count>=10+r.level*5 THEN RAISE EXCEPTION 'STAFF_CAPACITY_REACHED';END IF;
  v_price:=5000;
 ELSIF p_operation='HIRE_VET' THEN
  IF r.veterinarian_count>=3+r.level*2 THEN RAISE EXCEPTION 'VET_CAPACITY_REACHED';END IF;
  v_price:=15000;
 ELSIF p_operation='FIRE_STAFF' THEN
  IF r.staff_count<=0 THEN RAISE EXCEPTION 'NO_STAFF_TO_FIRE';END IF;
 ELSIF p_operation='FIRE_VET' THEN
  IF r.veterinarian_count<=0 THEN RAISE EXCEPTION 'NO_VET_TO_FIRE';END IF;
 ELSE RAISE EXCEPTION 'RANCH_OPERATION_INVALID';END IF;
 IF v_price>0 THEN
  PERFORM my_derby_private.wallet_mutate(u,w,v_day,-v_price,
   'RANCH_MANAGEMENT','RANCH_MANAGEMENT',p_request_id);
 END IF;
 IF p_operation='EXPAND' THEN
  UPDATE my_derby.ranches SET level=v_new_lvl WHERE id=r.id;
 ELSIF p_operation='UPGRADE_FACILITY' THEN
  UPDATE my_derby.ranch_facilities SET level=v_new_lvl,capacity=capacity+2
   WHERE id=v_fac;
 ELSIF p_operation='HIRE_STAFF' THEN
  UPDATE my_derby.ranches SET staff_count=staff_count+1 WHERE id=r.id;
 ELSIF p_operation='HIRE_VET' THEN
  UPDATE my_derby.ranches SET veterinarian_count=veterinarian_count+1 WHERE id=r.id;
 ELSIF p_operation='FIRE_STAFF' THEN
  UPDATE my_derby.ranches SET staff_count=staff_count-1 WHERE id=r.id;
 ELSIF p_operation='FIRE_VET' THEN
  UPDATE my_derby.ranches SET veterinarian_count=veterinarian_count-1 WHERE id=r.id;
 END IF;
 INSERT INTO my_derby.ranch_management_events(request_id,owner_user_id,ranch_id,
   game_day,operation,facility_id,amount,new_level)
 VALUES(p_request_id,u,r.id,v_day,p_operation,v_fac,v_price,v_new_lvl);
 RETURN jsonb_build_object('status','APPLIED','operation',p_operation,
   'paid',v_price,'newLevel',v_new_lvl,'pricesProvisional',true);
END $fn$;
REVOKE ALL ON FUNCTION my_derby.player_ranch_management_board() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_ranch_manage(text,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_ranch_management_board() TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_ranch_manage(text,uuid,uuid) TO authenticated;
