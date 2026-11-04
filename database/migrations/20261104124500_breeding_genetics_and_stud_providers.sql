-- Inheritable breeding traits, progressive discovery, and NPC stallion providers.
-- Trait records live in the private schema; player-facing RPCs expose only discovered data.

CREATE TABLE IF NOT EXISTS my_derby_private.breeding_trait_catalog (
  trait_code text PRIMARY KEY,
  category text NOT NULL,
  display_name text NOT NULL,
  description text NOT NULL,
  stat_effect jsonb NOT NULL DEFAULT '{}'::jsonb,
  inheritance_probability numeric NOT NULL DEFAULT 0.35
    CHECK (inheritance_probability BETWEEN 0 AND 1)
);

CREATE TABLE IF NOT EXISTS my_derby_private.horse_breeding_traits (
  horse_id uuid NOT NULL REFERENCES my_derby.horses(id) ON DELETE CASCADE,
  trait_code text NOT NULL REFERENCES my_derby_private.breeding_trait_catalog(trait_code),
  strength smallint NOT NULL CHECK (strength BETWEEN 1 AND 100),
  parent_source text NOT NULL CHECK (parent_source IN ('DAM','SIRE','BOTH','MUTATION','DERIVED')),
  discover_after_observations smallint NOT NULL DEFAULT 3 CHECK (discover_after_observations BETWEEN 1 AND 20),
  revealed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (horse_id,trait_code)
);
REVOKE ALL ON TABLE my_derby_private.breeding_trait_catalog FROM PUBLIC,anon,authenticated;
REVOKE ALL ON TABLE my_derby_private.horse_breeding_traits FROM PUBLIC,anon,authenticated;

INSERT INTO my_derby_private.breeding_trait_catalog
 (trait_code,category,display_name,description,stat_effect,inheritance_probability) VALUES
 ('DISTANCE_STAMINA','DISTANCE','장거리 지구력','긴 거리에서도 페이스를 유지하는 유전 경향입니다.','{"stamina":3,"recovery":1}'::jsonb,0.35),
 ('CLASSIC_POWER','POWER','클래식 파워','중거리 이상에서 힘을 유지하고 밀어붙이는 경향입니다.','{"power":3,"stamina":1}'::jsonb,0.35),
 ('EARLY_BURST','SPEED','선행 스피드','초반 출발과 가속에 강점을 보이는 경향입니다.','{"start":2,"acceleration":3}'::jsonb,0.35),
 ('LATE_KICK','FINISH','막판 탄력','직선 주로에서 막판 속도를 끌어올리는 경향입니다.','{"finishing":3,"speed":1}'::jsonb,0.35),
 ('FRONT_SPEED','SPEED','초반 폭발력','초반 스피드와 선두권 진입에 강점을 보이는 경향입니다.','{"speed":2,"start":2}'::jsonb,0.35),
 ('POWERFUL_STRIDE','POWER','강한 주폭','힘 있는 주폭으로 파워를 발휘하는 경향입니다.','{"power":3,"grit":1}'::jsonb,0.35),
 ('COMPETITIVE_GRIT','TEMPERAMENT','승부 근성','경주 후반에도 집중력을 유지하는 경향입니다.','{"grit":3,"stability":1}'::jsonb,0.35),
 ('CALM_FOCUS','TEMPERAMENT','침착한 집중력','경주 중 페이스와 리듬을 안정적으로 유지하는 경향입니다.','{"stability":3,"recovery":1}'::jsonb,0.35),
 ('RAPID_RECOVERY','HEALTH','빠른 회복력','훈련과 경주 뒤 피로를 회복하는 데 유리한 경향입니다.','{"recovery":3,"stamina":1}'::jsonb,0.35),
 ('QUICK_ACCELERATION','SPEED','순간 가속','짧은 구간에서 가속도를 높이는 경향입니다.','{"acceleration":3,"speed":1}'::jsonb,0.35),
 ('STEADY_START','SPEED','안정된 출발','출발 과정에서 균형을 잡고 리듬을 찾는 경향입니다.','{"start":3,"stability":1}'::jsonb,0.35)
ON CONFLICT (trait_code) DO UPDATE SET
 category=excluded.category,display_name=excluded.display_name,
 description=excluded.description,stat_effect=excluded.stat_effect,
 inheritance_probability=excluded.inheritance_probability;

CREATE OR REPLACE FUNCTION my_derby_private.seeded_roll(p_key text,p_min integer,p_max integer)
RETURNS integer LANGUAGE sql IMMUTABLE STRICT SET search_path TO ''
AS $fn$
 SELECT p_min + (((('x'||substr(md5(p_key),1,8))::bit(32)::bigint & 2147483647)
   % (p_max-p_min+1))::integer)
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.seeded_roll(text,integer,integer) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.ensure_horse_breeding_genotype(p_horse_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE h my_derby.horses%rowtype; stats jsonb; primary_code text; secondary_code text;
BEGIN
 IF EXISTS(SELECT 1 FROM my_derby_private.horse_breeding_traits WHERE horse_id=p_horse_id) THEN RETURN; END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id;
 IF NOT FOUND OR h.sex='GELDING' OR h.life_stage='DECEASED' THEN RETURN; END IF;
 IF h.source_model_version IN ('MY_DERBY_ASSOCIATION_STUD_V1','MY_DERBY_RANCH_STUD_V1') THEN RETURN; END IF;
 SELECT CASE WHEN a.gene_stats<>'{}'::jsonb THEN a.gene_stats ELSE a.potential_stats END
 INTO stats FROM my_derby.horse_abilities a WHERE a.horse_id=p_horse_id;
 IF stats IS NULL OR stats='{}'::jsonb THEN RETURN; END IF;
 SELECT CASE k
   WHEN 'start' THEN 'STEADY_START' WHEN 'speed' THEN 'FRONT_SPEED'
   WHEN 'acceleration' THEN 'QUICK_ACCELERATION' WHEN 'stamina' THEN 'DISTANCE_STAMINA'
   WHEN 'finishing' THEN 'LATE_KICK' WHEN 'power' THEN 'POWERFUL_STRIDE'
   WHEN 'grit' THEN 'COMPETITIVE_GRIT' WHEN 'stability' THEN 'CALM_FOCUS'
   ELSE 'RAPID_RECOVERY' END
 INTO primary_code
 FROM jsonb_each_text(stats) AS e(k,v)
 WHERE k IN ('start','speed','acceleration','stamina','finishing','power','grit','stability','recovery')
 ORDER BY v::numeric DESC,k
 LIMIT 1;
 SELECT c.trait_code INTO secondary_code
 FROM my_derby_private.breeding_trait_catalog c
 WHERE c.trait_code<>coalesce(primary_code,'')
 ORDER BY md5(p_horse_id::text||c.trait_code) LIMIT 1;
 IF primary_code IS NOT NULL THEN
  INSERT INTO my_derby_private.horse_breeding_traits
   (horse_id,trait_code,strength,parent_source,discover_after_observations)
  VALUES(p_horse_id,primary_code,my_derby_private.seeded_roll(p_horse_id::text||primary_code,55,88),
   'DERIVED',my_derby_private.seeded_roll(p_horse_id::text||primary_code||'reveal',3,6))
  ON CONFLICT DO NOTHING;
 END IF;
 IF secondary_code IS NOT NULL THEN
  INSERT INTO my_derby_private.horse_breeding_traits
   (horse_id,trait_code,strength,parent_source,discover_after_observations)
  VALUES(p_horse_id,secondary_code,my_derby_private.seeded_roll(p_horse_id::text||secondary_code,35,70),
   'DERIVED',my_derby_private.seeded_roll(p_horse_id::text||secondary_code||'reveal',5,8))
  ON CONFLICT DO NOTHING;
 END IF;
END;
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.ensure_horse_breeding_genotype(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.inherit_foal_breeding_traits(p_foal_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE foal my_derby.horses%rowtype; inherited_count integer; mutation_code text;
 v_gene jsonb;v_potential jsonb;v_current jsonb; trait_row record; stat_row record; bonus numeric;
BEGIN
 SELECT * INTO foal FROM my_derby.horses WHERE id=p_foal_id;
 IF NOT FOUND OR foal.father_id IS NULL OR foal.mother_id IS NULL THEN RETURN; END IF;
 IF EXISTS(SELECT 1 FROM my_derby_private.horse_breeding_traits WHERE horse_id=p_foal_id) THEN RETURN; END IF;
 WITH passed AS (
  SELECT t.trait_code,t.strength,'DAM'::text AS source
  FROM my_derby_private.horse_breeding_traits t
  WHERE t.horse_id=foal.mother_id
   AND my_derby_private.seeded_roll(p_foal_id::text||t.trait_code||'DAM',0,9999)<3500
  UNION ALL
  SELECT t.trait_code,t.strength,'SIRE'::text
  FROM my_derby_private.horse_breeding_traits t
  WHERE t.horse_id=foal.father_id
   AND my_derby_private.seeded_roll(p_foal_id::text||t.trait_code||'SIRE',0,9999)<3500
 ), grouped AS (
  SELECT trait_code,round(avg(strength))::smallint AS strength,
   CASE WHEN count(DISTINCT source)>1 THEN 'BOTH' ELSE min(source) END AS parent_source
  FROM passed GROUP BY trait_code
 ), chosen AS (
  SELECT *,row_number() OVER(ORDER BY strength DESC,trait_code) AS n FROM grouped
 )
 INSERT INTO my_derby_private.horse_breeding_traits
  (horse_id,trait_code,strength,parent_source,discover_after_observations)
 SELECT p_foal_id,trait_code,greatest(1,strength),parent_source,
  my_derby_private.seeded_roll(p_foal_id::text||trait_code||'reveal',3,7)
 FROM chosen WHERE n<=3 ON CONFLICT DO NOTHING;

 SELECT count(*) INTO inherited_count FROM my_derby_private.horse_breeding_traits WHERE horse_id=p_foal_id;
 IF inherited_count=0 OR my_derby_private.seeded_roll(p_foal_id::text||'mutation',0,9999)<500 THEN
  SELECT c.trait_code INTO mutation_code FROM my_derby_private.breeding_trait_catalog c
  WHERE NOT EXISTS(SELECT 1 FROM my_derby_private.horse_breeding_traits t
    WHERE t.horse_id=p_foal_id AND t.trait_code=c.trait_code)
  ORDER BY md5(p_foal_id::text||c.trait_code||'mutation') LIMIT 1;
  IF mutation_code IS NOT NULL THEN
   INSERT INTO my_derby_private.horse_breeding_traits
    (horse_id,trait_code,strength,parent_source,discover_after_observations)
   VALUES(p_foal_id,mutation_code,my_derby_private.seeded_roll(p_foal_id::text||mutation_code,45,80),
    'MUTATION',my_derby_private.seeded_roll(p_foal_id::text||mutation_code||'reveal',3,7))
   ON CONFLICT DO NOTHING;
  END IF;
 END IF;

 SELECT gene_stats,potential_stats,current_stats INTO v_gene,v_potential,v_current
 FROM my_derby.horse_abilities WHERE horse_id=p_foal_id;
 IF v_gene IS NULL THEN RETURN; END IF;
 FOR trait_row IN
  SELECT c.stat_effect,t.strength FROM my_derby_private.horse_breeding_traits t
  JOIN my_derby_private.breeding_trait_catalog c USING(trait_code)
  WHERE t.horse_id=p_foal_id
 LOOP
  FOR stat_row IN SELECT key,value::numeric AS value FROM jsonb_each_text(trait_row.stat_effect)
  LOOP
   bonus:=stat_row.value*(0.5+(trait_row.strength::numeric/200));
   v_gene:=jsonb_set(v_gene,ARRAY[stat_row.key],to_jsonb(least(100,coalesce((v_gene->>stat_row.key)::numeric,65)+bonus)),true);
   v_potential:=jsonb_set(v_potential,ARRAY[stat_row.key],to_jsonb(least(100,coalesce((v_potential->>stat_row.key)::numeric,65)+bonus*0.94)),true);
   v_current:=jsonb_set(v_current,ARRAY[stat_row.key],to_jsonb(least(100,coalesce((v_current->>stat_row.key)::numeric,35)+bonus*0.35)),true);
  END LOOP;
 END LOOP;
 UPDATE my_derby.horse_abilities SET gene_stats=v_gene,potential_stats=v_potential,
  current_stats=v_current,estimation_metadata=estimation_metadata||jsonb_build_object('geneticsModel','BREEDING_TRAITS_V1')
 WHERE horse_id=p_foal_id;
END;
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.inherit_foal_breeding_traits(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.on_horse_ability_insert_breeding_genetics()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE model text;
BEGIN
 SELECT source_model_version INTO model FROM my_derby.horses WHERE id=NEW.horse_id;
 IF model IN ('MY_DERBY_BREEDING_V1','MY_DERBY_NPC_BREEDING_V1') THEN
  PERFORM my_derby_private.inherit_foal_breeding_traits(NEW.horse_id);
 ELSE
  PERFORM my_derby_private.ensure_horse_breeding_genotype(NEW.horse_id);
 END IF;
 RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.on_horse_ability_insert_breeding_genetics() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS trg_horse_ability_breeding_genetics ON my_derby.horse_abilities;
CREATE TRIGGER trg_horse_ability_breeding_genetics
AFTER INSERT ON my_derby.horse_abilities
FOR EACH ROW EXECUTE FUNCTION my_derby_private.on_horse_ability_insert_breeding_genetics();

-- Retain legacy seed studs in data for historical breeding records, but replace
-- the public offering with the requested association and ranch suppliers.
UPDATE my_derby.horses SET source_model_version='MY_DERBY_LEGACY_STUD_V1'
WHERE source_model_version='MY_DERBY_SYSTEM_STUD_V1';

WITH worlds AS (
 SELECT id FROM my_derby.worlds WHERE world_key='kra_roster_v1'
), assoc AS (
 INSERT INTO my_derby.npc_owners(world_id,name,reputation,policy)
 SELECT w.id,'한국경마협회',85,
  jsonb_build_object('active',false,'risk','BALANCED','breedingProviderKey','BREEDING_ASSOCIATION',
   'providerType','ASSOCIATION','providerLabel','협회 씨수말')
 FROM worlds w
 WHERE NOT EXISTS(SELECT 1 FROM my_derby.npc_owners o WHERE o.world_id=w.id
  AND o.policy->>'breedingProviderKey'='BREEDING_ASSOCIATION')
 RETURNING id,world_id
)
SELECT 1;

INSERT INTO my_derby.npc_owners(world_id,name,reputation,policy)
SELECT w.id,
 'NPC 목장 '||i::text||' · '||(ARRAY['은하','청명','달빛','솔바람','푸른언덕','별빛','가람','한결','백야','하늘숲'])[
   my_derby_private.seeded_roll(w.id::text||':ranch:'||i,1,10)]||'목장',
 my_derby_private.seeded_roll(w.id::text||':reputation:'||i,45,92),
 jsonb_build_object('active',true,'risk','BALANCED','breedingProviderKey','RANCH_STUD_'||i::text,
  'providerType','NPC_RANCH','providerLabel','NPC 목장 씨수말')
FROM my_derby.worlds w CROSS JOIN generate_series(1,5) i
WHERE w.world_key='kra_roster_v1'
 AND NOT EXISTS(SELECT 1 FROM my_derby.npc_owners o WHERE o.world_id=w.id
   AND o.policy->>'breedingProviderKey'='RANCH_STUD_'||i::text);

WITH seeds AS (
 SELECT w.id world_id,o.id owner_id, i,
  (ARRAY['닉스고','클래식엠파이어','한센','위키드스트롱','바이언'])[i] horse_name,
  (ARRAY['DISTANCE_STAMINA','CLASSIC_POWER','EARLY_BURST','LATE_KICK','FRONT_SPEED'])[i] signature
 FROM my_derby.worlds w
 JOIN my_derby.npc_owners o ON o.world_id=w.id
  AND o.policy->>'breedingProviderKey'='BREEDING_ASSOCIATION'
 CROSS JOIN generate_series(1,5) i
 WHERE w.world_key='kra_roster_v1'
), inserted AS (
 INSERT INTO my_derby.horses
  (world_id,npc_owner_id,name,sex,age_years,life_stage,location,health_state,
   breeding_state,breeding_retired_at,racing_retired_permanently,source_model_version)
 SELECT s.world_id,s.owner_id,s.horse_name,'MALE',5+my_derby_private.seeded_roll(s.world_id::text||s.horse_name,0,6),
  'STALLION','NPC_STABLE','HEALTHY','AVAILABLE',now(),true,'MY_DERBY_ASSOCIATION_STUD_V1'
 FROM seeds s WHERE NOT EXISTS(SELECT 1 FROM my_derby.horses h WHERE h.world_id=s.world_id
   AND h.source_model_version='MY_DERBY_ASSOCIATION_STUD_V1' AND h.name=s.horse_name)
 RETURNING id,world_id,name
), themed AS (
 SELECT i.*,
  CASE i.name WHEN '닉스고' THEN 'stamina' WHEN '클래식엠파이어' THEN 'power'
   WHEN '한센' THEN 'acceleration' WHEN '위키드스트롱' THEN 'grit' ELSE 'start' END focus
 FROM inserted i
), ability AS (
 INSERT INTO my_derby.horse_abilities(horse_id,current_stats,potential_stats,gene_stats,estimation_metadata)
 SELECT t.id,
  (SELECT jsonb_object_agg(k,round(least(100,greatest(25,v::numeric*0.62)),2)) FROM jsonb_each_text(g.stats) AS e(k,v)),
  (SELECT jsonb_object_agg(k,round(least(100,greatest(45,v::numeric*0.94)),2)) FROM jsonb_each_text(g.stats) AS e(k,v)),
  g.stats,jsonb_build_object('model','ASSOCIATION_STUD_V1','dataQuality','SYNTHETIC_INSPIRED_PROFILE',
   'inspiration',t.name,'generatedRandomly',true)
 FROM themed t
 CROSS JOIN LATERAL (SELECT jsonb_build_object(
  'start',my_derby_private.seeded_roll(t.id::text||'start',70,88)+CASE WHEN t.focus='start' THEN 7 ELSE 0 END,
  'speed',my_derby_private.seeded_roll(t.id::text||'speed',70,89)+CASE WHEN t.focus='speed' THEN 7 ELSE 0 END,
  'acceleration',my_derby_private.seeded_roll(t.id::text||'acceleration',68,88)+CASE WHEN t.focus='acceleration' THEN 8 ELSE 0 END,
  'stamina',my_derby_private.seeded_roll(t.id::text||'stamina',68,88)+CASE WHEN t.focus='stamina' THEN 8 ELSE 0 END,
  'finishing',my_derby_private.seeded_roll(t.id::text||'finishing',68,88)+CASE WHEN t.focus='finishing' THEN 7 ELSE 0 END,
  'power',my_derby_private.seeded_roll(t.id::text||'power',68,88)+CASE WHEN t.focus='power' THEN 7 ELSE 0 END,
  'grit',my_derby_private.seeded_roll(t.id::text||'grit',68,88)+CASE WHEN t.focus='grit' THEN 7 ELSE 0 END,
  'stability',my_derby_private.seeded_roll(t.id::text||'stability',68,88),
  'recovery',my_derby_private.seeded_roll(t.id::text||'recovery',68,88)) stats) g
 RETURNING horse_id
)
INSERT INTO my_derby_private.horse_breeding_traits
 (horse_id,trait_code,strength,parent_source,discover_after_observations,revealed_at)
SELECT t.id,s.signature,my_derby_private.seeded_roll(t.id::text||s.signature,78,96),
 'DERIVED',1,now()
FROM themed t JOIN seeds s ON s.world_id=t.world_id AND s.horse_name=t.name
ON CONFLICT(horse_id,trait_code) DO NOTHING;

INSERT INTO my_derby_private.horse_breeding_traits
 (horse_id,trait_code,strength,parent_source,discover_after_observations)
SELECT h.id,c.trait_code,my_derby_private.seeded_roll(h.id::text||c.trait_code,38,76),
 'DERIVED',my_derby_private.seeded_roll(h.id::text||c.trait_code||'reveal',4,8)
FROM my_derby.horses h
JOIN my_derby_private.breeding_trait_catalog signature ON signature.trait_code=CASE h.name
 WHEN '닉스고' THEN 'DISTANCE_STAMINA' WHEN '클래식엠파이어' THEN 'CLASSIC_POWER'
 WHEN '한센' THEN 'EARLY_BURST' WHEN '위키드스트롱' THEN 'LATE_KICK' ELSE 'FRONT_SPEED' END
CROSS JOIN LATERAL (
 SELECT trait_code FROM my_derby_private.breeding_trait_catalog
 WHERE trait_code<>signature.trait_code ORDER BY md5(h.id::text||trait_code||'association-hidden') LIMIT 1
) c
WHERE h.source_model_version='MY_DERBY_ASSOCIATION_STUD_V1'
 AND NOT EXISTS(SELECT 1 FROM my_derby_private.horse_breeding_traits t
   WHERE t.horse_id=h.id AND t.revealed_at IS NULL)
ON CONFLICT(horse_id,trait_code) DO NOTHING;

WITH ranches AS (
 SELECT w.id world_id,o.id owner_id,o.policy->>'breedingProviderKey' provider_key,
  o.name provider_name,
  my_derby_private.seeded_roll(w.id::text||(o.policy->>'breedingProviderKey'),1,5) idx
 FROM my_derby.worlds w JOIN my_derby.npc_owners o ON o.world_id=w.id
 WHERE w.world_key='kra_roster_v1' AND o.policy->>'providerType'='NPC_RANCH'
), inserted AS (
 INSERT INTO my_derby.horses
  (world_id,npc_owner_id,name,sex,age_years,life_stage,location,health_state,
   breeding_state,breeding_retired_at,racing_retired_permanently,source_model_version)
 SELECT r.world_id,r.owner_id,
  (ARRAY['바람','은빛','청운','붉은','초원','달빛','태양','고요','새벽','천둥'])[
   my_derby_private.seeded_roll(r.provider_key||':name-a',1,10)]||
  (ARRAY['질주','왕관','질풍','명예','전설','기상','보석','비상','선봉','희망'])[
   my_derby_private.seeded_roll(r.provider_key||':name-b',1,10)],
  'MALE',4+my_derby_private.seeded_roll(r.provider_key||':age',0,9),
  'STALLION','NPC_STABLE','HEALTHY','AVAILABLE',now(),true,'MY_DERBY_RANCH_STUD_V1'
 FROM ranches r
 WHERE NOT EXISTS(SELECT 1 FROM my_derby.horses h WHERE h.world_id=r.world_id
   AND h.npc_owner_id=r.owner_id AND h.source_model_version='MY_DERBY_RANCH_STUD_V1')
 RETURNING id,world_id,npc_owner_id,name
), stats AS (
 SELECT i.*,
  (SELECT jsonb_object_agg(k,my_derby_private.seeded_roll(i.id::text||k,58,94))
   FROM unnest(ARRAY['start','speed','acceleration','stamina','finishing','power','grit','stability','recovery']) k) genes
 FROM inserted i
), abilities AS (
 INSERT INTO my_derby.horse_abilities(horse_id,current_stats,potential_stats,gene_stats,estimation_metadata)
 SELECT id,
  (SELECT jsonb_object_agg(k,round((v::numeric*0.62),2)) FROM jsonb_each_text(genes) AS e(k,v)),
  (SELECT jsonb_object_agg(k,round((v::numeric*0.94),2)) FROM jsonb_each_text(genes) AS e(k,v)),
  genes,jsonb_build_object('model','NPC_RANCH_STUD_V1','dataQuality','RANDOM_SYNTHETIC','generatedRandomly',true)
 FROM stats RETURNING horse_id
), tagged AS (
 INSERT INTO my_derby_private.horse_breeding_traits
  (horse_id,trait_code,strength,parent_source,discover_after_observations,revealed_at)
 SELECT s.id,c.trait_code,my_derby_private.seeded_roll(s.id::text||c.trait_code,62,90),
  'DERIVED',1,now()
 FROM stats s
 JOIN LATERAL (SELECT trait_code FROM my_derby_private.breeding_trait_catalog
   ORDER BY md5(s.id::text||trait_code||'ranchtrait') LIMIT 1) c ON true
 ON CONFLICT(horse_id,trait_code) DO NOTHING
 RETURNING horse_id
)
SELECT count(*) FROM tagged;

INSERT INTO my_derby_private.horse_breeding_traits
 (horse_id,trait_code,strength,parent_source,discover_after_observations)
SELECT h.id,c.trait_code,my_derby_private.seeded_roll(h.id::text||c.trait_code,35,74),
 'DERIVED',my_derby_private.seeded_roll(h.id::text||c.trait_code||'reveal',4,8)
FROM my_derby.horses h
CROSS JOIN LATERAL (
 SELECT trait_code FROM my_derby_private.breeding_trait_catalog c
 WHERE NOT EXISTS(SELECT 1 FROM my_derby_private.horse_breeding_traits t
   WHERE t.horse_id=h.id AND t.trait_code=c.trait_code)
 ORDER BY md5(h.id::text||c.trait_code||'ranch-hidden') LIMIT 1
) c
WHERE h.source_model_version='MY_DERBY_RANCH_STUD_V1'
 AND NOT EXISTS(SELECT 1 FROM my_derby_private.horse_breeding_traits existing
   WHERE existing.horse_id=h.id AND existing.revealed_at IS NULL)
ON CONFLICT(horse_id,trait_code) DO NOTHING;

-- Give existing eligible mares, player stallions, and legacy NPC stock a stable
-- hidden genetic profile derived from their own top ability and a random secondary marker.
SELECT my_derby_private.ensure_horse_breeding_genotype(a.horse_id)
FROM my_derby.horse_abilities a JOIN my_derby.horses h ON h.id=a.horse_id
WHERE h.sex IN ('MALE','FEMALE') AND h.life_stage<>'DECEASED';

CREATE OR REPLACE FUNCTION my_derby_private.breeding_genetic_summary(p_horse_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 SELECT jsonb_build_object(
  'knownTraits',coalesce((SELECT jsonb_agg(jsonb_build_object('code',c.trait_code,
    'name',c.display_name,'category',c.category,'description',c.description)
    ORDER BY c.category,c.display_name)
    FROM my_derby_private.horse_breeding_traits t
    JOIN my_derby_private.breeding_trait_catalog c USING(trait_code)
    WHERE t.horse_id=p_horse_id AND t.revealed_at IS NOT NULL),'[]'::jsonb),
  'undiscoveredCount',coalesce((SELECT count(*) FROM my_derby_private.horse_breeding_traits t
    WHERE t.horse_id=p_horse_id AND t.revealed_at IS NULL),0))
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.breeding_genetic_summary(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_horse_genetic_discovery(p_horse_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;h my_derby.horses%rowtype;observations integer:=0;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id AND world_id=w;
 IF h.id IS NULL THEN RAISE EXCEPTION 'HORSE_NOT_FOUND' USING ERRCODE='42501'; END IF;
 IF h.owner_user_id IS DISTINCT FROM u AND coalesce(h.source_model_version,'') NOT IN
   ('MY_DERBY_ASSOCIATION_STUD_V1','MY_DERBY_RANCH_STUD_V1') THEN
   RAISE EXCEPTION 'HORSE_NOT_OWNED' USING ERRCODE='42501'; END IF;
 IF h.owner_user_id=u THEN
  SELECT (SELECT count(*) FROM my_derby.training_reports tr WHERE tr.horse_id=h.id)
       +(SELECT count(*) FROM my_derby.race_results rr WHERE rr.horse_id=h.id)
       +(SELECT count(*) FROM my_derby.ranch_course_requests cr WHERE cr.horse_id=h.id AND cr.status='DONE')
  INTO observations;
  UPDATE my_derby_private.horse_breeding_traits t SET revealed_at=now()
  WHERE t.horse_id=h.id AND t.revealed_at IS NULL
    AND t.discover_after_observations<=observations;
 END IF;
 RETURN jsonb_build_object('horseId',h.id,'observations',observations,
  'knownTraits',coalesce((SELECT jsonb_agg(jsonb_build_object('code',c.trait_code,
    'name',c.display_name,'category',c.category,'description',c.description,
    'inheritedFrom',t.parent_source) ORDER BY c.category,c.display_name)
    FROM my_derby_private.horse_breeding_traits t
    JOIN my_derby_private.breeding_trait_catalog c USING(trait_code)
    WHERE t.horse_id=h.id AND t.revealed_at IS NOT NULL),'[]'::jsonb),
  'undiscoveredCount',coalesce((SELECT count(*) FROM my_derby_private.horse_breeding_traits t
    WHERE t.horse_id=h.id AND t.revealed_at IS NULL),0),
  'nextDiscoveryAt',(SELECT min(t.discover_after_observations) FROM my_derby_private.horse_breeding_traits t
    WHERE t.horse_id=h.id AND t.revealed_at IS NULL));
END;
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_horse_genetic_discovery(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_horse_genetic_discovery(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_breeding_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid(); w uuid; c jsonb; v_mares jsonb;v_sires jsonb;v_requests jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 c:=my_derby.world_clock(w);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',h.id,'name',h.name,'sex',h.sex,'age',h.age_years,'stage',h.life_stage,
  'breedingState',h.breeding_state,'retired',h.breeding_retired_at IS NOT NULL,
  'health',h.health_state,'condition',h.condition_score,'sourceMeet',h.source_meet,
  'genetics',my_derby_private.breeding_genetic_summary(h.id),
  'canMate',h.sex='FEMALE' AND h.age_years BETWEEN 4 AND 18 AND h.life_stage='BROODMARE'
   AND h.breeding_state IN ('AVAILABLE','COOLDOWN')
   AND NOT EXISTS(SELECT 1 FROM my_derby.pregnancies p WHERE p.mare_id=h.id AND p.status='PREGNANT')
   AND NOT EXISTS(SELECT 1 FROM my_derby.breeding_requests br
    WHERE br.mare_id=h.id AND br.season_number=(c->>'season')::int)
 ) ORDER BY h.name),'[]'::jsonb) INTO v_mares
 FROM my_derby.horses h WHERE h.world_id=w AND h.owner_user_id=u;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',h.id,'name',h.name,'age',h.age_years,
  'ownerType',CASE WHEN h.owner_user_id=u THEN 'MY_STALLION'
   WHEN h.source_model_version='MY_DERBY_ASSOCIATION_STUD_V1' THEN 'ASSOCIATION'
   ELSE 'NPC_RANCH' END,
  'providerName',CASE WHEN h.owner_user_id=u THEN NULL ELSE o.name END,
  'genetics',my_derby_private.breeding_genetic_summary(h.id),
  'booked',(SELECT count(*) FROM my_derby.breeding_requests br
    WHERE br.sire_id=h.id AND br.season_number=(c->>'season')::int)
 ) ORDER BY CASE WHEN h.source_model_version='MY_DERBY_ASSOCIATION_STUD_V1' THEN 0 ELSE 1 END,h.name),'[]'::jsonb)
 INTO v_sires FROM my_derby.horses h LEFT JOIN my_derby.npc_owners o ON o.id=h.npc_owner_id
 WHERE h.world_id=w AND h.sex='MALE' AND h.age_years BETWEEN 4 AND 25
  AND h.life_stage='STALLION' AND h.breeding_retired_at IS NOT NULL
  AND h.health_state='HEALTHY' AND h.sale_state='NOT_LISTED'
  AND (h.owner_user_id=u OR h.source_model_version IN
   ('MY_DERBY_ASSOCIATION_STUD_V1','MY_DERBY_RANCH_STUD_V1'));
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',br.id,'mareId',br.mare_id,'mareName',m.name,'sireId',br.sire_id,'sireName',s.name,
  'season',br.season_number,'status',br.status,'createdAt',br.created_at,
  'compatibility',br.compatibility_score,'knownInbreeding',br.inbreeding_coefficient,
  'chance',br.conception_chance,'decisionDetail',br.decision_detail,'conceivedGameDay',br.conception_game_day,
  'pregnancy',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('id',p.id,'status',p.status,
   'dueGameDay',p.due_game_day,'conceivedGameDay',p.conceived_game_day,
   'daysRemaining',greatest(0,p.due_game_day-((c->>'gameDayStart')::int+6)),'foalId',p.foal_id) END
 ) ORDER BY br.created_at DESC),'[]'::jsonb) INTO v_requests
 FROM my_derby.breeding_requests br JOIN my_derby.horses m ON m.id=br.mare_id
 JOIN my_derby.horses s ON s.id=br.sire_id LEFT JOIN my_derby.pregnancies p ON p.breeding_request_id=br.id
 WHERE br.owner_user_id=u AND m.world_id=w;
 RETURN jsonb_build_object('world',c,'mares',v_mares,'sires',v_sires,'requests',v_requests,
  'gestationGameDays',330,'seasonGameDays',364,'sireSeasonLimit',40);
END;
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_breeding_dashboard() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_breeding_dashboard() TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_breeding_pair_preview(p_mare_id uuid,p_sire_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;mare my_derby.horses%rowtype;sire my_derby.horses%rowtype;
 a jsonb;c jsonb;traits jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 SELECT * INTO mare FROM my_derby.horses WHERE id=p_mare_id;
 SELECT * INTO sire FROM my_derby.horses WHERE id=p_sire_id;
 IF mare.id IS NULL OR mare.world_id IS DISTINCT FROM w OR mare.owner_user_id IS DISTINCT FROM u
  THEN RAISE EXCEPTION 'MARE_NOT_OWNED' USING ERRCODE='42501';END IF;
 IF mare.sex<>'FEMALE' THEN RAISE EXCEPTION 'MARE_NOT_ELIGIBLE';END IF;
 IF sire.id IS NULL OR sire.world_id IS DISTINCT FROM w OR
  (sire.owner_user_id IS DISTINCT FROM u AND coalesce(sire.source_model_version,'') NOT IN
   ('MY_DERBY_ASSOCIATION_STUD_V1','MY_DERBY_RANCH_STUD_V1')) OR
   sire.sex<>'MALE' OR sire.life_stage<>'STALLION' THEN RAISE EXCEPTION 'SIRE_NOT_AVAILABLE';END IF;
 a:=my_derby.breeding_pair_assessment(mare.id,sire.id);c:=my_derby.world_clock(w);
 SELECT coalesce(jsonb_agg(jsonb_build_object('code',x.trait_code,'name',x.display_name,
  'category',x.category,'description',x.description,
  'inheritanceChance',CASE WHEN x.parents=2 THEN 57.8 ELSE 35.0 END,
  'knownFrom',x.parent_names) ORDER BY x.category,x.display_name),'[]'::jsonb)
 INTO traits FROM (
  SELECT t.trait_code,c.display_name,c.category,c.description,count(DISTINCT h.id) parents,
   jsonb_agg(DISTINCT h.name) parent_names
  FROM my_derby_private.horse_breeding_traits t
  JOIN my_derby_private.breeding_trait_catalog c USING(trait_code)
  JOIN my_derby.horses h ON h.id=t.horse_id
  WHERE h.id IN (mare.id,sire.id) AND t.revealed_at IS NOT NULL
  GROUP BY t.trait_code,c.display_name,c.category,c.description
 ) x;
 RETURN a||jsonb_build_object('mareName',mare.name,'sireName',sire.name,
  'mareEligible',mare.age_years BETWEEN 4 AND 18 AND mare.life_stage='BROODMARE'
   AND mare.breeding_state IN ('AVAILABLE','COOLDOWN')
   AND NOT EXISTS(SELECT 1 FROM my_derby.breeding_requests br WHERE br.mare_id=mare.id AND br.season_number=(c->>'season')::int)
   AND NOT EXISTS(SELECT 1 FROM my_derby.pregnancies p WHERE p.mare_id=mare.id AND p.status='PREGNANT'),
  'possibleInheritedTraits',traits,'warning','특성은 확률로 유전되며 근친 평가는 혈통 자료가 불완전할 수 있습니다.');
END;
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_breeding_pair_preview(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_breeding_pair_preview(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_apply_breeding(p_mare_id uuid,p_sire_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();mare my_derby.horses%rowtype;sire my_derby.horses%rowtype;
 w uuid;c jsonb;v_season int;v_day int;assessment jsonb;v_request uuid;v_preg uuid;
 roll numeric;pregnant boolean;v_due int;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST';END IF;
 c:=my_derby.world_clock(w);IF c->>'status'<>'ACTIVE' THEN RAISE EXCEPTION 'WORLD_NOT_ACTIVE';END IF;
 v_season:=(c->>'season')::int;v_day:=(c->>'gameDayStart')::int;
 IF p_mare_id=p_sire_id THEN RAISE EXCEPTION 'BREEDING_PAIR_INVALID';END IF;
 PERFORM 1 FROM my_derby.horses h WHERE h.id IN(p_mare_id,p_sire_id) ORDER BY h.id FOR UPDATE;
 SELECT * INTO mare FROM my_derby.horses WHERE id=p_mare_id;
 SELECT * INTO sire FROM my_derby.horses WHERE id=p_sire_id;
 IF mare.id IS NULL OR mare.world_id IS DISTINCT FROM w OR mare.owner_user_id IS DISTINCT FROM u
  THEN RAISE EXCEPTION 'MARE_NOT_OWNED' USING ERRCODE='42501';END IF;
 IF sire.id IS NULL OR sire.world_id IS DISTINCT FROM w OR
  (sire.owner_user_id IS DISTINCT FROM u AND coalesce(sire.source_model_version,'') NOT IN
   ('MY_DERBY_ASSOCIATION_STUD_V1','MY_DERBY_RANCH_STUD_V1'))
  THEN RAISE EXCEPTION 'SIRE_NOT_AVAILABLE' USING ERRCODE='42501';END IF;
 IF mare.sex<>'FEMALE' OR mare.age_years NOT BETWEEN 4 AND 18 OR mare.life_stage<>'BROODMARE'
  OR mare.breeding_retired_at IS NULL OR NOT mare.racing_retired_permanently
  OR mare.health_state<>'HEALTHY' OR mare.sale_state<>'NOT_LISTED'
  OR mare.breeding_state NOT IN('AVAILABLE','COOLDOWN') THEN RAISE EXCEPTION 'MARE_NOT_ELIGIBLE';END IF;
 IF sire.sex<>'MALE' OR sire.age_years NOT BETWEEN 4 AND 25 OR sire.life_stage<>'STALLION'
  OR sire.breeding_retired_at IS NULL OR NOT sire.racing_retired_permanently
  OR sire.health_state<>'HEALTHY' OR sire.sale_state<>'NOT_LISTED' THEN RAISE EXCEPTION 'SIRE_NOT_ELIGIBLE';END IF;
 IF EXISTS(SELECT 1 FROM my_derby.pregnancies p WHERE p.mare_id=mare.id AND p.status='PREGNANT')
  THEN RAISE EXCEPTION 'MARE_ALREADY_PREGNANT';END IF;
 IF EXISTS(SELECT 1 FROM my_derby.breeding_requests br WHERE br.mare_id=mare.id AND br.season_number=v_season)
  THEN RAISE EXCEPTION 'MARE_SEASON_LIMIT';END IF;
 IF (SELECT count(*) FROM my_derby.breeding_requests WHERE sire_id=sire.id AND season_number=v_season)>=40
  THEN RAISE EXCEPTION 'SIRE_SEASON_LIMIT';END IF;
 assessment:=my_derby.breeding_pair_assessment(mare.id,sire.id);
 roll:=((('x'||substring(md5(mare.id::text||sire.id::text||v_season::text),1,8))::bit(32)::bigint%10000)::numeric/100);
 pregnant:=roll<(assessment->>'chance')::numeric;
 INSERT INTO my_derby.breeding_requests(owner_user_id,mare_id,sire_id,season_number,
  inbreeding_coefficient,compatibility_score,status,conception_game_day,conception_chance,decision_detail)
 VALUES(u,mare.id,sire.id,v_season,(assessment->>'knownInbreeding')::numeric,
  (assessment->>'compatibility')::numeric,CASE WHEN pregnant THEN 'APPROVED' ELSE 'REJECTED' END,
  v_day,(assessment->>'chance')::numeric,jsonb_build_object('pregnant',pregnant,
   'pedigreeIncomplete',assessment->'pedigreeIncomplete','system','BREEDING_GENETICS_V1','feeStatus','NOT_CHARGED'))
 RETURNING id INTO v_request;
 IF pregnant THEN
  v_due:=v_day+330;
  INSERT INTO my_derby.pregnancies(breeding_request_id,mare_id,conceived_game_day,due_game_day,status)
  VALUES(v_request,mare.id,v_day,v_due,'PREGNANT') RETURNING id INTO v_preg;
 END IF;
 UPDATE my_derby.horses SET breeding_state=CASE WHEN pregnant THEN 'PREGNANT' ELSE 'COOLDOWN' END WHERE id=mare.id;
 INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
 VALUES(u,'BREEDING',CASE WHEN pregnant THEN '임신 성공' ELSE '임신 실패' END,
  mare.name||' · '||sire.name||CASE WHEN pregnant THEN ' 임신이 확인되었습니다.' ELSE ' 이번 시즌 교배에서는 임신하지 못했습니다.' END,
  jsonb_build_object('requestId',v_request,'mareId',mare.id,'pregnant',pregnant));
 RETURN jsonb_build_object('status',CASE WHEN pregnant THEN 'PREGNANT' ELSE 'NOT_CONCEIVED' END,
  'requestId',v_request,'pregnancyId',v_preg,'dueGameDay',v_due,'chance',assessment->'chance',
  'compatibility',assessment->'compatibility','knownInbreeding',assessment->'knownInbreeding',
  'pedigreeIncomplete',assessment->'pedigreeIncomplete','feeStatus','NOT_CHARGED');
END;
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_apply_breeding(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_apply_breeding(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
