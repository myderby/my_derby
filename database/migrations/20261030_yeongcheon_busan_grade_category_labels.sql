-- Yeongcheon mirrors Busan's game display categories (국/혼 + grade)
-- while retaining original 제주 labels in source_rank and history.
-- Numeric grade rebalancing was applied separately and is intentionally untouched.
CREATE TABLE IF NOT EXISTS my_derby_private.yeongcheon_grade_label_audit (
  race_id uuid PRIMARY KEY REFERENCES my_derby.races(id),
  original_class_name text NOT NULL,
  game_class_name text NOT NULL,
  game_grade_no integer NOT NULL CHECK(game_grade_no BETWEEN 1 AND 6),
  busan_mix_policy text NOT NULL DEFAULT 'YEONGCHEON_BUSAN_GAME_CATEGORY_V1',
  recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE my_derby_private.yeongcheon_grade_label_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby_private.yeongcheon_grade_label_audit FROM PUBLIC,anon,authenticated;

WITH yeongcheon AS (
 SELECT r.id,r.class_name,(r.prize_policy->>'grade_no')::integer grade_no,
   upper(r.class_name) LIKE '%OPEN%' is_open,
   row_number() OVER(
     PARTITION BY (r.prize_policy->>'grade_no')::integer,
                  (upper(r.class_name) LIKE '%OPEN%')
     ORDER BY md5(r.id::text)) AS seq,
   count(*) OVER(
     PARTITION BY (r.prize_policy->>'grade_no')::integer,
                  (upper(r.class_name) LIKE '%OPEN%')) AS n
 FROM my_derby.races r
 WHERE r.track='영천' AND r.status='OPEN'
  AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  AND (r.prize_policy->>'kst_date')::date >
    (now() AT TIME ZONE 'Asia/Seoul')::date
),
desired AS (
 SELECT y.*,
  CASE WHEN y.is_open THEN
    CASE WHEN y.seq <= round(y.n::numeric*11/19)
      THEN '국OPEN' ELSE '혼OPEN' END
  WHEN y.grade_no=1 THEN '1등급'
  WHEN y.grade_no=2 THEN '2등급'
  WHEN y.grade_no=3 THEN
    CASE WHEN y.seq<=round(y.n::numeric*36/83)
     THEN '국3등급' ELSE '혼3등급' END
  WHEN y.grade_no=4 THEN
    CASE WHEN y.seq<=round(y.n::numeric*72/162)
     THEN '국4등급' ELSE '혼4등급' END
  WHEN y.grade_no=5 THEN '국5등급'
  WHEN y.grade_no=6 THEN '국6등급'
  END new_label
 FROM yeongcheon y
)
INSERT INTO my_derby_private.yeongcheon_grade_label_audit
 (race_id,original_class_name,game_class_name,game_grade_no)
SELECT id,class_name,new_label,grade_no
 FROM desired WHERE new_label IS NOT NULL
ON CONFLICT (race_id) DO NOTHING;

DO $audit$
DECLARE planned bigint;total bigint;
BEGIN
 SELECT count(*) INTO total FROM my_derby.races r
 WHERE r.track='영천' AND r.status='OPEN'
  AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  AND (r.prize_policy->>'kst_date')::date >
    (now() AT TIME ZONE 'Asia/Seoul')::date;
 SELECT count(*) INTO planned FROM my_derby_private.yeongcheon_grade_label_audit a
 JOIN my_derby.races r ON r.id=a.race_id WHERE r.status='OPEN'
  AND (r.prize_policy->>'kst_date')::date >
    (now() AT TIME ZONE 'Asia/Seoul')::date;
 IF total<>planned THEN RAISE EXCEPTION 'YEONGCHEON_GRADE_LABELS_UNDERPLANNED_%_%',total,planned;END IF;
 IF EXISTS (SELECT 1 FROM my_derby_private.yeongcheon_grade_label_audit a
   JOIN my_derby.races r ON r.id=a.race_id
   WHERE r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   AND (r.prize_policy->>'grade_no')::integer<>a.game_grade_no)
 THEN RAISE EXCEPTION 'YEONGCHEON_LABEL_PLAN_MISMATCH';END IF;
END $audit$;

UPDATE my_derby.races r SET class_name=a.game_class_name,
  prize_policy=r.prize_policy||jsonb_build_object(
    'game_display_class',a.game_class_name,
    'game_grade_category_policy',a.busan_mix_policy,
    'game_source_class_name',a.original_class_name)
FROM my_derby_private.yeongcheon_grade_label_audit a
WHERE r.id=a.race_id AND r.status='OPEN'
 AND r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
 AND (r.prize_policy->>'kst_date')::date >
    (now() AT TIME ZONE 'Asia/Seoul')::date;

-- Default template display also uses Busan-style class names.
UPDATE my_derby.race_program_templates t SET
 class_name=CASE t.grade_no
  WHEN 1 THEN '1등급' WHEN 2 THEN '2등급'
  WHEN 3 THEN '국3등급' WHEN 4 THEN '국4등급'
  WHEN 5 THEN '국5등급' WHEN 6 THEN '국6등급'
  ELSE t.class_name END
WHERE t.track='영천' AND t.source_meet='제주'
 AND t.grade_no BETWEEN 1 AND 6;
