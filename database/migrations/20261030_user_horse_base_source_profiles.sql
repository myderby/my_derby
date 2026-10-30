-- Uploaded horse base-information snapshot.
-- Only records explicitly present in the supplied CSV are imported.
-- The original source horse number and meet are preserved; unmatched records
-- remain available in the snapshot without creating unowned game racehorses.
CREATE TABLE IF NOT EXISTS my_derby.horse_source_profiles(
 source_meet text NOT NULL,
 source_hr_no text NOT NULL,
 horse_id uuid REFERENCES my_derby.horses(id) ON DELETE SET NULL,
 horse_name text NOT NULL,
 source_rank text,
 source_rating integer,
 birth_date date,
 source_sex text,
 country text,
 father_name text,
 father_no text,
 mother_name text,
 mother_no text,
 owner_name text,
 owner_no text,
 trainer_name text,
 trainer_no text,
 starts_total integer NOT NULL,
 starts_year integer NOT NULL,
 wins_total integer NOT NULL,
 wins_year integer NOT NULL,
 seconds_total integer NOT NULL,
 seconds_year integer NOT NULL,
 thirds_total integer NOT NULL,
 thirds_year integer NOT NULL,
 total_prize_raw text,
 original_horse_price text,
 imported_at timestamptz NOT NULL DEFAULT now(),
 source_label text NOT NULL DEFAULT 'USER_CSV_QUERY_56',
 PRIMARY KEY(source_meet,source_hr_no),
 CONSTRAINT horse_source_meet_ck CHECK (source_meet IN ('서울','영남','제주')),
 CONSTRAINT horse_source_nonnegative_ck CHECK(
  starts_total>=0 AND starts_year>=0 AND wins_total>=0 AND wins_year>=0 AND
  seconds_total>=0 AND seconds_year>=0 AND thirds_total>=0 AND thirds_year>=0),
 CONSTRAINT horse_source_stats_consistency_ck CHECK (
  wins_total+seconds_total+thirds_total<=starts_total AND
  wins_year+seconds_year+thirds_year<=starts_year AND starts_year<=starts_total)
);
CREATE INDEX IF NOT EXISTS horse_source_profiles_horse_idx
 ON my_derby.horse_source_profiles(horse_id) WHERE horse_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS horse_source_profiles_search_idx
 ON my_derby.horse_source_profiles(horse_name);
ALTER TABLE my_derby.horse_source_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.horse_source_profiles FROM PUBLIC,anon,authenticated;
COMMENT ON TABLE my_derby.horse_source_profiles IS
 'User-supplied CSV source snapshot. Year stats refer to one-year window from source, not My Derby 364 game days.';
