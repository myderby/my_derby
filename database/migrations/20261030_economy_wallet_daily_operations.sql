
-- ECONOMY V2 ledger: source tables retained; unresolved initial capital/fee 
-- are isolated as explicitly provisional configuration rather than pretending
-- those two values were set by Appendix F.
CREATE TABLE IF NOT EXISTS my_derby.economy_config(
 key text PRIMARY KEY,
 amount bigint NOT NULL CHECK(amount>=0),
 policy_status text NOT NULL CHECK(policy_status IN ('ORIGINAL_V2','PROVISIONAL')),
 explanation text NOT NULL
);
INSERT INTO my_derby.economy_config(key,amount,policy_status,explanation) VALUES
 ('INITIAL_CAPITAL',2000000,'PROVISIONAL','Starting capital not specified numerically in economy_v2; adjustable'),
 ('ENTRY_FEE_BASIS_POINTS',200,'ORIGINAL_V2','Economy v2 example general race entry 2%'),
 ('MARKET_FEE_BASIS_POINTS',500,'PROVISIONAL','Original appendix specifies a fee but does not fix a rate')
 ON CONFLICT(key) DO NOTHING;
ALTER TABLE my_derby.economy_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.economy_config FROM anon,authenticated;

CREATE TABLE IF NOT EXISTS my_derby.economy_daily_operations(
 owner_user_id uuid NOT NULL REFERENCES auth.users(id),
 world_id uuid NOT NULL REFERENCES my_derby.worlds(id),
 game_day integer NOT NULL CHECK(game_day>=1),
 expected_fee bigint NOT NULL CHECK(expected_fee>=0),
 paid_fee bigint NOT NULL CHECK(paid_fee>=0),
 unpaid_fee bigint NOT NULL CHECK(unpaid_fee>=0),
 breakdown jsonb NOT NULL DEFAULT '{}'::jsonb,
 processed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(owner_user_id,game_day)
);
ALTER TABLE my_derby.economy_daily_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.economy_daily_operations FROM anon,authenticated;

CREATE UNIQUE INDEX IF NOT EXISTS ix_wallet_unique_reference
 ON my_derby.wallet_transactions(owner_user_id,transaction_type,reference_type,reference_id)
 WHERE reference_id IS NOT NULL;

CREATE OR REPLACE FUNCTION my_derby_private.wallet_initialise(p_owner uuid,p_world uuid,p_game_day integer)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_balance bigint;v_grant bigint;
BEGIN
 PERFORM 1 FROM my_derby.profiles WHERE user_id=p_owner AND world_id=p_world
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'WALLET_OWNER_INVALID'; END IF;
 IF NOT EXISTS(SELECT 1 FROM my_derby.wallet_transactions WHERE owner_user_id=p_owner
  AND transaction_type='INITIAL_CAPITAL') THEN
  SELECT amount INTO v_grant FROM my_derby.economy_config WHERE key='INITIAL_CAPITAL';
  SELECT balance_after INTO v_balance FROM my_derby.wallet_transactions
    WHERE owner_user_id=p_owner ORDER BY id DESC LIMIT 1;
  INSERT INTO my_derby.wallet_transactions(owner_user_id,world_id,game_day,
   change_amount,balance_after,transaction_type,reference_type,reference_id)
  VALUES(p_owner,p_world,p_game_day,v_grant,coalesce(v_balance,0)+v_grant,
    'INITIAL_CAPITAL','USER',p_owner);
 END IF;
 SELECT balance_after INTO v_balance FROM my_derby.wallet_transactions
  WHERE owner_user_id=p_owner ORDER BY id DESC LIMIT 1;
 RETURN coalesce(v_balance,0);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.wallet_mutate(
 p_owner uuid,p_world uuid,p_day int,p_amount bigint,p_type text,
 p_reference_type text,p_reference_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE current_balance bigint; prior my_derby.wallet_transactions%rowtype;
BEGIN
 IF p_owner IS NULL OR p_world IS NULL OR p_day<1
 OR p_reference_id IS NULL OR length(trim(p_type))<2 THEN
  RAISE EXCEPTION 'INVALID_WALLET_OPERATION';END IF;
 current_balance:=my_derby_private.wallet_initialise(p_owner,p_world,p_day);
 SELECT * INTO prior FROM my_derby.wallet_transactions
  WHERE owner_user_id=p_owner AND transaction_type=p_type
    AND reference_type=p_reference_type AND reference_id=p_reference_id
  LIMIT 1;
 IF FOUND THEN RETURN jsonb_build_object('status','ALREADY_APPLIED',
    'balance',current_balance,'transactionId',prior.id);END IF;
 IF current_balance+p_amount<0 THEN RAISE EXCEPTION 'INSUFFICIENT_FUNDS';END IF;
 INSERT INTO my_derby.wallet_transactions(owner_user_id,world_id,game_day,
   change_amount,balance_after,transaction_type,reference_type,reference_id)
 VALUES(p_owner,p_world,p_day,p_amount,current_balance+p_amount,
   p_type,p_reference_type,p_reference_id);
 RETURN jsonb_build_object('status','APPLIED','amount',p_amount,
  'balance',current_balance+p_amount);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_finance_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid; v_clock jsonb;v_balance bigint;
 v_history jsonb; v_debts bigint;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 v_clock:=my_derby.world_clock(w);
 v_balance:=my_derby_private.wallet_initialise(u,w,(v_clock->>'gameDayStart')::int);
 SELECT coalesce(sum(unpaid_fee),0) INTO v_debts FROM my_derby.economy_daily_operations
  WHERE owner_user_id=u;
 SELECT coalesce(jsonb_agg(row.entry ORDER BY row.id DESC),'[]'::jsonb) INTO v_history
 FROM(SELECT wt.id,jsonb_build_object('gameDay',wt.game_day,'amount',wt.change_amount,
 'balanceAfter',wt.balance_after,'type',wt.transaction_type,'createdAt',wt.created_at) entry
 FROM my_derby.wallet_transactions wt WHERE wt.owner_user_id=u
 ORDER BY wt.id DESC LIMIT 80)row;
 RETURN jsonb_build_object('balance',v_balance,'unpaidExpenses',v_debts,
  'world',v_clock,'recentTransactions',v_history,
  'protected',v_debts>0,'economyVersion','economy_v2');
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.process_daily_player_economy()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE p record; v_day int; v_last int; v_paid bigint;v_cost bigint;
 v_horses bigint;v_ranch bigint;v_facilities bigint;v_staff bigint;
 v_n int;v_factor numeric;v_balance bigint;v_owed bigint;v_count int:=0; v_failed int:=0;
 v_ref uuid; v_grade int;
BEGIN
 IF (now() AT TIME ZONE 'Asia/Seoul')::time<'22:40'::time
 THEN RETURN jsonb_build_object('status','NOT_DUE');END IF;
 FOR p IN SELECT pr.user_id,pr.world_id
  FROM my_derby.profiles pr JOIN my_derby.worlds w ON w.id=pr.world_id
  WHERE pr.initial_setup_complete AND w.status='ACTIVE'
 LOOP
  v_day:=(my_derby.world_clock(p.world_id)->>'gameDayStart')::int;
  -- Seven game days once per real-world day, with per-game-day unique key.
  FOR v_last IN v_day..v_day+6 LOOP
   IF EXISTS(SELECT 1 FROM my_derby.economy_daily_operations
      WHERE owner_user_id=p.user_id AND game_day=v_last) THEN CONTINUE;END IF;
   SELECT count(*),coalesce(sum(CASE h.source_grade_no WHEN 6 THEN 8000
     WHEN 5 THEN 12000 WHEN 4 THEN 18000 WHEN 3 THEN 28000
     WHEN 2 THEN 45000 WHEN 1 THEN 70000 ELSE 8000 END),0)
   INTO v_n,v_horses FROM my_derby.horses h WHERE h.owner_user_id=p.user_id;
   v_factor:=CASE WHEN v_n<=3 THEN 1 WHEN v_n<=6 THEN 1.10
     WHEN v_n<=10 THEN 1.25 ELSE 1.40 END;
   v_horses:=ceil(v_horses*v_factor);
   -- Baseline ranch Lv1 and five Lv1 facility maintenance from original Appendix F.
   SELECT CASE WHEN count(*)>0 THEN 5000 ELSE 0 END INTO v_ranch
    FROM my_derby.ranches WHERE owner_user_id=p.user_id;
   SELECT coalesce(sum(CASE f.facility_type
    WHEN 'PASTURE' THEN 2000 WHEN 'RECOVERY_STABLE' THEN 3000
    WHEN 'REHAB_TRACK' THEN 5000 WHEN 'VET_CLINIC' THEN 8000
    WHEN 'YOUNG_HORSE_AREA' THEN 4000 ELSE 0 END),0) INTO v_facilities
    FROM my_derby.ranch_facilities f JOIN my_derby.ranches r ON r.id=f.ranch_id
    WHERE r.owner_user_id=p.user_id;
   SELECT coalesce(sum(1000*(staff_count+veterinarian_count)),0) INTO v_staff
    FROM my_derby.ranches WHERE owner_user_id=p.user_id;
   v_cost:=v_horses+v_ranch+v_facilities+v_staff;
   v_balance:=my_derby_private.wallet_initialise(p.user_id,p.world_id,v_last);
   v_paid:=least(v_cost,v_balance);v_owed:=v_cost-v_paid;
   v_ref:=md5(p.user_id::text||':economy:'||v_last::text)::uuid;
   IF v_paid>0 THEN
    PERFORM my_derby_private.wallet_mutate(p.user_id,p.world_id,v_last,
     -v_paid,'DAILY_OPERATION','GAME_DAY',v_ref);
   END IF;
   INSERT INTO my_derby.economy_daily_operations
    (owner_user_id,world_id,game_day,expected_fee,paid_fee,unpaid_fee,breakdown)
   VALUES(p.user_id,p.world_id,v_last,v_cost,v_paid,v_owed,
    jsonb_build_object('horseMaintenance',v_horses,'ranchMaintenance',v_ranch,
      'facilityMaintenance',v_facilities,'staffSalary',v_staff,
      'horseCount',v_n,'ownerMultiplier',v_factor));
   v_count:=v_count+1;
   IF v_owed>0 THEN v_failed:=v_failed+1;END IF;
  END LOOP;
 END LOOP;
 RETURN jsonb_build_object('status','PROCESSED','gameDays',v_count,
   'unpaidDays',v_failed);
END $fn$;
REVOKE ALL ON FUNCTION my_derby_private.wallet_initialise(uuid,uuid,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.wallet_mutate(uuid,uuid,integer,bigint,text,text,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_daily_player_economy() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_finance_dashboard() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_finance_dashboard() TO authenticated;

SELECT cron.schedule('my-derby-daily-economy','45 13 * * *',
 'select my_derby_private.process_daily_player_economy();');
