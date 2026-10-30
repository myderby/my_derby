CREATE OR REPLACE FUNCTION my_derby_private.settle_due_horse_auctions()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE l my_derby.market_listings%rowtype;bid my_derby.market_bids%rowtype;
 h my_derby.horses%rowtype;v_day int;v_fee bigint;v_n int:=0;
 v_sold int:=0;v_expired int:=0;
BEGIN
 FOR l IN SELECT m.* FROM my_derby.market_listings m
 JOIN my_derby.horses horse ON horse.id=m.horse_id
 JOIN my_derby.worlds w ON w.id=horse.world_id
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