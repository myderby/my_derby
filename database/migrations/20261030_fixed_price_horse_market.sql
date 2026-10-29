
-- Playable market v1. Fixed-price offers (auction bidding remains a separate extension).
CREATE TABLE IF NOT EXISTS my_derby.market_sale_events(
 listing_id uuid PRIMARY KEY REFERENCES my_derby.market_listings(id),
 horse_id uuid NOT NULL REFERENCES my_derby.horses(id),
 buyer_user_id uuid NOT NULL REFERENCES auth.users(id),
 seller_user_id uuid,
 amount bigint NOT NULL,
 fee bigint NOT NULL DEFAULT 0,
 game_day integer NOT NULL,
 completed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE my_derby.market_sale_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.market_sale_events FROM anon,authenticated;
-- Seed system sale offers from currently unowned reserved horses. Never list a
-- horse that is running in the official race or permanently retired.
WITH eligible AS(
 SELECT h.id,h.source_grade_no,
 row_number() OVER(PARTITION BY h.source_grade_no ORDER BY h.id) position
 FROM my_derby.horses h
 WHERE h.owner_user_id IS NULL AND h.npc_owner_id IS NULL
 AND h.life_stage='RACING' AND h.sale_state='NOT_LISTED'
 AND h.source_grade_no BETWEEN 1 AND 6
 AND NOT EXISTS(SELECT 1 FROM my_derby.race_entries e
  JOIN my_derby.races r ON r.id=e.race_id
  WHERE e.horse_id=h.id AND e.status IN('APPLIED','CONFIRMED')
  AND r.status IN('OPEN','RUNNING','CLOSED'))
),
 new_listings AS(
 INSERT INTO my_derby.market_listings(horse_id,seller_user_id,asking_price,status)
 SELECT id,NULL,CASE source_grade_no
  WHEN 6 THEN 200000 WHEN 5 THEN 400000 WHEN 4 THEN 700000
  WHEN 3 THEN 1250000 WHEN 2 THEN 2400000 ELSE 4000000 END,'ACTIVE'
 FROM eligible WHERE position<=4
 AND NOT EXISTS(SELECT 1 FROM my_derby.market_listings m WHERE m.horse_id=eligible.id)
 RETURNING horse_id
)
UPDATE my_derby.horses SET sale_state='AUCTION_LISTED'
WHERE id IN(SELECT horse_id FROM new_listings);

CREATE OR REPLACE FUNCTION my_derby.player_market_board()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
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
  CASE WHEN l.seller_user_id IS NULL THEN 'SYSTEM' WHEN l.seller_user_id=u THEN 'MY_LISTING'
   ELSE 'PLAYER' END
  ) ORDER BY l.asking_price,h.name),'[]'::jsonb) INTO v_listings
 FROM my_derby.market_listings l JOIN my_derby.horses h ON h.id=l.horse_id
 WHERE l.status='ACTIVE' AND h.world_id=w;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'id',h.id,'name',h.name,'age',h.age_years,'sex',h.sex,
   'grade',h.source_grade_no,'saleState',h.sale_state,'stage',h.life_stage)
   ORDER BY h.name),'[]'::jsonb) INTO v_mine
 FROM my_derby.horses h WHERE h.owner_user_id=u AND h.world_id=w;
 RETURN jsonb_build_object('balance',v_balance,'world',c,'listings',v_listings,'horses',v_mine,
  'feeBasisPoints',(SELECT amount FROM my_derby.economy_config WHERE key='MARKET_FEE_BASIS_POINTS'));
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_market_list(p_horse_id uuid,p_price bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();h my_derby.horses%rowtype; v_listing uuid;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 IF p_price<50000 OR p_price>20000000 THEN RAISE EXCEPTION 'INVALID_MARKET_PRICE';END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id FOR UPDATE;
 IF NOT FOUND OR h.owner_user_id IS DISTINCT FROM u THEN
  RAISE EXCEPTION 'NOT_YOUR_HORSE' USING ERRCODE='42501';END IF;
 IF h.sale_state<>'NOT_LISTED' OR h.life_stage='DECEASED'
  OR h.breeding_state='PREGNANT' OR EXISTS(
  SELECT 1 FROM my_derby.race_entries e JOIN my_derby.races r ON r.id=e.race_id
  WHERE e.horse_id=h.id AND e.status IN('APPLIED','CONFIRMED')
  AND r.status IN('OPEN','CLOSED','RUNNING'))
 THEN RAISE EXCEPTION 'HORSE_CANNOT_BE_LISTED';END IF;
 INSERT INTO my_derby.market_listings(horse_id,seller_user_id,asking_price,status)
 VALUES(h.id,u,p_price,'ACTIVE') RETURNING id INTO v_listing;
 UPDATE my_derby.horses SET sale_state='AUCTION_LISTED' WHERE id=h.id;
 RETURN jsonb_build_object('status','ACTIVE','listingId',v_listing,'price',p_price);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_market_buy(p_listing uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;c jsonb;l my_derby.market_listings%rowtype;
 h my_derby.horses%rowtype; v_day int; v_fee bigint; v_wallet jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 SELECT * INTO l FROM my_derby.market_listings WHERE id=p_listing FOR UPDATE;
 IF NOT FOUND OR l.status<>'ACTIVE' THEN RAISE EXCEPTION 'LISTING_NOT_AVAILABLE'; END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=l.horse_id FOR UPDATE;
 IF h.world_id<>w OR h.sale_state<>'AUCTION_LISTED'
 OR h.owner_user_id IS NOT DISTINCT FROM u OR
  (l.seller_user_id IS NOT NULL AND h.owner_user_id IS DISTINCT FROM l.seller_user_id)
 OR (l.seller_user_id IS NULL AND (h.owner_user_id IS NOT NULL OR h.npc_owner_id IS NOT NULL))
 THEN RAISE EXCEPTION 'LISTING_OWNER_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM my_derby.race_entries e
 JOIN my_derby.races r ON r.id=e.race_id WHERE e.horse_id=h.id
 AND e.status IN('APPLIED','CONFIRMED') AND r.status IN('OPEN','RUNNING','CLOSED'))
 THEN RAISE EXCEPTION 'HORSE_ALREADY_RACING';END IF;
 c:=my_derby.world_clock(w);v_day:=(c->>'gameDayStart')::int;
 v_wallet:=my_derby_private.wallet_mutate(u,w,v_day,-l.asking_price,
  'HORSE_PURCHASE','MARKET',l.id);
 v_fee:=CASE WHEN l.seller_user_id IS NOT NULL THEN
  floor(l.asking_price * (SELECT amount FROM my_derby.economy_config
    WHERE key='MARKET_FEE_BASIS_POINTS')/10000.0)::bigint ELSE 0 END;
 IF l.seller_user_id IS NOT NULL THEN
  PERFORM my_derby_private.wallet_mutate(l.seller_user_id,w,v_day,
    l.asking_price-v_fee,'HORSE_SALE','MARKET',l.id);
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
 RETURN jsonb_build_object('status','SOLD','horseId',h.id,'name',h.name,
  'spent',l.asking_price,'balance',v_wallet->'balance');
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_market_cancel(p_listing uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();l my_derby.market_listings%rowtype;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT * INTO l FROM my_derby.market_listings WHERE id=p_listing FOR UPDATE;
 IF NOT FOUND OR l.status<>'ACTIVE' OR l.seller_user_id IS DISTINCT FROM u
 THEN RAISE EXCEPTION 'CANNOT_CANCEL_LISTING';END IF;
 UPDATE my_derby.market_listings SET status='CANCELLED' WHERE id=l.id;
 UPDATE my_derby.horses SET sale_state='NOT_LISTED' WHERE id=l.horse_id;
 RETURN jsonb_build_object('status','CANCELLED','listingId',l.id);
END $fn$;
REVOKE INSERT,UPDATE,DELETE ON my_derby.market_listings FROM anon,authenticated;
REVOKE INSERT,UPDATE,DELETE ON my_derby.market_bids FROM anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_market_board() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_market_list(uuid,bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_market_buy(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_market_cancel(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_market_board() TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_market_list(uuid,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_market_buy(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_market_cancel(uuid) TO authenticated;
