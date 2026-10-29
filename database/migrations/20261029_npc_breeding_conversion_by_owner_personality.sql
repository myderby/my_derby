-- NPC mare/stallion breeding conversion based on NPC owner's temperament.
-- No NPC owners are retired and no new generic RETIRED horse records are created.
-- Preserve every NPC owner and every horse; add owner-specific breeding tolerance.
UPDATE my_derby.npc_owners
SET policy=jsonb_set(policy,'{poorFormBreeding}',CASE policy->>'risk'
 WHEN 'CONSERVATIVE' THEN jsonb_build_object('minRaces',4,'bottom40Min',3,'avgRelativeMin',0.68,'style','EARLY_BREED')
 WHEN 'AGGRESSIVE' THEN jsonb_build_object('minRaces',8,'bottom40Min',7,'avgRelativeMin',0.78,'style','PERSISTENT_RACER')
 ELSE jsonb_build_object('minRaces',6,'bottom40Min',5,'avgRelativeMin',0.72,'style','BALANCED')
 END,true)
WHERE policy->>'risk' IN ('CONSERVATIVE','BALANCED','AGGRESSIVE');
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
 )
 SELECT h.id,
  CASE WHEN h.health_state='INJURED' AND h.injury_prognosis='RACING_UNFIT'
       THEN 'PERMANENT_INJURY' ELSE 'POOR_FORM' END,
  CASE WHEN h.health_state='INJURED' AND h.injury_prognosis='RACING_UNFIT'
       THEN jsonb_build_object('prognosis',h.injury_prognosis,'assessedDay',h.injury_assessed_game_day,'ownerRisk',o.policy->>'risk','ownerName',o.name,'ruleVersion','NPC_BREED_V2')
       ELSE jsonb_build_object('window',f.n,'unplaced',f.unplaced,
        'bottom40',f.bottom_40,'avgRelativeRank',f.avg_relative,
        'ownerRisk',o.policy->>'risk','ownerName',o.name,
        'minEligibleRuns',coalesce((o.policy->'poorFormBreeding'->>'minRaces')::int,6),
        'ownerThreshold',o.policy->'poorFormBreeding',
        'ruleVersion','NPC_BREED_V2') END
 FROM my_derby.horses h
 JOIN my_derby.npc_owners o ON o.id=h.npc_owner_id
 LEFT JOIN LATERAL (
  SELECT count(*) n,
    count(*) FILTER(WHERE f.finishing_rank>3) unplaced,
    count(*) FILTER(WHERE f.finishing_rank>ceil(f.field_size*0.6)) bottom_40,
    round(avg((f.finishing_rank-1)::numeric/greatest(f.field_size-1,1)),3) avg_relative
  FROM finishes f
  WHERE f.horse_id=h.id
    AND f.row_no<=coalesce((o.policy->'poorFormBreeding'->>'minRaces')::int,6)
    AND f.field_size>=5
 ) f ON true
 WHERE h.world_id=p_world_id AND h.npc_owner_id IS NOT NULL AND h.owner_user_id IS NULL
  AND h.life_stage='RACING' AND NOT h.racing_retired_permanently
  AND h.breeding_retired_at IS NULL
  AND h.source_model_version IS DISTINCT FROM 'MY_DERBY_SYSTEM_STUD_V1'
  AND NOT EXISTS (SELECT 1 FROM my_derby.npc_retirement_decisions d WHERE d.horse_id=h.id)
  AND ((h.sex='MALE' AND h.age_years BETWEEN 4 AND 25)
   OR (h.sex='FEMALE' AND h.age_years BETWEEN 4 AND 18))
  AND (
   (h.health_state='INJURED' AND h.injury_prognosis='RACING_UNFIT')
   OR (h.health_state='HEALTHY'
    AND f.n=coalesce((o.policy->'poorFormBreeding'->>'minRaces')::int,6)
    AND f.unplaced=f.n
    AND f.bottom_40>=coalesce((o.policy->'poorFormBreeding'->>'bottom40Min')::int,5)
    AND f.avg_relative>=coalesce((o.policy->'poorFormBreeding'->>'avgRelativeMin')::numeric,0.72))
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
 -- No generic NPC horse retirement. Eligibility for breeding is mandatory.
 IF NOT ((h.sex='MALE' AND h.age_years BETWEEN 4 AND 25)
    OR(h.sex='FEMALE' AND h.age_years BETWEEN 4 AND 18)) THEN
  RETURN jsonb_build_object('status','SKIPPED_NOT_BREEDABLE','horseId',h.id);
 END IF;
 -- Revalidate real race history and the owner's personality in the transaction.
 IF p_reason='POOR_FORM' AND NOT EXISTS(
  SELECT 1 FROM my_derby_private.npc_retirement_candidates(h.world_id) c
  WHERE c.horse_id=h.id AND c.reason='POOR_FORM'
 ) THEN RETURN jsonb_build_object('status','SKIPPED_OWNER_WILL_KEEP_RACING'); END IF;

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

 v_stage:=CASE WHEN h.sex='MALE' THEN 'STALLION' ELSE 'BROODMARE' END;
 v_pending:=false;
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
 VALUES(h.id,v_day,'NPC_OWNER_BREEDING_CONVERSION',
  jsonb_build_object('lifeStage',h.life_stage,'health',h.health_state,'breeding',h.breeding_state),
  jsonb_build_object('lifeStage',v_stage,'reason',p_reason,'replacedEntries',n,
   'awaitingBreedingAge',v_pending));
 RETURN jsonb_build_object('status','BREEDING_CONVERTED','horseId',h.id,
   'newStage',v_stage,'reason',p_reason,'replacedRaceEntries',n,
   'breedingPending',v_pending,
   'ownerRisk',(SELECT policy->>'risk' FROM my_derby.npc_owners WHERE id=h.npc_owner_id));
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
   IF response->>'status'='BREEDING_CONVERTED' THEN
    retired:=retired+1;
    -- All new conversions are STALLION or BROODMARE; no normal retirements.
   ELSIF response->>'status'='DEFERRED_ACTIVE_RACE' THEN deferred:=deferred+1;END IF;
  END LOOP;
 END LOOP;
 RETURN jsonb_build_object('status','OK','candidatesConsidered',examined,
  'retired',0,'breedingConversions',retired,'deferredRaceEntry',deferred,
  'regularRetirementOrYoung',geldings,'breedingAgeConversions',breeding);
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
  'retired',0,'policyVersion','NPC_BREED_V2',
  'ownerStyles',(select coalesce(jsonb_agg(z.item order by z.risk),'[]'::jsonb) from (
     select o.policy->>'risk' risk,jsonb_build_object(
       'risk',o.policy->>'risk','count',count(*),
       'minRaces',max((o.policy->'poorFormBreeding'->>'minRaces')::int),
       'bottom40Min',max((o.policy->'poorFormBreeding'->>'bottom40Min')::int),
       'avgRelativeMin',max((o.policy->'poorFormBreeding'->>'avgRelativeMin')::numeric)) item
     from my_derby.npc_owners o group by o.policy->>'risk') z),
  'recent',coalesce((select jsonb_agg(t.item ORDER BY t.id DESC) FROM (
    select d.id,jsonb_build_object('horseName',h.name,'ownerName',o.name,'ownerRisk',o.policy->>'risk','reason',d.reason,'newStage',d.converted_to,
     'gameDay',d.game_day,'replacedEntries',d.replaced_race_entries,
     'breedingPending',d.breeding_pending) item
    from my_derby.npc_retirement_decisions d join my_derby.horses h on h.id=d.horse_id
    join my_derby.npc_owners o on o.id=d.npc_owner_id
    order by d.id desc limit 15
   ) t),'[]'::jsonb)
 );
$fn$;
DO $do$ BEGIN
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='my-derby-npc-retirement') THEN
  PERFORM cron.unschedule('my-derby-npc-retirement');
 END IF;
 END $do$;
SELECT cron.schedule('my-derby-npc-breeding','5 14 * * *',
 'select my_derby_private.process_npc_retirement_decisions();');