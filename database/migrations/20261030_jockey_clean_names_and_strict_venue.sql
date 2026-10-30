-- Use original 2025 jockey roster to canonically identify track & jockey.
-- Keep globally unique internal name; display '강수한' for source roster.
-- Source number, internal identity, and skill/race results
-- and existing rider assignments are not deleted or rewritten.

ALTER TABLE my_derby.npc_jockeys
 ADD COLUMN IF NOT EXISTS display_name text,
 ADD COLUMN IF NOT EXISTS source_jk_no text,
 ADD COLUMN IF NOT EXISTS source_meet text;

DO $normalize$
DECLARE v_roster integer;v_found integer;v_cleaned integer;v_bad integer;
BEGIN
 SELECT count(*) INTO v_roster FROM my_derby.npc_jockeys
 WHERE name LIKE '2025 %';
 IF v_roster<>156 THEN
  RAISE EXCEPTION 'SOURCE_JOCKEY_BASELINE_CHANGED: %',v_roster;
 END IF;
 WITH imported AS (
  SELECT j.id,j.name,j.home_track,
    (regexp_match(j.name,
      '^2025 (서울|부산|영천) (.+) [(]([A-Za-z0-9]+)[)]$'))[3] parsed_jk_no
  FROM my_derby.npc_jockeys j WHERE j.name LIKE '2025 %'
 ), matches AS(
  SELECT imported.*,r.source_meet,r.jk_no,r.name AS source_name,
    regexp_replace(r.name,'^[（(][-]?[0-9]+[)）]','') AS expected_name
  FROM imported JOIN my_derby.schedule_jockey_roster_2025 r
   ON r.jk_no=imported.parsed_jk_no
   AND imported.home_track=CASE r.source_meet
    WHEN '부산경남' THEN '부산'
    WHEN '제주' THEN '영천'
    ELSE r.source_meet END
 )
 SELECT count(*) INTO v_found FROM matches
 WHERE name='2025 '||home_track||' '||expected_name||' ('||jk_no||')';
 IF v_found<>v_roster THEN
  RAISE EXCEPTION 'CANONICAL_JOCKEY_SOURCE_MISMATCH: expected % got %',
    v_roster,v_found;
 END IF;

 WITH matches AS(
 SELECT j.id,r.source_meet,r.jk_no,
   regexp_replace(r.name,'^[（(][-]?[0-9]+[)）]','') clean_name
 FROM my_derby.npc_jockeys j
 JOIN my_derby.schedule_jockey_roster_2025 r
  ON j.name='2025 '||
   (CASE r.source_meet WHEN '부산경남' THEN '부산'
    WHEN '제주' THEN '영천' ELSE r.source_meet END)||' '||
   regexp_replace(r.name,'^[（(][-]?[0-9]+[)）]','')||' ('||r.jk_no||')'
 WHERE j.name LIKE '2025 %'
 )
 UPDATE my_derby.npc_jockeys j
 SET display_name=m.clean_name,source_meet=m.source_meet,source_jk_no=m.jk_no
 FROM matches m WHERE j.id=m.id;
 GET DIAGNOSTICS v_cleaned=ROW_COUNT;
 IF v_cleaned<>156 THEN RAISE EXCEPTION 'NAMES_CLEANED_INVALID_%',v_cleaned;END IF;

 SELECT count(*) INTO v_bad FROM my_derby.npc_jockeys j
 JOIN my_derby.schedule_jockey_roster_2025 r
   ON j.source_meet=r.source_meet AND j.source_jk_no=r.jk_no
 WHERE j.display_name<>regexp_replace(r.name,'^[（(][-]?[0-9]+[)）]','')
   OR j.home_track<>CASE r.source_meet WHEN '부산경남' THEN '부산'
   WHEN '제주' THEN '영천' ELSE r.source_meet END;
 IF v_bad<>0 THEN RAISE EXCEPTION 'SOURCE_MISMATCH_AFTER_NORMALIZATION_%',v_bad;END IF;
 RAISE NOTICE 'SUCCESS % source jockeys normalized; 2025 roster region enforced',v_cleaned;
END $normalize$;

ALTER TABLE my_derby.npc_jockeys
 ADD CONSTRAINT npc_jockeys_source_track_consistent
 CHECK ((source_jk_no IS NULL AND source_meet IS NULL) OR
   (source_jk_no IS NOT NULL AND source_meet IN('서울','부산경남','제주')
    AND home_track=(CASE source_meet WHEN '부산경남' THEN '부산'
     WHEN '제주' THEN '영천' ELSE source_meet END)));

CREATE UNIQUE INDEX IF NOT EXISTS npc_jockeys_source_unique
 ON my_derby.npc_jockeys(world_id,source_meet,source_jk_no)
 WHERE source_meet IS NOT NULL AND source_jk_no IS NOT NULL;

-- Official entry writing must satisfy location matching in every codepath,
-- not just the screen's jockey selection RPC. Historical rows stay intact.
CREATE OR REPLACE FUNCTION my_derby_private.assert_official_jockey_home_track()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE race_track text;race_world uuid;jockey_track text;jockey_world uuid;
BEGIN
 IF NEW.jockey_id IS NULL THEN RETURN NEW; END IF;
 SELECT r.track,r.world_id INTO race_track,race_world
 FROM my_derby.races r WHERE r.id=NEW.race_id;
 SELECT j.home_track,j.world_id INTO jockey_track,jockey_world
 FROM my_derby.npc_jockeys j WHERE j.id=NEW.jockey_id;
 IF race_track IS NULL OR jockey_track IS NULL OR race_world IS DISTINCT FROM jockey_world
  OR race_track IS DISTINCT FROM jockey_track THEN
    RAISE EXCEPTION 'JOCKEY_TRACK_MISMATCH' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS enforce_official_jockey_home_track
 ON my_derby.race_entries;
CREATE TRIGGER enforce_official_jockey_home_track
 BEFORE INSERT OR UPDATE OF race_id,jockey_id
 ON my_derby.race_entries FOR EACH ROW
 EXECUTE FUNCTION my_derby_private.assert_official_jockey_home_track();
REVOKE ALL ON FUNCTION my_derby_private.assert_official_jockey_home_track()
 FROM PUBLIC,anon,authenticated;

-- Future 2025-style inserts are resolved and cleaned by trusted roster.
CREATE OR REPLACE FUNCTION my_derby_private.normalize_2025_jockey_on_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_match text[];v_roster my_derby.schedule_jockey_roster_2025%rowtype;
 v_expect_track text;
BEGIN
 IF NEW.name NOT LIKE '2025 %' THEN RETURN NEW;END IF;
 v_match:=regexp_match(NEW.name,
   '^2025 (서울|부산|영천) (.+) [(]([A-Za-z0-9]+)[)]$');
 IF v_match IS NULL THEN RAISE EXCEPTION 'UNRECOGNIZED_2025_JOCKEY_FORMAT';END IF;
 v_expect_track:=v_match[1];
 SELECT * INTO v_roster FROM my_derby.schedule_jockey_roster_2025 r
 WHERE r.jk_no=v_match[3]
  AND v_expect_track=(CASE r.source_meet WHEN '부산경남' THEN '부산'
   WHEN '제주' THEN '영천' ELSE r.source_meet END);
 IF NOT FOUND
  OR regexp_replace(v_roster.name,'^[（(][-]?[0-9]+[)）]','')<>v_match[2]
  OR NEW.home_track<>v_expect_track
 THEN RAISE EXCEPTION 'JOCKEY_ROSTER_IDENTITY_OR_TRACK_MISMATCH';END IF;
 NEW.display_name:=v_match[2];
 NEW.source_meet:=v_roster.source_meet;
 NEW.source_jk_no:=v_roster.jk_no;
 RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS normalize_2025_jockey_on_insert
 ON my_derby.npc_jockeys;
CREATE TRIGGER normalize_2025_jockey_on_insert
 BEFORE INSERT ON my_derby.npc_jockeys
 FOR EACH ROW EXECUTE FUNCTION my_derby_private.normalize_2025_jockey_on_insert();
REVOKE ALL ON FUNCTION my_derby_private.normalize_2025_jockey_on_insert()
 FROM PUBLIC,anon,authenticated;
