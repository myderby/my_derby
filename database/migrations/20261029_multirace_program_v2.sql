-- Deployed 2026-10-29; reproduced from live SQL function definitions.
-- Source CSV data rows must be imported separately into my_derby.race_program_source_2025.
-- Re-running this DDL does not generate new races or alter existing official results.
create schema if not exists my_derby_private;
create table if not exists my_derby.race_program_source_2025 (
 source_date date not null, source_meet text not null,
 source_rc_no smallint not null, source_rank text not null,
 distance_m integer not null, original_st_time time not null,
 source_runner_count smallint, original_rc_name text,
 primary key(source_date,source_meet,source_rc_no),
 constraint valid_meet check(source_meet in ('서울','부산경남','제주')),
 constraint source_dist check(distance_m between 800 and 3200)
);
alter table my_derby.race_program_source_2025 enable row level security;
revoke all on my_derby.race_program_source_2025 from public,anon,authenticated;
grant all on my_derby.race_program_source_2025 to service_role;
create table if not exists my_derby_private.race_pending_results(
 race_id uuid primary key references my_derby.races(id),
 run_id uuid not null unique references my_derby.race_runs(id),
 result jsonb not null,
 due_at timestamptz not null,
 created_at timestamptz not null default now()
);
revoke all on my_derby_private.race_pending_results from public,anon,authenticated;
create index if not exists idx_my_derby_pending_due on my_derby_private.race_pending_results(due_at);

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
  and (select count(*) from my_derby.race_entries e where e.race_id=ra.id and e.status='CONFIRMED') between 2 and 12
 order by ra.start_time,ra.track,ra.race_no
 limit 1 for update of ra skip locked;
 if not found then return jsonb_build_object('status','WAITING','slot',p_slot);end if;
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

CREATE OR REPLACE FUNCTION my_derby.secure_program_preview_race(p_secret text, p_race_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 r my_derby.races%rowtype;
 input_runners jsonb;
 n integer;
 seed integer;
begin
 if p_secret is null or p_secret is distinct from
   (select secret from my_derby_private.dispatch_credentials where key='race_runner')
   then raise exception 'OFFICIAL_AUTH_REQUIRED' using errcode='42501';end if;
 select * into r from my_derby.races where id=p_race_id;
 if not found or r.status='CANCELLED' or
   r.prize_policy->>'schedule_version'<>'csv2025_rank_sttime_v2'
   then raise exception 'NEW_PROGRAM_RACE_NOT_FOUND';end if;
 if (r.prize_policy->>'kst_date')::date<>((now() at time zone 'Asia/Seoul')::date) then
   raise exception 'NOT_TODAY_PROGRAM';end if;
 select count(*) into n from my_derby.race_entries e where e.race_id=p_race_id and e.status in ('CONFIRMED','COMPLETED');
 if n<2 or n>12 then raise exception 'NEED_2_TO_12_CONFIRMED_HORSES' using errcode='23514';end if;
 if exists(select 1 from my_derby.race_entries e join my_derby.horses h on h.id=e.horse_id
    where e.race_id=p_race_id and e.status in ('CONFIRMED','COMPLETED')
      and (h.life_stage<>'RACING' or h.racing_retired_permanently
         or h.breeding_retired_at is not null or
         h.source_meet is distinct from (r.prize_policy->>'source_meet')
         or h.source_grade_no is distinct from (r.prize_policy->>'grade_no')::smallint)
 ) then raise exception 'ENTRY_INELIGIBLE_BY_REGION_GRADE_OR_RETIREMENT';end if;
 select jsonb_agg(jsonb_build_object(
   'id',h.id::text,'number',e.gate_no,'name',h.name,'gate',e.gate_no,
   'horse',a.current_stats,'jockey',j.skill_stats,
   'strategies',coalesce(e.snapshot->'strategies','["FREE"]'::jsonb),
   'condition',h.condition_score,'fatigue',h.fatigue,'weightKg',e.weight_kg,
   'distanceFit',coalesce(nullif(a.distance_affinity->>(r.distance_m::text),'')::numeric,75),
   'trainerReadiness',coalesce((e.snapshot->>'trainerReadiness')::numeric,75)
 ) order by e.gate_no) into input_runners
 from my_derby.race_entries e
 join my_derby.horses h on h.id=e.horse_id
 join my_derby.horse_abilities a on a.horse_id=h.id
 join my_derby.npc_jockeys j on j.id=e.jockey_id and j.is_active
 where e.race_id=p_race_id and e.status in ('CONFIRMED','COMPLETED')
   and e.gate_no is not null and e.weight_kg is not null;
 if input_runners is null or jsonb_array_length(input_runners)<>n then
   raise exception 'ENTRY_ABILITY_JOCKEY_MISSING';end if;
 seed:=floor(random()*2147483646)::int+1;
 return jsonb_build_object('status','PREVIEW','raceId',r.id,
   'displayRaceNo',r.prize_policy->>'source_rc_no',
   'startTime',to_char(r.start_time,'HH24:MI'),
   'resultTime',r.prize_policy->>'result_kst_time',
   'rank',r.class_name,
   'input',jsonb_build_object('raceId',r.id,'track',r.track,
    'distanceM',r.distance_m,'seed',seed,'runners',input_runners));
end $function$;

CREATE OR REPLACE FUNCTION my_derby.secure_program_publish_due(p_secret text, p_slot integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row record;v_result jsonb;v_n int:=0;v_ids jsonb:='[]'::jsonb;
begin
 if p_secret is null or p_secret is distinct from
   (select secret from my_derby_private.dispatch_credentials where key='race_runner')
   then raise exception 'OFFICIAL_AUTH_REQUIRED' using errcode='42501';end if;
 if p_slot not between 0 and 2 then raise exception 'INVALID_SLOT';end if;
 for v_row in
  select p.race_id,p.run_id,p.result from my_derby_private.race_pending_results p
  join my_derby.races r on r.id=p.race_id
  where p.due_at<=now()
   and (r.prize_policy->>'slot_index')::int=p_slot
   and r.status='RUNNING'
  order by p.due_at limit 4 for update of p skip locked
 loop
  v_result:=my_derby.secure_official_race_finalize(p_secret,v_row.run_id,v_row.result);
  delete from my_derby_private.race_pending_results where race_id=v_row.race_id;
  v_ids:=v_ids||jsonb_build_array(jsonb_build_object('raceId',v_row.race_id,'result',v_result));
  v_n:=v_n+1;
 end loop;
 return jsonb_build_object('status',case when v_n>0 then 'PUBLISHED' else 'WAITING' end,
  'count',v_n,'results',v_ids);
end $function$;

CREATE OR REPLACE FUNCTION my_derby.secure_program_stage_result(p_secret text, p_run_id uuid, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_run my_derby.race_runs%rowtype;
 r my_derby.races%rowtype;
 v_due timestamptz;
 v_count integer;
begin
 if p_secret is null or p_secret is distinct from
   (select secret from my_derby_private.dispatch_credentials where key='race_runner')
   then raise exception 'OFFICIAL_AUTH_REQUIRED' using errcode='42501';end if;
 select * into v_run from my_derby.race_runs where id=p_run_id for update;
 if not found or v_run.status<>'RUNNING' then raise exception 'RUN_NOT_RUNNING';end if;
 select * into r from my_derby.races where id=v_run.race_id for update;
 if r.status<>'RUNNING' or r.prize_policy->>'schedule_version'<>'csv2025_rank_sttime_v2'
   then raise exception 'NEW_PROGRAM_RACE_NOT_RUNNING';end if;
 if (p_result->>'raceId') is distinct from r.id::text or
    (p_result->>'seed')::bigint is distinct from v_run.random_seed or
    p_result->>'version'<>'0.1.0' or
    (p_result->>'tickSeconds')::numeric<>0.2 then
   raise exception 'ENGINE_SNAPSHOT_MISMATCH';end if;
 if jsonb_typeof(p_result->'results')<>'array' or
  jsonb_typeof(p_result->'events')<>'array' or
  jsonb_typeof(p_result->'sections')<>'array' then
  raise exception 'RESULT_ARRAYS_INVALID';end if;
 select count(*) into v_count from my_derby.race_entries e
  where e.race_id=r.id and e.status='CONFIRMED';
 if v_count<2 or jsonb_array_length(p_result->'results')<>v_count then
   raise exception 'FINISHER_COUNT_MISMATCH';end if;
 v_due:=(((r.prize_policy->>'kst_date')::date+r.start_time) at time zone 'Asia/Seoul')+interval '3 minutes';
 insert into my_derby_private.race_pending_results(race_id,run_id,result,due_at)
 values(r.id,v_run.id,p_result,v_due)
 on conflict(race_id) do nothing;
 insert into my_derby.official_race_process_audit(race_id,slot_time,action,event_detail)
 values(r.id,r.start_time,'RESULT_STAGED_3_MINUTES',
   jsonb_build_object('runId',v_run.id,'dueAt',v_due));
 return jsonb_build_object('status','STAGED','raceId',r.id,'runId',v_run.id,
   'scheduledResultAt',v_due,'resultPublic',false);
end $function$;

CREATE OR REPLACE FUNCTION my_derby_private.prepare_program_entries(p_game_day integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_world uuid;
 v_race my_derby.races%rowtype;
 v_h record;
 v_jockey uuid;
 v_added integer:=0;
 v_ready integer:=0;
 v_not_ready integer:=0;
 v_existing integer;
 v_gate smallint;
 v_target integer;
 v_strategies jsonb;
 v_source text;
 v_grade integer;
begin
 select id into v_world from my_derby.worlds where world_key='kra_roster_v1';
 if v_world is null or p_game_day<1 then raise exception 'INVALID_WORLD_OR_DAY';end if;
 for v_race in
  select * from my_derby.races
  where world_id=v_world and race_day=p_game_day and status='OPEN'
   and prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  order by start_time,track,race_no
 loop
  v_source:=v_race.prize_policy->>'source_meet';
  v_grade:=(v_race.prize_policy->>'grade_no')::int;
  v_target:=case when v_race.track='서울' then 4 else 2 end;
  select count(*) into v_existing from my_derby.race_entries where race_id=v_race.id and status in ('APPLIED','CONFIRMED');
  v_gate:=coalesce((select max(gate_no) from my_derby.race_entries where race_id=v_race.id),0);
  for v_h in
   select h.id, h.owner_user_id,h.npc_owner_id,a.current_stats,h.name
   from my_derby.horses h
   join my_derby.horse_abilities a on a.horse_id=h.id
   where h.world_id=v_world
     and h.source_meet=v_source and h.source_grade_no=v_grade
     and h.life_stage='RACING'
     and h.racing_retired_permanently=false and h.breeding_retired_at is null
     and h.npc_owner_id is not null and h.age_years>=2
     and not exists (
       select 1 from my_derby.race_entries e
       join my_derby.races x on x.id=e.race_id
       where x.race_day=p_game_day and x.world_id=v_world
        and x.status<>'CANCELLED' and e.horse_id=h.id
        and e.status in ('APPLIED','CONFIRMED','COMPLETED')
     )
   order by md5(h.id::text||':'||v_race.id::text)
   limit greatest(0,v_target-v_existing)
  loop
   select j.id into v_jockey
   from my_derby.npc_jockeys j
   where j.world_id=v_world and j.home_track=v_race.track and j.is_active
     and not exists(select 1 from my_derby.race_entries e where e.race_id=v_race.id and e.jockey_id=j.id)
     and (select count(*) from my_derby.race_entries e join my_derby.races r on r.id=e.race_id
          where e.jockey_id=j.id and r.race_day=p_game_day and r.world_id=v_world
           and r.status<>'CANCELLED' and e.status in ('CONFIRMED','COMPLETED'))<j.max_daily_rides
   order by (
     select count(*) from my_derby.race_entries e join my_derby.races r on r.id=e.race_id
     where e.jockey_id=j.id and r.race_day=p_game_day and r.world_id=v_world and r.status<>'CANCELLED'
   ),md5(j.id::text||v_race.id::text)
   limit 1;
   if v_jockey is null then continue;end if;
   v_strategies:=case when (v_h.current_stats->>'start')::numeric > (v_h.current_stats->>'finishing')::numeric
     then '["FRONT","PRESS","SAVE"]'::jsonb
     else '["SAVE","MOVE","CLOSER"]'::jsonb end;
   v_gate:=v_gate+1;
   insert into my_derby.race_entries(race_id,horse_id,owner_user_id,jockey_id,gate_no,weight_kg,status,snapshot)
    values(v_race.id,v_h.id,null,v_jockey,v_gate,54,'CONFIRMED',
     jsonb_build_object('strategies',v_strategies,'trainerReadiness',75,
       'entry_source','NPC_AUTOFILL_V2','grade_no',v_grade));
   v_added:=v_added+1;
  end loop;
  if (select count(*) from my_derby.race_entries where race_id=v_race.id and status='CONFIRMED')>=2
    then
      v_ready:=v_ready+1;
      update my_derby.races set prize_policy=prize_policy||
         jsonb_build_object('entry_status','READY') where id=v_race.id;
    else
      v_not_ready:=v_not_ready+1;
      update my_derby.races set prize_policy=prize_policy||
         jsonb_build_object('entry_status','INSUFFICIENT_ELIGIBLE_HORSES') where id=v_race.id;
  end if;
 end loop;
 return jsonb_build_object('gameDay',p_game_day,'addedEntries',v_added,
   'readyRaces',v_ready,'insufficientRaces',v_not_ready);
end;
$function$;

CREATE OR REPLACE FUNCTION my_derby_private.send_race_slot(p_slot integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_secret text;v_request bigint;
begin
 if p_slot not between 0 and 2 then raise exception 'INVALID_SLOT';end if;
 -- Never regenerate old 3-races-per-day templates. The rank/stTime programme is source of truth.
 select secret into v_secret from my_derby_private.dispatch_credentials where key='race_runner';
 if v_secret is null then raise exception 'DISPATCH_SECRET_MISSING';end if;
 select net.http_get(
  url:='https://my-derby.vercel.app/api/cron/race?slot='||p_slot::text,
  headers:=jsonb_build_object('Authorization','Bearer '||v_secret),
  timeout_milliseconds:=45000
 ) into v_request;
 return v_request;
end $function$;

revoke all on function my_derby.secure_program_preview_race(text,uuid) from public;
revoke all on function my_derby.secure_program_claim_next(text,integer) from public;
revoke all on function my_derby.secure_program_stage_result(text,uuid,jsonb) from public;
revoke all on function my_derby.secure_program_publish_due(text,integer) from public;
grant execute on function my_derby.secure_program_preview_race(text,uuid) to anon,authenticated;
grant execute on function my_derby.secure_program_claim_next(text,integer) to anon,authenticated;
grant execute on function my_derby.secure_program_stage_result(text,uuid,jsonb) to anon,authenticated;
grant execute on function my_derby.secure_program_publish_due(text,integer) to anon,authenticated;
revoke all on function my_derby_private.prepare_program_entries(integer) from public,anon,authenticated;
revoke all on function my_derby_private.send_race_slot(integer) from public,anon,authenticated;
notify pgrst, 'reload schema';
