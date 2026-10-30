-- Rating KRA 2025 explanatory guide, interpreted as a game simulation.
-- The guide explicitly requires human handicapper judgement; derived margin
-- points and legacy grade seeding below are estimates, not official KRA ratings.
ALTER TABLE my_derby.horses
 ADD COLUMN IF NOT EXISTS domestic_rating integer,
 ADD COLUMN IF NOT EXISTS rating_derived_grade smallint,
 ADD COLUMN IF NOT EXISTS rating_seed_source text,
 ADD COLUMN IF NOT EXISTS rating_pending_grade boolean NOT NULL DEFAULT false;
ALTER TABLE my_derby.horses DROP CONSTRAINT IF EXISTS horse_domestic_rating_bound;
ALTER TABLE my_derby.horses ADD CONSTRAINT horse_domestic_rating_bound
 CHECK(domestic_rating IS NULL OR domestic_rating BETWEEN 1 AND 140);

CREATE TABLE IF NOT EXISTS my_derby.horse_rating_events(
 race_id uuid NOT NULL REFERENCES my_derby.races(id),
 horse_id uuid NOT NULL REFERENCES my_derby.horses(id),
 world_id uuid NOT NULL REFERENCES my_derby.worlds(id),
 game_day integer NOT NULL,
 race_grade smallint NOT NULL,
 finishing_rank integer NOT NULL,
 old_rating integer,
 new_rating integer,
 delta integer NOT NULL DEFAULT 0,
 old_grade smallint,
 proposed_grade smallint,
 policy_version text NOT NULL DEFAULT 'KRA_2025_GAME_V1',
 decision_data jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(race_id,horse_id)
);
ALTER TABLE my_derby.horse_rating_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.horse_rating_events FROM PUBLIC,anon,authenticated;
CREATE INDEX IF NOT EXISTS idx_horse_rating_history
 ON my_derby.horse_rating_events(horse_id,game_day DESC);

-- Bootstrap old game horses by grade, never label them officially rated.
UPDATE my_derby.horses SET
 domestic_rating=CASE source_grade_no
 WHEN 1 THEN 88 WHEN 2 THEN 73 WHEN 3 THEN 58
 WHEN 4 THEN 43 WHEN 5 THEN 29 ELSE NULL END,
 rating_derived_grade=source_grade_no,
 rating_seed_source='LEGACY_GRADE_ESTIMATE_NOT_KRA_OFFICIAL'
WHERE domestic_rating IS NULL AND rating_seed_source IS NULL
 AND source_grade_no BETWEEN 1 AND 6;

CREATE OR REPLACE FUNCTION my_derby_private.kra_rating_grade(p_rating integer)
RETURNS smallint LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $fn$
 SELECT CASE WHEN p_rating IS NULL THEN 6::smallint
 WHEN p_rating>=81 THEN 1::smallint
 WHEN p_rating>=66 THEN 2::smallint
 WHEN p_rating>=51 THEN 3::smallint
 WHEN p_rating>=36 THEN 4::smallint ELSE 5::smallint END
$fn$;

CREATE OR REPLACE FUNCTION my_derby_private.kra_handicap_weight(
 p_rating integer,p_highest integer,p_grade integer,p_age integer,
 p_sex text,p_quarter integer,p_southern boolean DEFAULT false,
 p_apprentice_kg numeric DEFAULT 0)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE SET search_path TO ''
AS $fn$
DECLARE v_ceiling numeric;v_base numeric;v_age numeric:=0;
 v_floor numeric:=51;v_year2 numeric[];
BEGIN
 IF p_grade NOT BETWEEN 1 AND 5 OR p_rating IS NULL OR p_highest IS NULL
 OR p_rating>p_highest OR p_quarter NOT BETWEEN 1 AND 4
 THEN RAISE EXCEPTION 'RATING_HANDICAP_INPUT_INVALID';END IF;
 v_ceiling:=CASE p_grade WHEN 1 THEN 60 WHEN 2 THEN 59
 WHEN 3 THEN 58 WHEN 4 THEN 58 ELSE 57 END;
 v_base:=v_ceiling - (p_highest-p_rating)*0.5;
 IF p_age=2 THEN
   v_age:=(CASE WHEN p_southern THEN ARRAY[2.5,2,3,2.5]::numeric[]
    ELSE ARRAY[2.5,2,1.5,1]::numeric[] END)[p_quarter];
 ELSIF p_age=3 THEN
   v_age:=(CASE WHEN p_southern THEN ARRAY[2,1.5,1,0.5]::numeric[]
    ELSE ARRAY[0.5,0,0,0]::numeric[] END)[p_quarter];
 END IF;
 RETURN least(v_ceiling,greatest(v_floor,
  v_base-v_age-(CASE WHEN p_sex='FEMALE' THEN 2 ELSE 0 END)
  -greatest(0,coalesce(p_apprentice_kg,0))));
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.apply_race_rating(p_race_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE r my_derby.races%rowtype;v_run uuid;v_count int;v_second numeric;
 v_third numeric;v_fourth numeric;v_first numeric;v_rank4 int;
 rec record; v_old int;v_rating int;v_grade smallint;v_new_grade smallint;
 v_delta int;v_streak int;v_placings record;v_margin numeric;
 v_incident boolean;v_count_changed int:=0;v_new int:=0;v_race_grade int;
 v_context jsonb;
BEGIN
 SELECT * INTO r FROM my_derby.races WHERE id=p_race_id FOR UPDATE;
 IF NOT FOUND OR r.status<>'FINISHED' THEN RETURN jsonb_build_object('status','NOT_FINISHED');END IF;
 v_race_grade:=coalesce((r.prize_policy->>'grade_no')::int,0);
 IF v_race_grade NOT BETWEEN 1 AND 6 THEN
  RETURN jsonb_build_object('status','UNSUPPORTED_GRADE');END IF;
 SELECT id INTO v_run FROM my_derby.race_runs WHERE race_id=r.id
  AND status='FINISHED' ORDER BY result_applied_at DESC LIMIT 1;
 IF v_run IS NULL THEN RAISE EXCEPTION 'RATING_OFFICIAL_RESULTS_MISSING';END IF;
 SELECT count(*),
  min(finish_time_sec) FILTER (WHERE finishing_rank=1),
  min(finish_time_sec) FILTER (WHERE finishing_rank=2),
  min(finish_time_sec) FILTER (WHERE finishing_rank=3),
  min(finish_time_sec) FILTER (WHERE finishing_rank=4)
 INTO v_count,v_first,v_second,v_third,v_fourth
 FROM my_derby.race_results WHERE race_run_id=v_run;
 IF v_count<2 THEN RAISE EXCEPTION 'RATING_FIELD_TOO_SMALL'; END IF;
 FOR rec IN
  SELECT rr.id result_id,rr.horse_id,rr.finishing_rank,rr.finish_time_sec,
   rr.change_snapshot,h.domestic_rating,h.rating_seed_source,
   h.source_grade_no,h.owner_user_id
  FROM my_derby.race_results rr JOIN my_derby.horses h ON h.id=rr.horse_id
  WHERE rr.race_run_id=v_run ORDER BY rr.finishing_rank,rr.id
 LOOP
  PERFORM 1 FROM my_derby.horses WHERE id=rec.horse_id FOR UPDATE;
  IF EXISTS(SELECT 1 FROM my_derby.horse_rating_events
    WHERE horse_id=rec.horse_id AND race_id=r.id) THEN CONTINUE;END IF;
  v_grade:=rec.source_grade_no;
  v_old:=rec.domestic_rating;
  IF v_old IS NULL AND v_race_grade BETWEEN 1 AND 5 THEN
   v_old:=CASE v_race_grade WHEN 1 THEN 88 WHEN 2 THEN 73
     WHEN 3 THEN 58 WHEN 4 THEN 43 ELSE 29 END;
  END IF;
  v_delta:=0;v_rating:=v_old;v_streak:=0;
  v_incident:=coalesce((rec.change_snapshot->>'rating_exempt')::boolean,false);
  IF v_race_grade=6 AND v_old IS NULL THEN
   SELECT count(*) FILTER(WHERE rr.finishing_rank=1) wins,
    count(*) FILTER(WHERE rr.finishing_rank=2) seconds,
    count(*) FILTER(WHERE rr.finishing_rank=3) thirds
   INTO v_placings FROM my_derby.race_results rr
   JOIN my_derby.race_runs rr_run ON rr_run.id=rr.race_run_id AND rr_run.status='FINISHED'
   JOIN my_derby.races hr ON hr.id=rr_run.race_id
   WHERE rr.horse_id=rec.horse_id AND hr.status='FINISHED'
    AND (hr.prize_policy->>'grade_no')='6'
    AND (hr.race_day<r.race_day OR (hr.race_day=r.race_day
       AND hr.start_time<=r.start_time));
   IF v_placings.wins>=1 OR v_placings.seconds>=2
    OR (v_placings.seconds>=1 AND v_placings.thirds>=2)
    OR v_placings.thirds>=3 THEN
    -- KRA specifies 26..32 but expert decides within range.
    -- This reproducible estimate is expressly NOT official.
    v_rating:=least(32,26+(CASE WHEN rec.finishing_rank=1 THEN 3 ELSE 0 END)
      +least(3,greatest(0,floor(
        coalesce(v_second-v_first,0)/0.2))::int));
    v_delta:=v_rating;
   END IF;
  ELSIF v_old IS NOT NULL THEN
   IF rec.finishing_rank=1 THEN
     v_delta:=CASE WHEN v_race_grade=1 THEN
      least(15,1+greatest(0,floor(coalesce(v_second-v_first,0)/0.2*2))::int)
      ELSE least(15,5+greatest(0,floor(coalesce(v_second-v_first,0)/0.2*2))::int) END;
   ELSIF rec.finishing_rank=2 AND v_race_grade BETWEEN 1 AND 5 THEN
     v_delta:=least(5,2+greatest(0,floor(coalesce(v_third-v_second,0)/0.2))::int);
   ELSIF rec.finishing_rank=3 AND v_race_grade BETWEEN 1 AND 5 THEN
     v_delta:=least(3,1+greatest(0,floor(coalesce(v_fourth-v_third,0)/0.2))::int);
   ELSIF rec.finishing_rank>3 AND NOT v_incident THEN
     v_streak:=0;
     FOR v_rank4 IN SELECT prev.finishing_rank FROM my_derby.race_results prev
      JOIN my_derby.race_runs run ON run.id=prev.race_run_id AND run.status='FINISHED'
      JOIN my_derby.races previous ON previous.id=run.race_id
      WHERE prev.horse_id=rec.horse_id AND previous.status='FINISHED'
       AND previous.race_day<=r.race_day
      ORDER BY previous.race_day DESC,previous.start_time DESC,prev.id DESC LIMIT 6
     LOOP
       EXIT WHEN v_rank4<=3;
       v_streak:=v_streak+1;
     END LOOP;
     v_delta:=CASE WHEN v_streak>=5 THEN -4 WHEN v_streak>=4 THEN -3
      WHEN v_streak>=3 THEN -2 WHEN v_streak>=2 THEN -1 ELSE 0 END;
   END IF;
   v_rating:=least(140,greatest(1,v_old+v_delta));
   v_delta:=v_rating-v_old;
  END IF;
  v_new_grade:=CASE WHEN v_rating IS NOT NULL
   THEN my_derby_private.kra_rating_grade(v_rating) ELSE 6 END;
  v_context:=jsonb_build_object('referenceHorseRank',CASE
    WHEN v_race_grade=1 THEN 3 ELSE 4 END,
   'marginModel','GAME_ESTIMATE_0.2SEC_PER_LENGTH',
   'firstToSecondSeconds',CASE WHEN v_first IS NOT NULL AND v_second IS NOT NULL
     THEN v_second-v_first ELSE null END,'poorStreak',v_streak,
   'ratingExempt',v_incident,'legacyBase',rec.rating_seed_source,
   'manualHandicapperRequiredForOfficial',true);
  INSERT INTO my_derby.horse_rating_events(
   race_id,horse_id,world_id,game_day,race_grade,finishing_rank,
   old_rating,new_rating,delta,old_grade,proposed_grade,decision_data)
  VALUES(r.id,rec.horse_id,r.world_id,r.race_day,v_race_grade,rec.finishing_rank,
   v_old,v_rating,v_delta,v_grade,v_new_grade,v_context);
  UPDATE my_derby.horses SET domestic_rating=v_rating,
   rating_derived_grade=v_new_grade,
   rating_seed_source=CASE WHEN rec.rating_seed_source IS NULL THEN
     'GAME_ESTIMATED_FROM_OFFICIAL_RACE' ELSE rating_seed_source END,
   rating_pending_grade=(source_grade_no IS DISTINCT FROM v_new_grade)
  WHERE id=rec.horse_id;
  UPDATE my_derby.race_results SET change_snapshot=change_snapshot||
   jsonb_build_object('game_rating_after',v_rating,'game_rating_delta',v_delta,
    'game_rating_grade',v_new_grade,'game_rating_policy','KRA_2025_GAME_V1')
  WHERE id=rec.result_id;
  v_new:=v_new+1;
  IF v_grade IS DISTINCT FROM v_new_grade THEN v_count_changed:=v_count_changed+1;END IF;
 END LOOP;
 RETURN jsonb_build_object('status','RATED','processed',v_new,
  'proposedGradeChanges',v_count_changed,'raceId',p_race_id);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.process_game_rating_grades()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE h record;v_changed int:=0;v_deferred int:=0;
 v_day int;
BEGIN
 FOR h IN SELECT x.id,x.world_id,x.source_grade_no,x.rating_derived_grade,x.owner_user_id
   FROM my_derby.horses x WHERE x.rating_pending_grade
    AND x.rating_derived_grade BETWEEN 1 AND 6
   ORDER BY x.id FOR UPDATE OF x SKIP LOCKED
 LOOP
  IF EXISTS(SELECT 1 FROM my_derby.race_entries e
   JOIN my_derby.races r ON r.id=e.race_id
   WHERE e.horse_id=h.id AND e.status IN('APPLIED','CONFIRMED')
    AND r.status IN('OPEN','CLOSED','RUNNING')) THEN
   v_deferred:=v_deferred+1;CONTINUE;END IF;
  v_day:=(my_derby.world_clock(h.world_id)->>'gameDayStart')::int;
  UPDATE my_derby.horses SET source_grade_no=h.rating_derived_grade,
    rating_pending_grade=false WHERE id=h.id;
  IF h.source_grade_no IS NOT NULL THEN
   INSERT INTO my_derby.horse_grade_events(horse_id,world_id,game_day,
     old_grade,new_grade,reason,evidence)
   VALUES(h.id,h.world_id,v_day,h.source_grade_no,h.rating_derived_grade,
     CASE WHEN h.rating_derived_grade<h.source_grade_no THEN 'PROMOTION'
      ELSE 'DEMOTION' END,
    jsonb_build_object('policy','KRA_2025_GAME_V1','ratingBased',true))
   ON CONFLICT(horse_id,game_day) DO NOTHING;
  END IF;
  v_changed:=v_changed+1;
 END LOOP;
 RETURN jsonb_build_object('status','OK','gradesChanged',v_changed,
  'deferredExistingEntries',v_deferred);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_horse_rating_board()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();v_world uuid;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO v_world FROM my_derby.profiles
  WHERE user_id=u AND initial_setup_complete;
 IF v_world IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object(
  'policy','KRA_2025_GAME_V1',
  'disclaimer','게임 자동 레이팅 추정치. 실제 KRA 핸디캡퍼 공식 레이팅 아님.',
  'horses',coalesce((SELECT jsonb_agg(jsonb_build_object(
    'id',h.id,'name',h.name,'grade',h.source_grade_no,
    'ratingGrade',h.rating_derived_grade,'rating',h.domestic_rating,
    'seed',h.rating_seed_source,'pendingGrade',h.rating_pending_grade,
    'recent',(SELECT coalesce(jsonb_agg(z ORDER BY z.game_day DESC),'[]'::jsonb)
      FROM(SELECT e.game_day,e.race_grade,e.finishing_rank,e.old_rating,
       e.new_rating,e.delta,e.proposed_grade
       FROM my_derby.horse_rating_events e WHERE e.horse_id=h.id
       ORDER BY e.game_day DESC LIMIT 10)z)
   ) ORDER BY h.name) FROM my_derby.horses h
   WHERE h.owner_user_id=u AND h.world_id=v_world),'[]'::jsonb));
END $fn$;
REVOKE ALL ON FUNCTION my_derby_private.kra_rating_grade(integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.kra_handicap_weight(integer,integer,integer,integer,text,integer,boolean,numeric) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.apply_race_rating(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_game_rating_grades() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_horse_rating_board() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_horse_rating_board() TO authenticated;

-- Replace speculative previous automatic 3-wins grade system with rating-driven promotion only.
DO $do$ BEGIN
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='my-derby-grade-changes') THEN
  PERFORM cron.unschedule('my-derby-grade-changes');
 END IF;
END $do$;
SELECT cron.schedule('my-derby-rating-grade-sync','25 14 * * *',
 'select my_derby_private.process_game_rating_grades();');
