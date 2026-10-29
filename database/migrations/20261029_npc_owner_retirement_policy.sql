
-- NPC owner retirement policy v1.
-- Only saved OFFICIAL game races drive form decisions; historical KRA input is not used.
-- A severe injury requires an explicit medically irreversible racing prognosis.
ALTER TABLE my_derby.horses
 ADD COLUMN IF NOT EXISTS injury_prognosis text NOT NULL DEFAULT 'NONE',
 ADD COLUMN IF NOT EXISTS injury_assessed_game_day integer;
ALTER TABLE my_derby.horses DROP CONSTRAINT IF EXISTS horses_injury_prognosis_check;
ALTER TABLE my_derby.horses ADD CONSTRAINT horses_injury_prognosis_check
 CHECK (injury_prognosis IN('NONE','RECOVERABLE','RACING_UNFIT'));
CREATE INDEX IF NOT EXISTS idx_my_derby_horses_npc_retirement
 ON my_derby.horses(world_id,npc_owner_id,life_stage,injury_prognosis)
 WHERE npc_owner_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS my_derby.npc_retirement_decisions(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 world_id uuid NOT NULL REFERENCES my_derby.worlds(id),
 horse_id uuid NOT NULL UNIQUE REFERENCES my_derby.horses(id),
 npc_owner_id uuid NOT NULL REFERENCES my_derby.npc_owners(id),
 game_day integer NOT NULL CHECK (game_day>0),
 reason text NOT NULL CHECK(reason IN ('POOR_FORM','PERMANENT_INJURY')),
 converted_to text NOT NULL CHECK(converted_to IN ('STALLION','BROODMARE','RETIRED')),
 breeding_pending boolean NOT NULL DEFAULT false,
 evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
 replaced_race_entries integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(),
 breeding_converted_at timestamptz
);
ALTER TABLE my_derby.npc_retirement_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE my_derby.npc_retirement_decisions FROM anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.npc_retirement_candidates(p_world_id uuid)
RETURNS TABLE(horse_id uuid, reason text, evidence jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 WITH finishes AS (
  SELECT rr.horse_id,rr.finishing_rank,r.race_day,r.id race_id,
    count(*) OVER (PARTITION BY rr.race_run_id) field_size,
    row_number() OVER (PARTITION BY rr.horse_id ORDER BY r.race_day DESC, r.start_time DESC, rr.id DESC) row_no
  FROM my_derby.race_results rr
  JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
  JOIN my_derby.races r ON r.id=run.race_id AND r.status='FINISHED'
  WHERE r.world_id=p_world_id
 ), form AS (
  SELECT f.horse_id,count(*) n,
    count(*) FILTER(WHERE f.finishing_rank>3) unplaced,
    count(*) FILTER(WHERE f.finishing_rank>floor(f.field_size*0.6)) bottom_40,
    round(avg((f.finishing_rank-1)::numeric/greatest(f.field_size-1,1)),3) avg_relative
  FROM finishes f WHERE f.row_no<=6 AND f.field_size>=5
  GROUP BY f.horse_id
 )
 SELECT h.id,
  CASE WHEN h.health_state='INJURED' AND h.injury_prognosis='RACING_UNFIT'
       THEN 'PERMANENT_INJURY' ELSE 'POOR_FORM' END,
  CASE WHEN h.health_state='INJURED' AND h.injury_prognosis='RACING_UNFIT'
       THEN jsonb_build_object('prognosis',h.injury_prognosis,'assessedDay',h.injury_assessed_game_day)
       ELSE jsonb_build_object('window',6,'unplaced',f.unplaced,
        'bottom40',f.bottom_40,'avgRelativeRank',f.avg_relative,
        'minEligibleRuns',6,'ruleVersion','NPC_RETIRE_V1') END
 FROM my_derby.horses h
 LEFT JOIN form f ON f.horse_id=h.id
 WHERE h.world_id=p_world_id AND h.npc_owner_id IS NOT NULL AND h.owner_user_id IS NULL
  AND h.life_stage='RACING' AND NOT h.racing_retired_permanently
  AND h.breeding_retired_at IS NULL
  AND h.source_model_version IS DISTINCT FROM 'MY_DERBY_SYSTEM_STUD_V1'
  AND NOT EXISTS (SELECT 1 FROM my_derby.npc_retirement_decisions d WHERE d.horse_id=h.id)
  AND (
   (h.health_state='INJURED' AND h.injury_prognosis='RACING_UNFIT')
   OR (h.age_years>=4 AND f.n=6 AND f.unplaced=6
     AND f.bottom_40>=5 AND f.avg_relative>=0.72)
  );
$fn$;

CREATE OR REPLACE FUNCTION my_derby_private.npc_try_retirement(
 p_horse_id uuid,p_reason text,p_evidence jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 h my_derby.horses%rowtype; er record; replacement uuid;
 v_stage text; v_day integer; n int:=0; v_pending boolean:=false;
 v_kst timestamp:=now() at time zone 'Asia/Seoul';
 v_deferred boolean:=false;
BEGIN
 IF p_reason NOT IN('POOR_FORM','PERMANENT_INJURY') THEN RAISE EXCEPTION 'INVALID_RETIRE_REASON';END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id FOR UPDATE;
 IF NOT FOUND OR h.npc_owner_id IS NULL OR h.owner_user_id IS NOT NULL
    OR h.life_stage<>'RACING' OR h.racing_retired_permanently
 THEN RETURN jsonb_build_object('status','SKIPPED_NOT_NPC_RACER');END IF;
 IF p_reason='PERMANENT_INJURY' AND NOT
    (h.health_state='INJURED' AND h.injury_prognosis='RACING_UNFIT')
 THEN RETURN jsonb_build_object('status','SKIPPED_NOT_PERMANENT');END IF;
 IF p_reason='POOR_FORM' AND h.age_years<4 THEN
  RETURN jsonb_build_object('status','SKIPPED_YOUNG');END IF;

 SELECT (my_derby.world_clock(h.world_id)->>'gameDayStart')::int INTO v_day;
 IF EXISTS(SELECT 1 FROM my_derby.npc_retirement_decisions WHERE horse_id=h.id) THEN
  RETURN jsonb_build_object('status','ALREADY_RETIRED');END IF;

 -- Replacing NPC runners is atomic. A race that has started or has no valid
 -- replacement postpones retirement. Never scratch a player-owned entry.
 BEGIN
  FOR er IN
   SELECT e.id entry_id,e.snapshot,r.id race_id,r.status race_status,
       r.race_day,r.start_time,r.prize_policy,r.world_id
   FROM my_derby.race_entries e JOIN my_derby.races r ON r.id=e.race_id
   WHERE e.horse_id=h.id AND e.owner_user_id IS NULL
     AND e.status IN('APPLIED','CONFIRMED')
     AND r.status IN('OPEN','CLOSED','RUNNING')
   ORDER BY r.race_day,r.start_time,r.id
   FOR UPDATE OF e,r
  LOOP
   IF er.race_status<>'OPEN'
     OR (er.prize_policy->>'kst_date') IS NULL
     OR ((er.prize_policy->>'kst_date')::date< v_kst::date)
     OR ((er.prize_policy->>'kst_date')::date=v_kst::date AND er.start_time<=v_kst::time)
   THEN RAISE EXCEPTION 'NPC_RETIRE_ENTRY_BLOCKED' USING ERRCODE='P0002';END IF;

   SELECT alt.id INTO replacement
   FROM my_derby.horses alt
   WHERE alt.world_id=h.world_id
     AND alt.npc_owner_id IS NOT NULL AND alt.owner_user_id IS NULL
     AND alt.id<>h.id
     AND alt.source_meet=er.prize_policy->>'source_meet'
     AND alt.source_grade_no::text=er.prize_policy->>'grade_no'
     AND alt.life_stage='RACING' AND alt.health_state='HEALTHY'
     AND alt.injury_prognosis<>'RACING_UNFIT'
     AND alt.racing_retired_permanently=false AND alt.breeding_retired_at IS NULL
     AND alt.sale_state='NOT_LISTED' AND alt.age_years BETWEEN 2 AND 10
     AND NOT EXISTS(
       SELECT 1 FROM my_derby.race_entries ae JOIN my_derby.races ar ON ar.id=ae.race_id
       WHERE ae.horse_id=alt.id AND ar.world_id=er.world_id
         AND ar.race_day=er.race_day AND ar.status<>'CANCELLED'
         AND ae.status IN('APPLIED','CONFIRMED','COMPLETED')
     )
   ORDER BY md5(alt.id::text||':'||er.race_id::text)
   LIMIT 1 FOR UPDATE OF alt SKIP LOCKED;
   IF replacement IS NULL THEN
     RAISE EXCEPTION 'NPC_RETIRE_NO_REPLACEMENT' USING ERRCODE='P0002';
   END IF;

   UPDATE my_derby.race_entries SET horse_id=replacement,
    snapshot=coalesce(snapshot,'{}'::jsonb)||jsonb_build_object(
      'npc_retirement_replacement',true,'replacedHorseId',h.id,
      'retirementReason',p_reason)
   WHERE id=er.entry_id;
   n:=n+1;
  END LOOP;
 EXCEPTION WHEN SQLSTATE 'P0002' THEN
  v_deferred:=true;n:=0;
 END;
 IF v_deferred THEN RETURN jsonb_build_object('status','DEFERRED_ACTIVE_RACE','horseId',h.id);END IF;

 v_stage:=CASE
   WHEN h.sex='MALE' AND h.age_years BETWEEN 4 AND 25 THEN 'STALLION'
   WHEN h.sex='FEMALE' AND h.age_years BETWEEN 4 AND 18 THEN 'BROODMARE'
   ELSE 'RETIRED' END;
 v_pending:=(v_stage='RETIRED' AND h.age_years<4 AND h.sex IN('MALE','FEMALE'));
 UPDATE my_derby.horses SET
  life_stage=v_stage,race_entry_state='NONE',
  breeding_state=CASE WHEN v_stage IN('STALLION','BROODMARE') THEN 'AVAILABLE'
    ELSE breeding_state END
 WHERE id=h.id;
 UPDATE my_derby.trainer_contracts
  SET status='ENDED',end_game_day=v_day
 WHERE horse_id=h.id AND status='ACTIVE';
 INSERT INTO my_derby.npc_retirement_decisions
  (world_id,horse_id,npc_owner_id,game_day,reason,converted_to,
    breeding_pending,evidence,replaced_race_entries)
 VALUES(h.world_id,h.id,h.npc_owner_id,v_day,p_reason,v_stage,
   v_pending,coalesce(p_evidence,'{}'::jsonb),n);
 INSERT INTO my_derby.horse_state_history(horse_id,game_day,event_code,old_state,new_state)
 VALUES(h.id,v_day,'NPC_OWNER_RETIREMENT',
  jsonb_build_object('lifeStage',h.life_stage,'health',h.health_state,'breeding',h.breeding_state),
  jsonb_build_object('lifeStage',v_stage,'reason',p_reason,'replacedEntries',n,
   'awaitingBreedingAge',v_pending));
 RETURN jsonb_build_object('status','RETIRED','horseId',h.id,
   'newStage',v_stage,'reason',p_reason,'replacedRaceEntries',n,
   'breedingPending',v_pending);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.process_npc_retirement_decisions()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE w record; rec record; d record; response jsonb;
 examined int:=0; retired int:=0; deferred int:=0;
 breeding int:=0; geldings int:=0; v_day int;
BEGIN
 FOR w IN SELECT * FROM my_derby.worlds
  WHERE status='ACTIVE' AND automatic_processing_enabled=true
 LOOP
  v_day:=(my_derby.world_clock(w.id)->>'gameDayStart')::int;
  -- If the season age processor ages a young medically retired horse later,
  -- convert it to breeding stock. Never turn geldings into breeders.
  FOR d IN
   SELECT dec.id decision_id,h.id horse_id,h.sex,h.age_years
   FROM my_derby.npc_retirement_decisions dec
   JOIN my_derby.horses h ON h.id=dec.horse_id
   WHERE dec.world_id=w.id AND dec.breeding_pending
    AND h.life_stage='RETIRED' AND h.racing_retired_permanently
    AND ((h.sex='MALE' AND h.age_years BETWEEN 4 AND 25)
       OR(h.sex='FEMALE' AND h.age_years BETWEEN 4 AND 18))
   ORDER BY dec.id FOR UPDATE OF dec SKIP LOCKED
  LOOP
   UPDATE my_derby.horses SET
    life_stage=CASE WHEN d.sex='MALE' THEN 'STALLION' ELSE 'BROODMARE' END,
    breeding_state='AVAILABLE' WHERE id=d.horse_id;
   UPDATE my_derby.npc_retirement_decisions
    SET converted_to=CASE WHEN d.sex='MALE' THEN 'STALLION' ELSE 'BROODMARE' END,
     breeding_pending=false,breeding_converted_at=now()
    WHERE id=d.decision_id;
   INSERT INTO my_derby.horse_state_history(horse_id,game_day,event_code,new_state)
   VALUES(d.horse_id,v_day,'NPC_BREEDING_AGE_REACHED',
    jsonb_build_object('lifeStage',CASE WHEN d.sex='MALE' THEN 'STALLION' ELSE 'BROODMARE' END));
   breeding:=breeding+1;
  END LOOP;
  FOR rec IN SELECT * FROM my_derby_private.npc_retirement_candidates(w.id)
   ORDER BY CASE WHEN reason='PERMANENT_INJURY' THEN 0 ELSE 1 END,horse_id
   LIMIT 120
  LOOP
   response:=my_derby_private.npc_try_retirement(rec.horse_id,rec.reason,rec.evidence);
   examined:=examined+1;
   IF response->>'status'='RETIRED' THEN
    retired:=retired+1;
    IF response->>'newStage'='RETIRED' THEN geldings:=geldings+1; END IF;
   ELSIF response->>'status'='DEFERRED_ACTIVE_RACE' THEN deferred:=deferred+1;END IF;
  END LOOP;
 END LOOP;
 RETURN jsonb_build_object('status','OK','candidatesConsidered',examined,
  'retired',retired,'deferredRaceEntry',deferred,
  'regularRetirementOrYoung',geldings,'breedingAgeConversions',breeding);
END $fn$;

-- Explicit private diagnosis; a generic INJURED flag is NOT permanent.
CREATE OR REPLACE FUNCTION my_derby_private.record_npc_permanent_racing_injury(
 p_horse_id uuid,p_diagnosis text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE h my_derby.horses%rowtype; day_no int; result jsonb;
BEGIN
 IF length(trim(coalesce(p_diagnosis,''))) NOT BETWEEN 12 AND 500
 THEN RAISE EXCEPTION 'DIAGNOSIS_REQUIRED';END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id FOR UPDATE;
 IF NOT FOUND OR h.npc_owner_id IS NULL OR h.owner_user_id IS NOT NULL
   OR h.life_stage<>'RACING' THEN RAISE EXCEPTION 'NOT_NPC_RACER';END IF;
 day_no:=(my_derby.world_clock(h.world_id)->>'gameDayStart')::int;
 UPDATE my_derby.horses SET
  health_state='INJURED',injury_prognosis='RACING_UNFIT',
  injury_assessed_game_day=day_no
 WHERE id=p_horse_id;
 INSERT INTO my_derby.horse_state_history(horse_id,game_day,event_code,old_state,new_state)
 VALUES(h.id,day_no,'NPC_PERMANENT_INJURY_DIAGNOSED',
   jsonb_build_object('health',h.health_state,'injuryPrognosis',h.injury_prognosis),
   jsonb_build_object('health','INJURED','injuryPrognosis','RACING_UNFIT',
     'diagnosis',trim(p_diagnosis)));
 result:=my_derby_private.npc_try_retirement(p_horse_id,'PERMANENT_INJURY',
   jsonb_build_object('diagnosis',trim(p_diagnosis),'assessedDay',day_no));
 RETURN result;
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.npc_retirement_public_summary()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 SELECT jsonb_build_object(
  'total',(select count(*) FROM my_derby.npc_retirement_decisions),
  'poorForm',(select count(*) FROM my_derby.npc_retirement_decisions WHERE reason='POOR_FORM'),
  'injury',(select count(*) FROM my_derby.npc_retirement_decisions WHERE reason='PERMANENT_INJURY'),
  'stallions',(select count(*) FROM my_derby.npc_retirement_decisions WHERE converted_to='STALLION'),
  'broodmares',(select count(*) FROM my_derby.npc_retirement_decisions WHERE converted_to='BROODMARE'),
  'retired',(select count(*) FROM my_derby.npc_retirement_decisions WHERE converted_to='RETIRED'),
  'recent',coalesce((select jsonb_agg(t.item ORDER BY t.id DESC) FROM (
    select d.id,jsonb_build_object('horseName',h.name,'reason',d.reason,'newStage',d.converted_to,
     'gameDay',d.game_day,'replacedEntries',d.replaced_race_entries,
     'breedingPending',d.breeding_pending) item
    from my_derby.npc_retirement_decisions d join my_derby.horses h on h.id=d.horse_id
    order by d.id desc limit 15
   ) t),'[]'::jsonb)
 );
$fn$;

REVOKE ALL ON FUNCTION my_derby_private.npc_retirement_candidates(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.npc_try_retirement(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_npc_retirement_decisions() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.record_npc_permanent_racing_injury(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.npc_retirement_public_summary() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.npc_retirement_public_summary() TO anon,authenticated,service_role;
CREATE INDEX IF NOT EXISTS idx_npc_retirement_world ON my_derby.npc_retirement_decisions(world_id,created_at DESC);
SELECT cron.schedule('my-derby-npc-retirement','5 14 * * *',
 'select my_derby_private.process_npc_retirement_decisions();');
