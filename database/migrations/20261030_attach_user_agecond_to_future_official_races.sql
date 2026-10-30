
-- Future official races inherit ageCond from user-verified source rows even
-- when a new weekly program is created after the original CSV import.
-- Game racing at Yeongcheon uses source_meet=제주 to resolve these rows.
CREATE OR REPLACE FUNCTION my_derby_private.attach_source_age_cond_to_new_race()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_cond text;v_rank text;v_dist integer;v_meet text;
BEGIN
 IF NEW.status IS DISTINCT FROM 'OPEN' OR NOT
   my_derby_private.player_is_special_race(
     NEW.class_name,NEW.prize_policy->>'source_rc_name')
 THEN RETURN NEW; END IF;
 v_meet:=NEW.prize_policy->>'source_meet';
 SELECT s.age_cond,s.source_rank,s.distance_m
  INTO v_cond,v_rank,v_dist
 FROM my_derby.race_program_source_2025 s
 WHERE s.source_date=(NEW.prize_policy->>'source_date')::date
 AND s.source_meet=v_meet
 AND s.source_rc_no=(NEW.prize_policy->>'source_rc_no')::integer
 LIMIT 1;
 IF my_derby_private.player_age_cond_valid(v_cond) THEN
   NEW.prize_policy:=NEW.prize_policy||
    jsonb_build_object('ageCond',v_cond,
      'ageCondSource','RACE_PROGRAM_SOURCE_2025',
      'ageCondOriginalRank',v_rank,
      'ageCondOriginalDistance',v_dist,
      'ageCondOriginalMeet',v_meet,
      'ageCondGameTrack',CASE v_meet WHEN '제주' THEN '영천'
        WHEN '부산경남' THEN '부산' ELSE '서울' END);
 END IF;
 RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS attach_source_age_cond_to_new_race
 ON my_derby.races;
CREATE TRIGGER attach_source_age_cond_to_new_race
 BEFORE INSERT ON my_derby.races
 FOR EACH ROW
 EXECUTE FUNCTION my_derby_private.attach_source_age_cond_to_new_race();
REVOKE ALL ON FUNCTION my_derby_private.attach_source_age_cond_to_new_race()
 FROM PUBLIC,anon,authenticated;
