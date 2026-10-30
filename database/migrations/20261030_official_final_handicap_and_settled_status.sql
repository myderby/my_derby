CREATE OR REPLACE FUNCTION my_derby.secure_program_claim_next(p_secret text, p_slot integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 r my_derby.races%rowtype;
 v_data jsonb;
 v_input jsonb;
 v_run my_derby.race_runs%rowtype;
 v_world my_derby.worlds%rowtype;
 v_today date;
begin
 if p_secret is null or p_secret is distinct from
   (select secret from my_derby_private.dispatch_credentials where key='race_runner')
   then raise exception 'OFFICIAL_AUTH_REQUIRED' using errcode='42501';end if;
 if p_slot not between 0 and 2 then raise exception 'INVALID_SLOT';end if;
 select * into v_world from my_derby.worlds where world_key='kra_roster_v1';
 if v_world.status<>'ACTIVE' or not v_world.automatic_processing_enabled
   then return jsonb_build_object('status','WORLD_NOT_PROCESSING');end if;
 v_today:=(now() at time zone 'Asia/Seoul')::date;
 select * into r from my_derby.races ra
 where ra.world_id=v_world.id and ra.status='OPEN'
  and ra.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  and ra.prize_policy->>'kst_date'=v_today::text
  and (ra.prize_policy->>'slot_index')::int=p_slot
  and ra.start_time<=(now() at time zone 'Asia/Seoul')::time
  and ra.target_runner_count between 2 and 16 and (select count(*) from my_derby.race_entries e where e.race_id=ra.id and e.status='CONFIRMED')=ra.target_runner_count
 order by ra.start_time,ra.track,ra.race_no
 limit 1 for update of ra skip locked;
 if not found then return jsonb_build_object('status','WAITING','slot',p_slot);end if;
 -- Recompute weight from final entrants immediately before engine snapshot.
 PERFORM my_derby_private.recalculate_official_handicap_race(r.id);
  v_data:=my_derby.secure_program_preview_race(p_secret,r.id);
 v_input:=v_data->'input';
 insert into my_derby.race_runs
 (race_id,race_input,random_seed,balance_version,tick_seconds,status,claimed_at,engine_version)
 values(r.id,v_input,(v_input->>'seed')::bigint,v_world.balance_version,0.2,'RUNNING',now(),'0.1.0')
 on conflict(race_id) do nothing returning * into v_run;
 if not found then return jsonb_build_object('status','ALREADY_RUNNING','raceId',r.id);end if;
 update my_derby.races set status='RUNNING' where id=r.id;
 insert into my_derby.official_race_process_audit(race_id,slot_time,action,event_detail)
 values(r.id,r.start_time,'SCHEDULE_V2_CLAIM',jsonb_build_object('runId',v_run.id,'grade',r.class_name));
 return jsonb_build_object('status','CLAIMED','raceId',r.id,'runId',v_run.id,
   'rank',r.class_name,'startTime',r.start_time,'input',v_input);
end $function$;
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
   'prizeSettlement','ECONOMY_V2_SETTLED');
end;
$function$;
