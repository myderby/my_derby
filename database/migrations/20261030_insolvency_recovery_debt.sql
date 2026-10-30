-- Player insolvency recovery. Provisional one-time bridge grant,
-- never sell players' horses or delete their existing race entries.
CREATE TABLE IF NOT EXISTS my_derby.financial_recovery_events(
 owner_user_id uuid NOT NULL REFERENCES auth.users(id),
 season_number integer NOT NULL,
 world_id uuid NOT NULL REFERENCES my_derby.worlds(id),
 game_day integer NOT NULL,
 relief_amount bigint NOT NULL CHECK(relief_amount>=0),
 outstanding_before bigint NOT NULL,
 outstanding_after bigint NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(owner_user_id,season_number)
);
ALTER TABLE my_derby.financial_recovery_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.financial_recovery_events FROM PUBLIC,anon,authenticated;
INSERT INTO my_derby.economy_config(key,amount,policy_status,explanation)
 VALUES('ONE_SEASON_RECOVERY_GRANT',300000,'PROVISIONAL',
  'Emergency grant available only for serious operating debt, one grant per season. Not a finalized economy_v2 value')
 ON CONFLICT(key) DO NOTHING;

CREATE OR REPLACE FUNCTION my_derby_private.repay_player_operating_debts(
 p_owner uuid,p_world uuid,p_now_day integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE debt record;v_balance bigint;v_pay bigint;v_total bigint:=0;
 v_ref uuid;v_left bigint;
BEGIN
 IF p_owner IS NULL OR p_world IS NULL OR p_now_day<1 THEN RAISE EXCEPTION 'BAD_DEBT_SCOPE';END IF;
 v_balance:=my_derby_private.wallet_initialise(p_owner,p_world,p_now_day);
 FOR debt IN SELECT * FROM my_derby.economy_daily_operations
  WHERE owner_user_id=p_owner AND world_id=p_world AND unpaid_fee>0
  ORDER BY game_day FOR UPDATE SKIP LOCKED
 LOOP
  EXIT WHEN v_balance<=0;
  v_pay:=least(debt.unpaid_fee,v_balance);
  -- Each real-world operating week can contribute at most one repayment.
  v_ref:=md5(p_owner::text||':debt:'||debt.game_day::text||':week:'||p_now_day::text)::uuid;
  IF EXISTS(SELECT 1 FROM my_derby.wallet_transactions
    WHERE owner_user_id=p_owner AND reference_id=v_ref
      AND transaction_type='OPERATING_DEBT_PAYMENT') THEN CONTINUE;END IF;
  PERFORM my_derby_private.wallet_mutate(p_owner,p_world,p_now_day,-v_pay,
   'OPERATING_DEBT_PAYMENT','OPERATION_DAY',v_ref);
  UPDATE my_derby.economy_daily_operations
   SET paid_fee=paid_fee+v_pay,unpaid_fee=unpaid_fee-v_pay
   WHERE owner_user_id=p_owner AND game_day=debt.game_day;
  v_total:=v_total+v_pay;v_balance:=v_balance-v_pay;
 END LOOP;
 SELECT coalesce(sum(unpaid_fee),0) INTO v_left
 FROM my_derby.economy_daily_operations WHERE owner_user_id=p_owner;
 RETURN jsonb_build_object('paid',v_total,'outstanding',v_left);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_financial_recovery()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;c jsonb;
 v_season integer;v_day int;v_balance bigint;v_due bigint;v_amount bigint;v_after jsonb;
 v_ref uuid;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles
  WHERE user_id=u AND initial_setup_complete FOR UPDATE;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 c:=my_derby.world_clock(w);v_season:=(c->>'season')::int;v_day:=(c->>'gameDayStart')::int;
 v_balance:=my_derby_private.wallet_initialise(u,w,v_day);
 SELECT coalesce(sum(unpaid_fee),0) INTO v_due FROM my_derby.economy_daily_operations
 WHERE owner_user_id=u;
 IF v_balance>=20000 OR v_due<=0 THEN RAISE EXCEPTION 'RECOVERY_NOT_ELIGIBLE';END IF;
 IF EXISTS(SELECT 1 FROM my_derby.financial_recovery_events
  WHERE owner_user_id=u AND season_number=v_season)
 THEN RAISE EXCEPTION 'RECOVERY_ALREADY_USED_THIS_SEASON';END IF;
 SELECT amount INTO v_amount FROM my_derby.economy_config
 WHERE key='ONE_SEASON_RECOVERY_GRANT';
 v_ref:=md5(u::text||':recovery_season:'||v_season::text)::uuid;
 PERFORM my_derby_private.wallet_mutate(u,w,v_day,v_amount,
  'EMERGENCY_RECOVERY_GRANT','RECOVERY',v_ref);
 v_after:=my_derby_private.repay_player_operating_debts(u,w,v_day);
 INSERT INTO my_derby.financial_recovery_events(owner_user_id,season_number,
  world_id,game_day,relief_amount,outstanding_before,outstanding_after)
 VALUES(u,v_season,w,v_day,v_amount,v_due,(v_after->>'outstanding')::bigint);
 INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
 VALUES(u,'ECONOMY','재정 회생 지원금 지급',
  '게임 재정 회복 지원금 '||v_amount||' G 지급 및 미납 운영비 처리',
  jsonb_build_object('season',v_season,'grant',v_amount,'debtsPaid',v_after->'paid'));
 RETURN jsonb_build_object('status','RECOVERED','grant',v_amount,
   'debtsPaid',v_after->'paid','remainingDebt',v_after->'outstanding',
   'onePerSeason',true,'policyStatus','PROVISIONAL');
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.process_player_debt_collection()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE pr record;v_day int;v_count int:=0;
BEGIN
 FOR pr IN SELECT p.user_id,p.world_id FROM my_derby.profiles p
  JOIN my_derby.worlds w ON w.id=p.world_id
  WHERE p.initial_setup_complete AND w.status='ACTIVE'
 LOOP
  v_day:=(my_derby.world_clock(pr.world_id)->>'gameDayStart')::int;
  IF EXISTS(SELECT 1 FROM my_derby.economy_daily_operations
    WHERE owner_user_id=pr.user_id AND unpaid_fee>0) THEN
   PERFORM my_derby_private.repay_player_operating_debts(pr.user_id,pr.world_id,v_day);
   v_count:=v_count+1;
  END IF;
 END LOOP;
 RETURN jsonb_build_object('status','OK','debtAccountsReviewed',v_count);
END $fn$;
REVOKE ALL ON FUNCTION my_derby_private.repay_player_operating_debts(uuid,uuid,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_player_debt_collection() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_financial_recovery() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_financial_recovery() TO authenticated;
SELECT cron.schedule('my-derby-debt-collection','48 13 * * *',
 'select my_derby_private.process_player_debt_collection();');
