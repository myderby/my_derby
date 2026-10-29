-- My Derby economy_v2: official prizes and post-race horse state once per race.
-- Grade pools from Appendix F, split 50/25/15/7/3. No invented starter cash.
CREATE TABLE IF NOT EXISTS my_derby.race_postprocess_state(
 race_id uuid PRIMARY KEY REFERENCES my_derby.races(id),
 world_id uuid NOT NULL REFERENCES my_derby.worlds(id),
 processed_at timestamptz NOT NULL DEFAULT now(),
 finishers integer NOT NULL,
 player_prize_total bigint NOT NULL DEFAULT 0,
 prize_total bigint NOT NULL DEFAULT 0,
 policy_version text NOT NULL DEFAULT 'economy_v2'
);
ALTER TABLE my_derby.race_postprocess_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.race_postprocess_state FROM anon,authenticated;
-- Dedicated ledger uniqueness for idempotent (race, transaction type, recipient).
CREATE UNIQUE INDEX IF NOT EXISTS ix_wallet_unique_race_prize
ON my_derby.wallet_transactions(owner_user_id,reference_id,transaction_type)
WHERE reference_type='RACE' AND transaction_type='RACE_PRIZE';

CREATE OR REPLACE FUNCTION my_derby_private.economy_grade_pool(p_grade integer)
RETURNS bigint LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $$
 SELECT CASE p_grade WHEN 6 THEN 100000::bigint WHEN 5 THEN 200000::bigint
 WHEN 4 THEN 400000::bigint WHEN 3 THEN 800000::bigint WHEN 2 THEN 1500000::bigint
 WHEN 1 THEN 3000000::bigint ELSE 0::bigint END
$$;

CREATE OR REPLACE FUNCTION my_derby_private.apply_official_race_aftercare(p_race_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
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
   -- Profiles row serializes wallet writes by this player.
   PERFORM 1 FROM my_derby.profiles WHERE user_id=entry.owner_user_id FOR UPDATE;
   SELECT coalesce((SELECT balance_after FROM my_derby.wallet_transactions
    WHERE owner_user_id=entry.owner_user_id ORDER BY id DESC LIMIT 1),0)
    INTO v_balance;
   INSERT INTO my_derby.wallet_transactions(owner_user_id,world_id,game_day,
      change_amount,balance_after,transaction_type,reference_type,reference_id)
   VALUES(entry.owner_user_id,race.world_id,race.race_day,v_prize,
     v_balance+v_prize,'RACE_PRIZE','RACE',p_race_id)
   ON CONFLICT DO NOTHING;
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
 RETURN jsonb_build_object('status','SETTLED','raceId',p_race_id,
 'finishers',v_processed,'totalPrizes',v_total,'playerPrizes',v_players);
END $fn$;

REVOKE ALL ON FUNCTION my_derby_private.apply_official_race_aftercare(uuid)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.economy_grade_pool(integer)
 FROM PUBLIC,anon,authenticated;

-- New races settle atomically together with official finalization.
CREATE OR REPLACE FUNCTION my_derby.secure_official_race_finalize(p_secret text, p_run_id uuid, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_run my_derby.race_runs%rowtype;
 v_race my_derby.races%rowtype;
 v_count int;v_finished int;v_different int;v_sections int;v_event_count int;
begin
 if p_secret is null or p_secret is distinct from
   (select secret from my_derby_private.dispatch_credentials where key='race_runner')
 then raise exception 'OFFICIAL_AUTH_REQUIRED' using errcode='42501';end if;
 select * into v_run from my_derby.race_runs where id=p_run_id for update;
 if not found then raise exception 'RUN_NOT_FOUND';end if;
 if v_run.status='FINISHED' then return jsonb_build_object('status','ALREADY_FINISHED','raceId',v_run.race_id);end if;
 if v_run.status<>'RUNNING' then raise exception 'RUN_NOT_CLAIMED';end if;
 select * into v_race from my_derby.races where id=v_run.race_id for update;
 if v_race.status<>'RUNNING' then raise exception 'RACE_NOT_RUNNING';end if;
 if p_result->>'raceId' is distinct from v_race.id::text or
    (p_result->>'seed')::integer is distinct from v_run.random_seed or
    p_result->>'version'<>'0.1.0' or
    (p_result->>'tickSeconds')::numeric<>0.2 then
  raise exception 'ENGINE_SNAPSHOT_MISMATCH';end if;
 if jsonb_typeof(p_result->'results')<>'array' or
   jsonb_typeof(p_result->'sections')<>'array' or
   jsonb_typeof(p_result->'events')<>'array' then
  raise exception 'RESULT_ARRAYS_INVALID';end if;
 select count(*)::int into v_count from my_derby.race_entries
 where race_id=v_race.id and status='CONFIRMED';
 if jsonb_array_length(p_result->'results')<>v_count or v_count<2 or v_count>16 or (v_race.target_runner_count is not null and v_count<>v_race.target_runner_count)
 then raise exception 'FINISHER_COUNT_MISMATCH';end if;
 select count(*)::int into v_different from jsonb_array_elements(p_result->'results') f
 where not exists(
  select 1 from my_derby.race_entries e
  where e.race_id=v_race.id and e.horse_id=(f->>'horseId')::uuid
 )
 or (f->>'timeSec')::numeric<=0
 or (f->>'rank')::int not between 1 and v_count;
 if v_different>0 then raise exception 'INVALID_FINISHER';end if;
 if (select count(distinct f->>'horseId') from jsonb_array_elements(p_result->'results') f)<>v_count or
    (select count(distinct (f->>'rank')::int) from jsonb_array_elements(p_result->'results') f)<>v_count
 then raise exception 'DUPLICATE_FINISHER_OR_RANK';end if;
 select jsonb_array_length(p_result->'sections'),jsonb_array_length(p_result->'events')
 into v_sections,v_event_count;
 if v_sections>20 or v_event_count>650 then raise exception 'RESULT_TOO_LARGE';end if;

 insert into my_derby.race_results(race_run_id,horse_id,finishing_rank,finish_time_sec,prize_amount,change_snapshot)
 select v_run.id,(f->>'horseId')::uuid,(f->>'rank')::smallint,
   (f->>'timeSec')::numeric,0,
   jsonb_build_object('engine_version',p_result->>'version',
     'prize_settlement','PENDING_ECONOMY_V2','final_stamina',f->>'finalStamina')
 from jsonb_array_elements(p_result->'results') f;
 insert into my_derby.race_section_ranks(race_run_id,horse_id,distance_m,ranking,gap_m,pace)
 select v_run.id,(ranked.r->>'horseId')::uuid,(sec.s->>'distanceM')::int,
  (ranked.r->>'rank')::smallint,(ranked.r->>'gapM')::numeric,
  ranked.r->>'strategy'
 from jsonb_array_elements(p_result->'sections') sec(s)
 cross join lateral jsonb_array_elements(sec.s->'ranks') ranked(r);

 insert into my_derby.race_event_logs(race_run_id,seq,time_sec,distance_m,horse_id,
  event_type,reason_code,params,importance)
 select v_run.id,(e->>'seq')::int,(e->>'timeSec')::numeric,(e->>'distanceM')::numeric,
  nullif(e->>'horseId','')::uuid,e->>'eventType',e->>'reasonCode',
  coalesce(e->'params','{}'::jsonb)||jsonb_build_object('text',e->>'text'),
  coalesce((e->>'importance')::smallint,1)
 from jsonb_array_elements(p_result->'events') e;
 update my_derby.race_entries set status='COMPLETED' where race_id=v_race.id and status='CONFIRMED';
 update my_derby.races set status='FINISHED',
   prize_policy=prize_policy||'{"prize_status":"PENDING_ECONOMY_V2"}'::jsonb where id=v_race.id;
 update my_derby.race_runs set status='FINISHED',engine_version=p_result->>'version',
  result_applied_at=now() where id=v_run.id;
 insert into my_derby.official_race_process_audit(race_id,slot_time,action,event_detail)
 values(v_race.id,v_race.start_time,'FINISHED',jsonb_build_object(
  'runId',v_run.id,'finishers',v_count,'events',v_event_count,'sections',v_sections));
 perform my_derby_private.apply_official_race_aftercare(v_race.id);
  return jsonb_build_object('status','FINISHED','raceId',v_race.id,
   'runId',v_run.id,'winner',p_result->'results'->0->>'name','finishers',v_count,
   'prizeSettlement','PENDING_ECONOMY_V2');
end;
$function$;
