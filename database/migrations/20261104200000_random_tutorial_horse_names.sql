CREATE OR REPLACE FUNCTION my_derby_private.random_tutorial_horse_name(
  p_world_id uuid,
  p_starter_type text
)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_prefixes text[]:=ARRAY[
    '태양','천하','청룡','한라','백두','불꽃','푸른','황금','미라클','글로벌',
    '스마트','브라보','드림','에이스','파워','스피드','럭키','골든','로열','퀸즈',
    '블루','스카이','그랜드','레이디','슈퍼','명품','질풍','승리','기적','별빛'
  ];
  v_suffixes text[]:=ARRAY[
    '질주','비상','우승','천둥','질풍','드래곤','히어로','레전드','스타','챔프',
    '퀸','킹','스톰','포스','러너','블레이드','스피릿','윈드','스텝','하트',
    '라이더','플라잉','대왕','여왕','선더','임팩트','돌풍','명장','위너','프린스'
  ];
  v_candidate text;
  v_attempt integer;
BEGIN
  IF p_world_id IS NULL OR p_starter_type NOT IN ('YOUNG','GRADE6','US_GRADE4') THEN
    RAISE EXCEPTION 'INVALID_TUTORIAL_HORSE_NAME_REQUEST';
  END IF;

  -- Serialize name selection per world so simultaneous signups do not pick
  -- the same name before either generated horse is inserted.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('tutorial-horse-name:'||p_world_id::text,0)
  );

  FOR v_attempt IN 1..100 LOOP
    v_candidate:=v_prefixes[1+floor(random()*array_length(v_prefixes,1))::integer]
      ||v_suffixes[1+floor(random()*array_length(v_suffixes,1))::integer];
    IF NOT EXISTS(SELECT 1 FROM my_derby.horses h
      WHERE h.world_id=p_world_id AND h.name=v_candidate) THEN
      RETURN v_candidate;
    END IF;
  END LOOP;

  RETURN v_prefixes[1+floor(random()*array_length(v_prefixes,1))::integer]
    ||v_suffixes[1+floor(random()*array_length(v_suffixes,1))::integer]
    ||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
END
$function$;
REVOKE ALL ON FUNCTION my_derby_private.random_tutorial_horse_name(uuid,text)
  FROM PUBLIC,anon,authenticated;

-- Patch the existing starter creator without replacing its stat-generation
-- and raceability logic.
DO $patch_creator$
DECLARE
  v_def text;
  v_old text;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'my_derby_private.create_tutorial_starter(uuid,uuid,text,text)'::regprocedure
  ) INTO v_def;
  v_old:=v_def;
  v_def:=replace(v_def,
    $old$  v_name:=CASE p_starter_type
    WHEN 'YOUNG' THEN '첫걸음-'||upper(substr(v_id::text,1,4))
    WHEN 'GRADE6' THEN '도전마-'||upper(substr(v_id::text,1,4))
    ELSE '미국산 신마-'||upper(substr(v_id::text,1,4)) END;$old$,
    $new$  v_name:=my_derby_private.random_tutorial_horse_name(p_world_id,p_starter_type);$new$);
  IF v_def=v_old OR position('random_tutorial_horse_name(p_world_id,p_starter_type)' in v_def)=0 THEN
    RAISE EXCEPTION 'Could not safely patch tutorial starter naming';
  END IF;
  EXECUTE v_def;
END
$patch_creator$;

-- Give names to the newly generated tutorial horses created before this change.
DO $rename_existing$
DECLARE
  r record;
  v_name text;
BEGIN
  FOR r IN
    SELECT h.id,h.world_id,h.tutorial_starter_type
    FROM my_derby.horses h
    WHERE h.source_model_version='TUTORIAL_STARTER_LOTTERY_V1'
      AND (h.name LIKE '첫걸음-%' OR h.name LIKE '도전마-%' OR h.name LIKE '미국산 신마-%')
    ORDER BY h.created_at,h.id
  LOOP
    v_name:=my_derby_private.random_tutorial_horse_name(r.world_id,r.tutorial_starter_type);
    UPDATE my_derby.horses SET name=v_name WHERE id=r.id;
    UPDATE my_derby.horse_source_profiles SET horse_name=v_name WHERE horse_id=r.id;
  END LOOP;
END
$rename_existing$;
