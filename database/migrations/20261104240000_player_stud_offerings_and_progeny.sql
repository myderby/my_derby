-- Player-listed stallions, offspring-based stud fees, and public progeny records.
CREATE TABLE IF NOT EXISTS my_derby_private.breeding_stud_offerings (
  horse_id uuid PRIMARY KEY REFERENCES my_derby.horses(id) ON DELETE CASCADE,
  owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  listed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_breeding_stud_offerings_owner
  ON my_derby_private.breeding_stud_offerings(owner_user_id,listed_at DESC);
CREATE INDEX IF NOT EXISTS ix_horses_father_id ON my_derby.horses(father_id) WHERE father_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_horses_mother_id ON my_derby.horses(mother_id) WHERE mother_id IS NOT NULL;
ALTER TABLE my_derby_private.breeding_stud_offerings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby_private.breeding_stud_offerings FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.stud_fee_quote(p_sire_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 WITH progeny AS (
  SELECT child.id
  FROM my_derby.horses child
  WHERE child.father_id=p_sire_id
 ), results AS (
  SELECT rr.finishing_rank,r.is_stakes
  FROM progeny p
  JOIN my_derby.race_results rr ON rr.horse_id=p.id
  JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
  JOIN my_derby.races r ON r.id=run.race_id AND r.status='FINISHED'
 ), totals AS (
  SELECT count(*) FILTER(WHERE finishing_rank=1) wins,
   count(*) FILTER(WHERE finishing_rank=2) seconds,
   count(*) FILTER(WHERE finishing_rank=3) thirds,
   count(*) FILTER(WHERE is_stakes AND finishing_rank=1) stakes_wins,
   count(*) FILTER(WHERE is_stakes AND finishing_rank BETWEEN 1 AND 3) stakes_placings,
   count(*) starts
  FROM results
 )
 SELECT jsonb_build_object(
  'offspringCount',(SELECT count(*) FROM progeny),
  'starts',starts,'wins',wins,'seconds',seconds,'thirds',thirds,
  'stakesWins',stakes_wins,'stakesPlacings',stakes_placings,
  'feeG',least(200000,10000+wins*10000+seconds*5000+thirds*2000
   +stakes_wins*50000+greatest(0,stakes_placings-stakes_wins)*10000)
 ) FROM totals
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.stud_fee_quote(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_manage_stud_offer(p_horse_id uuid,p_listed boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;h my_derby.horses%rowtype;quote jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id FOR UPDATE;
 IF h.id IS NULL OR h.world_id IS DISTINCT FROM w OR h.owner_user_id IS DISTINCT FROM u
  THEN RAISE EXCEPTION 'HORSE_NOT_OWNED' USING ERRCODE='42501';END IF;
 IF h.sex<>'MALE' OR h.age_years NOT BETWEEN 4 AND 25 OR h.life_stage<>'STALLION'
  OR h.breeding_retired_at IS NULL OR NOT h.racing_retired_permanently
  OR h.health_state<>'HEALTHY' OR h.sale_state<>'NOT_LISTED'
  THEN RAISE EXCEPTION 'SIRE_NOT_ELIGIBLE';END IF;
 IF p_listed THEN
  INSERT INTO my_derby_private.breeding_stud_offerings(horse_id,owner_user_id)
   VALUES(h.id,u) ON CONFLICT(horse_id) DO UPDATE SET owner_user_id=excluded.owner_user_id,listed_at=now();
 ELSE
  DELETE FROM my_derby_private.breeding_stud_offerings WHERE horse_id=h.id AND owner_user_id=u;
 END IF;
 quote:=my_derby_private.stud_fee_quote(h.id);
 RETURN jsonb_build_object('status',CASE WHEN p_listed THEN 'LISTED' ELSE 'UNLISTED' END,
  'horseId',h.id,'feeG',quote->'feeG');
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_manage_stud_offer(uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_manage_stud_offer(uuid,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_breeding_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;c jsonb;v_mares jsonb;v_sires jsonb;v_my_studs jsonb;v_requests jsonb;
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
  'id',h.id,'name',h.name,'age',h.age_years,'ownerType','PLAYER_STALLION',
  'providerName','플레이어 마주 공개','feeG',my_derby_private.stud_fee_quote(h.id)->'feeG',
  'progenyRecord',my_derby_private.stud_fee_quote(h.id),
  'genetics',my_derby_private.breeding_genetic_summary(h.id),
  'booked',(SELECT count(*) FROM my_derby.breeding_requests br
    WHERE br.sire_id=h.id AND br.season_number=(c->>'season')::int),
  'listedByMe',o.owner_user_id=u
 ) ORDER BY h.name),'[]'::jsonb) INTO v_sires
 FROM my_derby_private.breeding_stud_offerings o
 JOIN my_derby.horses h ON h.id=o.horse_id
 WHERE h.world_id=w AND h.sex='MALE' AND h.age_years BETWEEN 4 AND 25
  AND h.life_stage='STALLION' AND h.breeding_retired_at IS NOT NULL
  AND h.racing_retired_permanently AND h.health_state='HEALTHY' AND h.sale_state='NOT_LISTED'
  AND h.owner_user_id IS NOT NULL;

 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',h.id,'name',h.name,'age',h.age_years,'listed',o.horse_id IS NOT NULL,
  'feeG',my_derby_private.stud_fee_quote(h.id)->'feeG',
  'starts',(my_derby_private.stud_fee_quote(h.id)->>'starts')::int,
  'wins',(my_derby_private.stud_fee_quote(h.id)->>'wins')::int
 ) ORDER BY h.name),'[]'::jsonb) INTO v_my_studs
 FROM my_derby.horses h LEFT JOIN my_derby_private.breeding_stud_offerings o
  ON o.horse_id=h.id AND o.owner_user_id=u
 WHERE h.world_id=w AND h.owner_user_id=u AND h.sex='MALE' AND h.age_years BETWEEN 4 AND 25
  AND h.life_stage='STALLION' AND h.breeding_retired_at IS NOT NULL
  AND h.racing_retired_permanently AND h.health_state='HEALTHY' AND h.sale_state='NOT_LISTED';

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
 RETURN jsonb_build_object('world',c,'mares',v_mares,'sires',v_sires,
  'myStuds',v_my_studs,'requests',v_requests,'gestationGameDays',330,
  'seasonGameDays',364,'sireSeasonLimit',40);
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_breeding_dashboard() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_breeding_dashboard() TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_breeding_pair_preview(p_mare_id uuid,p_sire_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;mare my_derby.horses%rowtype;sire my_derby.horses%rowtype;
 a jsonb;c jsonb;traits jsonb;fee jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 SELECT * INTO mare FROM my_derby.horses WHERE id=p_mare_id;
 SELECT * INTO sire FROM my_derby.horses WHERE id=p_sire_id;
 IF mare.id IS NULL OR mare.world_id IS DISTINCT FROM w OR mare.owner_user_id IS DISTINCT FROM u
  THEN RAISE EXCEPTION 'MARE_NOT_OWNED' USING ERRCODE='42501';END IF;
 IF mare.sex<>'FEMALE' THEN RAISE EXCEPTION 'MARE_NOT_ELIGIBLE';END IF;
 IF sire.id IS NULL OR sire.world_id IS DISTINCT FROM w OR sire.owner_user_id IS NULL OR
  NOT EXISTS(SELECT 1 FROM my_derby_private.breeding_stud_offerings o
   WHERE o.horse_id=sire.id AND o.owner_user_id=sire.owner_user_id) OR
  sire.sex<>'MALE' OR sire.life_stage<>'STALLION' OR sire.breeding_retired_at IS NULL OR
  NOT sire.racing_retired_permanently OR sire.health_state<>'HEALTHY' OR sire.sale_state<>'NOT_LISTED'
  THEN RAISE EXCEPTION 'SIRE_NOT_AVAILABLE';END IF;
 a:=my_derby.breeding_pair_assessment(mare.id,sire.id);c:=my_derby.world_clock(w);
 fee:=my_derby_private.stud_fee_quote(sire.id);
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
  'studFeeG',CASE WHEN sire.owner_user_id=u THEN 0 ELSE (fee->>'feeG')::bigint END,
  'studFeeRecord',fee,'possibleInheritedTraits',traits,
  'warning','씨수말은 마주가 공개한 경우에만 신청할 수 있습니다. 교배료는 자마의 실제 성적에 따라 정해집니다.');
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_breeding_pair_preview(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_breeding_pair_preview(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_apply_breeding(p_mare_id uuid,p_sire_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();mare my_derby.horses%rowtype;sire my_derby.horses%rowtype;
 w uuid;c jsonb;v_season int;v_day int;assessment jsonb;v_request uuid;v_preg uuid;
 roll numeric;pregnant boolean;v_due int;fee jsonb;fee_amount bigint;debit jsonb;credit jsonb;
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
 IF sire.id IS NULL OR sire.world_id IS DISTINCT FROM w OR sire.owner_user_id IS NULL OR
  NOT EXISTS(SELECT 1 FROM my_derby_private.breeding_stud_offerings o
   WHERE o.horse_id=sire.id AND o.owner_user_id=sire.owner_user_id)
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
 fee:=my_derby_private.stud_fee_quote(sire.id);
 fee_amount:=CASE WHEN sire.owner_user_id=u THEN 0 ELSE (fee->>'feeG')::bigint END;
 roll:=((('x'||substring(md5(mare.id::text||sire.id::text||v_season::text),1,8))::bit(32)::bigint%10000)::numeric/100);
 pregnant:=roll<(assessment->>'chance')::numeric;
 INSERT INTO my_derby.breeding_requests(owner_user_id,mare_id,sire_id,season_number,
  inbreeding_coefficient,compatibility_score,status,conception_game_day,conception_chance,decision_detail)
 VALUES(u,mare.id,sire.id,v_season,(assessment->>'knownInbreeding')::numeric,
  (assessment->>'compatibility')::numeric,CASE WHEN pregnant THEN 'APPROVED' ELSE 'REJECTED' END,
  v_day,(assessment->>'chance')::numeric,jsonb_build_object('pregnant',pregnant,
   'pedigreeIncomplete',assessment->'pedigreeIncomplete','system','BREEDING_OFFERS_V1',
   'feeStatus',CASE WHEN fee_amount>0 THEN 'PAID' ELSE 'NO_CHARGE' END,'studFeeG',fee_amount,
   'studFeeRecord',fee)) RETURNING id INTO v_request;
 IF fee_amount>0 THEN
  PERFORM 1 FROM my_derby.profiles WHERE user_id IN(u,sire.owner_user_id) ORDER BY user_id FOR UPDATE;
  debit:=my_derby_private.wallet_mutate(u,w,v_day,-fee_amount,'BREEDING_FEE','BREEDING_REQUEST',v_request);
  credit:=my_derby_private.wallet_mutate(sire.owner_user_id,w,v_day,fee_amount,
   'STUD_FEE_INCOME','BREEDING_REQUEST',v_request);
 END IF;
 IF pregnant THEN
  v_due:=v_day+330;
  INSERT INTO my_derby.pregnancies(breeding_request_id,mare_id,conceived_game_day,due_game_day,status)
  VALUES(v_request,mare.id,v_day,v_due,'PREGNANT') RETURNING id INTO v_preg;
 END IF;
 UPDATE my_derby.horses SET breeding_state=CASE WHEN pregnant THEN 'PREGNANT' ELSE 'COOLDOWN' END WHERE id=mare.id;
 INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
 VALUES(u,'BREEDING',CASE WHEN pregnant THEN '임신 성공' ELSE '임신 실패' END,
  mare.name||' · '||sire.name||CASE WHEN pregnant THEN ' 임신이 확인되었습니다.' ELSE ' 이번 시즌 교배에서는 임신하지 못했습니다.' END,
  jsonb_build_object('requestId',v_request,'mareId',mare.id,'pregnant',pregnant,'studFeeG',fee_amount));
 IF fee_amount>0 THEN
  INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
  VALUES(sire.owner_user_id,'BREEDING','씨수말 교배료 수입',sire.name||' 교배료 '||fee_amount||'G를 받았습니다.',
   jsonb_build_object('requestId',v_request,'sireId',sire.id,'feeG',fee_amount));
 END IF;
 RETURN jsonb_build_object('status',CASE WHEN pregnant THEN 'PREGNANT' ELSE 'NOT_CONCEIVED' END,
  'requestId',v_request,'pregnancyId',v_preg,'dueGameDay',v_due,'chance',assessment->'chance',
  'compatibility',assessment->'compatibility','knownInbreeding',assessment->'knownInbreeding',
  'pedigreeIncomplete',assessment->'pedigreeIncomplete','studFeeG',fee_amount,
  'feeStatus',CASE WHEN fee_amount>0 THEN 'PAID' ELSE 'NO_CHARGE' END);
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_apply_breeding(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_apply_breeding(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.world_horse_offspring_profile(
 p_horse_id uuid,p_page integer DEFAULT 1,p_page_size integer DEFAULT 20
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE parent my_derby.horses%rowtype;v_page int:=coalesce(p_page,1);v_size int:=coalesce(p_page_size,20);
 v_count int;v_summary jsonb;v_grade jsonb;v_distance jsonb;v_stakes jsonb;v_items jsonb;
BEGIN
 IF p_horse_id IS NULL OR v_page NOT BETWEEN 1 AND 10000 OR v_size NOT BETWEEN 1 AND 50
  THEN RAISE EXCEPTION 'OFFSPRING_FILTER_INVALID';END IF;
 SELECT * INTO parent FROM my_derby.horses WHERE id=p_horse_id;
 IF parent.id IS NULL OR parent.sex NOT IN ('MALE','FEMALE')
  THEN RETURN jsonb_build_object('status','NOT_AVAILABLE');END IF;
 DROP TABLE IF EXISTS pg_temp._offspring_base;
 CREATE TEMP TABLE pg_temp._offspring_base ON COMMIT DROP AS
 SELECT h.id,h.name,h.sex,h.life_stage,h.health_state,h.domestic_rating,
  coalesce(h.rating_derived_grade,h.source_grade_no) current_grade,
  CASE WHEN h.sex='MALE' AND h.life_stage='STALLION' THEN '씨수말' WHEN h.sex='FEMALE' AND h.life_stage='BROODMARE'
   THEN '씨암말' WHEN h.life_stage='RACING' AND h.health_state<>'HEALTHY' THEN '휴양마'
   WHEN h.life_stage='RACING' THEN '경주마' WHEN h.life_stage='RETIRED' THEN '은퇴마'
   ELSE h.life_stage END current_status,
  (SELECT count(*) FROM my_derby.race_results rr JOIN my_derby.race_runs ru
    ON ru.id=rr.race_run_id AND ru.status='FINISHED'
    WHERE rr.horse_id=h.id) starts,
  (SELECT count(*) FROM my_derby.race_results rr JOIN my_derby.race_runs ru
    ON ru.id=rr.race_run_id AND ru.status='FINISHED'
    WHERE rr.horse_id=h.id AND rr.finishing_rank=1) wins,
  (SELECT count(*) FROM my_derby.race_results rr JOIN my_derby.race_runs ru
    ON ru.id=rr.race_run_id AND ru.status='FINISHED'
    WHERE rr.horse_id=h.id AND rr.finishing_rank=2) seconds,
  (SELECT count(*) FROM my_derby.race_results rr JOIN my_derby.race_runs ru
    ON ru.id=rr.race_run_id AND ru.status='FINISHED'
    WHERE rr.horse_id=h.id AND rr.finishing_rank=3) thirds
 FROM my_derby.horses h
 WHERE CASE parent.sex WHEN 'MALE' THEN h.father_id=parent.id ELSE h.mother_id=parent.id END;
 SELECT count(*) INTO v_count FROM pg_temp._offspring_base;
 SELECT jsonb_build_object('offspring',v_count,'starts',coalesce(sum(starts),0),
  'wins',coalesce(sum(wins),0),'second',coalesce(sum(seconds),0),'third',coalesce(sum(thirds),0))
 INTO v_summary FROM pg_temp._offspring_base;
 WITH rows AS (
  SELECT rr.finishing_rank,coalesce((r.prize_policy->>'grade_no')::int,child.current_grade) grade_no
  FROM pg_temp._offspring_base child
  JOIN my_derby.race_results rr ON rr.horse_id=child.id
  JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
  JOIN my_derby.races r ON r.id=run.race_id AND r.status='FINISHED'
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('grade',grade_no,'starts',starts,'wins',wins,
  'second',seconds,'third',thirds) ORDER BY grade_no),'[]'::jsonb) INTO v_grade
 FROM (SELECT grade_no,count(*) starts,count(*) FILTER(WHERE finishing_rank=1) wins,
  count(*) FILTER(WHERE finishing_rank=2) seconds,count(*) FILTER(WHERE finishing_rank=3) thirds
  FROM rows WHERE grade_no IS NOT NULL GROUP BY grade_no) g;
 WITH rows AS (
  SELECT r.distance_m,rr.finishing_rank FROM pg_temp._offspring_base child
  JOIN my_derby.race_results rr ON rr.horse_id=child.id
  JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
  JOIN my_derby.races r ON r.id=run.race_id AND r.status='FINISHED'
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('distanceM',distance_m,'starts',starts,
  'wins',wins,'second',seconds,'third',thirds) ORDER BY distance_m),'[]'::jsonb) INTO v_distance
 FROM (SELECT distance_m,count(*) starts,count(*) FILTER(WHERE finishing_rank=1) wins,
  count(*) FILTER(WHERE finishing_rank=2) seconds,count(*) FILTER(WHERE finishing_rank=3) thirds
  FROM rows GROUP BY distance_m) d;
 WITH rows AS (
  SELECT r.competition_name,rr.finishing_rank FROM pg_temp._offspring_base child
  JOIN my_derby.race_results rr ON rr.horse_id=child.id
  JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
  JOIN my_derby.races r ON r.id=run.race_id AND r.status='FINISHED'
  WHERE r.is_stakes
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('name',competition_name,'starts',starts,
  'wins',wins,'second',seconds,'third',thirds) ORDER BY starts DESC,competition_name),'[]'::jsonb)
 INTO v_stakes FROM (SELECT competition_name,count(*) starts,
  count(*) FILTER(WHERE finishing_rank=1) wins,
  count(*) FILTER(WHERE finishing_rank=2) seconds,
  count(*) FILTER(WHERE finishing_rank=3) thirds FROM rows GROUP BY competition_name) s;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'sex',sex,
  'status',current_status,'starts',starts,'first',wins,'second',seconds,'third',thirds,
  'retirementRating',CASE WHEN life_stage IN ('RETIRED','STALLION','BROODMARE') THEN domestic_rating ELSE NULL END,
  'retirementGrade',CASE WHEN life_stage IN ('RETIRED','STALLION','BROODMARE') THEN current_grade ELSE NULL END,
  'rating',domestic_rating,'grade',current_grade) ORDER BY name,id),'[]'::jsonb) INTO v_items
 FROM (SELECT * FROM pg_temp._offspring_base ORDER BY name,id LIMIT v_size OFFSET(v_page-1)*v_size) p;
 RETURN jsonb_build_object('status','OK','parent',jsonb_build_object('id',parent.id,
  'name',parent.name,'sex',parent.sex,'rating',parent.domestic_rating,
  'grade',coalesce(parent.rating_derived_grade,parent.source_grade_no),
  'status',CASE WHEN parent.sex='MALE' AND parent.life_stage='STALLION' THEN '씨수마'
   WHEN parent.sex='FEMALE' AND parent.life_stage='BROODMARE' THEN '씨암말'
   WHEN parent.life_stage='RACING' AND parent.health_state<>'HEALTHY' THEN '휴양마'
   WHEN parent.life_stage='RACING' THEN '경주마' ELSE parent.life_stage END),
  'summary',v_summary,'byGrade',v_grade,'byDistance',v_distance,'stakes',v_stakes,
  'offspring',v_items,'page',v_page,'pageSize',v_size,'total',v_count,
  'totalPages',greatest(1,ceil(v_count::numeric/v_size)::int));
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.world_horse_offspring_profile(uuid,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.world_horse_offspring_profile(uuid,integer,integer) TO anon,authenticated;

NOTIFY pgrst,'reload schema';
