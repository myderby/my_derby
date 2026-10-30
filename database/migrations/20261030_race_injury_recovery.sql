-- Deterministic in-game racing injury model. 
-- These are fictional game events, not real veterinary diagnoses.
ALTER TABLE my_derby.horses
 ADD COLUMN IF NOT EXISTS injury_recovery_game_day integer;
CREATE TABLE IF NOT EXISTS my_derby.race_injuries(
 race_id uuid NOT NULL REFERENCES my_derby.races(id),
 horse_id uuid NOT NULL REFERENCES my_derby.horses(id),
 world_id uuid NOT NULL REFERENCES my_derby.worlds(id),
 game_day integer NOT NULL,
 severity text NOT NULL CHECK(severity IN ('RECOVERABLE','RACING_UNFIT')),
 incident_roll numeric NOT NULL,
 risk_percent numeric NOT NULL,
 recovery_game_day integer,
 treatment_status text NOT NULL DEFAULT 'INJURED'
  CHECK(treatment_status IN('INJURED','RECOVERED','PERMANENT')),
 game_model_version text NOT NULL DEFAULT 'INJURY_RISK_V1',
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(race_id,horse_id)
);
ALTER TABLE my_derby.race_injuries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.race_injuries FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.assess_official_race_injuries(p_race_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE r my_derby.races%rowtype;v_run my_derby.race_runs%rowtype;
 h my_derby.horses%rowtype;row_result record;v_roll numeric;
 v_risk numeric;v_permanent numeric;v_severity text;v_recover int;
 v_count int:=0;v_affected int:=0;
BEGIN
 SELECT * INTO r FROM my_derby.races WHERE id=p_race_id FOR UPDATE;
 IF NOT FOUND OR r.status<>'FINISHED' THEN
 RETURN jsonb_build_object('status','NOT_FINISHED');END IF;
 SELECT * INTO v_run FROM my_derby.race_runs
 WHERE race_id=r.id AND status='FINISHED'
 ORDER BY result_applied_at DESC LIMIT 1;
 IF v_run.id IS NULL THEN RAISE EXCEPTION 'OFFICIAL_RACE_RUN_MISSING';END IF;
 FOR row_result IN SELECT rr.id result_id,rr.horse_id,rr.finishing_rank
   FROM my_derby.race_results rr WHERE rr.race_run_id=v_run.id
   ORDER BY rr.id LOOP
  SELECT * INTO h FROM my_derby.horses WHERE id=row_result.horse_id FOR UPDATE;
  IF EXISTS(SELECT 1 FROM my_derby.race_injuries
    WHERE race_id=r.id AND horse_id=h.id) THEN CONTINUE;END IF;
  IF h.health_state<>'HEALTHY' OR h.life_stage<>'RACING' THEN CONTINUE;END IF;
  -- Risk is deliberately low; higher fatigue makes an injury more likely.
  v_risk:=round(0.35+greatest(0,h.fatigue-50)*0.022,3);
  v_permanent:=CASE WHEN h.fatigue>=85 THEN 0.05 ELSE 0.008 END;
  v_roll:=(('x'||substr(md5(
     v_run.random_seed::text||':'||h.id::text||':INJURY_V1'),1,8))
    ::bit(32)::bigint %100000)::numeric/1000;
  v_count:=v_count+1;
  IF v_roll>=v_risk THEN CONTINUE; END IF;
  v_severity:=CASE WHEN v_roll<v_permanent THEN 'RACING_UNFIT' ELSE 'RECOVERABLE' END;
  v_recover:=CASE WHEN v_severity='RECOVERABLE'
    THEN r.race_day+7+(('x'||substr(md5(h.id::text||r.id::text),1,4))::bit(16)::int%14)
    ELSE NULL END;
  INSERT INTO my_derby.race_injuries(race_id,horse_id,world_id,
   game_day,severity,incident_roll,risk_percent,recovery_game_day,treatment_status)
  VALUES(r.id,h.id,r.world_id,r.race_day,v_severity,v_roll,v_risk,
   v_recover,CASE WHEN v_severity='RACING_UNFIT' THEN 'PERMANENT' ELSE 'INJURED' END);
  UPDATE my_derby.horses SET health_state='INJURED',
    injury_prognosis=v_severity,
    injury_assessed_game_day=r.race_day,
    injury_recovery_game_day=v_recover WHERE id=h.id;
  INSERT INTO my_derby.horse_state_history(horse_id,game_day,event_code,new_state)
  VALUES(h.id,r.race_day,'GAME_RACE_INJURY',
    jsonb_build_object('severity',v_severity,'recoveryDay',v_recover,
      'raceId',r.id,'model','INJURY_RISK_V1'));
  IF h.owner_user_id IS NOT NULL THEN
   INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
   VALUES(h.owner_user_id,'RACE','경주 부상 소식',
    h.name||CASE WHEN v_severity='RACING_UNFIT'
     THEN ' 경주 복귀 불가능 판정' ELSE ' 경미한 경주 부상 발생' END,
    jsonb_build_object('raceId',r.id,'horseId',h.id,
      'prognosis',v_severity,'recoveryDay',v_recover));
  END IF;
  v_affected:=v_affected+1;
 END LOOP;
 RETURN jsonb_build_object('status','ASSESSED','eligible',v_count,
  'injured',v_affected,'model','INJURY_RISK_V1');
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.recover_due_racing_injuries()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE h record;v_n int:=0;
BEGIN
 FOR h IN SELECT horse.id,horse.world_id,horse.injury_recovery_game_day
  FROM my_derby.horses horse JOIN my_derby.worlds w ON w.id=horse.world_id
  WHERE w.status='ACTIVE'
   AND horse.injury_prognosis='RECOVERABLE'
   AND horse.health_state IN('INJURED','RECOVERING')
   AND horse.injury_recovery_game_day IS NOT NULL
   AND horse.injury_recovery_game_day<=(my_derby.world_clock(w.id)->>'gameDayStart')::int+6
  ORDER BY horse.id FOR UPDATE OF horse SKIP LOCKED
 LOOP
  UPDATE my_derby.horses SET health_state='HEALTHY',
   injury_prognosis='NONE',injury_recovery_game_day=NULL
  WHERE id=h.id;
  UPDATE my_derby.race_injuries SET treatment_status='RECOVERED'
   WHERE horse_id=h.id AND treatment_status='INJURED';
  INSERT INTO my_derby.horse_state_history(horse_id,game_day,event_code,new_state)
  VALUES(h.id,h.injury_recovery_game_day,'GAME_RACE_INJURY_RECOVERED',
   jsonb_build_object('health','HEALTHY'));
  v_n:=v_n+1;
 END LOOP;
 RETURN jsonb_build_object('status','OK','recovered',v_n);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_horse_injury_board()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('horses',coalesce((SELECT jsonb_agg(
   jsonb_build_object('id',h.id,'name',h.name,'health',h.health_state,
   'injuryPrognosis',h.injury_prognosis,
   'recoveryGameDay',h.injury_recovery_game_day,
   'racingRetired',h.racing_retired_permanently,
   'recentInjuries',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'gameDay',inj.game_day,'severity',inj.severity,
      'recoverDay',inj.recovery_game_day,'status',inj.treatment_status)
     ORDER BY inj.game_day DESC) FROM my_derby.race_injuries inj
      WHERE inj.horse_id=h.id),'[]'::jsonb))
   ORDER BY h.name)
   FROM my_derby.horses h WHERE h.owner_user_id=u),'[]'::jsonb),
  'source','INJURY_RISK_V1_GAME_SIMULATION');
END $fn$;

REVOKE ALL ON FUNCTION my_derby_private.assess_official_race_injuries(uuid)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.recover_due_racing_injuries()
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_horse_injury_board()
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_horse_injury_board() TO authenticated;
SELECT cron.schedule('my-derby-injury-recovery','40 0 * * *',
 'select my_derby_private.recover_due_racing_injuries();');
