
-- The user-supplied latest source (Supabase Snippet Untitled query (57).csv)
-- has 89 current active jockeys. A jockey's jkNo belongs to exactly one meet.
-- retain archived jockey IDs for past race result referential integrity.
CREATE TABLE IF NOT EXISTS my_derby.jockey_current_source_roster (
 jk_no text PRIMARY KEY,
 source_meet text NOT NULL CHECK (source_meet IN ('서울','부산경남','제주')),
 jockey_name text NOT NULL,
 game_track text GENERATED ALWAYS AS
  (CASE source_meet WHEN '부산경남' THEN '부산'
    WHEN '제주' THEN '영천' ELSE source_meet END) STORED,
 source_file text NOT NULL DEFAULT 'Supabase Snippet Untitled query (57).csv'
);
ALTER TABLE my_derby.jockey_current_source_roster ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.jockey_current_source_roster FROM PUBLIC,anon,authenticated;
INSERT INTO my_derby.jockey_current_source_roster(jk_no,source_meet,jockey_name)
SELECT v.jk_no,v.meet,v.name FROM jsonb_to_recordset('[{"meet":"제주","jkNo":"003077","name":"강수한"},{"meet":"제주","jkNo":"003084","name":"김한남"},{"meet":"제주","jkNo":"003089","name":"박성광"},{"meet":"제주","jkNo":"003080","name":"문현진"},{"meet":"제주","jkNo":"003092","name":"이성민"},{"meet":"제주","jkNo":"003093","name":"이소연"},{"meet":"제주","jkNo":"003082","name":"김홍권"},{"meet":"제주","jkNo":"003006","name":"김용섭"},{"meet":"제주","jkNo":"003094","name":"곽석"},{"meet":"제주","jkNo":"003075","name":"원유일"},{"meet":"제주","jkNo":"003095","name":"박재희"},{"meet":"제주","jkNo":"003073","name":"김다영"},{"meet":"제주","jkNo":"003053","name":"안득수"},{"meet":"제주","jkNo":"003097","name":"김동규"},{"meet":"제주","jkNo":"003055","name":"장우성"},{"meet":"제주","jkNo":"003061","name":"곽용남"},{"meet":"제주","jkNo":"003096","name":"양민재"},{"meet":"제주","jkNo":"003087","name":"임재광"},{"meet":"제주","jkNo":"003066","name":"나유나"},{"meet":"제주","jkNo":"003079","name":"김경휴"},{"meet":"제주","jkNo":"003058","name":"한영민"},{"meet":"제주","jkNo":"003070","name":"전현준"},{"meet":"제주","jkNo":"003044","name":"정명일"},{"meet":"제주","jkNo":"003086","name":"이동준"},{"meet":"제주","jkNo":"003081","name":"김준호"},{"meet":"서울","jkNo":"080100","name":"김옥성"},{"meet":"서울","jkNo":"080122","name":"신형철"},{"meet":"서울","jkNo":"080337","name":"문정균"},{"meet":"서울","jkNo":"080361","name":"최범현"},{"meet":"서울","jkNo":"080405","name":"김용근"},{"meet":"서울","jkNo":"080417","name":"유승완"},{"meet":"서울","jkNo":"080434","name":"김철호"},{"meet":"서울","jkNo":"080473","name":"김정준"},{"meet":"서울","jkNo":"080476","name":"장추열"},{"meet":"서울","jkNo":"080486","name":"이혁"},{"meet":"서울","jkNo":"080487","name":"임기원"},{"meet":"서울","jkNo":"080512","name":"김태훈"},{"meet":"서울","jkNo":"080513","name":"송재철"},{"meet":"서울","jkNo":"080515","name":"조한별"},{"meet":"서울","jkNo":"080529","name":"김동수"},{"meet":"서울","jkNo":"080530","name":"정정희"},{"meet":"서울","jkNo":"080533","name":"조상범"},{"meet":"서울","jkNo":"080547","name":"이용호"},{"meet":"서울","jkNo":"080550","name":"조재로"},{"meet":"서울","jkNo":"080562","name":"이동하"},{"meet":"서울","jkNo":"080578","name":"김효정"},{"meet":"서울","jkNo":"080582","name":"빅투아르"},{"meet":"서울","jkNo":"080588","name":"정우주"},{"meet":"서울","jkNo":"080598","name":"김아현"},{"meet":"서울","jkNo":"080599","name":"김태현"},{"meet":"서울","jkNo":"080602","name":"임다빈"},{"meet":"서울","jkNo":"080603","name":"김태희"},{"meet":"서울","jkNo":"080608","name":"오수철"},{"meet":"서울","jkNo":"080611","name":"푸르칸"},{"meet":"서울","jkNo":"080612","name":"김성현"},{"meet":"서울","jkNo":"080616","name":"마이아"},{"meet":"서울","jkNo":"080617","name":"코지"},{"meet":"서울","jkNo":"080618","name":"권중석"},{"meet":"서울","jkNo":"080621","name":"우인철"},{"meet":"서울","jkNo":"080622","name":"조성환"},{"meet":"서울","jkNo":"080624","name":"루이스"},{"meet":"서울","jkNo":"080625","name":"안드레"},{"meet":"부산경남","jkNo":"080401","name":"김동영"},{"meet":"부산경남","jkNo":"080403","name":"김어수"},{"meet":"부산경남","jkNo":"080421","name":"송경윤"},{"meet":"부산경남","jkNo":"080423","name":"최시대"},{"meet":"부산경남","jkNo":"080431","name":"이성재"},{"meet":"부산경남","jkNo":"080438","name":"조인권"},{"meet":"부산경남","jkNo":"080482","name":"정동철"},{"meet":"부산경남","jkNo":"080483","name":"유광희"},{"meet":"부산경남","jkNo":"080484","name":"서승운"},{"meet":"부산경남","jkNo":"080516","name":"다나카"},{"meet":"부산경남","jkNo":"080532","name":"채상현"},{"meet":"부산경남","jkNo":"080546","name":"박재이"},{"meet":"부산경남","jkNo":"080548","name":"이현종"},{"meet":"부산경남","jkNo":"080551","name":"진겸"},{"meet":"부산경남","jkNo":"080564","name":"이효식"},{"meet":"부산경남","jkNo":"080565","name":"정도윤"},{"meet":"부산경남","jkNo":"080566","name":"최은경"},{"meet":"부산경남","jkNo":"080568","name":"다실바"},{"meet":"부산경남","jkNo":"080580","name":"전진구"},{"meet":"부산경남","jkNo":"080584","name":"다비드"},{"meet":"부산경남","jkNo":"080600","name":"모준호"},{"meet":"부산경남","jkNo":"080605","name":"서강주"},{"meet":"부산경남","jkNo":"080606","name":"신윤섭"},{"meet":"부산경남","jkNo":"080607","name":"윤형석"},{"meet":"부산경남","jkNo":"080610","name":"이홍락"},{"meet":"부산경남","jkNo":"080619","name":"남정혁"},{"meet":"부산경남","jkNo":"080627","name":"홍환웅"}]'::jsonb)
 v(meet text,jk_no text,name text)
ON CONFLICT(jk_no) DO UPDATE SET
 source_meet=EXCLUDED.source_meet,jockey_name=EXCLUDED.jockey_name;

DO $validate$
DECLARE n integer;matching integer;
BEGIN
 SELECT count(*) INTO n FROM my_derby.jockey_current_source_roster;
 IF n<>89 THEN RAISE EXCEPTION 'EXPECTED_89_CURRENT_JOCKEYS_%',n;END IF;
 SELECT count(*) INTO matching FROM my_derby.jockey_current_source_roster src
 JOIN my_derby.npc_jockeys j
 ON j.source_jk_no=src.jk_no AND j.source_meet=src.source_meet
 AND j.display_name=src.jockey_name AND j.home_track=src.game_track;
 IF matching<>89 THEN RAISE EXCEPTION 'ROSTER_FILE_MATCHED_%_OF_89',matching;END IF;
END $validate$;

-- Never delete jockeys from completed historical results.
-- Non-CSV and cross-meet duplicates become inactive and thus invisible.
UPDATE my_derby.npc_jockeys j SET is_active=
 EXISTS(SELECT 1 FROM my_derby.jockey_current_source_roster src
 WHERE src.jk_no=j.source_jk_no AND src.source_meet=j.source_meet
 AND src.jockey_name=j.display_name AND src.game_track=j.home_track)
WHERE j.world_id=(SELECT id FROM my_derby.worlds WHERE world_key='kra_roster_v1')
AND j.is_active IS DISTINCT FROM EXISTS(
 SELECT 1 FROM my_derby.jockey_current_source_roster src
 WHERE src.jk_no=j.source_jk_no AND src.source_meet=j.source_meet
 AND src.jockey_name=j.display_name AND src.game_track=j.home_track);

CREATE UNIQUE INDEX IF NOT EXISTS jockey_one_active_row_per_source_no
 ON my_derby.npc_jockeys(world_id,source_jk_no)
 WHERE is_active AND source_jk_no IS NOT NULL;

CREATE OR REPLACE FUNCTION my_derby_private.enforce_current_jockey_source()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
 IF NEW.is_active AND NOT EXISTS(
  SELECT 1 FROM my_derby.jockey_current_source_roster src
  WHERE src.jk_no=NEW.source_jk_no
    AND src.source_meet=NEW.source_meet
    AND src.game_track=NEW.home_track
    AND src.jockey_name=NEW.display_name)
 THEN RAISE EXCEPTION 'JOCKEY_NOT_IN_CURRENT_MEET_FILE';END IF;
 RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS enforce_current_jockey_source ON my_derby.npc_jockeys;
CREATE TRIGGER enforce_current_jockey_source
 BEFORE INSERT OR UPDATE OF is_active,home_track,source_meet,source_jk_no,display_name
 ON my_derby.npc_jockeys FOR EACH ROW
 EXECUTE FUNCTION my_derby_private.enforce_current_jockey_source();
REVOKE ALL ON FUNCTION my_derby_private.enforce_current_jockey_source()
 FROM PUBLIC,anon,authenticated;

-- Existing official entry guard now also disallows non-CSV/inactive jockeys.
CREATE OR REPLACE FUNCTION my_derby_private.assert_official_jockey_home_track()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE race_track text;race_world uuid;jockey_track text;jockey_world uuid;
 active_ok boolean;csv_no text;csv_meet text;name_display text;
BEGIN
 IF NEW.jockey_id IS NULL THEN RETURN NEW;END IF;
 SELECT r.track,r.world_id INTO race_track,race_world
 FROM my_derby.races r WHERE r.id=NEW.race_id;
 SELECT j.home_track,j.world_id,j.is_active,j.source_jk_no,
    j.source_meet,j.display_name
 INTO jockey_track,jockey_world,active_ok,csv_no,csv_meet,name_display
 FROM my_derby.npc_jockeys j WHERE j.id=NEW.jockey_id;
 IF race_track IS NULL OR jockey_track IS NULL
 OR race_world IS DISTINCT FROM jockey_world
 OR race_track IS DISTINCT FROM jockey_track
 THEN RAISE EXCEPTION 'JOCKEY_TRACK_MISMATCH';END IF;
 IF NOT coalesce(active_ok,false) OR NOT EXISTS(
   SELECT 1 FROM my_derby.jockey_current_source_roster src
   WHERE src.jk_no=csv_no AND src.source_meet=csv_meet
    AND src.game_track=jockey_track AND src.jockey_name=name_display)
 THEN RAISE EXCEPTION 'JOCKEY_NOT_IN_CURRENT_MEET_FILE';END IF;
 RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION my_derby_private.assert_official_jockey_home_track()
 FROM PUBLIC,anon,authenticated;

-- Only unfinished races are corrected; horse, gate, weight, strategy unchanged.
-- Already valid jockey picks are preserved. Invalid picks are replaced by a
-- rider from the same track with the fewest game-day bookings, max daily rides.
DO $reassign$
DECLARE rec record; replacement uuid; corrected integer:=0; remaining integer;
BEGIN
 IF (SELECT count(*) FROM my_derby.npc_jockeys WHERE is_active)<>89
 THEN RAISE EXCEPTION 'ACTIVE_JOCKEY_COUNT_NOT_89';END IF;
 FOR rec IN
  SELECT e.id,e.race_id,r.world_id,r.track,r.race_day
  FROM my_derby.race_entries e
  JOIN my_derby.races r ON r.id=e.race_id
  LEFT JOIN my_derby.npc_jockeys j ON j.id=e.jockey_id
  WHERE r.status='OPEN' AND e.status IN('CONFIRMED','APPLIED')
  AND (j.id IS NULL OR j.is_active=false
     OR j.home_track IS DISTINCT FROM r.track)
  ORDER BY r.race_day,r.track,r.start_time,r.race_no,e.gate_no,e.id
 LOOP
  replacement:=null;
  SELECT j.id INTO replacement
  FROM my_derby.npc_jockeys j
  WHERE j.world_id=rec.world_id
   AND j.is_active AND j.home_track=rec.track
   AND EXISTS(SELECT 1 FROM my_derby.jockey_current_source_roster src
     WHERE src.jk_no=j.source_jk_no AND src.source_meet=j.source_meet
       AND src.game_track=j.home_track AND src.jockey_name=j.display_name)
   AND NOT EXISTS(
     SELECT 1 FROM my_derby.race_entries other
     WHERE other.race_id=rec.race_id AND other.id<>rec.id
       AND other.jockey_id=j.id AND other.status IN('CONFIRMED','APPLIED','COMPLETED'))
   AND (
     SELECT count(*) FROM my_derby.race_entries booked
     JOIN my_derby.races race ON race.id=booked.race_id
     WHERE booked.jockey_id=j.id AND race.race_day=rec.race_day
      AND race.world_id=rec.world_id
      AND race.status NOT IN('CANCELLED')
      AND booked.status IN('CONFIRMED','APPLIED','COMPLETED')
   )<j.max_daily_rides
  ORDER BY (
   SELECT count(*) FROM my_derby.race_entries booked
   JOIN my_derby.races race ON race.id=booked.race_id
   WHERE booked.jockey_id=j.id AND race.race_day=rec.race_day
    AND race.world_id=rec.world_id
    AND race.status NOT IN('CANCELLED')
    AND booked.status IN('CONFIRMED','APPLIED','COMPLETED')
  ),md5(j.id::text||rec.race_id::text) LIMIT 1;
  IF replacement IS NULL THEN
    RAISE EXCEPTION 'NO_RIDER_CAPACITY_FOR_OPEN_RACE_%',rec.race_id;
  END IF;
  UPDATE my_derby.race_entries SET jockey_id=replacement WHERE id=rec.id;
  corrected:=corrected+1;
 END LOOP;
 SELECT count(*) INTO remaining FROM my_derby.race_entries e
 JOIN my_derby.races r ON r.id=e.race_id
 LEFT JOIN my_derby.npc_jockeys j ON j.id=e.jockey_id
 WHERE r.status='OPEN' AND e.status IN('CONFIRMED','APPLIED')
 AND (j.id IS NULL OR NOT j.is_active OR j.home_track IS DISTINCT FROM r.track);
 IF remaining>0 THEN RAISE EXCEPTION 'INVALID_OPEN_RIDER_ASSIGNMENTS_REMAIN_%',remaining;END IF;
 RAISE NOTICE 'FILE_89_ACTIVE_JOCKEYS_ENFORCED, reassigned % unfinished entries',corrected;
END $reassign$;
