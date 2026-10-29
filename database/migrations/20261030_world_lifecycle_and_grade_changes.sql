
-- World lifecycle: time, ages and ordinary game-grade transitions.
-- NPC owner breeding conversion remains EXCLUSIVELY the separate injury/form policy.
CREATE TABLE IF NOT EXISTS my_derby.season_age_events(
 horse_id uuid NOT NULL REFERENCES my_derby.horses(id),
 season_number integer NOT NULL CHECK(season_number>=1),
 old_age integer NOT NULL,new_age integer NOT NULL,
 old_stage text NOT NULL,new_stage text NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(horse_id,season_number)
);
ALTER TABLE my_derby.season_age_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.season_age_events FROM anon,authenticated;
CREATE TABLE IF NOT EXISTS my_derby.horse_grade_events(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 horse_id uuid NOT NULL REFERENCES my_derby.horses(id),
 world_id uuid NOT NULL REFERENCES my_derby.worlds(id),
 game_day integer NOT NULL,
 old_grade smallint NOT NULL,new_grade smallint NOT NULL,
 reason text NOT NULL CHECK(reason IN('PROMOTION','DEMOTION')),
 evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
 UNIQUE(horse_id,game_day)
);
ALTER TABLE my_derby.horse_grade_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.horse_grade_events FROM anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.progress_world_lifecycle()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE w my_derby.worlds%rowtype;v_clock jsonb; v_target int;v_day int;
 v_year int;h record;new_stage text;new_age int;v_n int:=0;v_transitions int:=0;
 v_stat jsonb; v_potential jsonb; v_name text; v_growth numeric;
BEGIN
 FOR w IN SELECT * FROM my_derby.worlds WHERE status='ACTIVE' AND
 automatic_processing_enabled FOR UPDATE LOOP
  v_clock:=my_derby.world_clock(w.id);
  v_target:=(v_clock->>'season')::int;v_day:=(v_clock->>'gameDayStart')::int;
  -- No duplicate aging: world season counter is advanced in this same transaction.
  FOR v_year IN (w.season_number+1)..v_target LOOP
   FOR h IN SELECT id,age_years,life_stage,owner_user_id,source_meet,source_grade_no,mother_id
     FROM my_derby.horses WHERE world_id=w.id ORDER BY id FOR UPDATE SKIP LOCKED LOOP
    new_age:=h.age_years+1;
    new_stage:=h.life_stage;
    IF h.life_stage='FOAL' AND new_age>=1 THEN new_stage:='YEARLING';END IF;
    IF h.life_stage='YEARLING' AND new_age>=2 AND
      coalesce(h.source_meet,(select m.source_meet from my_derby.horses m where m.id=h.mother_id)) IS NOT NULL
    THEN new_stage:='RACING'; END IF;
    -- Latest NPC-owner policy forbids a generic NPC retirement decision.
    -- Only user-owned horses follow the V3 11-year ordinary retirement.
    IF h.life_stage='RACING' AND new_age>=11 AND h.owner_user_id IS NOT NULL
     AND NOT EXISTS(SELECT 1 FROM my_derby.race_entries e
       JOIN my_derby.races r ON r.id=e.race_id
       WHERE e.horse_id=h.id AND e.status IN('APPLIED','CONFIRMED')
       AND r.status IN('OPEN','CLOSED','RUNNING')) THEN new_stage:='RETIRED';
    END IF;
    UPDATE my_derby.horses SET age_years=new_age,life_stage=new_stage,
      source_meet=CASE WHEN new_stage='RACING' THEN coalesce(source_meet,
       (select mother.source_meet from my_derby.horses mother where mother.id=h.mother_id))
       ELSE source_meet END,
      source_grade_no=CASE WHEN new_stage='RACING' THEN coalesce(source_grade_no,6)
       ELSE source_grade_no END
    WHERE id=h.id;
    IF h.life_stage='YEARLING' AND new_stage='RACING' THEN
      SELECT current_stats,potential_stats INTO v_stat,v_potential
      FROM my_derby.horse_abilities WHERE horse_id=h.id FOR UPDATE;
      IF v_stat IS NOT NULL THEN
       FOREACH v_name IN ARRAY ARRAY['start','speed','acceleration','stamina',
         'finishing','power','grit','stability','recovery'] LOOP
        v_growth:=greatest(coalesce((v_stat->>v_name)::numeric,0),
          round(coalesce((v_potential->>v_name)::numeric,50)*0.60,2));
        v_stat:=jsonb_set(v_stat,ARRAY[v_name],
          to_jsonb(least(coalesce((v_potential->>v_name)::numeric,v_growth),v_growth)),true);
       END LOOP;
       UPDATE my_derby.horse_abilities SET current_stats=v_stat,updated_at=now()
        WHERE horse_id=h.id;
      END IF;
    END IF;
    INSERT INTO my_derby.season_age_events
      (horse_id,season_number,old_age,new_age,old_stage,new_stage)
    VALUES(h.id,v_year,h.age_years,new_age,h.life_stage,new_stage)
    ON CONFLICT DO NOTHING;
    v_n:=v_n+1;
   END LOOP;
   v_transitions:=v_transitions+1;
  END LOOP;
  UPDATE my_derby.worlds SET game_day=v_day,season_number=v_target WHERE id=w.id;
 END LOOP;
 RETURN jsonb_build_object('status','OK','horsesAged',v_n,
  'seasonTransitions',v_transitions);
END $fn$;

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
   SELECT rr.finishing_rank,count(*) OVER(PARTITION BY rr.race_run_id) field_size
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
REVOKE ALL ON FUNCTION my_derby_private.progress_world_lifecycle() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_horse_grade_changes() FROM PUBLIC,anon,authenticated;
SELECT cron.schedule('my-derby-world-lifecycle','30 15 * * *',
 'select my_derby_private.progress_world_lifecycle();');
SELECT cron.schedule('my-derby-grade-changes','20 14 * * *',
 'select my_derby_private.process_horse_grade_changes();');
