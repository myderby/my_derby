-- Keep market actions consistent; never treat an auction as an instant listing.
CREATE OR REPLACE FUNCTION my_derby.player_market_cancel(p_listing uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();l my_derby.market_listings%rowtype;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT * INTO l FROM my_derby.market_listings WHERE id=p_listing FOR UPDATE;
 IF NOT FOUND OR l.status<>'ACTIVE' OR l.sale_mode<>'FIXED'
    OR l.seller_user_id IS DISTINCT FROM u
 THEN RAISE EXCEPTION 'CANNOT_CANCEL_LISTING';END IF;
 UPDATE my_derby.market_listings SET status='CANCELLED' WHERE id=l.id;
 UPDATE my_derby.horses SET sale_state='NOT_LISTED' WHERE id=l.horse_id;
 RETURN jsonb_build_object('status','CANCELLED','listingId',l.id);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_auction_cancel(p_listing uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();l my_derby.market_listings%rowtype;
 v_bid my_derby.market_bids%rowtype;v_world uuid;v_day integer;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT * INTO l FROM my_derby.market_listings WHERE id=p_listing FOR UPDATE;
 IF NOT FOUND OR l.status<>'ACTIVE' OR l.sale_mode<>'AUCTION'
    OR l.seller_user_id IS DISTINCT FROM u
 THEN RAISE EXCEPTION 'AUCTION_CANCEL_NOT_ALLOWED' USING ERRCODE='42501';END IF;
 SELECT h.world_id INTO v_world FROM my_derby.horses h WHERE h.id=l.horse_id FOR UPDATE;
 v_day:=(my_derby.world_clock(v_world)->>'gameDayStart')::integer;
 IF v_day>=l.auction_end_game_day THEN
  RAISE EXCEPTION 'AUCTION_ALREADY_ENDED';END IF;
 SELECT * INTO v_bid FROM my_derby.market_bids
  WHERE listing_id=l.id AND status='PENDING'
  ORDER BY bid_amount DESC,created_at,id LIMIT 1 FOR UPDATE;
 IF FOUND THEN
  PERFORM my_derby_private.wallet_mutate(v_bid.bidder_user_id,v_world,
   v_day,v_bid.bid_amount,'AUCTION_BID_REFUND','AUCTION_BID',v_bid.id);
  UPDATE my_derby.market_bids SET status='WITHDRAWN' WHERE id=v_bid.id;
 END IF;
 UPDATE my_derby.market_listings SET status='CANCELLED' WHERE id=l.id;
 UPDATE my_derby.horses SET sale_state='NOT_LISTED' WHERE id=l.horse_id;
 RETURN jsonb_build_object('status','CANCELLED','listingId',l.id,
    'refunded',coalesce(v_bid.bid_amount,0));
END $fn$;
REVOKE ALL ON FUNCTION my_derby.player_market_cancel(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_auction_cancel(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_market_cancel(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_auction_cancel(uuid) TO authenticated;
