-- Raise each listed stallion's seasonal cap to 200. From the 151st request,
-- an association/ranch board reviews expected bloodline value and can deny it.
CREATE OR REPLACE FUNCTION my_derby_private.review_breeding_pair(
 p_mare_id uuid,p_sire_id uuid,p_season integer
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE mare my_derby.horses%rowtype;sire my_derby.horses%rowtype;assess jsonb;fee jsonb;
 v_booked integer;v_shared integer;v_rating numeric;v_score numeric;v_reviewer text;
 v_reviewer_type text;v_pick integer;
BEGIN
 SELECT * INTO mare FROM my_derby.horses WHERE id=p_mare_id;
 SELECT * INTO sire FROM my_derby.horses WHERE id=p_sire_id;
 IF mare.id IS NULL OR sire.id IS NULL THEN RAISE EXCEPTION 'BREEDING_PAIR_NOT_FOUND';END IF;
 assess:=my_derby.breeding_pair_assessment(mare.id,sire.id);
 fee:=my_derby_private.stud_fee_quote(sire.id);
 SELECT count(*) INTO v_booked FROM my_derby.breeding_requests
  WHERE sire_id=sire.id AND season_number=p_season;
 SELECT count(*) INTO v_shared
 FROM my_derby_private.horse_breeding_traits m
 JOIN my_derby_private.horse_breeding_traits s USING(trait_code)
 WHERE m.horse_id=mare.id AND s.horse_id=sire.id
  AND m.revealed_at IS NOT NULL AND s.revealed_at IS NOT NULL;
 v_rating:=coalesce((SELECT avg(coalesce(domestic_rating,60)) FROM my_derby.horses
  WHERE id IN(mare.id,sire.id)),60);
 v_score:=round(least(100,greatest(0,
   (assess->>'compatibility')::numeric
   - (assess->>'knownInbreeding')::numeric*100
   + least(12,v_shared*3)
   + least(15,greatest(0,((fee->>'feeG')::numeric-10000)/10000))
   + least(8,greatest(0,(v_rating-60)/5))
 )),1);
 v_pick:=my_derby_private.seeded_roll(mare.id::text||sire.id::text||p_season::text,0,5);
 SELECT o.name,o.policy->>'providerType' INTO v_reviewer,v_reviewer_type
 FROM my_derby.npc_owners o
 WHERE o.world_id=mare.world_id
  AND ((v_pick=0 AND o.policy->>'providerType'='ASSOCIATION') OR
       (v_pick BETWEEN 1 AND 5 AND o.policy->>'breedingProviderKey'='RANCH_STUD_'||v_pick::text))
 LIMIT 1;
 v_reviewer:=coalesce(v_reviewer,CASE WHEN v_pick=0 THEN '한국경마협회' ELSE 'NPC 목장 심사위원회' END);
 v_reviewer_type:=coalesce(v_reviewer_type,CASE WHEN v_pick=0 THEN 'ASSOCIATION' ELSE 'NPC_RANCH' END);
 RETURN jsonb_build_object('required',v_booked>=150,'demandBeforeRequest',v_booked,
  'reviewer',v_reviewer,'reviewerType',v_reviewer_type,'expectationScore',v_score,
  'approvalThreshold',60,'decision',CASE WHEN v_score>=60 THEN 'APPROVED' ELSE 'DENIED' END,
  'rationale',CASE WHEN v_score>=60 THEN '혈통 궁합과 자마 기대 성적 기준을 충족했습니다.'
   ELSE '혈통 궁합 또는 자마 기대 성적이 심사 기준에 미달합니다.' END,
  'basis',jsonb_build_object('compatibility',assess->'compatibility',
   'knownInbreeding',assess->'knownInbreeding','sharedKnownTraits',v_shared,
   'sireOffspringRecord',fee,'averageParentRating',round(v_rating,1)));
END
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.review_breeding_pair(uuid,uuid,integer) FROM PUBLIC,anon,authenticated;

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
  'offspringCount',(my_derby_private.stud_fee_quote(h.id)->>'offspringCount')::int,
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
  'seasonGameDays',364,'sireSeasonLimit',200,'demandReviewThreshold',150);
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_breeding_dashboard() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_breeding_dashboard() TO authenticated;

CREATE OR REPLACE FUNCTION my_derby.player_breeding_pair_preview(p_mare_id uuid,p_sire_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;mare my_derby.horses%rowtype;sire my_derby.horses%rowtype;
 a jsonb;c jsonb;traits jsonb;fee jsonb;review jsonb;v_booked integer;
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
 SELECT count(*) INTO v_booked FROM my_derby.breeding_requests br
 WHERE br.sire_id=sire.id AND br.season_number=(c->>'season')::int;
 IF v_booked>=150 THEN
  review:=my_derby_private.review_breeding_pair(mare.id,sire.id,(c->>'season')::int);
 END IF;
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
  'studFeeRecord',fee,'boardReviewRequired',v_booked>=150,'boardReview',review,
  'possibleInheritedTraits',traits,
  'warning','씨수말은 마주가 공개한 경우에만 신청할 수 있으며, 신청이 몰리면 협회·NPC 목장이 혈통 기대치를 심사합니다.');
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
 v_booked int;review jsonb;review_denied boolean:=false;
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
 SELECT count(*) INTO v_booked FROM my_derby.breeding_requests br
 WHERE br.sire_id=sire.id AND br.season_number=v_season;
 IF v_booked>=200 THEN RAISE EXCEPTION 'SIRE_SEASON_LIMIT';END IF;

 assessment:=my_derby.breeding_pair_assessment(mare.id,sire.id);
 fee:=my_derby_private.stud_fee_quote(sire.id);
 IF v_booked>=150 THEN
  review:=my_derby_private.review_breeding_pair(mare.id,sire.id,v_season);
  review_denied:=review->>'decision'='DENIED';
 END IF;
 fee_amount:=CASE WHEN review_denied OR sire.owner_user_id=u THEN 0 ELSE (fee->>'feeG')::bigint END;
 roll:=((('x'||substring(md5(mare.id::text||sire.id::text||v_season::text),1,8))::bit(32)::bigint%10000)::numeric/100);
 pregnant:=NOT review_denied AND roll<(assessment->>'chance')::numeric;
 INSERT INTO my_derby.breeding_requests(owner_user_id,mare_id,sire_id,season_number,
  inbreeding_coefficient,compatibility_score,status,conception_game_day,conception_chance,decision_detail)
 VALUES(u,mare.id,sire.id,v_season,(assessment->>'knownInbreeding')::numeric,
  (assessment->>'compatibility')::numeric,CASE WHEN pregnant THEN 'APPROVED' ELSE 'REJECTED' END,
  v_day,(assessment->>'chance')::numeric,jsonb_build_object('pregnant',pregnant,
   'pedigreeIncomplete',assessment->'pedigreeIncomplete','system','BREEDING_REVIEW_V1',
   'approvalState',CASE WHEN review_denied THEN 'DENIED' ELSE 'APPROVED' END,
   'review',review,'feeStatus',CASE WHEN fee_amount>0 THEN 'PAID' ELSE 'NO_CHARGE' END,
   'studFeeG',fee_amount,'studFeeRecord',fee)) RETURNING id INTO v_request;
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
 UPDATE my_derby.horses SET breeding_state='COOLDOWN' WHERE id=mare.id;
 IF pregnant THEN UPDATE my_derby.horses SET breeding_state='PREGNANT' WHERE id=mare.id;END IF;
 INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
 VALUES(u,'BREEDING',CASE WHEN review_denied THEN '교배 심사 불허'
   WHEN pregnant THEN '임신 성공' ELSE '임신 실패' END,
  CASE WHEN review_denied THEN mare.name||' × '||sire.name||' 신청이 '||coalesce(review->>'reviewer','심사위원회')||'에서 불허되었습니다.'
   ELSE mare.name||' · '||sire.name||CASE WHEN pregnant THEN ' 임신이 확인되었습니다.' ELSE ' 이번 시즌 교배에서는 임신하지 못했습니다.' END END,
  jsonb_build_object('requestId',v_request,'mareId',mare.id,'pregnant',pregnant,
   'approvalState',CASE WHEN review_denied THEN 'DENIED' ELSE 'APPROVED' END,
   'review',review,'studFeeG',fee_amount));
 IF fee_amount>0 THEN
  INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
  VALUES(sire.owner_user_id,'BREEDING','씨수말 교배료 수입',sire.name||' 교배료 '||fee_amount||'G를 받았습니다.',
   jsonb_build_object('requestId',v_request,'sireId',sire.id,'feeG',fee_amount));
 END IF;
 RETURN jsonb_build_object('status',CASE WHEN review_denied THEN 'BREEDING_DENIED'
   WHEN pregnant THEN 'PREGNANT' ELSE 'NOT_CONCEIVED' END,
  'requestId',v_request,'pregnancyId',v_preg,'dueGameDay',v_due,'chance',assessment->'chance',
  'compatibility',assessment->'compatibility','knownInbreeding',assessment->'knownInbreeding',
  'pedigreeIncomplete',assessment->'pedigreeIncomplete','studFeeG',fee_amount,
  'review',review,'feeStatus',CASE WHEN fee_amount>0 THEN 'PAID' ELSE 'NO_CHARGE' END);
END
$fn$;
REVOKE ALL ON FUNCTION my_derby.player_apply_breeding(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_apply_breeding(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
