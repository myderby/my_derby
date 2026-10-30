-- Risk personality correction: conservative owners keep racing longer,
-- aggressive owners decide sooner on breeding after persistent poor performance.
-- BALANCED stays at 6 races; permanent injury policy is unchanged.
DO $policy$
DECLARE v_cons integer;v_agg integer;v_bal integer;
BEGIN
 SELECT count(*) INTO v_cons FROM my_derby.npc_owners
 WHERE policy->>'risk'='CONSERVATIVE';
 SELECT count(*) INTO v_agg FROM my_derby.npc_owners
 WHERE policy->>'risk'='AGGRESSIVE';
 SELECT count(*) INTO v_bal FROM my_derby.npc_owners
 WHERE policy->>'risk'='BALANCED';
 IF v_cons<>27 OR v_agg<>26 OR v_bal<>27 THEN
   RAISE EXCEPTION 'OWNER_PERSONALITY_BASELINE_CHANGED: %,%,%',v_cons,v_agg,v_bal;
 END IF;

 UPDATE my_derby.npc_owners
 SET policy=jsonb_set(policy,'{poorFormBreeding}',
   jsonb_build_object('style','PERSISTENT_RACER','minRaces',8,
     'bottom40Min',7,'avgRelativeMin',0.78),true)
 WHERE policy->>'risk'='CONSERVATIVE';

 UPDATE my_derby.npc_owners
 SET policy=jsonb_set(policy,'{poorFormBreeding}',
   jsonb_build_object('style','EARLY_BREED','minRaces',4,
     'bottom40Min',3,'avgRelativeMin',0.68),true)
 WHERE policy->>'risk'='AGGRESSIVE';

 IF EXISTS (
  SELECT 1 FROM my_derby.npc_owners
  WHERE (policy->>'risk'='CONSERVATIVE' AND
         (policy->'poorFormBreeding'->>'minRaces')::int<>8)
     OR (policy->>'risk'='AGGRESSIVE' AND
         (policy->'poorFormBreeding'->>'minRaces')::int<>4)
     OR (policy->>'risk'='BALANCED' AND
         (policy->'poorFormBreeding'->>'minRaces')::int<>6)
 ) THEN RAISE EXCEPTION 'NPC_RISK_THRESHOLD_VALIDATION_FAILED';END IF;
 RAISE NOTICE 'NPC breeding decision windows: conservative 8, balanced 6, aggressive 4';
END $policy$;
