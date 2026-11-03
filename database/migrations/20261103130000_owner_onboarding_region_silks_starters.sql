-- Owner onboarding: region and silks customization, fixed starter package,
-- and C-grade initial ranch staff.

ALTER TABLE my_derby.profiles
  ADD COLUMN IF NOT EXISTS starting_region text,
  ADD COLUMN IF NOT EXISTS silks_design jsonb NOT NULL DEFAULT
    '{"bodyColor":"#D6A84F","sleeveColor":"#23180F","pattern":"solid","patternColor":"#FFFFFF"}'::jsonb;

ALTER TABLE my_derby.profiles DROP CONSTRAINT IF EXISTS profiles_starting_region_check;
ALTER TABLE my_derby.profiles ADD CONSTRAINT profiles_starting_region_check
  CHECK (starting_region IS NULL OR starting_region IN ('SEOUL','YEONGCHEON','BUSAN'));
ALTER TABLE my_derby.profiles DROP CONSTRAINT IF EXISTS profiles_silks_design_check;
ALTER TABLE my_derby.profiles ADD CONSTRAINT profiles_silks_design_check
  CHECK (
    jsonb_typeof(silks_design)='object'
    AND silks_design ?& ARRAY['bodyColor','sleeveColor','pattern','patternColor']
  );

DROP FUNCTION IF EXISTS my_derby.join_world(text);

CREATE OR REPLACE FUNCTION my_derby.join_world(
  p_nickname text,
  p_starting_region text,
  p_silks_design jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_world uuid;
  v_prev my_derby.profiles%rowtype;
  v_existing integer;
  v_assigned integer;
  v_ranch uuid;
  v_silks jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'LOGIN_REQUIRED' USING errcode='42501';
  END IF;
  IF p_nickname IS NULL OR char_length(btrim(p_nickname))<2 OR char_length(btrim(p_nickname))>32 THEN
    RAISE EXCEPTION 'NICKNAME_LENGTH_2_32' USING errcode='22023';
  END IF;
  IF p_starting_region IS NULL OR p_starting_region NOT IN ('SEOUL','YEONGCHEON','BUSAN') THEN
    RAISE EXCEPTION 'INVALID_STARTING_REGION' USING errcode='22023';
  END IF;
  IF jsonb_typeof(p_silks_design)<>'object'
    OR NOT (p_silks_design ?& ARRAY['bodyColor','sleeveColor','pattern','patternColor'])
    OR coalesce(p_silks_design->>'bodyColor','') !~ '^#[0-9A-Fa-f]{6}$'
    OR coalesce(p_silks_design->>'sleeveColor','') !~ '^#[0-9A-Fa-f]{6}$'
    OR coalesce(p_silks_design->>'patternColor','') !~ '^#[0-9A-Fa-f]{6}$'
    OR coalesce(p_silks_design->>'pattern','') NOT IN ('solid','stripe','check','diamond','dot','star') THEN
    RAISE EXCEPTION 'INVALID_SILKS_DESIGN' USING errcode='22023';
  END IF;
  v_silks := jsonb_build_object(
    'bodyColor',upper(p_silks_design->>'bodyColor'),
    'sleeveColor',upper(p_silks_design->>'sleeveColor'),
    'pattern',p_silks_design->>'pattern',
    'patternColor',upper(p_silks_design->>'patternColor')
  );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('myderby-world-join:'||v_uid::text,0)
  );
  SELECT id INTO v_world FROM my_derby.worlds WHERE world_key='kra_roster_v1';
  IF v_world IS NULL THEN RAISE EXCEPTION 'WORLD_NOT_READY' USING errcode='23514'; END IF;

  SELECT * INTO v_prev FROM my_derby.profiles WHERE user_id=v_uid FOR UPDATE;
  IF FOUND AND v_prev.world_id IS NOT NULL AND v_prev.world_id<>v_world THEN
    RAISE EXCEPTION 'ALREADY_JOINED_ANOTHER_WORLD' USING errcode='23514';
  END IF;
  IF FOUND AND v_prev.initial_setup_complete THEN
    SELECT count(*)::int INTO v_existing FROM my_derby.horses
      WHERE owner_user_id=v_uid AND world_id=v_world;
    RETURN jsonb_build_object('joined',true,'alreadyJoined',true,
      'worldId',v_world,'ownedHorses',v_existing,
      'startingRegion',v_prev.starting_region,'silksDesign',v_prev.silks_design);
  END IF;
  SELECT count(*)::int INTO v_existing FROM my_derby.horses
    WHERE owner_user_id=v_uid AND world_id=v_world;
  IF v_existing<>0 THEN
    RAISE EXCEPTION 'PARTIAL_ONBOARDING_REQUIRES_REVIEW' USING errcode='23514';
  END IF;

  INSERT INTO my_derby.profiles(
    user_id,nickname,world_id,starting_region,silks_design,initial_setup_complete
  ) VALUES (
    v_uid,btrim(p_nickname),v_world,p_starting_region,v_silks,false
  )
  ON CONFLICT(user_id) DO UPDATE SET
    world_id=excluded.world_id,
    nickname=excluded.nickname,
    starting_region=excluded.starting_region,
    silks_design=excluded.silks_design,
    updated_at=now();

  WITH young_horse AS MATERIALIZED (
    SELECT h.id,'YOUNG'::text AS starter_type
    FROM my_derby.horses h
    WHERE h.world_id=v_world AND h.owner_user_id IS NULL AND h.npc_owner_id IS NULL
      AND h.source_model_version='kra_v1' AND h.life_stage='RACING'
      AND h.racing_retired_permanently=false AND h.breeding_retired_at IS NULL
      AND h.age_years=2 AND h.source_grade_no BETWEEN 1 AND 6
    ORDER BY h.source_grade_no DESC,h.id
    LIMIT 1 FOR UPDATE OF h SKIP LOCKED
  ), grade6_newcomer AS MATERIALIZED (
    SELECT h.id,'GRADE6'::text AS starter_type
    FROM my_derby.horses h
    WHERE h.world_id=v_world AND h.owner_user_id IS NULL AND h.npc_owner_id IS NULL
      AND h.source_model_version='kra_v1' AND h.life_stage='RACING'
      AND h.racing_retired_permanently=false AND h.breeding_retired_at IS NULL
      AND h.age_years=3 AND h.source_grade_no=6
    ORDER BY h.id
    LIMIT 1 FOR UPDATE OF h SKIP LOCKED
  ), us_grade4_newcomer AS MATERIALIZED (
    SELECT h.id,'US_GRADE4'::text AS starter_type
    FROM my_derby.horses h
    JOIN my_derby.horse_source_profiles sp ON sp.horse_id=h.id
    WHERE h.world_id=v_world AND h.owner_user_id IS NULL AND h.npc_owner_id IS NULL
      AND h.source_model_version='kra_v1' AND h.life_stage='RACING'
      AND h.racing_retired_permanently=false AND h.breeding_retired_at IS NULL
      AND h.age_years=3 AND h.source_grade_no=4
      AND lower(btrim(sp.country)) IN ('미국','usa','united states','united states of america')
    ORDER BY h.id
    LIMIT 1 FOR UPDATE OF h SKIP LOCKED
  ), selected AS (
    SELECT * FROM young_horse
    UNION ALL SELECT * FROM grade6_newcomer
    UNION ALL SELECT * FROM us_grade4_newcomer
  )
  UPDATE my_derby.horses h SET
    owner_user_id=v_uid,
    location=CASE WHEN selected.starter_type='YOUNG' THEN 'OWNER_RANCH' ELSE 'NPC_STABLE' END,
    imported_foreign=CASE WHEN selected.starter_type='US_GRADE4' THEN true ELSE h.imported_foreign END,
    foreign_import_year=CASE WHEN selected.starter_type='US_GRADE4' THEN 2026 ELSE h.foreign_import_year END
  FROM selected
  WHERE h.id=selected.id;
  GET DIAGNOSTICS v_assigned = ROW_COUNT;
  IF v_assigned<>3 THEN
    RAISE EXCEPTION 'STARTER_PACKAGE_UNAVAILABLE' USING errcode='23514';
  END IF;

  -- Seed the first five staff as C grade. Later candidate hires retain their
  -- normal randomized C/B/A/S grades.
  INSERT INTO my_derby.ranches(owner_user_id,name,staff_count,veterinarian_count)
  VALUES(v_uid,btrim(p_nickname)||' 목장',0,0)
  ON CONFLICT(owner_user_id) DO NOTHING
  RETURNING id INTO v_ranch;

  IF v_ranch IS NOT NULL THEN
    INSERT INTO my_derby.ranch_workers(
      ranch_id,role,specialty,name,grade,skills,salary_per_game_day,is_active
    )
    SELECT v_ranch,
      CASE WHEN seed.specialty='VET' THEN 'VET' ELSE 'CARETAKER' END,
      seed.specialty,seed.label||' '||substr(gen_random_uuid()::text,1,4),
      'C',jsonb_build_object(
        'care',35+floor(random()*21)::int,
        'medical',35+floor(random()*21)::int,
        'growth',35+floor(random()*21)::int,
        'stability',35+floor(random()*21)::int
      ),1000,true
    FROM (VALUES
      ('PASTURE_CARETAKER'::text,'방목지 관리사'::text),
      ('RECOVERY_CARETAKER','회복 관리사'),
      ('REHAB_CARETAKER','재활 관리사'),
      ('YOUNG_HORSE_CARETAKER','육성 관리사'),
      ('VET','수의사')
    ) AS seed(specialty,label);

    UPDATE my_derby.ranches SET staff_count=4,veterinarian_count=1 WHERE id=v_ranch;
  END IF;

  UPDATE my_derby.profiles
    SET initial_setup_complete=true,updated_at=now()
    WHERE user_id=v_uid;

  RETURN jsonb_build_object('joined',true,'alreadyJoined',false,'worldId',v_world,
    'ownedHorses',v_assigned,'startingRegion',p_starting_region,'silksDesign',v_silks,
    'starterPackage',jsonb_build_array('2세 육성마','3세 6등급 신마','3세 미국산 외국 4등급 신마'),
    'initialStaffGrade','C');
END
$function$;

CREATE OR REPLACE FUNCTION my_derby.join_world(p_nickname text)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT my_derby.join_world(
    p_nickname,'SEOUL',
    '{"bodyColor":"#D6A84F","sleeveColor":"#23180F","pattern":"solid","patternColor":"#FFFFFF"}'::jsonb
  );
$function$;

REVOKE ALL ON FUNCTION my_derby.join_world(text,text,jsonb) FROM public,anon;
REVOKE ALL ON FUNCTION my_derby.join_world(text) FROM public,anon;
GRANT EXECUTE ON FUNCTION my_derby.join_world(text,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.join_world(text) TO authenticated;

-- A requested two-year-old starter must be eligible for the young-horse course.
CREATE OR REPLACE FUNCTION my_derby.player_ranch_apply(
  p_horse uuid,
  p_course text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  u uuid := auth.uid();
  h my_derby.horses%rowtype;
  ranch my_derby.ranches%rowtype;
  f my_derby.ranch_facilities%rowtype;
  v_course_type text;
  v_days integer;
  v_price bigint;
  v_factor numeric;
  v_day integer;
  v_cost bigint;
  v_id uuid;
  v_world uuid;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING errcode='42501'; END IF;
  SELECT world_id INTO v_world FROM my_derby.profiles
    WHERE user_id=u AND initial_setup_complete;
  IF v_world IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING errcode='42501'; END IF;
  SELECT * INTO h FROM my_derby.horses WHERE id=p_horse AND world_id=v_world FOR UPDATE;
  IF NOT FOUND OR h.owner_user_id IS DISTINCT FROM u THEN
    RAISE EXCEPTION 'NOT_YOUR_HORSE' USING errcode='42501';
  END IF;
  SELECT * INTO ranch FROM my_derby.ranches WHERE owner_user_id=u FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RANCH_NOT_AVAILABLE'; END IF;
  v_course_type:=CASE p_course WHEN 'REST_3D' THEN 'PASTURE'
    WHEN 'RECOVERY_7D' THEN 'RECOVERY_STABLE' WHEN 'REHAB' THEN 'REHAB_TRACK'
    WHEN 'YOUNG_BASIC' THEN 'YOUNG_HORSE_AREA' ELSE NULL END;
  IF v_course_type IS NULL THEN RAISE EXCEPTION 'UNKNOWN_RANCH_COURSE'; END IF;
  v_days:=CASE p_course WHEN 'REST_3D' THEN 3 ELSE 7 END;
  v_price:=CASE p_course WHEN 'REST_3D' THEN 5000 WHEN 'RECOVERY_7D' THEN 5000
    WHEN 'REHAB' THEN 20000 ELSE 10000 END;
  IF h.sale_state<>'NOT_LISTED' OR h.life_stage='DECEASED'
    OR h.injury_prognosis='RACING_UNFIT' THEN RAISE EXCEPTION 'HORSE_NOT_RANCH_ELIGIBLE'; END IF;
  IF (p_course='YOUNG_BASIC' AND h.age_years>2)
    OR (p_course<>'YOUNG_BASIC' AND h.age_years<2) THEN
    RAISE EXCEPTION 'RANCH_COURSE_AGE_MISMATCH';
  END IF;
  IF p_course='REHAB' AND h.health_state='HEALTHY' THEN
    RAISE EXCEPTION 'REHAB_REQUIRES_INJURY';
  END IF;
  IF EXISTS(SELECT 1 FROM my_derby.ranch_course_requests c
    WHERE c.horse_id=h.id AND c.status='ACTIVE') THEN
    RAISE EXCEPTION 'RANCH_COURSE_ALREADY_ACTIVE';
  END IF;
  v_day:=(my_derby.world_clock(v_world)->>'gameDayStart')::int;
  IF EXISTS(SELECT 1 FROM my_derby.race_entries e JOIN my_derby.races r ON r.id=e.race_id
    WHERE e.horse_id=h.id AND e.status IN('APPLIED','CONFIRMED')
      AND r.status IN('OPEN','CLOSED','RUNNING')
      AND r.race_day BETWEEN v_day AND v_day+v_days-1) THEN
    RAISE EXCEPTION 'RANCH_RACE_CONFLICT';
  END IF;
  SELECT * INTO f FROM my_derby.ranch_facilities
    WHERE ranch_id=ranch.id AND facility_type=v_course_type FOR UPDATE;
  IF NOT FOUND OR f.capacity<1 THEN RAISE EXCEPTION 'RANCH_FACILITY_NOT_READY'; END IF;
  IF (SELECT count(*) FROM my_derby.ranch_course_requests c
    WHERE c.ranch_id=ranch.id AND c.status='ACTIVE' AND c.course_type=p_course)>=f.capacity THEN
    RAISE EXCEPTION 'RANCH_FACILITY_FULL';
  END IF;
  v_factor:=CASE h.source_grade_no WHEN 5 THEN 1.2 WHEN 4 THEN 1.5
    WHEN 3 THEN 2.0 WHEN 2 THEN 2.8 WHEN 1 THEN 4.0 ELSE 1 END;
  v_cost:=round(v_price*v_factor*v_days)::bigint;
  INSERT INTO my_derby.ranch_course_requests(
    ranch_id,horse_id,owner_user_id,course_type,status,start_game_day,end_game_day
  ) VALUES(ranch.id,h.id,u,p_course,'ACTIVE',v_day,v_day+v_days-1)
  RETURNING id INTO v_id;
  PERFORM my_derby_private.wallet_mutate(
    u,v_world,v_day,-v_cost,'RANCH_COURSE_FEE','RANCH_COURSE',v_id
  );
  UPDATE my_derby.horses SET location='OWNER_RANCH' WHERE id=h.id;
  RETURN jsonb_build_object('status','ACTIVE','courseId',v_id,'horseId',h.id,
    'startGameDay',v_day,'endGameDay',v_day+v_days-1,'fee',v_cost);
END
$function$;

NOTIFY pgrst,'reload schema';
