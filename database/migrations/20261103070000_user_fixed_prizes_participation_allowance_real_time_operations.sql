-- Fixed grade purses, participation allowances, and a fixed four-real-day operating fee.

CREATE OR REPLACE FUNCTION my_derby_private.economy_grade_pool(p_grade integer)
RETURNS bigint LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $$
 SELECT CASE p_grade
  WHEN 6 THEN 300000::bigint WHEN 5 THEN 450000::bigint
  WHEN 4 THEN 600000::bigint WHEN 3 THEN 750000::bigint
  WHEN 2 THEN 900000::bigint WHEN 1 THEN 1100000::bigint
  ELSE 0::bigint END
$$;

CREATE OR REPLACE FUNCTION my_derby_private.economy_race_payout(p_grade integer,p_rank integer)
RETURNS bigint LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $$
 SELECT CASE p_grade
  WHEN 6 THEN CASE p_rank WHEN 1 THEN 165000 WHEN 2 THEN 66000 WHEN 3 THEN 42000 WHEN 4 THEN 15000 WHEN 5 THEN 12000 ELSE 0 END
  WHEN 5 THEN CASE p_rank WHEN 1 THEN 247500 WHEN 2 THEN 99000 WHEN 3 THEN 63000 WHEN 4 THEN 22500 WHEN 5 THEN 18000 ELSE 0 END
  WHEN 4 THEN CASE p_rank WHEN 1 THEN 330000 WHEN 2 THEN 132000 WHEN 3 THEN 84000 WHEN 4 THEN 30000 WHEN 5 THEN 24000 ELSE 0 END
  WHEN 3 THEN CASE p_rank WHEN 1 THEN 412500 WHEN 2 THEN 165000 WHEN 3 THEN 105000 WHEN 4 THEN 37500 WHEN 5 THEN 30000 ELSE 0 END
  WHEN 2 THEN CASE p_rank WHEN 1 THEN 495000 WHEN 2 THEN 198000 WHEN 3 THEN 126000 WHEN 4 THEN 45000 WHEN 5 THEN 36000 ELSE 0 END
  WHEN 1 THEN CASE p_rank WHEN 1 THEN 605000 WHEN 2 THEN 242000 WHEN 3 THEN 154000 WHEN 4 THEN 55000 WHEN 5 THEN 44000 ELSE 0 END
  ELSE 0 END::bigint
$$;

CREATE OR REPLACE FUNCTION my_derby_private.economy_participation_allowance(p_rank integer)
RETURNS bigint LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $$ SELECT CASE WHEN p_rank BETWEEN 6 AND 10 THEN (11-p_rank)*2000::bigint ELSE 0::bigint END $$;

REVOKE ALL ON FUNCTION my_derby_private.economy_grade_pool(integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.economy_race_payout(integer,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.economy_participation_allowance(integer) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.apply_official_race_aftercare(p_race_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 race my_derby.races%rowtype; v_pool bigint; v_prize bigint; v_allowance bigint;
 run_id uuid; entry record; v_gain numeric; v_drop numeric; v_balance bigint;
 v_processed int:=0; v_total bigint:=0; v_players bigint:=0; v_rank int; v_count int;
 v_purse_paid bigint:=0; v_allowance_paid bigint:=0;
BEGIN
 SELECT * INTO race FROM my_derby.races WHERE id=p_race_id FOR UPDATE;
 IF NOT FOUND OR race.status<>'FINISHED'
 THEN RETURN jsonb_build_object('status','NOT_FINALIZED'); END IF;
 IF EXISTS (SELECT 1 FROM my_derby.race_postprocess_state WHERE race_id=p_race_id)
 THEN RETURN jsonb_build_object('status','ALREADY_SETTLED','raceId',p_race_id); END IF;
 SELECT id INTO run_id FROM my_derby.race_runs
 WHERE race_id=p_race_id AND status='FINISHED'
 ORDER BY result_applied_at DESC LIMIT 1;
 IF run_id IS NULL THEN RAISE EXCEPTION 'OFFICIAL_RACE_RUN_MISSING'; END IF;
 v_pool:=my_derby_private.economy_grade_pool(coalesce((race.prize_policy->>'grade_no')::int,0));
 IF v_pool<=0 THEN RAISE EXCEPTION 'UNSUPPORTED_RACE_PRIZE_GRADE'; END IF;
 SELECT count(*) INTO v_count FROM my_derby.race_results WHERE race_run_id=run_id;
 IF v_count<2 THEN RAISE EXCEPTION 'OFFICIAL_RESULTS_NOT_READY';END IF;
 FOR entry IN
  SELECT rr.id result_id,rr.horse_id,rr.finishing_rank, h.owner_user_id,h.name,
    h.fatigue,h.condition_score,h.health_state
  FROM my_derby.race_results rr JOIN my_derby.horses h ON h.id=rr.horse_id
  WHERE rr.race_run_id=run_id ORDER BY rr.finishing_rank,rr.id
 LOOP
  v_rank:=entry.finishing_rank;
  v_prize:=CASE WHEN v_rank BETWEEN 1 AND 5
    THEN my_derby_private.economy_race_payout((race.prize_policy->>'grade_no')::int,v_rank)
    ELSE 0 END;
  v_allowance:=my_derby_private.economy_participation_allowance(v_rank);
  v_gain:=round(least(20,8+8*((v_rank-1)::numeric/greatest(v_count-1,1))),1);
  v_drop:=round(least(8,2+4*((v_rank-1)::numeric/greatest(v_count-1,1))),1);
  UPDATE my_derby.race_results SET prize_amount=v_prize+v_allowance,
   change_snapshot=change_snapshot||jsonb_build_object('prize_settlement','ECONOMY_V2_SETTLED',
    'fatigue_change',least(100,entry.fatigue+v_gain)-entry.fatigue,
    'condition_change',greatest(0,entry.condition_score-v_drop)-entry.condition_score,
    'prize_pool',v_pool,'prize_amount',v_prize,'participation_allowance',v_allowance,
    'paid_to_player',entry.owner_user_id IS NOT NULL)
  WHERE id=entry.result_id;
  UPDATE my_derby.horses SET fatigue=least(100,fatigue+v_gain),
    condition_score=greatest(0,condition_score-v_drop),
    race_entry_state='COMPLETED' WHERE id=entry.horse_id;
  INSERT INTO my_derby.horse_state_history(horse_id,game_day,event_code,old_state,new_state)
   VALUES(entry.horse_id,race.race_day,'OFFICIAL_RACE_AFTERCARE',
    jsonb_build_object('fatigue',entry.fatigue,'condition',entry.condition_score),
    jsonb_build_object('fatigue',least(100,entry.fatigue+v_gain),
      'condition',greatest(0,entry.condition_score-v_drop),
      'rank',v_rank,'raceId',p_race_id,'prize',v_prize,'participationAllowance',v_allowance));
  IF entry.owner_user_id IS NOT NULL AND (v_prize+v_allowance)>0 THEN
   IF v_prize>0 THEN
    PERFORM my_derby_private.economy_credit_race_prize(
     entry.owner_user_id,race.world_id,race.race_day,entry.result_id,v_prize);
    v_purse_paid:=v_purse_paid+v_prize;
   END IF;
   IF v_allowance>0 THEN
    PERFORM my_derby_private.wallet_mutate(entry.owner_user_id,race.world_id,race.race_day,
     v_allowance,'RACE_PARTICIPATION_ALLOWANCE','RACE_RESULT',entry.result_id);
    v_allowance_paid:=v_allowance_paid+v_allowance;
   END IF;
   v_players:=v_players+v_prize+v_allowance;
   INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
   VALUES(entry.owner_user_id,'RACE',
    CASE WHEN v_prize>0 THEN '상금 획득' ELSE '출전수당 지급' END,
    entry.name||CASE WHEN v_prize>0 THEN ' 상금 '||v_prize ELSE ' 출전수당 '||v_allowance END||' G 지급',
    jsonb_build_object('raceId',p_race_id,'horseId',entry.horse_id,'prize',v_prize,
      'participationAllowance',v_allowance));
  END IF;
  v_total:=v_total+v_prize+v_allowance;v_processed:=v_processed+1;
 END LOOP;
 UPDATE my_derby.races SET prize_policy=prize_policy||
 jsonb_build_object('prize_status','ECONOMY_V2_SETTLED','total_prize_pool',v_pool,
  'paid_prizes',v_purse_paid,'paid_participation_allowances',v_allowance_paid,
  'paid_prizes_and_allowances',v_total,'horse_aftercare',true) WHERE id=p_race_id;
 INSERT INTO my_derby.race_postprocess_state
 (race_id,world_id,finishers,player_prize_total,prize_total)
 VALUES(p_race_id,race.world_id,v_processed,v_players,v_total);
 PERFORM my_derby_private.apply_race_rating(p_race_id);
 PERFORM my_derby_private.assess_official_race_injuries(p_race_id);
 RETURN jsonb_build_object('status','SETTLED','raceId',p_race_id,
  'finishers',v_processed,'totalPrizes',v_total,'gradePursePrizes',v_purse_paid,
  'participationAllowances',v_allowance_paid,'playerPrizes',v_players);
END $fn$;
REVOKE ALL ON FUNCTION my_derby_private.apply_official_race_aftercare(uuid)
 FROM PUBLIC,anon,authenticated;

INSERT INTO my_derby.economy_config(key,amount,policy_status,explanation)
VALUES('OPERATING_FEE',20000,'PROVISIONAL',
 'User-configured fixed operating fee of 20,000 G charged every four real-world days')
ON CONFLICT(key) DO UPDATE SET amount=EXCLUDED.amount,
 policy_status=EXCLUDED.policy_status,explanation=EXCLUDED.explanation;

ALTER TABLE my_derby.profiles
 ADD COLUMN IF NOT EXISTS operating_fee_next_at timestamptz;
UPDATE my_derby.profiles SET operating_fee_next_at=now()+interval '4 days'
 WHERE initial_setup_complete AND operating_fee_next_at IS NULL;

CREATE OR REPLACE FUNCTION my_derby_private.initialize_operating_fee_cycle()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $fn$
BEGIN
 IF NEW.initial_setup_complete AND NEW.operating_fee_next_at IS NULL THEN
  NEW.operating_fee_next_at:=now()+interval '4 days';
 END IF;
 RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS initialize_operating_fee_cycle ON my_derby.profiles;
CREATE TRIGGER initialize_operating_fee_cycle
 BEFORE INSERT OR UPDATE ON my_derby.profiles
 FOR EACH ROW EXECUTE FUNCTION my_derby_private.initialize_operating_fee_cycle();
REVOKE ALL ON FUNCTION my_derby_private.initialize_operating_fee_cycle() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.process_daily_player_economy()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE p record; v_day int; v_cost bigint; v_paid bigint; v_owed bigint;
 v_balance bigint; v_ref uuid; v_count int:=0; v_failed int:=0;
BEGIN
 IF (now() AT TIME ZONE 'Asia/Seoul')::time<'22:40'::time
 THEN RETURN jsonb_build_object('status','NOT_DUE');END IF;
 FOR p IN
  SELECT pr.user_id,pr.world_id,pr.operating_fee_next_at
  FROM my_derby.profiles pr JOIN my_derby.worlds w ON w.id=pr.world_id
  WHERE pr.initial_setup_complete AND w.status='ACTIVE'
   AND pr.operating_fee_next_at<=now()
  ORDER BY pr.operating_fee_next_at,pr.user_id
  FOR UPDATE OF pr SKIP LOCKED
 LOOP
  v_day:=(my_derby.world_clock(p.world_id)->>'gameDayStart')::int;
  SELECT amount INTO v_cost FROM my_derby.economy_config WHERE key='OPERATING_FEE';
  v_balance:=my_derby_private.wallet_initialise(p.user_id,p.world_id,v_day);
  v_paid:=least(v_cost,greatest(v_balance,0));v_owed:=v_cost-v_paid;
  v_ref:=md5(p.user_id::text||':operating-fee:'||extract(epoch FROM p.operating_fee_next_at)::text)::uuid;
  IF v_paid>0 THEN
   PERFORM my_derby_private.wallet_mutate(p.user_id,p.world_id,v_day,
    -v_paid,'DAILY_OPERATION','OPERATION_CYCLE',v_ref);
  END IF;
  INSERT INTO my_derby.economy_daily_operations
   (owner_user_id,world_id,game_day,expected_fee,paid_fee,unpaid_fee,breakdown,processed_at)
  VALUES(p.user_id,p.world_id,v_day,v_cost,v_paid,v_owed,
   jsonb_build_object('fixedRealTimeFee',true,'intervalDays',4,
    'nextDueAt',p.operating_fee_next_at,'horseCount',0,'ownerMultiplier',1),now())
  ON CONFLICT(owner_user_id,game_day) DO UPDATE SET
   expected_fee=my_derby.economy_daily_operations.expected_fee+EXCLUDED.expected_fee,
   paid_fee=my_derby.economy_daily_operations.paid_fee+EXCLUDED.paid_fee,
   unpaid_fee=my_derby.economy_daily_operations.unpaid_fee+EXCLUDED.unpaid_fee,
   breakdown=my_derby.economy_daily_operations.breakdown||jsonb_build_object(
    'latestFixedRealTimeFee',EXCLUDED.breakdown),processed_at=EXCLUDED.processed_at;
  UPDATE my_derby.profiles SET operating_fee_next_at=p.operating_fee_next_at+interval '4 days'
   WHERE user_id=p.user_id;
  v_count:=v_count+1;
  IF v_owed>0 THEN v_failed:=v_failed+1;END IF;
 END LOOP;
 RETURN jsonb_build_object('status','PROCESSED','chargedCycles',v_count,'unpaidCycles',v_failed,
  'fee',20000,'intervalRealDays',4);
END $fn$;
REVOKE ALL ON FUNCTION my_derby_private.process_daily_player_economy() FROM PUBLIC,anon,authenticated;
