-- My Derby Yeongcheon GAME class labels aligned to Busan future proportions.
-- Not a claim about real Jeju-bred horses. Provenance remains source_meet=제주,
-- source_rank/original_name and the numeric grade remain unchanged.
-- Existing confirmed race entries, gates, finances and finished races are untouched.

CREATE OR REPLACE FUNCTION my_derby_private.yeongcheon_game_class_name(
 p_grade integer,p_is_open boolean,p_seed text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path TO ''
AS $fn$
DECLARE v_draw numeric;
BEGIN
 IF p_grade NOT BETWEEN 1 AND 6 THEN RAISE EXCEPTION 'BAD_GRADE';END IF;
 -- Stable pseudo-random partition for future newly created programs.
 v_draw:=(('x'||substr(md5(coalesce(p_seed,'')||':YC_CLASS_MIX_V1'),1,8))
      ::bit(32)::bigint % 100000)::numeric/100000;
 IF p_is_open THEN
  RETURN CASE WHEN v_draw<11.0/19 THEN '국OPEN' ELSE '혼OPEN' END;
 END IF;
 RETURN CASE p_grade
 WHEN 1 THEN '1등급'
 WHEN 2 THEN '2등급'
 WHEN 3 THEN CASE WHEN v_draw<34.0/80 THEN '국3등급' ELSE '혼3등급' END
 WHEN 4 THEN CASE WHEN v_draw<68.0/154 THEN '국4등급' ELSE '혼4등급' END
 WHEN 5 THEN '국5등급'
 WHEN 6 THEN '국6등급'
 END;
END $fn$;

-- Incoming Yeongcheon programs are automatically translated on creation,
-- with the original source class retained as provenance. 2025-source lists
-- can retain the historical 제주 name independently of the game display.
CREATE OR REPLACE FUNCTION my_derby_private.yeongcheon_game_class_on_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_grade integer;v_source_name text;
BEGIN
 IF NEW.track<>'영천' OR NEW.class_name NOT LIKE '제%' THEN
  RETURN NEW;
 END IF;
 IF NEW.prize_policy->>'source_meet' IS DISTINCT FROM '제주' THEN
  RETURN NEW;
 END IF;
 v_grade:=nullif(NEW.prize_policy->>'grade_no','')::integer;
 IF v_grade NOT BETWEEN 1 AND 6 THEN RETURN NEW;END IF;
 v_source_name:=NEW.class_name;
 NEW.class_name:=my_derby_private.yeongcheon_game_class_name(
    v_grade,upper(v_source_name) LIKE '%OPEN%',
    coalesce(NEW.id::text,'')||':'||NEW.race_day::text||':'||NEW.race_no::text);
 NEW.prize_policy:=coalesce(NEW.prize_policy,'{}'::jsonb)||
   jsonb_build_object('game_class_label_source',v_source_name,
    'game_class_label_policy','BUSAN_MIX_V1','game_class_label_game_only',true);
 RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS yeongcheon_game_class_on_insert ON my_derby.races;
CREATE TRIGGER yeongcheon_game_class_on_insert
 BEFORE INSERT ON my_derby.races FOR EACH ROW
 EXECUTE FUNCTION my_derby_private.yeongcheon_game_class_on_insert();

-- Rebalance existing *future* schedule labels exactly by each source grade:
-- source Busan mix at 2026-10-30: 3등급 국34/80 혼46/80,
-- 4등급 국68/154 혼86/154 and OPEN 국11/19 혼8/19.
-- The 717 ordinary races keep the numeric grade mix already set earlier.
DO $rebalance$
DECLARE v_today date:=(now() AT TIME ZONE 'Asia/Seoul')::date;
 v_n integer;v_open integer;v_actual integer;
 v_counts jsonb;v_expected jsonb;
BEGIN
 SELECT count(*) INTO v_n FROM my_derby.races r
 WHERE r.track='영천' AND r.status='OPEN'
   AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND r.class_name NOT ILIKE '%OPEN%'
   AND (r.prize_policy->>'kst_date')::date>v_today;
 SELECT count(*) INTO v_open FROM my_derby.races r
 WHERE r.track='영천' AND r.status='OPEN'
   AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND r.class_name ILIKE '%OPEN%'
   AND (r.prize_policy->>'kst_date')::date>v_today;
 IF v_n<>717 OR v_open<>9 THEN
   RAISE EXCEPTION 'SAFETY_BASELINE_CHANGED normal % open %',v_n,v_open;
 END IF;

 WITH future AS (
  SELECT r.id,r.class_name,
    (r.prize_policy->>'grade_no')::integer as grade,
    upper(r.class_name) LIKE '%OPEN%' is_open
  FROM my_derby.races r
  WHERE r.track='영천' AND r.status='OPEN'
   AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND (r.prize_policy->>'kst_date')::date>v_today
 ), order_by_grade AS (
  SELECT f.*,row_number() OVER(PARTITION BY grade,is_open ORDER BY md5(id::text)) rn,
   count(*) OVER(PARTITION BY grade,is_open) n
  FROM future f
 ), mapped AS(
  SELECT x.id,x.class_name previous_name,
  CASE WHEN x.is_open THEN
    CASE WHEN x.rn<=round(x.n*11.0/19) THEN '국OPEN' ELSE '혼OPEN' END
  ELSE CASE x.grade
    WHEN 1 THEN '1등급'
    WHEN 2 THEN '2등급'
    WHEN 3 THEN CASE WHEN x.rn<=round(x.n*34.0/80) THEN '국3등급' ELSE '혼3등급' END
    WHEN 4 THEN CASE WHEN x.rn<=round(x.n*68.0/154) THEN '국4등급' ELSE '혼4등급' END
    WHEN 5 THEN '국5등급'
    WHEN 6 THEN '국6등급'
  END END as game_class
  FROM order_by_grade x
 )
 UPDATE my_derby.races r
 SET class_name=m.game_class,
  prize_policy=coalesce(r.prize_policy,'{}'::jsonb)||
   jsonb_build_object('game_class_label_source',m.previous_name,
    'game_class_label_policy','BUSAN_MIX_V1',
    'game_class_label_game_only',true)
 FROM mapped m WHERE r.id=m.id;
 GET DIAGNOSTICS v_actual=ROW_COUNT;

 SELECT jsonb_object_agg(class_name,n) INTO v_counts FROM (
  SELECT class_name,count(*) n FROM my_derby.races
  WHERE track='영천' AND status='OPEN'
   AND prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND (prize_policy->>'kst_date')::date>v_today
  GROUP BY 1
 ) a;
 v_expected:=jsonb_build_object(
  '1등급',16,'2등급',34,'국3등급',35,'혼3등급',47,
  '국4등급',70,'혼4등급',88,'국5등급',207,
  '국6등급',220,'국OPEN',5,'혼OPEN',4);
 IF v_actual<>726 OR v_counts<>v_expected THEN
  RAISE EXCEPTION 'GRADE_MIX_VERIFICATION_FAILED updated % actual % expected %',
    v_actual,v_counts,v_expected;
 END IF;
 RAISE NOTICE 'YEONGCHEON_CLASS_MIX_OK updated % future game class labels; numeric grade and source preserved',v_actual;
END $rebalance$;

REVOKE ALL ON FUNCTION my_derby_private.yeongcheon_game_class_name(integer,boolean,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.yeongcheon_game_class_on_insert()
 FROM PUBLIC,anon,authenticated;
