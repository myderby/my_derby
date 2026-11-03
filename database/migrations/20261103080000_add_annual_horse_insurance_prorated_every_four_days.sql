-- Annual horse insurance is 4% of each horse's recorded purchase price,
-- split across the 13 four-day billing cycles in the 52-real-day game year.
INSERT INTO my_derby.economy_config(key,amount,policy_status,explanation)
VALUES('HORSE_INSURANCE_ANNUAL_BASIS_POINTS',400,'PROVISIONAL',
 'User-configured annual insurance premium: 4% of purchase amount, divided across four-real-day billing cycles')
ON CONFLICT(key) DO UPDATE SET amount=EXCLUDED.amount,
 policy_status=EXCLUDED.policy_status,explanation=EXCLUDED.explanation;

CREATE INDEX IF NOT EXISTS ix_market_sale_events_horse_buyer_completed
 ON my_derby.market_sale_events(horse_id,buyer_user_id,completed_at DESC);

CREATE OR REPLACE FUNCTION my_derby_private.process_daily_player_economy()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE p record; v_day int; v_cost bigint; v_paid bigint; v_owed bigint;
 v_balance bigint; v_ref uuid; v_count int:=0; v_failed int:=0;
 v_insurance_rate bigint;v_insurance bigint;v_insurance_paid bigint;v_insurance_owed bigint;
 v_purchased_horses int;v_season_days int;v_installments int;
BEGIN
 IF (now() AT TIME ZONE 'Asia/Seoul')::time<'22:40'::time
 THEN RETURN jsonb_build_object('status','NOT_DUE');END IF;
 SELECT amount INTO v_insurance_rate FROM my_derby.economy_config
  WHERE key='HORSE_INSURANCE_ANNUAL_BASIS_POINTS';
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
  SELECT real_days_per_season INTO v_season_days
   FROM my_derby.worlds WHERE id=p.world_id;
  v_installments:=greatest(1,ceil(v_season_days::numeric/4)::int);

  SELECT count(*)::int,
   coalesce(sum(round(sale.amount::numeric*v_insurance_rate/
     (10000::numeric*v_installments))::bigint),0)::bigint
  INTO v_purchased_horses,v_insurance
  FROM my_derby.horses h
  JOIN LATERAL (
   SELECT e.amount FROM my_derby.market_sale_events e
   WHERE e.horse_id=h.id AND e.buyer_user_id=h.owner_user_id
   ORDER BY e.completed_at DESC LIMIT 1
  ) sale ON true
  WHERE h.owner_user_id=p.user_id AND h.tutorial_starter_type IS NULL
   AND h.life_stage<>'DECEASED';

  v_balance:=my_derby_private.wallet_initialise(p.user_id,p.world_id,v_day);
  v_paid:=least(v_cost,greatest(v_balance,0));v_owed:=v_cost-v_paid;
  v_ref:=md5(p.user_id::text||':operating-fee:'||extract(epoch FROM p.operating_fee_next_at)::text)::uuid;
  IF v_paid>0 THEN
   PERFORM my_derby_private.wallet_mutate(p.user_id,p.world_id,v_day,
    -v_paid,'DAILY_OPERATION','OPERATION_CYCLE',v_ref);
   v_balance:=v_balance-v_paid;
  END IF;

  v_insurance_paid:=least(v_insurance,greatest(v_balance,0));
  v_insurance_owed:=v_insurance-v_insurance_paid;
  IF v_insurance_paid>0 THEN
   PERFORM my_derby_private.wallet_mutate(p.user_id,p.world_id,v_day,
    -v_insurance_paid,'HORSE_INSURANCE_PREMIUM','OPERATION_CYCLE',
    md5(v_ref::text||':insurance')::uuid);
  END IF;

  INSERT INTO my_derby.economy_daily_operations
   (owner_user_id,world_id,game_day,expected_fee,paid_fee,unpaid_fee,breakdown,processed_at)
  VALUES(p.user_id,p.world_id,v_day,v_cost+v_insurance,v_paid+v_insurance_paid,
   v_owed+v_insurance_owed,
   jsonb_build_object('fixedRealTimeFee',true,'intervalDays',4,
    'nextDueAt',p.operating_fee_next_at,'operatingFee',v_cost,
    'insurancePremium',v_insurance,'insuranceRateAnnualBasisPoints',v_insurance_rate,
    'insuranceInstallmentsPerYear',v_installments,'insuredPurchasedHorseCount',v_purchased_horses,
    'horseCount',v_purchased_horses,'ownerMultiplier',1),now())
  ON CONFLICT(owner_user_id,game_day) DO UPDATE SET
   expected_fee=my_derby.economy_daily_operations.expected_fee+EXCLUDED.expected_fee,
   paid_fee=my_derby.economy_daily_operations.paid_fee+EXCLUDED.paid_fee,
   unpaid_fee=my_derby.economy_daily_operations.unpaid_fee+EXCLUDED.unpaid_fee,
   breakdown=my_derby.economy_daily_operations.breakdown||jsonb_build_object(
    'latestFixedRealTimeFee',EXCLUDED.breakdown),processed_at=EXCLUDED.processed_at;
  UPDATE my_derby.profiles SET operating_fee_next_at=p.operating_fee_next_at+interval '4 days'
   WHERE user_id=p.user_id;
  v_count:=v_count+1;
  IF v_owed+v_insurance_owed>0 THEN v_failed:=v_failed+1;END IF;
 END LOOP;
 RETURN jsonb_build_object('status','PROCESSED','chargedCycles',v_count,'unpaidCycles',v_failed,
  'operatingFee',20000,'insuranceAnnualBasisPoints',v_insurance_rate,'intervalRealDays',4);
END $fn$;
REVOKE ALL ON FUNCTION my_derby_private.process_daily_player_economy() FROM PUBLIC,anon,authenticated;
