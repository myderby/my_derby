-- 19:00 Seoul race 1: TEST FIXTURE ONLY.
-- Five actual game roster grade-1 horses and five grade-5 horses.
-- A snapshot of each current ability is used; actual horses and official
-- race entries/results are NEVER changed. Other test slots untouched.
DO $fixture$
DECLARE before_count integer;affected integer;result_count integer;
 v_grade1 integer;v_grade5 integer;v_label text;
BEGIN
 SELECT jsonb_array_length(race_input->'runners') INTO before_count
 FROM my_derby.race_test_fixtures WHERE slot=0 AND is_test_only FOR UPDATE;
 IF before_count IS NULL THEN RAISE EXCEPTION 'MISSING_TEST_ONLY_SLOT_0';END IF;
 WITH selection AS (
   SELECT h.id,h.name,h.source_hr_no,h.source_grade_no,h.fatigue,
    h.condition_score,a.current_stats,a.distance_affinity,
    ROW_NUMBER() OVER(PARTITION BY h.source_grade_no
      ORDER BY md5(h.id::text||':test19_grade_mix_v1')) rank_in_grade
   FROM my_derby.horses h
   JOIN my_derby.horse_abilities a ON a.horse_id=h.id
   WHERE h.source_meet='서울' AND h.source_grade_no IN(1,5)
    AND h.npc_owner_id IS NOT NULL
    AND h.life_stage='RACING' AND h.health_state='HEALTHY'
    AND NOT h.racing_retired_permanently
 ), selected AS (
   SELECT *,row_number() OVER(ORDER BY source_grade_no,rank_in_grade) gate
   FROM selection WHERE rank_in_grade<=5
 ), participants AS (
   SELECT s.gate,
   (fixture.race_input->'runners'->(s.gate::int-1))||
      jsonb_build_object(
        'id',s.id::text,'name',s.name,
        'horseNo',s.source_hr_no,'sourceHorseId',s.id::text,
        'sourceMeet','서울','gradeNo',s.source_grade_no,
        'gradeName',s.source_grade_no||'등급',
        'horse',s.current_stats,
        'fatigue',s.fatigue,'condition',s.condition_score,
        'number',s.gate,'gate',s.gate,
        'weightKg',CASE s.source_grade_no WHEN 1 THEN 57 ELSE 53 END,
        'distanceFit',coalesce((s.distance_affinity->>'1200')::numeric,85),
        'testOnly',true
      ) runner
   FROM selected s
   CROSS JOIN my_derby.race_test_fixtures fixture
   WHERE fixture.slot=0 AND fixture.is_test_only
 )
 UPDATE my_derby.race_test_fixtures f
 SET label='19:00 · 서울 1경주 · 1등급 5두 / 5등급 5두 (테스트)',
 race_input=(f.race_input-'runners')||
    jsonb_build_object(
    'runners',(SELECT jsonb_agg(runner ORDER BY gate) FROM participants),
    'raceId','TEST-19:00-1',
    'raceNo',1,'startTime','19:00',
    'fixtureClass','1등급 5두 + 5등급 5두 (혼합 테스트)',
    'testOnly',true,
    'fixtureSource','MY_DERBY_GRADE_1_AND_5_ROSTER_20261030',
    'gradeMix',jsonb_build_object('1',5,'5',5)),
 updated_at=now()
 WHERE f.slot=0 AND f.is_test_only;
 GET DIAGNOSTICS affected=ROW_COUNT;
 IF affected<>1 THEN RAISE EXCEPTION 'FIXTURE_SLOT_COUNT_INVALID %',affected;END IF;
 SELECT jsonb_array_length(f.race_input->'runners'),
 count(*) FILTER(WHERE (r.runner->>'gradeNo')::int=1),
 count(*) FILTER(WHERE (r.runner->>'gradeNo')::int=5),
 f.label INTO result_count,v_grade1,v_grade5,v_label
 FROM my_derby.race_test_fixtures f,
  LATERAL jsonb_array_elements(f.race_input->'runners') r(runner)
 WHERE f.slot=0 GROUP BY f.race_input,f.label;
 IF result_count<>10 OR v_grade1<>5 OR v_grade5<>5 OR
   (SELECT count(DISTINCT runner->>'id') FROM my_derby.race_test_fixtures f,
    LATERAL jsonb_array_elements(f.race_input->'runners') r(runner)
    WHERE f.slot=0)<>10
 THEN RAISE EXCEPTION 'TEST_FIXTURE_VALIDATION_FAILED count=% grade1=% grade5=%',
  result_count,v_grade1,v_grade5;END IF;
 RAISE NOTICE 'PASS race_test_fixtures slot 0: 10 participants, grade1 5, grade5 5. Official state untouched.';
END $fixture$;