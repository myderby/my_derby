-- UI label only for today's already-assembled official Yeongcheon races.
-- All grade_no, confirmed runners, historical results and source ranks remain unchanged.
WITH today AS (
 SELECT r.id,r.class_name old_class,(r.prize_policy->>'grade_no')::int grade,
  row_number() OVER(PARTITION BY (r.prize_policy->>'grade_no')::int ORDER BY md5(r.id::text)) rn,
  count(*) OVER(PARTITION BY (r.prize_policy->>'grade_no')::int) n
 FROM my_derby.races r WHERE r.track='영천' AND r.status='OPEN'
  AND r.class_name LIKE '제%등급'
  AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  AND (r.prize_policy->>'kst_date')::date=(now() AT TIME ZONE 'Asia/Seoul')::date
),
labels AS (
 SELECT id,old_class,grade,
 CASE grade
  WHEN 1 THEN '1등급' WHEN 2 THEN '2등급'
  WHEN 3 THEN CASE WHEN rn<=round(n::numeric*36/83)
    THEN '국3등급' ELSE '혼3등급' END
  WHEN 4 THEN CASE WHEN rn<=round(n::numeric*72/162)
    THEN '국4등급' ELSE '혼4등급' END
  WHEN 5 THEN '국5등급' WHEN 6 THEN '국6등급'
 END new_class FROM today
)
INSERT INTO my_derby_private.yeongcheon_grade_label_audit
  (race_id,original_class_name,game_class_name,game_grade_no)
SELECT id,old_class,new_class,grade FROM labels WHERE new_class IS NOT NULL
ON CONFLICT(race_id) DO NOTHING;

UPDATE my_derby.races r
SET class_name=a.game_class_name,
 prize_policy=r.prize_policy||jsonb_build_object(
  'game_display_class',a.game_class_name,
  'game_grade_category_policy',a.busan_mix_policy,
  'game_source_class_name',a.original_class_name)
FROM my_derby_private.yeongcheon_grade_label_audit a
WHERE r.id=a.race_id AND r.status='OPEN' AND r.track='영천'
 AND r.class_name LIKE '제%등급'
 AND (r.prize_policy->>'kst_date')::date=(now() AT TIME ZONE 'Asia/Seoul')::date
 AND a.game_grade_no=(r.prize_policy->>'grade_no')::integer;
