-- Generate an independent starter horse for every account. Current stats are
-- the per-stat mean for the horse's grade; growth and hidden traits are rolled
-- independently with a small elite tier and a meaningful low-potential tier.
CREATE OR REPLACE FUNCTION my_derby_private.create_tutorial_starter(
  p_user_id uuid,
  p_world_id uuid,
  p_starter_type text,
  p_starting_region text
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_id uuid := gen_random_uuid();
  v_source_hr_no text;
  v_name text;
  v_meet text;
  v_grade smallint;
  v_age integer;
  v_location text;
  v_country text;
  v_imported boolean;
  v_sex text;
  v_sex_source text;
  v_current jsonb;
  v_potential jsonb := '{}'::jsonb;
  v_distance jsonb := '{}'::jsonb;
  v_tags jsonb;
  v_key text;
  v_distance_key text;
  v_current_value numeric;
  v_growth numeric;
  v_stat_noise numeric;
  v_potential_value numeric;
  v_quality_roll numeric := random();
  v_quality_tier text;
  v_growth_low numeric;
  v_growth_high numeric;
  v_sample_count integer;
BEGIN
  IF p_user_id IS NULL OR p_world_id IS NULL OR p_starter_type IS NULL
    OR p_starting_region IS NULL
    OR p_starter_type NOT IN ('YOUNG','GRADE6','US_GRADE4')
    OR p_starting_region NOT IN ('SEOUL','YEONGCHEON','BUSAN') THEN
    RAISE EXCEPTION 'INVALID_TUTORIAL_STARTER_REQUEST';
  END IF;

  v_meet:=CASE p_starting_region
    WHEN 'SEOUL' THEN '서울' WHEN 'BUSAN' THEN '부산경남' ELSE '영천' END;
  v_grade:=CASE p_starter_type WHEN 'US_GRADE4' THEN 4 ELSE 6 END;
  v_age:=CASE p_starter_type WHEN 'YOUNG' THEN 2 ELSE 3 END;
  v_location:=CASE p_starter_type WHEN 'YOUNG' THEN 'OWNER_RANCH' ELSE 'NPC_STABLE' END;
  v_imported:=p_starter_type='US_GRADE4';
  v_country:=CASE WHEN v_imported THEN '미국' ELSE '한국' END;
  v_sex:=CASE WHEN random()<0.5 THEN 'MALE' ELSE 'FEMALE' END;
  v_sex_source:=CASE v_sex WHEN 'MALE' THEN '수' ELSE '암' END;
  v_source_hr_no:='TUT-'||upper(replace(v_id::text,'-',''));
  v_name:=CASE p_starter_type
    WHEN 'YOUNG' THEN '첫걸음-'||upper(substr(v_id::text,1,4))
    WHEN 'GRADE6' THEN '도전마-'||upper(substr(v_id::text,1,4))
    ELSE '미국산 신마-'||upper(substr(v_id::text,1,4)) END;

  SELECT count(*)::integer,
    jsonb_build_object(
      'start',round(coalesce(avg((a.current_stats->>'start')::numeric),45),2),
      'speed',round(coalesce(avg((a.current_stats->>'speed')::numeric),45),2),
      'acceleration',round(coalesce(avg((a.current_stats->>'acceleration')::numeric),45),2),
      'stamina',round(coalesce(avg((a.current_stats->>'stamina')::numeric),45),2),
      'finishing',round(coalesce(avg((a.current_stats->>'finishing')::numeric),45),2),
      'power',round(coalesce(avg((a.current_stats->>'power')::numeric),45),2),
      'grit',round(coalesce(avg((a.current_stats->>'grit')::numeric),45),2),
      'stability',round(coalesce(avg((a.current_stats->>'stability')::numeric),45),2),
      'recovery',round(coalesce(avg((a.current_stats->>'recovery')::numeric),45),2)
    )
  INTO v_sample_count,v_current
  FROM my_derby.horses h
  JOIN my_derby.horse_abilities a ON a.horse_id=h.id
  WHERE h.world_id=p_world_id AND h.source_model_version='kra_v1'
    AND h.source_grade_no=v_grade AND h.life_stage='RACING'
    AND a.current_stats<>'{}'::jsonb;
  IF v_sample_count=0 THEN RAISE EXCEPTION 'TUTORIAL_STARTER_GRADE_AVERAGE_UNAVAILABLE'; END IF;

  IF v_quality_roll<0.03 THEN
    v_quality_tier:='ELITE'; v_growth_low:=0.82; v_growth_high:=1.00;
  ELSIF v_quality_roll<0.15 THEN
    v_quality_tier:='HIGH'; v_growth_low:=0.62; v_growth_high:=0.82;
  ELSIF v_quality_roll<0.70 THEN
    v_quality_tier:='AVERAGE'; v_growth_low:=0.30; v_growth_high:=0.62;
  ELSE
    v_quality_tier:='LOW'; v_growth_low:=0.05; v_growth_high:=0.30;
  END IF;

  FOREACH v_key IN ARRAY ARRAY['start','speed','acceleration','stamina',
    'finishing','power','grit','stability','recovery'] LOOP
    v_current_value:=(v_current->>v_key)::numeric;
    v_growth:=v_growth_low+random()*(v_growth_high-v_growth_low);
    v_stat_noise:=(random()-0.5)*0.08;
    v_potential_value:=round(least(100,greatest(v_current_value,
      v_current_value+(100-v_current_value)*greatest(0.01,least(1,v_growth+v_stat_noise)))),2);
    v_potential:=jsonb_set(v_potential,ARRAY[v_key],to_jsonb(v_potential_value),true);
  END LOOP;

  FOREACH v_distance_key IN ARRAY ARRAY['800','900','1000','1110','1200','1300',
    '1400','1600','1700','1800','2000','2300'] LOOP
    v_distance:=jsonb_set(v_distance,ARRAY[v_distance_key],
      to_jsonb(55+floor(random()*36)::integer),true);
  END LOOP;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'code',trait.code,'score',35+floor(random()*66)::integer,
    'evidence','튜토리얼 무작위 배정') ORDER BY trait.code),'[]'::jsonb)
  INTO v_tags
  FROM (
    SELECT code FROM unnest(ARRAY['LATE_DEVELOPMENT','CONSISTENT',
      'TRAFFIC_RECOVERY','SPRINTER','STAYER','VARIABLE_FORM','UNDETERMINED']) code
    ORDER BY random() LIMIT 1+floor(random()*3)::integer
  ) trait;

  INSERT INTO my_derby.horses(
    id,world_id,owner_user_id,name,sex,age_years,life_stage,location,
    health_state,race_entry_state,breeding_state,condition_score,fatigue,
    source_hr_no,source_meet,source_birth_date,source_record_count,
    source_model_version,source_grade_no,imported_foreign,foreign_import_year,
    birth_hemisphere,tutorial_starter_type,tutorial_entry_fee_waived
  ) VALUES(
    v_id,p_world_id,p_user_id,v_name,v_sex,v_age,'RACING',v_location,
    'HEALTHY','NONE','AVAILABLE',80,0,v_source_hr_no,v_meet,
    (current_date-(v_age*interval '1 year'))::date,0,
    'TUTORIAL_STARTER_LOTTERY_V1',v_grade,v_imported,
    CASE WHEN v_imported THEN 2026 ELSE NULL END,'NORTH',
    p_starter_type,true
  );

  INSERT INTO my_derby.horse_abilities(
    horse_id,current_stats,potential_stats,gene_stats,public_estimates,
    distance_affinity,hidden_traits,estimation_metadata
  ) VALUES(
    v_id,v_current,v_potential,v_potential,v_current,v_distance,
    jsonb_build_object('tags',v_tags,'model','TUTORIAL_STARTER_LOTTERY_V1',
      'inferred',false,'confidence',0),
    jsonb_build_object('model','TUTORIAL_STARTER_LOTTERY_V1',
      'gradeMeanSampleCount',v_sample_count,'currentStatsMethod','PER_STAT_GRADE_MEAN',
      'randomGrowthTier',v_quality_tier,'randomPotential',true,'randomHiddenTraits',true)
  );

  INSERT INTO my_derby.horse_source_profiles(
    source_meet,source_hr_no,horse_id,horse_name,source_rank,birth_date,
    source_sex,country,owner_name,starts_total,starts_year,wins_total,wins_year,
    seconds_total,seconds_year,thirds_total,thirds_year,source_label
  ) VALUES(
    v_meet,v_source_hr_no,v_id,v_name,v_grade::text||'등급',
    (current_date-(v_age*interval '1 year'))::date,v_sex_source,v_country,
    'MY DERBY 튜토리얼',0,0,0,0,0,0,0,0,'TUTORIAL_STARTER_LOTTERY_V1'
  );

  RETURN v_id;
END
$function$;
REVOKE ALL ON FUNCTION my_derby_private.create_tutorial_starter(uuid,uuid,text,text)
  FROM PUBLIC,anon,authenticated;

-- Replace only the shared-horse selection in join_world; keep its existing
-- profile, staff, ranch, and idempotency rules intact.
DO $patch_join$
DECLARE
  v_def text;
  v_old text;
BEGIN
  SELECT pg_catalog.pg_get_functiondef('my_derby.join_world(text,text,jsonb)'::regprocedure)
    INTO v_def;
  v_old:=v_def;
  v_def:=regexp_replace(v_def,
    $pattern$  WITH young_horse AS MATERIALIZED \(.*?  IF v_assigned<>1 THEN$pattern$,
    $replacement$  PERFORM my_derby_private.create_tutorial_starter(
    v_uid,v_world,'YOUNG',p_starting_region);
  v_assigned:=1;
  IF v_assigned<>1 THEN$replacement$,'s');
  IF v_def=v_old OR position('create_tutorial_starter(' in v_def)=0
    OR position('v_assigned<>1' in v_def)=0 THEN
    RAISE EXCEPTION 'Could not safely patch join_world for generated tutorial starters';
  END IF;
  EXECUTE v_def;
END
$patch_join$;

CREATE OR REPLACE FUNCTION my_derby_private.award_tutorial_grade6_after_course()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_region text;
BEGIN
  IF NEW.status<>'ACTIVE' THEN RETURN NEW; END IF;
  IF NOT EXISTS(SELECT 1 FROM my_derby.horses h
    WHERE h.id=NEW.horse_id AND h.owner_user_id=NEW.owner_user_id
      AND h.tutorial_starter_type='YOUNG') THEN RETURN NEW; END IF;
  SELECT p.starting_region INTO v_region FROM my_derby.profiles p
    WHERE p.user_id=NEW.owner_user_id AND p.initial_setup_complete;
  IF v_region IS NULL OR NOT EXISTS(SELECT 1 FROM my_derby.player_tutorial_progress t
    WHERE t.user_id=NEW.owner_user_id AND t.story_stage=0) THEN RETURN NEW; END IF;

  PERFORM my_derby_private.create_tutorial_starter(
    NEW.owner_user_id,(SELECT p.world_id FROM my_derby.profiles p WHERE p.user_id=NEW.owner_user_id),
    'GRADE6',v_region);
  UPDATE my_derby.player_tutorial_progress SET story_stage=1,completed=false,updated_at=now()
    WHERE user_id=NEW.owner_user_id AND story_stage=0;
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION my_derby_private.award_tutorial_grade6_after_course()
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.award_tutorial_foreign_horse_after_entry()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_region text;
  v_world uuid;
BEGIN
  IF NEW.status<>'CONFIRMED' OR NEW.owner_user_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND OLD.status='CONFIRMED' THEN RETURN NEW; END IF;
  SELECT p.world_id,p.starting_region INTO v_world,v_region FROM my_derby.profiles p
    WHERE p.user_id=NEW.owner_user_id AND p.initial_setup_complete;
  IF v_world IS NULL OR NOT EXISTS(SELECT 1 FROM my_derby.player_tutorial_progress t
    WHERE t.user_id=NEW.owner_user_id AND t.story_stage=1) THEN RETURN NEW; END IF;
  IF NOT EXISTS(SELECT 1 FROM my_derby.horses h WHERE h.id=NEW.horse_id
    AND h.owner_user_id=NEW.owner_user_id AND h.tutorial_starter_type='GRADE6') THEN RETURN NEW; END IF;

  PERFORM my_derby_private.create_tutorial_starter(
    NEW.owner_user_id,v_world,'US_GRADE4',v_region);
  UPDATE my_derby.player_tutorial_progress SET story_stage=2,completed=false,updated_at=now()
    WHERE user_id=NEW.owner_user_id AND story_stage=1;
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION my_derby_private.award_tutorial_foreign_horse_after_entry()
  FROM PUBLIC,anon,authenticated;

-- Reissue only the next missing tutorial horse for existing accounts. Already
-- owned starters and their race history are left intact.
DO $repair$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT p.user_id,p.world_id,p.starting_region
    FROM my_derby.player_tutorial_progress t
    JOIN my_derby.profiles p ON p.user_id=t.user_id AND p.initial_setup_complete
    JOIN my_derby.horses y ON y.owner_user_id=p.user_id AND y.tutorial_starter_type='YOUNG'
    JOIN my_derby.ranch_course_requests c ON c.owner_user_id=p.user_id AND c.horse_id=y.id
      AND c.status IN ('ACTIVE','DONE')
    WHERE t.story_stage=0
  LOOP
    PERFORM my_derby_private.create_tutorial_starter(r.user_id,r.world_id,'GRADE6',r.starting_region);
    UPDATE my_derby.player_tutorial_progress SET story_stage=1,completed=false,updated_at=now()
      WHERE user_id=r.user_id AND story_stage=0;
  END LOOP;

  FOR r IN
    SELECT DISTINCT p.user_id,p.world_id,p.starting_region
    FROM my_derby.player_tutorial_progress t
    JOIN my_derby.profiles p ON p.user_id=t.user_id AND p.initial_setup_complete
    JOIN my_derby.horses g ON g.owner_user_id=p.user_id AND g.tutorial_starter_type='GRADE6'
    JOIN my_derby.race_entries e ON e.owner_user_id=p.user_id AND e.horse_id=g.id
      AND e.status IN ('CONFIRMED','COMPLETED')
    WHERE t.story_stage=1
  LOOP
    PERFORM my_derby_private.create_tutorial_starter(r.user_id,r.world_id,'US_GRADE4',r.starting_region);
    UPDATE my_derby.player_tutorial_progress SET story_stage=2,completed=false,updated_at=now()
      WHERE user_id=r.user_id AND story_stage=1;
  END LOOP;
END
$repair$;

NOTIFY pgrst,'reload schema';
