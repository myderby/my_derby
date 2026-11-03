-- Manage horse injury/illness names and their user-defined severity code (dvcd).
-- dvcd meanings follow the requested recovery / racing-retirement scale.

CREATE TABLE IF NOT EXISTS my_derby.horse_injury_severity_codes (
  dvcd smallint PRIMARY KEY CHECK (dvcd BETWEEN 1 AND 5),
  severity_name text NOT NULL,
  recovery_guidance text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO my_derby.horse_injury_severity_codes (dvcd, severity_name, recovery_guidance)
VALUES
  (1, '경주 생활 은퇴 수준', '경주마 생활을 은퇴해야 할 정도의 중증 부상'),
  (2, '1년 이상 요양', '회복까지 1년 이상 걸릴 것으로 예상되는 부상'),
  (3, '약 6개월 요양', '회복까지 약 6개월이 걸릴 것으로 예상되는 부상'),
  (4, '2~3개월 요양', '회복까지 2~3개월이 걸릴 것으로 예상되는 부상'),
  (5, '1개월 이내 치료', '1개월 이내 치료와 회복이 가능할 것으로 예상되는 경상')
ON CONFLICT (dvcd) DO UPDATE
SET severity_name = EXCLUDED.severity_name,
    recovery_guidance = EXCLUDED.recovery_guidance;

CREATE TABLE IF NOT EXISTS my_derby.horse_illness_catalog (
  ill_name text PRIMARY KEY,
  dvcd smallint NOT NULL REFERENCES my_derby.horse_injury_severity_codes(dvcd)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  description text,
  source_name text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT horse_illness_catalog_name_not_blank CHECK (btrim(ill_name) <> '')
);

CREATE INDEX IF NOT EXISTS horse_illness_catalog_dvcd_idx
  ON my_derby.horse_illness_catalog (dvcd)
  WHERE is_active;

COMMENT ON TABLE my_derby.horse_illness_catalog IS
  '경주마 질병·부상명(ill_name)별 심각도 코드(dvcd)를 관리하는 기준 목록';
COMMENT ON COLUMN my_derby.horse_illness_catalog.ill_name IS
  '원본 illName에 해당하는 경주마 질병 또는 부상명';
COMMENT ON COLUMN my_derby.horse_illness_catalog.dvcd IS
  '심각도 코드: 1 은퇴 수준, 2 1년 이상, 3 약 6개월, 4 2~3개월, 5 1개월 이내';
COMMENT ON TABLE my_derby.horse_injury_severity_codes IS
  '경주마 질병·부상 심각도 코드(dvcd)와 회복 안내';

ALTER TABLE my_derby.horse_injury_severity_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE my_derby.horse_illness_catalog ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.horse_injury_severity_codes FROM PUBLIC, anon, authenticated;
REVOKE ALL ON my_derby.horse_illness_catalog FROM PUBLIC, anon, authenticated;
