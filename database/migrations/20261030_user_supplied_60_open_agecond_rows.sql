
-- Imported directly from user-uploaded Supabase Snippet Untitled query (55).csv
-- 60 distinct source OPEN races: 서울 32, 부산경남 19, 제주 9.
-- Game track 제주 -> 영천, but source_meet='제주' and source_rank='제OPEN'
-- MUST remain unchanged, even where game class_name is 국OPEN/혼OPEN.
DO $apply$
DECLARE payload jsonb:='[{"source_date":"2025-02-16","source_meet":"서울","source_rc_no":8,"distance_m":1200,"rank":"국OPEN","age_cond":"4세이상"},{"source_date":"2025-02-23","source_meet":"부산경남","source_rc_no":6,"distance_m":1400,"rank":"국OPEN","age_cond":"3세"},{"source_date":"2025-02-23","source_meet":"서울","source_rc_no":8,"distance_m":1400,"rank":"국OPEN","age_cond":"3세"},{"source_date":"2025-03-09","source_meet":"부산경남","source_rc_no":6,"distance_m":1200,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-03-16","source_meet":"서울","source_rc_no":8,"distance_m":2000,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-03-22","source_meet":"제주","source_rc_no":7,"distance_m":1300,"rank":"제OPEN","age_cond":"2세이상"},{"source_date":"2025-03-23","source_meet":"서울","source_rc_no":8,"distance_m":1800,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-03-30","source_meet":"부산경남","source_rc_no":6,"distance_m":1600,"rank":"국OPEN","age_cond":"3세"},{"source_date":"2025-04-06","source_meet":"부산경남","source_rc_no":6,"distance_m":1600,"rank":"국OPEN","age_cond":"3세"},{"source_date":"2025-04-13","source_meet":"부산경남","source_rc_no":4,"distance_m":1600,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-04-13","source_meet":"부산경남","source_rc_no":5,"distance_m":1800,"rank":"혼OPEN","age_cond":"남4이하/북3"},{"source_date":"2025-04-13","source_meet":"부산경남","source_rc_no":6,"distance_m":1800,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-04-13","source_meet":"서울","source_rc_no":6,"distance_m":1800,"rank":"혼OPEN","age_cond":"남4이하/북3"},{"source_date":"2025-04-13","source_meet":"서울","source_rc_no":7,"distance_m":1600,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-04-13","source_meet":"서울","source_rc_no":8,"distance_m":1200,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-04-13","source_meet":"서울","source_rc_no":9,"distance_m":1800,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-04-20","source_meet":"서울","source_rc_no":7,"distance_m":2000,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-04-27","source_meet":"서울","source_rc_no":8,"distance_m":1400,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-05-04","source_meet":"부산경남","source_rc_no":6,"distance_m":1800,"rank":"국OPEN","age_cond":"3세"},{"source_date":"2025-05-10","source_meet":"제주","source_rc_no":7,"distance_m":1400,"rank":"제OPEN","age_cond":"2세이상"},{"source_date":"2025-05-11","source_meet":"서울","source_rc_no":7,"distance_m":1800,"rank":"국OPEN","age_cond":"3세"},{"source_date":"2025-05-18","source_meet":"서울","source_rc_no":7,"distance_m":2000,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-05-18","source_meet":"서울","source_rc_no":8,"distance_m":1200,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-05-25","source_meet":"부산경남","source_rc_no":2,"distance_m":1800,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-06-01","source_meet":"부산경남","source_rc_no":6,"distance_m":1600,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-06-08","source_meet":"서울","source_rc_no":7,"distance_m":2000,"rank":"국OPEN","age_cond":"3세"},{"source_date":"2025-06-15","source_meet":"서울","source_rc_no":8,"distance_m":2000,"rank":"국OPEN","age_cond":"3세"},{"source_date":"2025-06-29","source_meet":"부산경남","source_rc_no":6,"distance_m":1600,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-07-19","source_meet":"제주","source_rc_no":7,"distance_m":1300,"rank":"제OPEN","age_cond":"2세이상"},{"source_date":"2025-08-03","source_meet":"서울","source_rc_no":11,"distance_m":2000,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-08-17","source_meet":"부산경남","source_rc_no":6,"distance_m":1200,"rank":"국OPEN","age_cond":"2세"},{"source_date":"2025-08-17","source_meet":"서울","source_rc_no":8,"distance_m":1200,"rank":"국OPEN","age_cond":"2세"},{"source_date":"2025-09-06","source_meet":"서울","source_rc_no":4,"distance_m":1200,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-09-06","source_meet":"서울","source_rc_no":5,"distance_m":1700,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-09-06","source_meet":"서울","source_rc_no":6,"distance_m":1400,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-09-06","source_meet":"서울","source_rc_no":7,"distance_m":1800,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-09-06","source_meet":"서울","source_rc_no":8,"distance_m":1200,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-09-07","source_meet":"서울","source_rc_no":7,"distance_m":1200,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-09-07","source_meet":"서울","source_rc_no":8,"distance_m":1800,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-09-13","source_meet":"제주","source_rc_no":8,"distance_m":1610,"rank":"제OPEN","age_cond":"2세이상"},{"source_date":"2025-09-14","source_meet":"부산경남","source_rc_no":6,"distance_m":1200,"rank":"국OPEN","age_cond":"2세"},{"source_date":"2025-09-14","source_meet":"서울","source_rc_no":8,"distance_m":1200,"rank":"국OPEN","age_cond":"2세"},{"source_date":"2025-09-21","source_meet":"서울","source_rc_no":8,"distance_m":1400,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-09-28","source_meet":"서울","source_rc_no":8,"distance_m":1800,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-10-19","source_meet":"부산경남","source_rc_no":5,"distance_m":1200,"rank":"국OPEN","age_cond":"2세"},{"source_date":"2025-10-19","source_meet":"서울","source_rc_no":7,"distance_m":1200,"rank":"국OPEN","age_cond":"2세"},{"source_date":"2025-10-19","source_meet":"서울","source_rc_no":8,"distance_m":2000,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-10-25","source_meet":"제주","source_rc_no":5,"distance_m":1610,"rank":"제OPEN","age_cond":"7세이상"},{"source_date":"2025-10-25","source_meet":"제주","source_rc_no":6,"distance_m":1400,"rank":"제OPEN","age_cond":"6세이하"},{"source_date":"2025-10-26","source_meet":"부산경남","source_rc_no":3,"distance_m":2000,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-10-26","source_meet":"부산경남","source_rc_no":6,"distance_m":1400,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-11-15","source_meet":"제주","source_rc_no":6,"distance_m":1200,"rank":"제OPEN","age_cond":"3세이하"},{"source_date":"2025-11-16","source_meet":"서울","source_rc_no":8,"distance_m":1200,"rank":"혼OPEN","age_cond":"남3/북2"},{"source_date":"2025-11-23","source_meet":"부산경남","source_rc_no":5,"distance_m":1800,"rank":"국OPEN","age_cond":"3세이상"},{"source_date":"2025-11-23","source_meet":"부산경남","source_rc_no":6,"distance_m":1400,"rank":"국OPEN","age_cond":"2세"},{"source_date":"2025-11-30","source_meet":"부산경남","source_rc_no":5,"distance_m":1200,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-11-30","source_meet":"서울","source_rc_no":7,"distance_m":1200,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-11-30","source_meet":"서울","source_rc_no":8,"distance_m":2300,"rank":"혼OPEN","age_cond":"3세이상"},{"source_date":"2025-12-13","source_meet":"제주","source_rc_no":6,"distance_m":1610,"rank":"제OPEN","age_cond":"2세이상"},{"source_date":"2025-12-27","source_meet":"제주","source_rc_no":4,"distance_m":1610,"rank":"제OPEN","age_cond":"2세이상"}]'::jsonb;
 v_total int;v_match int;v_changed int;v_game int;v_yeongcheon int;
BEGIN
 CREATE TEMP TABLE age_cond_csv_import(
   source_date date NOT NULL,source_meet text NOT NULL,
   source_rc_no smallint NOT NULL,distance_m int NOT NULL,
   rank text NOT NULL,age_cond text NOT NULL,
   PRIMARY KEY(source_date,source_meet,source_rc_no)
 ) ON COMMIT DROP;
 INSERT INTO age_cond_csv_import
 SELECT source_date::date,source_meet,source_rc_no::smallint,distance_m,rank,age_cond
 FROM jsonb_to_recordset(payload) AS s(
   source_date text,source_meet text,source_rc_no int,
   distance_m int,rank text,age_cond text
 );
 SELECT count(*) INTO v_total FROM age_cond_csv_import;
 IF v_total<>60 THEN RAISE EXCEPTION 'AGE_COND_CSV_ROW_COUNT_INVALID: %',v_total;END IF;
 SELECT count(*) INTO v_match FROM age_cond_csv_import i
 JOIN my_derby.race_program_source_2025 s
   ON s.source_date=i.source_date AND s.source_meet=i.source_meet
    AND s.source_rc_no=i.source_rc_no
    AND s.distance_m=i.distance_m AND s.source_rank=i.rank
 WHERE my_derby_private.player_age_cond_valid(i.age_cond);
 IF v_match<>60 THEN
  RAISE EXCEPTION 'AGE_COND_ORIGINAL_IDENTITY_OR_FORMAT_MISMATCH: % / 60',v_match;
 END IF;

 -- Update existing source 2025 schedule for future generated programs.
 UPDATE my_derby.race_program_source_2025 s
 SET age_cond=i.age_cond FROM age_cond_csv_import i
 WHERE s.source_date=i.source_date AND s.source_meet=i.source_meet
   AND s.source_rc_no=i.source_rc_no
   AND s.age_cond IS DISTINCT FROM i.age_cond;
 GET DIAGNOSTICS v_changed=ROW_COUNT;
 IF v_changed NOT IN (0,60) THEN
  RAISE EXCEPTION 'SOURCE_UPSERT_PARTIAL_DATA_CONFLICT: %',v_changed;
 END IF;

 -- Update all open, scheduled game instances matching those original races.
 -- Race grade, age, runner slots, starts, stakes flags, and entrants remain intact.
 UPDATE my_derby.races r
 SET prize_policy=r.prize_policy||
   jsonb_build_object(
    'ageCond',i.age_cond,
    'ageCondSource','USER_UPLOADED_20261030_CSV',
    'ageCondOriginalRank',i.rank,
    'ageCondOriginalDistance',i.distance_m,
    'ageCondOriginalMeet',i.source_meet,
    'ageCondGameTrack',CASE i.source_meet
      WHEN '제주' THEN '영천'
      WHEN '부산경남' THEN '부산'
      ELSE '서울' END
   )
 FROM age_cond_csv_import i
 WHERE r.status='OPEN'
  AND r.prize_policy->>'source_date'=i.source_date::text
  AND r.prize_policy->>'source_meet'=i.source_meet
  AND (r.prize_policy->>'source_rc_no')::integer=i.source_rc_no
  AND r.track=CASE i.source_meet WHEN '제주' THEN '영천'
      WHEN '부산경남' THEN '부산' ELSE '서울' END
  AND my_derby_private.player_is_special_race(
     r.class_name,r.prize_policy->>'source_rc_name');
 GET DIAGNOSTICS v_game=ROW_COUNT;
 IF v_game<>62 THEN
   RAISE EXCEPTION 'AGE_COND_GAME_INSTANCES_EXPECTED_62_FOUND_%',v_game;
 END IF;
 SELECT count(*) INTO v_yeongcheon FROM my_derby.races r
 JOIN age_cond_csv_import i
  ON r.prize_policy->>'source_date'=i.source_date::text
  AND r.prize_policy->>'source_meet'=i.source_meet
  AND (r.prize_policy->>'source_rc_no')::integer=i.source_rc_no
 WHERE i.source_meet='제주' AND r.track='영천' AND r.status='OPEN'
 AND r.prize_policy->>'ageCond'=i.age_cond;
 IF v_yeongcheon<>9 THEN
   RAISE EXCEPTION 'JEJU_TO_YEONGCHEON_MAPPING_EXPECTED_9_FOUND_%',v_yeongcheon;
 END IF;
 RAISE NOTICE 'USER_AGECOND_IMPORT_OK source 60; gameInstances %; Yeongcheon %; birthHemisphere-dependent races 3',v_game,v_yeongcheon;
END $apply$;
