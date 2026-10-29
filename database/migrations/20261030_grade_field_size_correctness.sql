CREATE OR REPLACE FUNCTION my_derby_private.process_horse_grade_changes()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE h record; v_match record; v_target integer;v_reason text;
 v_day integer;v_count int:=0; v_skip int:=0;
BEGIN
 IF (now() AT TIME ZONE 'Asia/Seoul')::time <'23:10'::time THEN
  RETURN jsonb_build_object('status','NOT_DUE');END IF;
 FOR h IN SELECT x.id,x.world_id,x.source_grade_no,x.source_meet
  FROM my_derby.horses x JOIN my_derby.worlds w ON w.id=x.world_id
  WHERE w.status='ACTIVE' AND x.life_stage='RACING'
   AND x.source_grade_no BETWEEN 1 AND 6
   AND (x.owner_user_id IS NOT NULL OR x.npc_owner_id IS NOT NULL)
  ORDER BY x.id
 LOOP
  v_day:=(my_derby.world_clock(h.world_id)->>'gameDayStart')::int+6;
  SELECT count(*) n,
    count(*) FILTER(WHERE ranked.finishing_rank=1) wins,
    count(*) FILTER(WHERE ranked.finishing_rank<=3) places,
    count(*) FILTER(WHERE ranked.finishing_rank>ceil(ranked.field_size*0.6)) bottom
  INTO v_match
  FROM(
   SELECT rr.finishing_rank,(SELECT count(*) FROM my_derby.race_results fld WHERE fld.race_run_id=rr.race_run_id) field_size
   FROM my_derby.race_results rr JOIN my_derby.race_runs run ON run.id=rr.race_run_id
   JOIN my_derby.races race ON race.id=run.race_id
   WHERE rr.horse_id=h.id AND race.status='FINISHED'
    AND race.prize_policy->>'grade_no'=h.source_grade_no::text
   ORDER BY race.race_day DESC,race.start_time DESC
   LIMIT 6
  )ranked;
  v_target:=null;v_reason:=null;
  IF v_match.n>=3 AND v_match.wins>=3 AND h.source_grade_no>1 THEN
   v_target:=h.source_grade_no-1;v_reason:='PROMOTION';
  ELSIF v_match.n=6 AND v_match.places=0 AND v_match.bottom>=5
    AND h.source_grade_no<6 THEN
   v_target:=h.source_grade_no+1;v_reason:='DEMOTION';
  END IF;
  IF v_target IS NULL THEN CONTINUE;END IF;
  -- Avoid invalidating existing confirmed official schedules.
  IF EXISTS(SELECT 1 FROM my_derby.race_entries e
   JOIN my_derby.races race ON race.id=e.race_id WHERE e.horse_id=h.id
   AND e.status IN ('APPLIED','CONFIRMED') AND race.status IN ('OPEN','CLOSED','RUNNING'))
   THEN v_skip:=v_skip+1;CONTINUE;END IF;
  UPDATE my_derby.horses SET source_grade_no=v_target WHERE id=h.id
    AND source_grade_no=h.source_grade_no;
  INSERT INTO my_derby.horse_grade_events(horse_id,world_id,game_day,
   old_grade,new_grade,reason,evidence)
  VALUES(h.id,h.world_id,v_day,h.source_grade_no,v_target,v_reason,
   jsonb_build_object('recentRaces',v_match.n,'wins',v_match.wins,
    'places',v_match.places,'bottom40',v_match.bottom,'rule','PROVISIONAL_GRADE_V1'))
  ON CONFLICT(horse_id,game_day) DO NOTHING;
  v_count:=v_count+1;
 END LOOP;
 RETURN jsonb_build_object('status','OK','changes',v_count,
  'deferredScheduledHorses',v_skip,'rule','PROVISIONAL_GRADE_V1');
END $fn$;