-- Player may withdraw an open official race application.
-- Preserve race field size by restoring a qualified NPC horse, then refund
-- only a fee actually paid for the original entry.
CREATE OR REPLACE FUNCTION my_derby.player_withdraw_race_entry(
 p_race_id uuid,p_horse_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();w uuid;r my_derby.races%rowtype;
 e my_derby.race_entries%rowtype; replacement my_derby.horses%rowtype;
 v_preferred uuid;v_strategy jsonb;v_paid bigint;v_ref uuid;v_refund bigint:=0;
 v_stat jsonb;v_kst timestamp:=now() AT TIME ZONE 'Asia/Seoul';
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 SELECT * INTO r FROM my_derby.races WHERE id=p_race_id AND world_id=w FOR UPDATE;
 IF NOT FOUND OR r.status<>'OPEN' THEN RAISE EXCEPTION 'RACE_NOT_OPEN';END IF;
 IF (r.prize_policy->>'kst_date')::date<v_kst::date OR
  ((r.prize_policy->>'kst_date')::date=v_kst::date
   AND v_kst::time>=coalesce(r.entry_deadline,r.start_time-interval '10 minutes'))
 THEN RAISE EXCEPTION 'ENTRY_DEADLINE_PASSED';END IF;
 SELECT * INTO e FROM my_derby.race_entries
 WHERE race_id=r.id AND horse_id=p_horse_id AND owner_user_id=u
   AND status='CONFIRMED' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'OWN_CONFIRMED_ENTRY_REQUIRED' USING ERRCODE='42501';END IF;
 v_preferred:=nullif(e.snapshot->>'originalNpcHorseId','')::uuid;
 SELECT * INTO replacement FROM my_derby.horses candidate
 WHERE candidate.world_id=w AND candidate.npc_owner_id IS NOT NULL
  AND candidate.id=v_preferred
  AND candidate.source_meet=r.prize_policy->>'source_meet'
  AND candidate.source_grade_no=(r.prize_policy->>'grade_no')::smallint
  AND candidate.life_stage='RACING' AND candidate.health_state='HEALTHY'
  AND candidate.sale_state='NOT_LISTED' AND candidate.age_years BETWEEN 2 AND 10
  AND NOT candidate.racing_retired_permanently AND candidate.breeding_retired_at IS NULL
  AND candidate.fatigue<80 AND candidate.condition_score>=50
  AND NOT EXISTS(SELECT 1 FROM my_derby.race_entries taken
    JOIN my_derby.races taken_r ON taken_r.id=taken.race_id
    WHERE taken.horse_id=candidate.id AND taken_r.race_day=r.race_day
    AND taken_r.status<>'CANCELLED'
    AND taken.status IN('APPLIED','CONFIRMED','COMPLETED'))
 FOR UPDATE OF candidate SKIP LOCKED;
 IF replacement.id IS NULL THEN
  SELECT candidate.* INTO replacement FROM my_derby.horses candidate
  WHERE candidate.world_id=w AND candidate.npc_owner_id IS NOT NULL
   AND candidate.source_meet=r.prize_policy->>'source_meet'
   AND candidate.source_grade_no=(r.prize_policy->>'grade_no')::smallint
   AND candidate.life_stage='RACING' AND candidate.health_state='HEALTHY'
   AND candidate.sale_state='NOT_LISTED' AND candidate.age_years BETWEEN 2 AND 10
   AND NOT candidate.racing_retired_permanently AND candidate.breeding_retired_at IS NULL
   AND candidate.fatigue<80 AND candidate.condition_score>=50
   AND NOT EXISTS(SELECT 1 FROM my_derby.race_entries taken
    JOIN my_derby.races taken_r ON taken_r.id=taken.race_id
    WHERE taken.horse_id=candidate.id AND taken_r.race_day=r.race_day
    AND taken_r.status<>'CANCELLED'
    AND taken.status IN('APPLIED','CONFIRMED','COMPLETED'))
  ORDER BY candidate.condition_score DESC,md5(candidate.id::text||r.id::text)
  LIMIT 1 FOR UPDATE OF candidate SKIP LOCKED;
 END IF;
 IF replacement.id IS NULL THEN RAISE EXCEPTION 'NPC_REPLACEMENT_UNAVAILABLE';END IF;
 SELECT current_stats INTO v_stat FROM my_derby.horse_abilities
  WHERE horse_id=replacement.id;
 IF v_stat IS NULL THEN RAISE EXCEPTION 'NPC_REPLACEMENT_MISSING_ABILITIES';END IF;
 v_strategy:=CASE WHEN coalesce((v_stat->>'start')::numeric,0)>
    coalesce((v_stat->>'finishing')::numeric,0) THEN
    '["FRONT","PRESS","SAVE"]'::jsonb ELSE '["SAVE","MOVE","CLOSER"]'::jsonb END;
 -- Remove user-specific strategy rows before reusing the official entry slot.
 DELETE FROM my_derby.race_strategies WHERE race_entry_id=e.id;
 UPDATE my_derby.jockey_applications SET status='WITHDRAWN'
  WHERE race_id=r.id AND horse_id=p_horse_id AND owner_user_id=u
    AND status IN('PENDING','ACCEPTED','AUTO_ASSIGNED');
 UPDATE my_derby.race_entries SET horse_id=replacement.id,owner_user_id=NULL,
  snapshot=jsonb_build_object('entry_source','NPC_AUTOFILL_DUSU_V1',
   'strategies',v_strategy,'autoAssignedJockey',true,
   'playerWithdrewHorseId',p_horse_id,'trainerReadiness',75),
  status='CONFIRMED',weight_kg=54
 WHERE id=e.id;
 UPDATE my_derby.horses SET race_entry_state='NONE'
 WHERE id=p_horse_id;
 v_ref:=md5(p_race_id::text||':'||p_horse_id::text)::uuid;
 SELECT -t.change_amount INTO v_paid
 FROM my_derby.wallet_transactions t
 WHERE t.owner_user_id=u AND t.reference_type='RACE_ENTRY'
  AND t.transaction_type='RACE_ENTRY_FEE' AND t.reference_id=v_ref
  AND t.change_amount<0
 LIMIT 1;
 IF v_paid>0 THEN
  PERFORM my_derby_private.wallet_mutate(u,w,r.race_day,
   v_paid,'RACE_ENTRY_REFUND','RACE_ENTRY',v_ref);
  v_refund:=v_paid;
 END IF;
 PERFORM my_derby_private.recalculate_official_handicap_race(r.id);
 RETURN jsonb_build_object('status','WITHDRAWN','horseId',p_horse_id,
  'replacementHorseId',replacement.id,'refund',v_refund,
  'raceId',r.id,'capacityPreserved',true);
END $fn$;
REVOKE ALL ON FUNCTION my_derby.player_withdraw_race_entry(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_withdraw_race_entry(uuid,uuid)
 TO authenticated;
