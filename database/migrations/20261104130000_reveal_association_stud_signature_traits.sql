-- Publish each association stallion's advertised bloodline trait; secondary
-- inherited traits remain hidden until the owner's observations reach threshold.
WITH signatures(name,trait_code) AS (VALUES
 ('닉스고','DISTANCE_STAMINA'),
 ('클래식엠파이어','CLASSIC_POWER'),
 ('한센','EARLY_BURST'),
 ('위키드스트롱','LATE_KICK'),
 ('바이언','FRONT_SPEED')
)
INSERT INTO my_derby_private.horse_breeding_traits
 (horse_id,trait_code,strength,parent_source,discover_after_observations,revealed_at)
SELECT h.id,s.trait_code,my_derby_private.seeded_roll(h.id::text||s.trait_code,78,96),
 'DERIVED',1,now()
FROM my_derby.horses h JOIN signatures s ON s.name=h.name
WHERE h.source_model_version='MY_DERBY_ASSOCIATION_STUD_V1'
ON CONFLICT(horse_id,trait_code) DO UPDATE
 SET strength=excluded.strength,discover_after_observations=1,
     revealed_at=coalesce(my_derby_private.horse_breeding_traits.revealed_at,excluded.revealed_at);
