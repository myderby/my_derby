CREATE OR REPLACE FUNCTION my_derby.player_market_board()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE u uuid:=auth.uid();w uuid; c jsonb; v_balance bigint; v_listings jsonb;v_mine jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 c:=my_derby.world_clock(w);
 v_balance:=my_derby_private.wallet_initialise(u,w,(c->>'gameDayStart')::int);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',l.id,'horseId',h.id,'name',h.name,'age',h.age_years,'sex',h.sex,
  'track',CASE h.source_meet WHEN '제주' THEN '영천'
   WHEN '부산경남' THEN '부산' ELSE h.source_meet END,
  'grade',h.source_grade_no,'price',l.asking_price,'sellerType',
  CASE WHEN EXISTS(SELECT 1 FROM my_derby.npc_market_listings nl WHERE nl.listing_id=l.id) THEN 'NPC'
   WHEN l.seller_user_id IS NULL THEN 'SYSTEM' WHEN l.seller_user_id=u THEN 'MY_LISTING'
   ELSE 'PLAYER' END
  ) ORDER BY l.asking_price,h.name),'[]'::jsonb) INTO v_listings
 FROM my_derby.market_listings l JOIN my_derby.horses h ON h.id=l.horse_id
 WHERE l.status='ACTIVE' AND l.sale_mode='FIXED' AND h.world_id=w;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'id',h.id,'name',h.name,'age',h.age_years,'sex',h.sex,
   'grade',h.source_grade_no,'saleState',h.sale_state,'stage',h.life_stage)
   ORDER BY h.name),'[]'::jsonb) INTO v_mine
 FROM my_derby.horses h WHERE h.owner_user_id=u AND h.world_id=w;
 RETURN jsonb_build_object('balance',v_balance,'world',c,'listings',v_listings,'horses',v_mine,
  'feeBasisPoints',(SELECT amount FROM my_derby.economy_config WHERE key='MARKET_FEE_BASIS_POINTS'));
END $function$;
CREATE OR REPLACE FUNCTION my_derby.player_market_buy(p_listing uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE u uuid:=auth.uid();w uuid;c jsonb;l my_derby.market_listings%rowtype;
 h my_derby.horses%rowtype; v_day int; v_fee bigint; v_wallet jsonb;v_npc uuid;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 SELECT * INTO l FROM my_derby.market_listings WHERE id=p_listing FOR UPDATE;
 IF NOT FOUND OR l.status<>'ACTIVE' OR l.sale_mode<>'FIXED' THEN RAISE EXCEPTION 'LISTING_NOT_AVAILABLE'; END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=l.horse_id FOR UPDATE;
 SELECT npc_owner_id INTO v_npc FROM my_derby.npc_market_listings WHERE listing_id=l.id;
 IF h.world_id<>w OR h.sale_state<>'AUCTION_LISTED'
 OR h.owner_user_id IS NOT DISTINCT FROM u OR
  (l.seller_user_id IS NOT NULL AND h.owner_user_id IS DISTINCT FROM l.seller_user_id)
 OR (l.seller_user_id IS NULL AND
  (h.owner_user_id IS NOT NULL OR h.npc_owner_id IS DISTINCT FROM v_npc))
 THEN RAISE EXCEPTION 'LISTING_OWNER_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM my_derby.race_entries e
 JOIN my_derby.races r ON r.id=e.race_id WHERE e.horse_id=h.id
 AND e.status IN('APPLIED','CONFIRMED') AND r.status IN('OPEN','RUNNING','CLOSED'))
 THEN RAISE EXCEPTION 'HORSE_ALREADY_RACING';END IF;
 c:=my_derby.world_clock(w);v_day:=(c->>'gameDayStart')::int;
 v_wallet:=my_derby_private.wallet_mutate(u,w,v_day,-l.asking_price,
  'HORSE_PURCHASE','MARKET',l.id);
 v_fee:=CASE WHEN l.seller_user_id IS NOT NULL OR v_npc IS NOT NULL THEN
  floor(l.asking_price * (SELECT amount FROM my_derby.economy_config
    WHERE key='MARKET_FEE_BASIS_POINTS')/10000.0)::bigint ELSE 0 END;
 IF l.seller_user_id IS NOT NULL THEN
  PERFORM my_derby_private.wallet_mutate(l.seller_user_id,w,v_day,
    l.asking_price-v_fee,'HORSE_SALE','MARKET',l.id);
 END IF;
 IF v_npc IS NOT NULL THEN
  UPDATE my_derby.npc_owner_wallets SET balance=balance+l.asking_price-v_fee,
   updated_at=now() WHERE npc_owner_id=v_npc;
 END IF;
 UPDATE my_derby.trainer_contracts SET status='ENDED',end_game_day=v_day
 WHERE horse_id=h.id AND status='ACTIVE';
 DELETE FROM my_derby.training_plans WHERE horse_id=h.id;
 UPDATE my_derby.horses SET owner_user_id=u,npc_owner_id=NULL,
  sale_state='NOT_LISTED',location='OWNER_RANCH',race_entry_state='NONE'
 WHERE id=h.id;
 UPDATE my_derby.market_listings SET status='SOLD' WHERE id=l.id;
 INSERT INTO my_derby.market_sale_events(listing_id,horse_id,buyer_user_id,
  seller_user_id,amount,fee,game_day)
 VALUES(l.id,h.id,u,l.seller_user_id,l.asking_price,v_fee,v_day);
 IF v_npc IS NOT NULL THEN
  INSERT INTO my_derby.npc_market_trades(listing_id,horse_id,
   seller_npc_id,buyer_user_id,gross_amount,fee_amount,game_day)
  VALUES(l.id,h.id,v_npc,u,l.asking_price,v_fee,v_day);
 END IF;
 RETURN jsonb_build_object('status','SOLD','horseId',h.id,'name',h.name,
  'spent',l.asking_price,'balance',v_wallet->'balance');
END $function$;
