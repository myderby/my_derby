CREATE OR REPLACE FUNCTION my_derby_private.apply_official_race_aftercare(p_race_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 race my_derby.races%rowtype; v_pool bigint; v_prize bigint;
 run_id uuid; entry record; v_gain numeric; v_drop numeric; v_balance bigint;
 v_processed int:=0; v_total bigint:=0; v_players bigint:=0; v_rank int; v_count int;
BEGIN
 SELECT * INTO race FROM my_derby.races WHERE id=p_race_id FOR UPDATE;
 IF NOT FOUND OR race.status<>'FINISHED'
 THEN RETURN jsonb_build_object('status','NOT_FINALIZED'); END IF;
 IF EXISTS (SELECT 1 FROM my_derby.race_postprocess_state WHERE race_id=p_race_id)
 THEN RETURN jsonb_build_object('status','ALREADY_SETTLED','raceId',p_race_id); END IF;
 SELECT id INTO run_id FROM my_derby.race_runs
 WHERE race_id=p_race_id AND status='FINISHED'
 ORDER BY result_applied_at DESC LIMIT 1;
 IF run_id IS NULL THEN RAISE EXCEPTION 'OFFICIAL_RACE_RUN_MISSING'; END IF;
 v_pool:=my_derby_private.economy_grade_pool(coalesce((race.prize_policy->>'grade_no')::int,0));
 IF v_pool<=0 THEN RAISE EXCEPTION 'UNSUPPORTED_RACE_PRIZE_GRADE'; END IF;
 SELECT count(*) INTO v_count FROM my_derby.race_results WHERE race_run_id=run_id;
 IF v_count<2 THEN RAISE EXCEPTION 'OFFICIAL_RESULTS_NOT_READY';END IF;
 FOR entry IN
  SELECT rr.id result_id,rr.horse_id,rr.finishing_rank, h.owner_user_id,h.name,
    h.fatigue,h.condition_score,h.health_state
  FROM my_derby.race_results rr JOIN my_derby.horses h ON h.id=rr.horse_id
  WHERE rr.race_run_id=run_id ORDER BY rr.finishing_rank,rr.id
 LOOP
  v_rank:=entry.finishing_rank;
  v_prize:=CASE v_rank WHEN 1 THEN v_pool*50/100 WHEN 2 THEN v_pool*25/100
    WHEN 3 THEN v_pool*15/100 WHEN 4 THEN v_pool*7/100
    WHEN 5 THEN v_pool*3/100 ELSE 0 END;
  -- Use rank/field normalisation; no artificial injury is recorded here.
  v_gain:=round(least(20,8+8*((v_rank-1)::numeric/greatest(v_count-1,1))),1);
  v_drop:=round(least(8,2+4*((v_rank-1)::numeric/greatest(v_count-1,1))),1);
  UPDATE my_derby.race_results SET prize_amount=v_prize,
   change_snapshot=change_snapshot||jsonb_build_object('prize_settlement','ECONOMY_V2_SETTLED',
    'fatigue_change',least(100,entry.fatigue+v_gain)-entry.fatigue,
    'condition_change',greatest(0,entry.condition_score-v_drop)-entry.condition_score,
    'prize_pool',v_pool,'paid_to_player',entry.owner_user_id IS NOT NULL)
  WHERE id=entry.result_id;
  UPDATE my_derby.horses SET fatigue=least(100,fatigue+v_gain),
    condition_score=greatest(0,condition_score-v_drop),
    race_entry_state='COMPLETED' WHERE id=entry.horse_id;
  INSERT INTO my_derby.horse_state_history(horse_id,game_day,event_code,old_state,new_state)
   VALUES(entry.horse_id,race.race_day,'OFFICIAL_RACE_AFTERCARE',
    jsonb_build_object('fatigue',entry.fatigue,'condition',entry.condition_score),
    jsonb_build_object('fatigue',least(100,entry.fatigue+v_gain),
      'condition',greatest(0,entry.condition_score-v_drop),
      'rank',v_rank,'raceId',p_race_id,'prize',v_prize));
  IF entry.owner_user_id IS NOT NULL AND v_prize>0 THEN
   PERFORM my_derby_private.economy_credit_race_prize(
     entry.owner_user_id,race.world_id,race.race_day,entry.result_id,v_prize);
   v_players:=v_players+v_prize;
   INSERT INTO my_derby.notifications(owner_user_id,category,title,body,payload)
   VALUES(entry.owner_user_id,'RACE','상금 획득',entry.name||' 상금 '||v_prize||' 지급',
    jsonb_build_object('raceId',p_race_id,'horseId',entry.horse_id,'prize',v_prize));
  END IF;
  v_total:=v_total+v_prize;v_processed:=v_processed+1;
 END LOOP;
 UPDATE my_derby.races SET prize_policy=prize_policy||
 jsonb_build_object('prize_status','ECONOMY_V2_SETTLED','total_prize_pool',v_pool,
  'paid_prizes',v_total,'horse_aftercare',true) WHERE id=p_race_id;
 INSERT INTO my_derby.race_postprocess_state
 (race_id,world_id,finishers,player_prize_total,prize_total)
 VALUES(p_race_id,race.world_id,v_processed,v_players,v_total);
 PERFORM my_derby_private.apply_race_rating(p_race_id);
 PERFORM my_derby_private.assess_official_race_injuries(p_race_id);
  RETURN jsonb_build_object('status','SETTLED','raceId',p_race_id,
 'finishers',v_processed,'totalPrizes',v_total,'playerPrizes',v_players);
END $function$;