-- Competitive horse auctions, guaranteed escrow and settlement.
ALTER TABLE my_derby.market_listings
 ADD COLUMN IF NOT EXISTS sale_mode text NOT NULL DEFAULT 'FIXED',
 ADD COLUMN IF NOT EXISTS auction_end_game_day integer,
 ADD COLUMN IF NOT EXISTS auction_min_increment bigint NOT NULL DEFAULT 10000;
ALTER TABLE my_derby.market_listings DROP CONSTRAINT IF EXISTS listing_sale_mode_ck;
ALTER TABLE my_derby.market_listings ADD CONSTRAINT listing_sale_mode_ck
 CHECK(sale_mode IN ('FIXED','AUCTION'));
ALTER TABLE my_derby.market_listings ADD CONSTRAINT auction_needs_end
 CHECK(sale_mode='FIXED' OR auction_end_game_day IS NOT NULL);

CREATE OR REPLACE FUNCTION my_derby.player_auction_board()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;v_day int;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles
 WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501'; END IF;
 v_day:=(my_derby.world_clock(w)->>'gameDayStart')::int;
 RETURN jsonb_build_object('gameDay',v_day,
 'balance',my_derby_private.wallet_initialise(u,w,v_day),
 'auctions',coalesce((SELECT jsonb_agg(jsonb_build_object(
  'listingId',l.id,'horseId',h.id,'horseName',h.name,
  'horseGrade',h.source_grade_no,'track',h.source_meet,'age',h.age_years,
  'startPrice',l.asking_price,'minIncrement',l.auction_min_increment,
  'endGameDay',l.auction_end_game_day,'status',l.status,
  'sellerIsMe',l.seller_user_id=u,
  'highestBid',coalesce((SELECT max(b.bid_amount) FROM my_derby.market_bids b
    WHERE b.listing_id=l.id AND b.status='PENDING'),0),
  'myLeadingBid',coalesce((SELECT max(b.bid_amount) FROM my_derby.market_bids b
    WHERE b.listing_id=l.id AND b.bidder_user_id=u AND b.status='PENDING'),0)
 ) ORDER BY l.auction_end_game_day,h.name)
 FROM my_derby.market_listings l
 JOIN my_derby.horses h ON h.id=l.horse_id
 WHERE h.world_id=w AND l.sale_mode='AUCTION' AND l.status='ACTIVE'),'[]'::jsonb));
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_auction_create(
 p_horse uuid,p_start bigint,p_days integer DEFAULT 7)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();h my_derby.horses%rowtype;v_day int;v_listing uuid;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 IF p_start NOT BETWEEN 50000 AND 20000000 OR p_days NOT IN(7,14,21)
 THEN RAISE EXCEPTION 'AUCTION_PARAMETERS_INVALID';END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse FOR UPDATE;
 IF NOT FOUND OR h.owner_user_id IS DISTINCT FROM u THEN
 RAISE EXCEPTION 'NOT_YOUR_HORSE' USING ERRCODE='42501';END IF;
 IF h.sale_state<>'NOT_LISTED' OR h.breeding_state='PREGNANT'
 OR h.life_stage='DECEASED'
 OR EXISTS(SELECT 1 FROM my_derby.race_entries e
   JOIN my_derby.races r ON r.id=e.race_id
   WHERE e.horse_id=h.id AND e.status IN('APPLIED','CONFIRMED')
   AND r.status IN('OPEN','RUNNING','CLOSED'))
 THEN RAISE EXCEPTION 'HORSE_CANNOT_AUCTION';END IF;
 v_day:=(my_derby.world_clock(h.world_id)->>'gameDayStart')::int;
 INSERT INTO my_derby.market_listings(horse_id,seller_user_id,asking_price,
  status,sale_mode,auction_end_game_day)
 VALUES(h.id,u,p_start,'ACTIVE','AUCTION',v_day+p_days)
 RETURNING id INTO v_listing;
 UPDATE my_derby.horses SET sale_state='AUCTION_LISTED' WHERE id=h.id;
 RETURN jsonb_build_object('status','ACTIVE','listingId',v_listing,
  'auctionEndGameDay',v_day+p_days);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_auction_bid(
 p_listing uuid,p_amount bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;v_day int;
 l my_derby.market_listings%rowtype;h my_derby.horses%rowtype;
 prev my_derby.market_bids%rowtype; v_bid uuid;v_min bigint;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles
 WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 IF p_amount<50000 OR p_amount>20000000 THEN RAISE EXCEPTION 'BID_AMOUNT_INVALID';END IF;
 SELECT * INTO l FROM my_derby.market_listings WHERE id=p_listing FOR UPDATE;
 SELECT * INTO h FROM my_derby.horses WHERE id=l.horse_id FOR UPDATE;
 v_day:=(my_derby.world_clock(w)->>'gameDayStart')::int;
 IF l.id IS NULL OR l.sale_mode<>'AUCTION' OR l.status<>'ACTIVE'
 OR l.auction_end_game_day<=v_day
 OR h.world_id IS DISTINCT FROM w OR h.sale_state<>'AUCTION_LISTED'
 OR l.seller_user_id=u THEN RAISE EXCEPTION 'AUCTION_CLOSED_OR_INELIGIBLE';END IF;
 SELECT * INTO prev FROM my_derby.market_bids
 WHERE listing_id=l.id AND status='PENDING'
 ORDER BY bid_amount DESC,created_at DESC LIMIT 1 FOR UPDATE;
 v_min:=CASE WHEN prev.id IS NULL THEN l.asking_price
 ELSE prev.bid_amount+l.auction_min_increment END;
 IF p_amount<v_min THEN RAISE EXCEPTION 'BID_BELOW_REQUIRED_MINIMUM';END IF;
 -- A prior leading bid is refunded exactly once, including when a player
 -- increases their own bid. Wallet owner row locking serializes transfers.
 IF prev.id IS NOT NULL THEN
  PERFORM my_derby_private.wallet_mutate(prev.bidder_user_id,w,v_day,
    prev.bid_amount,'AUCTION_BID_REFUND','AUCTION_BID',prev.id);
  UPDATE my_derby.market_bids SET status='LOST' WHERE id=prev.id;
 END IF;
 INSERT INTO my_derby.market_bids(listing_id,bidder_user_id,bid_amount,status)
 VALUES(l.id,u,p_amount,'PENDING') RETURNING id INTO v_bid;
 PERFORM my_derby_private.wallet_mutate(u,w,v_day,-p_amount,
  'AUCTION_BID_HOLD','AUCTION_BID',v_bid);
 RETURN jsonb_build_object('status','LEADING','bidId',v_bid,
  'amount',p_amount,'auctionEndGameDay',l.auction_end_game_day);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.settle_due_horse_auctions()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE l my_derby.market_listings%rowtype;bid my_derby.market_bids%rowtype;
 h my_derby.horses%rowtype;v_day int;v_fee bigint;v_n int:=0;
 v_sold int:=0;v_expired int:=0;
BEGIN
 FOR l IN SELECT m.* FROM my_derby.market_listings m
 JOIN my_derby.horses h ON h.id=m.horse_id
 JOIN my_derby.worlds w ON w.id=h.world_id
 WHERE w.status='ACTIVE' AND m.sale_mode='AUCTION' AND m.status='ACTIVE'
  AND m.auction_end_game_day <= (my_derby.world_clock(w.id)->>'gameDayStart')::int
 ORDER BY m.auction_end_game_day,m.id FOR UPDATE OF m SKIP LOCKED
 LOOP
  SELECT * INTO h FROM my_derby.horses WHERE id=l.horse_id FOR UPDATE;
  v_day:=(my_derby.world_clock(h.world_id)->>'gameDayStart')::int;
  SELECT * INTO bid FROM my_derby.market_bids
   WHERE listing_id=l.id AND status='PENDING'
   ORDER BY bid_amount DESC,created_at DESC LIMIT 1 FOR UPDATE;
  IF bid.id IS NULL THEN
   UPDATE my_derby.market_listings SET status='EXPIRED' WHERE id=l.id;
   UPDATE my_derby.horses SET sale_state='NOT_LISTED' WHERE id=h.id;
   v_expired:=v_expired+1;v_n:=v_n+1;CONTINUE;
  END IF;
  v_fee:=floor(bid.bid_amount *
   (SELECT amount FROM my_derby.economy_config
      WHERE key='MARKET_FEE_BASIS_POINTS')/10000.0)::bigint;
  IF l.seller_user_id IS NOT NULL THEN
   PERFORM my_derby_private.wallet_mutate(l.seller_user_id,h.world_id,v_day,
     bid.bid_amount-v_fee,'HORSE_AUCTION_SALE','MARKET_AUCTION',l.id);
  END IF;
  UPDATE my_derby.trainer_contracts SET status='ENDED',end_game_day=v_day
   WHERE horse_id=h.id AND status='ACTIVE';
  UPDATE my_derby.horses SET owner_user_id=bid.bidder_user_id,
   npc_owner_id=NULL,sale_state='NOT_LISTED',
   race_entry_state='NONE',location='OWNER_RANCH' WHERE id=h.id;
  UPDATE my_derby.market_bids SET status='WON' WHERE id=bid.id;
  UPDATE my_derby.market_listings SET status='SOLD' WHERE id=l.id;
  INSERT INTO my_derby.market_sale_events(listing_id,horse_id,buyer_user_id,
   seller_user_id,amount,fee,game_day)
  VALUES(l.id,h.id,bid.bidder_user_id,l.seller_user_id,bid.bid_amount,v_fee,v_day)
  ON CONFLICT(listing_id) DO NOTHING;
  INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
  VALUES(bid.bidder_user_id,'MARKET','경주마 경매 낙찰',
   h.name||' 경매에서 낙찰됐습니다.',
   jsonb_build_object('listingId',l.id,'horseId',h.id,'price',bid.bid_amount));
  v_n:=v_n+1;v_sold:=v_sold+1;
 END LOOP;
 RETURN jsonb_build_object('status','OK','settled',v_n,'sold',v_sold,'expired',v_expired);
END $fn$;

REVOKE ALL ON FUNCTION my_derby.player_auction_board() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_auction_create(uuid,bigint,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_auction_bid(uuid,bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.settle_due_horse_auctions() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_auction_board() TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_auction_create(uuid,bigint,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_auction_bid(uuid,bigint) TO authenticated;
SELECT cron.schedule('my-derby-auction-settlement','35 0 * * *',
 'select my_derby_private.settle_due_horse_auctions();');
