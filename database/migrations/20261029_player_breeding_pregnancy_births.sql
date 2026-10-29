
-- My Derby breeding application -> deterministic pregnancy -> game-day birth.
-- The 8 dedicated system studs are synthetic game NPCs, never historic KRA race horses.
ALTER TABLE my_derby.breeding_requests
 ADD COLUMN IF NOT EXISTS conception_game_day integer,
 ADD COLUMN IF NOT EXISTS conception_chance numeric,
 ADD COLUMN IF NOT EXISTS decision_detail jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE my_derby.pregnancies
 ADD COLUMN IF NOT EXISTS conceived_game_day integer,
 ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Direct SQL writes by authenticated users are prohibited; use validated RPC only.
DROP POLICY IF EXISTS own_breeding_insert ON my_derby.breeding_requests;
REVOKE INSERT, UPDATE, DELETE ON my_derby.breeding_requests FROM anon,authenticated;
REVOKE INSERT, UPDATE, DELETE ON my_derby.pregnancies FROM anon,authenticated;

-- Foundation breeding stallions: separate from official runners and the reserved player-starter pool.
WITH studs AS (
 SELECT gs.i,
  (ARRAY['황금의제왕','블루메테오','챔피언로드','스톰마스터',
         '실버드래곤','윈드포스','레전드킹','오로라스타'])[gs.i] AS horse_name
 FROM generate_series(1,8) gs(i)
),
existing AS (
 SELECT w.id world_id,
  (SELECT o.id FROM my_derby.npc_owners o WHERE o.world_id=w.id ORDER BY o.id LIMIT 1) owner_id
 FROM my_derby.worlds w WHERE w.world_key='kra_roster_v1'
),
new_studs AS (
 INSERT INTO my_derby.horses
 (world_id,npc_owner_id,name,sex,age_years,life_stage,location,health_state,
  breeding_state,breeding_retired_at,racing_retired_permanently,source_model_version)
 SELECT e.world_id,e.owner_id,'시스템 씨수말 · '||s.horse_name,
  'MALE',4+((s.i+2)%6),'STALLION','NPC_STABLE','HEALTHY',
  'AVAILABLE',now(),true,'MY_DERBY_SYSTEM_STUD_V1'
 FROM studs s CROSS JOIN existing e
 WHERE e.owner_id IS NOT NULL
  AND NOT EXISTS (
   SELECT 1 FROM my_derby.horses h
   WHERE h.world_id=e.world_id AND h.name='시스템 씨수말 · '||s.horse_name
  )
 RETURNING id,name
)
INSERT INTO my_derby.horse_abilities
 (horse_id,current_stats,potential_stats,gene_stats,estimation_metadata)
SELECT h.id,
 jsonb_build_object('start',65+q.n%18,'speed',62+(q.n*3)%22,
  'acceleration',64+(q.n*7)%21,'stamina',63+(q.n*11)%20,
  'finishing',64+(q.n*13)%21,'power',61+(q.n*17)%22,
  'grit',65+(q.n*19)%20,'stability',63+(q.n*23)%22,
  'recovery',65+(q.n*29)%18),
 jsonb_build_object('start',75+q.n%15,'speed',76+(q.n*3)%15,
  'acceleration',74+(q.n*7)%17,'stamina',75+(q.n*11)%16,
  'finishing',74+(q.n*13)%17,'power',74+(q.n*17)%17,
  'grit',76+(q.n*19)%15,'stability',75+(q.n*23)%16,
  'recovery',75+(q.n*29)%17),
 jsonb_build_object('start',72+q.n%18,'speed',73+(q.n*3)%18,
  'acceleration',72+(q.n*7)%19,'stamina',72+(q.n*11)%19,
  'finishing',73+(q.n*13)%18,'power',71+(q.n*17)%19,
  'grit',72+(q.n*19)%19,'stability',73+(q.n*23)%18,
  'recovery',72+(q.n*29)%19),
 jsonb_build_object('model','SYSTEM_STUD_V1','dataQuality','SYNTHETIC_FOUNDATION')
FROM new_studs h
CROSS JOIN LATERAL (SELECT coalesce(nullif(substring(md5(h.id::text),1,2),''),'a1') code) a
CROSS JOIN LATERAL (SELECT (('x'||a.code)::bit(8)::int) n) q;

-- 3-generation pedigree risk estimation, limited to KNOWN family IDs.
-- Missing pedigree is unknown, never proof of no inbreeding.
CREATE OR REPLACE FUNCTION my_derby.breeding_pair_assessment(p_mare uuid,p_sire uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE m my_derby.horses%rowtype; s my_derby.horses%rowtype;
 gene_m jsonb;gene_s jsonb; k text;
 diff numeric:=0; n int:=0; comp numeric; inbreed numeric:=0;
 common_count int:=0; unknown boolean;
BEGIN
 SELECT * INTO m FROM my_derby.horses WHERE id=p_mare;
 SELECT * INTO s FROM my_derby.horses WHERE id=p_sire;
 IF NOT FOUND OR m.id IS NULL OR s.id IS NULL OR m.world_id<>s.world_id
 THEN RAISE EXCEPTION 'BREEDING_PAIR_NOT_FOUND'; END IF;
 IF m.id=s.id THEN RAISE EXCEPTION 'CLOSE_INBREEDING_PROHIBITED'; END IF;

 WITH RECURSIVE am(id,depth) AS (
   SELECT m.id,0
   UNION ALL SELECT parent.id,am.depth+1 FROM am
     JOIN my_derby.horses h ON h.id=am.id
     JOIN LATERAL (VALUES(h.father_id),(h.mother_id)) p(id) ON p.id IS NOT NULL
     JOIN my_derby.horses parent ON parent.id=p.id
     WHERE am.depth<3
 ), asire(id,depth) AS (
   SELECT s.id,0
   UNION ALL SELECT parent.id,asire.depth+1 FROM asire
     JOIN my_derby.horses h ON h.id=asire.id
     JOIN LATERAL (VALUES(h.father_id),(h.mother_id)) p(id) ON p.id IS NOT NULL
     JOIN my_derby.horses parent ON parent.id=p.id
     WHERE asire.depth<3
 ), links AS (
   SELECT am.id, min(am.depth) dm, min(asire.depth) ds
   FROM am JOIN asire USING(id)
   GROUP BY am.id
 )
 SELECT count(*),coalesce(sum(power(0.5::numeric,dm+ds+1)),0)
 INTO common_count,inbreed FROM links;
 IF common_count>0 AND
  EXISTS(WITH RECURSIVE ma(id,depth) AS(
   SELECT m.id,0 UNION ALL
   SELECT u.id,ma.depth+1 FROM ma JOIN my_derby.horses mh ON mh.id=ma.id
   JOIN LATERAL (VALUES(mh.father_id),(mh.mother_id)) u(id) ON u.id IS NOT NULL
   WHERE ma.depth<2
  ), sa(id,depth) AS(
   SELECT s.id,0 UNION ALL
   SELECT u.id,sa.depth+1 FROM sa JOIN my_derby.horses sh ON sh.id=sa.id
   JOIN LATERAL (VALUES(sh.father_id),(sh.mother_id)) u(id) ON u.id IS NOT NULL
   WHERE sa.depth<2
  ) SELECT 1 FROM ma JOIN sa USING(id))
 THEN RAISE EXCEPTION 'CLOSE_INBREEDING_PROHIBITED'; END IF;

 SELECT CASE WHEN a.gene_stats<>'{}'::jsonb THEN a.gene_stats ELSE a.potential_stats END
 INTO gene_m FROM my_derby.horse_abilities a WHERE a.horse_id=m.id;
 SELECT CASE WHEN a.gene_stats<>'{}'::jsonb THEN a.gene_stats ELSE a.potential_stats END
 INTO gene_s FROM my_derby.horse_abilities a WHERE a.horse_id=s.id;
 FOREACH k IN ARRAY ARRAY['start','speed','acceleration','stamina','finishing',
                            'power','grit','stability','recovery'] LOOP
  diff:=diff+abs(coalesce((gene_m->>k)::numeric,65)-coalesce((gene_s->>k)::numeric,65));
  n:=n+1;
 END LOOP;
 comp:=round(least(95,greatest(30,87-diff/n*0.8-inbreed*90)),1);
 unknown:=m.father_id IS NULL OR m.mother_id IS NULL
  OR s.father_id IS NULL OR s.mother_id IS NULL;
 RETURN jsonb_build_object('compatibility',comp,
   'knownInbreeding',round(inbreed,4),'pedigreeIncomplete',unknown,
   'chance',round(least(95,greatest(45,60+comp*0.32-inbreed*80)),1));
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_breeding_dashboard()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid(); w uuid; c jsonb; v_mares jsonb;v_sires jsonb;v_requests jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles
 WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 c:=my_derby.world_clock(w);

 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'id',h.id,'name',h.name,'sex',h.sex,'age',h.age_years,'stage',h.life_stage,
   'breedingState',h.breeding_state,'retired',h.breeding_retired_at IS NOT NULL,
   'health',h.health_state,'condition',h.condition_score,'sourceMeet',h.source_meet,
   'canMate',h.sex='FEMALE' AND h.age_years BETWEEN 4 AND 18
       AND h.life_stage='BROODMARE' AND h.breeding_state IN ('AVAILABLE','COOLDOWN')
       AND NOT EXISTS(SELECT 1 FROM my_derby.pregnancies p
           WHERE p.mare_id=h.id AND p.status='PREGNANT')
       AND NOT EXISTS(SELECT 1 FROM my_derby.breeding_requests br
           WHERE br.mare_id=h.id AND br.season_number=(c->>'season')::int)
 ) ORDER BY h.name),'[]'::jsonb) INTO v_mares
 FROM my_derby.horses h WHERE h.world_id=w AND h.owner_user_id=u;

 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'id',h.id,'name',h.name,'age',h.age_years,'ownerType',
     CASE WHEN h.owner_user_id=u THEN 'MY_STALLION' ELSE 'SYSTEM_NPC' END,
   'geneSummary',jsonb_build_object('speed',coalesce(a.gene_stats->>'speed',a.potential_stats->>'speed'),
      'stamina',coalesce(a.gene_stats->>'stamina',a.potential_stats->>'stamina'),
      'finishing',coalesce(a.gene_stats->>'finishing',a.potential_stats->>'finishing')),
   'booked',(select count(*) FROM my_derby.breeding_requests br
     WHERE br.sire_id=h.id AND br.season_number=(c->>'season')::int)
 ) ORDER BY h.name),'[]'::jsonb) INTO v_sires
 FROM my_derby.horses h
 LEFT JOIN my_derby.horse_abilities a ON a.horse_id=h.id
 WHERE h.world_id=w AND h.sex='MALE' AND h.age_years BETWEEN 4 AND 25
   AND h.life_stage='STALLION' AND h.breeding_retired_at IS NOT NULL
   AND h.health_state='HEALTHY' AND h.sale_state='NOT_LISTED'
   AND (h.owner_user_id=u OR h.source_model_version='MY_DERBY_SYSTEM_STUD_V1');

 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'id',br.id,'mareId',br.mare_id,'mareName',m.name,
   'sireId',br.sire_id,'sireName',s.name,'season',br.season_number,
   'status',br.status,'createdAt',br.created_at,
   'compatibility',br.compatibility_score,
   'knownInbreeding',br.inbreeding_coefficient,
   'chance',br.conception_chance,'decisionDetail',br.decision_detail,
   'conceivedGameDay',br.conception_game_day,
   'pregnancy',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object(
    'id',p.id,'status',p.status,'dueGameDay',p.due_game_day,
    'conceivedGameDay',p.conceived_game_day,
    'daysRemaining',greatest(0,p.due_game_day-((c->>'gameDayStart')::int+6)),
    'foalId',p.foal_id) END
 ) ORDER BY br.created_at DESC),'[]'::jsonb)
 INTO v_requests
 FROM my_derby.breeding_requests br
 JOIN my_derby.horses m ON m.id=br.mare_id
 JOIN my_derby.horses s ON s.id=br.sire_id
 LEFT JOIN my_derby.pregnancies p ON p.breeding_request_id=br.id
 WHERE br.owner_user_id=u AND m.world_id=w;

 RETURN jsonb_build_object('world',c,'mares',v_mares,'sires',v_sires,
   'requests',v_requests,'gestationGameDays',330,
   'seasonGameDays',364,'sireSeasonLimit',40);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_apply_breeding(p_mare_id uuid,p_sire_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid(); mare my_derby.horses%rowtype;sire my_derby.horses%rowtype;
 w uuid; c jsonb; v_season int; v_day int; assessment jsonb; v_request uuid; v_preg uuid;
 roll numeric; pregnant boolean; v_due int;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 c:=my_derby.world_clock(w);
 IF c->>'status'<>'ACTIVE' THEN RAISE EXCEPTION 'WORLD_NOT_ACTIVE';END IF;
 v_season:=(c->>'season')::int;v_day:=(c->>'gameDayStart')::int;
 IF p_mare_id=p_sire_id THEN RAISE EXCEPTION 'BREEDING_PAIR_INVALID';END IF;
 -- Consistent lock order prevents deadlocks when a user owns both parents.
 PERFORM 1 FROM my_derby.horses h WHERE h.id IN (p_mare_id,p_sire_id) ORDER BY h.id FOR UPDATE;
 SELECT * INTO mare FROM my_derby.horses WHERE id=p_mare_id;
 SELECT * INTO sire FROM my_derby.horses WHERE id=p_sire_id;
 IF mare.id IS NULL OR mare.world_id IS DISTINCT FROM w
   OR mare.owner_user_id IS DISTINCT FROM u THEN
   RAISE EXCEPTION 'MARE_NOT_OWNED' USING ERRCODE='42501';END IF;
 IF sire.id IS NULL OR sire.world_id IS DISTINCT FROM w OR
   (sire.owner_user_id IS DISTINCT FROM u AND
     sire.source_model_version IS DISTINCT FROM 'MY_DERBY_SYSTEM_STUD_V1') THEN
   RAISE EXCEPTION 'SIRE_NOT_AVAILABLE' USING ERRCODE='42501';END IF;
 IF mare.sex<>'FEMALE' OR mare.age_years NOT BETWEEN 4 AND 18
   OR mare.life_stage<>'BROODMARE' OR mare.breeding_retired_at IS NULL
   OR mare.racing_retired_permanently=false OR mare.health_state<>'HEALTHY'
   OR mare.sale_state<>'NOT_LISTED'
   OR mare.breeding_state NOT IN ('AVAILABLE','COOLDOWN') THEN
   RAISE EXCEPTION 'MARE_NOT_ELIGIBLE';END IF;
 IF sire.sex<>'MALE' OR sire.age_years NOT BETWEEN 4 AND 25
   OR sire.life_stage<>'STALLION' OR sire.breeding_retired_at IS NULL
   OR sire.racing_retired_permanently=false OR sire.health_state<>'HEALTHY'
   OR sire.sale_state<>'NOT_LISTED' THEN
   RAISE EXCEPTION 'SIRE_NOT_ELIGIBLE';END IF;
 IF EXISTS(SELECT 1 FROM my_derby.pregnancies p WHERE p.mare_id=mare.id AND p.status='PREGNANT')
  THEN RAISE EXCEPTION 'MARE_ALREADY_PREGNANT';END IF;
 IF EXISTS(SELECT 1 FROM my_derby.breeding_requests br
  WHERE br.mare_id=mare.id AND br.season_number=v_season) THEN
  RAISE EXCEPTION 'MARE_SEASON_LIMIT';END IF;
 IF (SELECT count(*) FROM my_derby.breeding_requests
      WHERE sire_id=sire.id AND season_number=v_season)>=40
 THEN RAISE EXCEPTION 'SIRE_SEASON_LIMIT';END IF;
 assessment:=my_derby.breeding_pair_assessment(mare.id,sire.id);
 -- Deterministic but unpredictable to the player; repeat requests cannot reroll.
 roll:=((('x'||substring(md5(mare.id::text||sire.id::text||v_season::text),1,8))
   ::bit(32)::bigint % 10000)::numeric/100);
 pregnant:=roll<(assessment->>'chance')::numeric;
 INSERT INTO my_derby.breeding_requests
 (owner_user_id,mare_id,sire_id,season_number,inbreeding_coefficient,
  compatibility_score,status,conception_game_day,conception_chance,decision_detail)
 VALUES(u,mare.id,sire.id,v_season,
  (assessment->>'knownInbreeding')::numeric,(assessment->>'compatibility')::numeric,
  CASE WHEN pregnant THEN 'APPROVED' ELSE 'REJECTED' END,
  v_day,(assessment->>'chance')::numeric,
  jsonb_build_object('pregnant',pregnant,'pedigreeIncomplete',
   assessment->'pedigreeIncomplete','system','BREEDING_V1','feeStatus','NOT_CHARGED'))
 RETURNING id INTO v_request;
 IF pregnant THEN
  v_due:=v_day+330;
  INSERT INTO my_derby.pregnancies
   (breeding_request_id,mare_id,conceived_game_day,due_game_day,status)
  VALUES(v_request,mare.id,v_day,v_due,'PREGNANT') RETURNING id INTO v_preg;
 END IF;
 UPDATE my_derby.horses
 SET breeding_state=CASE WHEN pregnant THEN 'PREGNANT' ELSE 'COOLDOWN' END
 WHERE id=mare.id;
 INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
 VALUES(u,'BREEDING',CASE WHEN pregnant THEN '임신 성공' ELSE '임신 실패' END,
  mare.name||' · '||sire.name||CASE WHEN pregnant THEN ' 임신이 확인되었습니다.'
  ELSE ' 이번 시즌 교배에서는 임신하지 못했습니다.' END,
  jsonb_build_object('requestId',v_request,'mareId',mare.id,'pregnant',pregnant));
 RETURN jsonb_build_object('status',CASE WHEN pregnant THEN 'PREGNANT' ELSE 'NOT_CONCEIVED' END,
   'requestId',v_request,'pregnancyId',v_preg,'dueGameDay',v_due,
   'chance',assessment->'chance','compatibility',assessment->'compatibility',
   'knownInbreeding',assessment->'knownInbreeding',
   'pedigreeIncomplete',assessment->'pedigreeIncomplete',
   'feeStatus','NOT_CHARGED');
END $fn$;

-- Automatic delivery each real morning. Creates an actual foal with father/mother
-- and estimated genotype, but never creates a racing eligible horse.
CREATE OR REPLACE FUNCTION my_derby_private.process_due_breeding_births()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_p record; v_m my_derby.horses%rowtype;v_s my_derby.horses%rowtype;
 v_foal uuid; v_gene jsonb:='{}'::jsonb;v_current jsonb:='{}'::jsonb;
 v_potential jsonb:='{}'::jsonb;v_gm jsonb;v_gs jsonb;k text;
 v_g numeric; v_now_day int; v_n int:=0;v_foals jsonb:='[]'::jsonb;
BEGIN
 FOR v_p IN
 SELECT pr.id preg_id,pr.mare_id,pr.due_game_day,br.sire_id,br.owner_user_id,
   br.id request_id,m.world_id,w.status world_status
 FROM my_derby.pregnancies pr
 JOIN my_derby.breeding_requests br ON br.id=pr.breeding_request_id
 JOIN my_derby.horses m ON m.id=pr.mare_id
 JOIN my_derby.worlds w ON w.id=m.world_id
 WHERE pr.status='PREGNANT' AND w.status='ACTIVE'
   AND pr.due_game_day<=((my_derby.world_clock(w.id)->>'gameDayStart')::int+6)
 ORDER BY pr.due_game_day,pr.id
 FOR UPDATE OF pr SKIP LOCKED
 LOOP
  SELECT * INTO v_m FROM my_derby.horses WHERE id=v_p.mare_id FOR UPDATE;
  SELECT * INTO v_s FROM my_derby.horses WHERE id=v_p.sire_id;
  IF v_m.id IS NULL OR v_s.id IS NULL OR v_m.owner_user_id IS DISTINCT FROM v_p.owner_user_id
  THEN CONTINUE;END IF;
  SELECT CASE WHEN gene_stats<>'{}'::jsonb THEN gene_stats ELSE potential_stats END
  INTO v_gm FROM my_derby.horse_abilities WHERE horse_id=v_m.id;
  SELECT CASE WHEN gene_stats<>'{}'::jsonb THEN gene_stats ELSE potential_stats END
  INTO v_gs FROM my_derby.horse_abilities WHERE horse_id=v_s.id;
  v_gene:='{}'::jsonb;v_current:='{}'::jsonb;v_potential:='{}'::jsonb;
  FOREACH k IN ARRAY ARRAY['start','speed','acceleration','stamina',
     'finishing','power','grit','stability','recovery'] LOOP
   v_g:=round(least(100,greatest(10,
     coalesce((v_gm->>k)::numeric,65)*0.45+
     coalesce((v_gs->>k)::numeric,65)*0.45+
     (50+((('x'||substring(md5(v_p.preg_id::text||k),1,8))::bit(32)::bigint%5100)::numeric/100))*0.10
   )),2);
   v_gene:=jsonb_set(v_gene,ARRAY[k],to_jsonb(v_g),true);
   v_potential:=jsonb_set(v_potential,ARRAY[k],
     to_jsonb(round(least(100,greatest(20,v_g*0.94)),2)),true);
   v_current:=jsonb_set(v_current,ARRAY[k],
     to_jsonb(round(least(40,greatest(12,v_g*0.35)),2)),true);
  END LOOP;
  INSERT INTO my_derby.horses
   (world_id,owner_user_id,name,sex,age_years,father_id,mother_id,life_stage,
    location,health_state,race_entry_state,breeding_state,condition_score,
    fatigue,source_model_version)
  VALUES(v_m.world_id,v_m.owner_user_id,'새별-'||upper(substring(v_p.preg_id::text,1,6)),
   CASE WHEN (('x'||substring(md5(v_p.preg_id::text),1,2))::bit(8)::int%2)=0 THEN 'MALE'
    ELSE 'FEMALE' END,
   0,v_s.id,v_m.id,'FOAL','OWNER_RANCH','HEALTHY','NONE','AVAILABLE',85,0,
   'MY_DERBY_BREEDING_V1')
  RETURNING id INTO v_foal;
  INSERT INTO my_derby.horse_abilities
   (horse_id,current_stats,potential_stats,gene_stats,estimation_metadata)
  VALUES(v_foal,v_current,v_potential,v_gene,
    jsonb_build_object('model','BREEDING_V1','genetics','ESTIMATED',
     'geneFormula','45% dam + 45% sire + 10% mutation',
     'birthGameDay',v_p.due_game_day));
  UPDATE my_derby.pregnancies SET status='BORN',foal_id=v_foal,updated_at=now()
   WHERE id=v_p.preg_id AND status='PREGNANT';
  UPDATE my_derby.breeding_requests SET status='COMPLETED'
   WHERE id=v_p.request_id;
  UPDATE my_derby.horses SET breeding_state='COOLDOWN' WHERE id=v_m.id;
  INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
  VALUES(v_m.owner_user_id,'BREEDING','망아지 탄생',
    v_m.name||'의 망아지가 태어났습니다.',
    jsonb_build_object('mareId',v_m.id,'sireId',v_s.id,'foalId',v_foal));
  v_n:=v_n+1;
  v_foals:=v_foals||jsonb_build_array(jsonb_build_object('foalId',v_foal,'mareId',v_m.id));
 END LOOP;
 RETURN jsonb_build_object('status','OK','births',v_n,'foals',v_foals);
END $fn$;

REVOKE ALL ON FUNCTION my_derby.breeding_pair_assessment(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_breeding_dashboard() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_apply_breeding(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_due_breeding_births() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_breeding_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_apply_breeding(uuid,uuid) TO authenticated;

SELECT cron.schedule('my-derby-breeding-births','15 0 * * *',
  'select my_derby_private.process_due_breeding_births();');
