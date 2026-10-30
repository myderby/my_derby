-- NPC owner market agency. Owners themselves never retire.
-- Start with provisional game budgets; no player money changed unless they list.
CREATE TABLE IF NOT EXISTS my_derby.npc_owner_wallets(
 npc_owner_id uuid PRIMARY KEY REFERENCES my_derby.npc_owners(id),
 balance bigint NOT NULL DEFAULT 10000000 CHECK(balance>=0),
 updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO my_derby.npc_owner_wallets(npc_owner_id)
 SELECT id FROM my_derby.npc_owners
 ON CONFLICT DO NOTHING;
ALTER TABLE my_derby.npc_owner_wallets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.npc_owner_wallets FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS my_derby.npc_market_listings(
 listing_id uuid PRIMARY KEY REFERENCES my_derby.market_listings(id),
 npc_owner_id uuid NOT NULL REFERENCES my_derby.npc_owners(id),
 game_day integer NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE my_derby.npc_market_listings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.npc_market_listings FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS my_derby.npc_market_trades(
 listing_id uuid PRIMARY KEY REFERENCES my_derby.market_listings(id),
 seller_npc_id uuid REFERENCES my_derby.npc_owners(id),
 buyer_npc_id uuid REFERENCES my_derby.npc_owners(id),
 buyer_user_id uuid REFERENCES auth.users(id),
 seller_user_id uuid REFERENCES auth.users(id),
 horse_id uuid NOT NULL REFERENCES my_derby.horses(id),
 game_day integer NOT NULL,
 gross_amount bigint NOT NULL CHECK(gross_amount>0),
 fee_amount bigint NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(buyer_npc_id IS NOT NULL OR buyer_user_id IS NOT NULL)
);
ALTER TABLE my_derby.npc_market_trades ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.npc_market_trades FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS my_derby.npc_market_activity(
 npc_owner_id uuid NOT NULL REFERENCES my_derby.npc_owners(id),
 game_day integer NOT NULL,
 action text NOT NULL CHECK(action IN('LIST','BUY')),
 reference_id uuid NOT NULL REFERENCES my_derby.market_listings(id),
 PRIMARY KEY(npc_owner_id,game_day,action)
);
ALTER TABLE my_derby.npc_market_activity ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.npc_market_activity FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.process_npc_owner_market()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v record;v_h record;v_offer record;v_owner record;
 v_day int;v_price bigint;v_price_fee bigint;v_id uuid;
 v_listed int:=0;v_bought int:=0;v_world uuid;
BEGIN
 -- Owner decides whether to release one idle horse based on herd size.
 FOR v IN
  SELECT o.id npc_owner_id,o.world_id,
   (my_derby.world_clock(o.world_id)->>'gameDayStart')::int current_day,
   count(h.id) herd,o.policy->>'risk' risk
  FROM my_derby.npc_owners o
  JOIN my_derby.worlds w ON w.id=o.world_id
  JOIN my_derby.horses h ON h.npc_owner_id=o.id
  WHERE w.status='ACTIVE' AND (o.policy->>'active')='true'
  GROUP BY o.id,o.world_id,o.policy->>'risk'
  HAVING count(h.id)>CASE WHEN o.policy->>'risk'='CONSERVATIVE' THEN 45
    WHEN o.policy->>'risk'='AGGRESSIVE' THEN 60 ELSE 52 END
  ORDER BY o.id LIMIT 80
 LOOP
  IF EXISTS(SELECT 1 FROM my_derby.npc_market_activity a
    WHERE a.npc_owner_id=v.npc_owner_id AND a.game_day=v.current_day AND a.action='LIST')
   OR (SELECT count(*) FROM my_derby.market_listings l
      JOIN my_derby.npc_market_listings nl ON nl.listing_id=l.id
      WHERE nl.npc_owner_id=v.npc_owner_id AND l.status='ACTIVE')>=2
  THEN CONTINUE;END IF;
  SELECT h.id,h.source_grade_no,h.age_years INTO v_h
  FROM my_derby.horses h
  WHERE h.npc_owner_id=v.npc_owner_id
   AND h.life_stage='RACING' AND h.age_years BETWEEN 4 AND 10
   AND h.health_state='HEALTHY' AND h.sale_state='NOT_LISTED'
   AND h.source_grade_no BETWEEN 1 AND 6
   AND h.breeding_retired_at IS NULL
   AND NOT EXISTS(SELECT 1 FROM my_derby.race_entries e
      JOIN my_derby.races r ON r.id=e.race_id
      WHERE e.horse_id=h.id AND r.status IN('OPEN','CLOSED','RUNNING')
        AND e.status IN('APPLIED','CONFIRMED'))
  ORDER BY md5(h.id::text||v.current_day::text) LIMIT 1 FOR UPDATE OF h SKIP LOCKED;
  IF v_h.id IS NULL THEN CONTINUE;END IF;
  v_price:=CASE v_h.source_grade_no WHEN 6 THEN 200000 WHEN 5 THEN 400000
   WHEN 4 THEN 700000 WHEN 3 THEN 1250000 WHEN 2 THEN 2400000 ELSE 4000000 END;
  INSERT INTO my_derby.market_listings(horse_id,seller_user_id,asking_price,status,sale_mode)
  VALUES(v_h.id,NULL,v_price,'ACTIVE','FIXED') RETURNING id INTO v_id;
  INSERT INTO my_derby.npc_market_listings(listing_id,npc_owner_id,game_day)
  VALUES(v_id,v.npc_owner_id,v.current_day);
  UPDATE my_derby.horses SET sale_state='AUCTION_LISTED' WHERE id=v_h.id;
  INSERT INTO my_derby.npc_market_activity(npc_owner_id,game_day,action,reference_id)
  VALUES(v.npc_owner_id,v.current_day,'LIST',v_id) ON CONFLICT DO NOTHING;
  v_listed:=v_listed+1;
 END LOOP;
 -- NPCs buy fixed-price horses listed by other owners only, never auto-sell player horses.
 FOR v_offer IN
  SELECT l.id listing_id,l.horse_id,l.seller_user_id,l.asking_price,
   h.source_meet,h.world_id,h.npc_owner_id previous_owner
  FROM my_derby.market_listings l
  JOIN my_derby.horses h ON h.id=l.horse_id
  JOIN my_derby.worlds w ON w.id=h.world_id
  WHERE l.status='ACTIVE' AND l.sale_mode='FIXED'
    AND l.seller_user_id IS NOT NULL
    AND w.status='ACTIVE'
  ORDER BY l.created_at,l.id LIMIT 35
 LOOP
  SELECT * INTO v_owner FROM (
   SELECT o.id,o.world_id,o.policy,
    w.balance,(SELECT count(*) FROM my_derby.horses h
      WHERE h.npc_owner_id=o.id) herd,
    (my_derby.world_clock(o.world_id)->>'gameDayStart')::int current_day
   FROM my_derby.npc_owners o
   JOIN my_derby.npc_owner_wallets w ON w.npc_owner_id=o.id
   WHERE o.world_id=v_offer.world_id AND (o.policy->>'active')='true'
    AND w.balance>=v_offer.asking_price
    AND NOT EXISTS(SELECT 1 FROM my_derby.npc_market_activity a
      WHERE a.npc_owner_id=o.id AND a.game_day=
      (my_derby.world_clock(o.world_id)->>'gameDayStart')::int AND a.action='BUY')
   ORDER BY md5(o.id::text||v_offer.listing_id::text)
  ) options WHERE herd<70 LIMIT 1;
  IF v_owner.id IS NULL THEN CONTINUE;END IF;
  PERFORM 1 FROM my_derby.npc_owner_wallets
   WHERE npc_owner_id=v_owner.id FOR UPDATE;
  PERFORM 1 FROM my_derby.market_listings
   WHERE id=v_offer.listing_id AND status='ACTIVE' FOR UPDATE;
  IF NOT FOUND THEN CONTINUE;END IF;
  PERFORM 1 FROM my_derby.horses WHERE id=v_offer.horse_id FOR UPDATE;
  IF NOT FOUND THEN CONTINUE;END IF;
  IF EXISTS(SELECT 1 FROM my_derby.race_entries e
    JOIN my_derby.races r ON r.id=e.race_id
    WHERE e.horse_id=v_offer.horse_id
      AND r.status IN('OPEN','CLOSED','RUNNING')
      AND e.status IN('APPLIED','CONFIRMED')) THEN CONTINUE;END IF;
  UPDATE my_derby.npc_owner_wallets SET balance=balance-v_offer.asking_price,
    updated_at=now() WHERE npc_owner_id=v_owner.id AND balance>=v_offer.asking_price;
  IF NOT FOUND THEN CONTINUE;END IF;
  v_price_fee:=floor(v_offer.asking_price*(SELECT amount
    FROM my_derby.economy_config WHERE key='MARKET_FEE_BASIS_POINTS')/10000.0)::bigint;
  PERFORM my_derby_private.wallet_mutate(v_offer.seller_user_id,v_offer.world_id,
    v_owner.current_day,v_offer.asking_price-v_price_fee,
    'HORSE_NPC_SALE','NPC_MARKET',v_offer.listing_id);
  UPDATE my_derby.trainer_contracts SET status='ENDED',end_game_day=v_owner.current_day
    WHERE horse_id=v_offer.horse_id AND status='ACTIVE';
  UPDATE my_derby.horses SET owner_user_id=NULL,npc_owner_id=v_owner.id,
    location='NPC_STABLE',sale_state='NOT_LISTED'
    WHERE id=v_offer.horse_id;
  UPDATE my_derby.market_listings SET status='SOLD'
    WHERE id=v_offer.listing_id;
  INSERT INTO my_derby.npc_market_trades(listing_id,buyer_npc_id,seller_user_id,
    horse_id,game_day,gross_amount,fee_amount)
  VALUES(v_offer.listing_id,v_owner.id,v_offer.seller_user_id,v_offer.horse_id,
    v_owner.current_day,v_offer.asking_price,v_price_fee);
  INSERT INTO my_derby.npc_market_activity(npc_owner_id,game_day,action,reference_id)
  VALUES(v_owner.id,v_owner.current_day,'BUY',v_offer.listing_id)
  ON CONFLICT DO NOTHING;
  INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
  VALUES(v_offer.seller_user_id,'MARKET','NPC 마주에게 판매 완료',
   'NPC 마주가 경주마를 구매했습니다. 판매대금이 지급되었습니다.',
   jsonb_build_object('listingId',v_offer.listing_id,'amount',v_offer.asking_price));
  v_bought:=v_bought+1;
 END LOOP;
 RETURN jsonb_build_object('status','OK','npcListingsCreated',v_listed,
    'npcPurchases',v_bought,'npcOwnersRetired',0);
END $fn$;
REVOKE ALL ON FUNCTION my_derby_private.process_npc_owner_market()
 FROM PUBLIC,anon,authenticated;
SELECT cron.schedule('my-derby-npc-market','0 2 * * *',
 'select my_derby_private.process_npc_owner_market();');
