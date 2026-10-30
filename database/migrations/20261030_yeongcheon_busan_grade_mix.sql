-- Align *future, unentered* Yeongcheon ordinary-grade race distribution
-- with Busan ordinary-grade shares; preserve source labels as provenance.
-- 2026-10-30 baseline: Busan counts 16/33/80/154/201/213 (697),
-- Yeongcheon counts 23/49/95/164/253/133 (717).
-- Hamilton largest-remainder approximation (717 slots):
-- desired Yeongcheon grades 1..6: 16/34/82/158/207/220.
-- Reclassify surplus grades 1-5 to grade 6; no OPEN, no completed,
-- no same-day, no current or historical entries are modified.
DO $rebalance$
DECLARE v_today date:=(now() AT TIME ZONE 'Asia/Seoul')::date;
 v_before int;v_updated int;v_open_before int;v_open_after int;
 v_with_entries int;v_counts integer[];
BEGIN
 SELECT count(*) INTO v_before FROM my_derby.races
  WHERE track='영천' AND status='OPEN'
    AND prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
    AND class_name NOT ILIKE '%OPEN%'
    AND (prize_policy->>'kst_date')::date>v_today;
 SELECT count(*) INTO v_open_before FROM my_derby.races
  WHERE track='영천' AND class_name ILIKE '%OPEN%';
 SELECT count(*) INTO v_with_entries FROM my_derby.races r
  WHERE r.track='영천' AND r.status='OPEN'
    AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
    AND r.class_name NOT ILIKE '%OPEN%'
    AND (r.prize_policy->>'kst_date')::date>v_today
    AND EXISTS(SELECT 1 FROM my_derby.race_entries e WHERE e.race_id=r.id);
 IF v_before<>717 OR v_open_before<>9 THEN
   RAISE EXCEPTION 'SAFETY_BASELINE_DRIFT future=% OPEN=%',v_before,v_open_before;
 END IF;
 CREATE TEMP TABLE tmp_yeongcheon_targets(grade int PRIMARY KEY,target int NOT NULL) ON COMMIT DROP;
 INSERT INTO tmp_yeongcheon_targets VALUES
 (1,16),(2,34),(3,82),(4,158),(5,207),(6,220);
 WITH counts AS (
  SELECT (r.prize_policy->>'grade_no')::int grade,count(*)::int current_n
  FROM my_derby.races r
  WHERE r.track='영천' AND r.status='OPEN'
   AND r.class_name NOT ILIKE '%OPEN%'
   AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND (r.prize_policy->>'kst_date')::date>v_today
  GROUP BY 1
 ), candidates AS (
  SELECT r.id,r.class_name old_name,(r.prize_policy->>'grade_no')::int grade,
    row_number() OVER(PARTITION BY (r.prize_policy->>'grade_no')::int
     ORDER BY (r.prize_policy->>'kst_date')::date DESC,r.id) rn
  FROM my_derby.races r
  WHERE r.track='영천' AND r.status='OPEN'
   AND r.class_name NOT ILIKE '%OPEN%'
   AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND (r.prize_policy->>'kst_date')::date>v_today
   AND (r.prize_policy->>'grade_no')::int BETWEEN 1 AND 5
   AND NOT EXISTS(SELECT 1 FROM my_derby.race_entries e WHERE e.race_id=r.id)
 ), changes AS (
  SELECT c.id,c.old_name,c.grade FROM candidates c
   JOIN counts n USING(grade)
   JOIN tmp_yeongcheon_targets t USING(grade)
   WHERE c.rn<=greatest(0,n.current_n-t.target)
 )
 UPDATE my_derby.races r SET class_name='제6등급',
   prize_policy=r.prize_policy||jsonb_build_object(
      'grade_no',6,
      'game_grade_rebalanced',true,
      'game_grade_rebalanced_from',c.old_name,
      'grade_distribution_basis','BUSAN_2026_10_30_FUTURE_SHARE',
      'grade_distribution_unchanged_source_rank',true)
 FROM changes c WHERE r.id=c.id;
 GET DIAGNOSTICS v_updated=ROW_COUNT;
 SELECT array_agg(n ORDER BY grade) INTO v_counts
 FROM (
  SELECT (prize_policy->>'grade_no')::int grade,count(*)::int n
  FROM my_derby.races
  WHERE track='영천' AND status='OPEN'
   AND class_name NOT ILIKE '%OPEN%'
   AND prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND (prize_policy->>'kst_date')::date>v_today
  GROUP BY 1
 ) x;
 SELECT count(*) INTO v_open_after FROM my_derby.races
  WHERE track='영천' AND class_name ILIKE '%OPEN%';
 IF v_counts<>ARRAY[16,34,82,158,207,220]::int[] OR
  v_updated<>87 OR v_open_before<>v_open_after THEN
  RAISE EXCEPTION 'POSTCHECK_FAIL grades=% changes=% openBefore=% openAfter=%',
   v_counts,v_updated,v_open_before,v_open_after;
 END IF;
 RAISE NOTICE 'PASS: % future unentered Yeongcheon races rebalanced, target %, OPEN stable %; existing entries % untouched',
  v_updated,v_counts,v_open_after,v_with_entries;
END $rebalance$;
