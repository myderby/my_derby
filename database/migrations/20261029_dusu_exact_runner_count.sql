-- MY DERBY CSV dusu exact starter count. Source data rows must be uploaded using
-- scripts/schedule/import_source_csv.py (user-provided 2025 CSV); never fake confirmed starters.
alter table my_derby.races add column if not exists target_runner_count smallint;
alter table my_derby.races drop constraint if exists races_target_runner_count_valid;
alter table my_derby.races add constraint races_target_runner_count_valid
check(target_runner_count between 2 and 16 or target_runner_count is null);
alter table my_derby.race_program_source_2025
add column if not exists source_runner_count smallint;
alter table my_derby.race_program_source_2025
drop constraint if exists source_runner_count_valid;
alter table my_derby.race_program_source_2025 add constraint source_runner_count_valid
check(source_runner_count between 2 and 16 or source_runner_count is null);
-- Real 2025 race entries/rider candidates are stored from the user's CSV in private,
-- RLS-protected tables. No new horse ownership is granted to existing users here.
create table if not exists my_derby.schedule_roster_2025(
 hr_no text primary key,name text not null,sex text not null,age_years integer not null,
 source_meet text not null,grade_no smallint not null,rating integer not null default 0,
 career_runs integer not null default 0,career_wins integer not null default 0,
 observed_races integer not null default 0,source_date date not null
);
create table if not exists my_derby.schedule_jockey_roster_2025(
 source_meet text not null,jk_no text not null,name text not null,
 source_races integer not null default 0,primary key(source_meet,jk_no)
);
alter table my_derby.schedule_roster_2025 enable row level security;
alter table my_derby.schedule_jockey_roster_2025 enable row level security;
revoke all on my_derby.schedule_roster_2025,my_derby.schedule_jockey_roster_2025 from public,anon,authenticated;
grant all on my_derby.schedule_roster_2025,my_derby.schedule_jockey_roster_2025 to service_role;
-- The functions below are reproduced from the deployed DB and enforce exact dusu
-- at entry preparation, preview, claim, stage and final official storage.
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
 return jsonb_build_object('status','FINISHED','raceId',v_race.id,
   'runId',v_run.id,'winner',p_result->'results'->0->>'name','finishers',v_count,
   'prizeSettlement','PENDING_ECONOMY_V2');
end;
$function$;

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
 if r.target_runner_count is null or n<>r.target_runner_count or n<2 or n>16 then raise exception 'DUSU_STARTERS_MISMATCH: required %, actual %',r.target_runner_count,n using errcode='23514';end if;
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
 if v_count<2 or v_count>16 or v_count<>r.target_runner_count or jsonb_array_length(p_result->'results')<>v_count then
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
 w uuid;
 r my_derby.races%rowtype;
 h record;
 jockey uuid;
 total_added int:=0;
 ready int:=0;
 missing int:=0;
 entry_count int;
 gate smallint;
 required int;
 strategies jsonb;
begin
 select id into w from my_derby.worlds where world_key='kra_roster_v1';
 if w is null or p_game_day<1 then raise exception 'INVALID_WORLD_OR_DAY';end if;
 for r in
  select * from my_derby.races
  where world_id=w and race_day=p_game_day and status='OPEN'
   and prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  order by start_time,track,race_no for update
 loop
  required:=r.target_runner_count;
  if required is null or required<2 or required>16 then
    raise exception 'DUSU_MISSING_OR_INVALID_FOR_RACE %',r.id;
  end if;
  select count(*) into entry_count from my_derby.race_entries
    where race_id=r.id and status in ('APPLIED','CONFIRMED');
  if entry_count>required then
   update my_derby.races set prize_policy=prize_policy||jsonb_build_object(
     'entry_status','OVERBOOKED','actual_starters',entry_count)
   where id=r.id;
   missing:=missing+1;continue;
  end if;
  gate:=coalesce((select max(gate_no) from my_derby.race_entries where race_id=r.id),0);
  for h in
   select hh.id,hh.name,hh.source_meet,a.current_stats
   from my_derby.horses hh
   join my_derby.horse_abilities a on a.horse_id=hh.id
   where hh.world_id=w
     and hh.source_meet=r.prize_policy->>'source_meet'
     and hh.source_grade_no=(r.prize_policy->>'grade_no')::smallint
     and hh.life_stage='RACING'
     and hh.racing_retired_permanently=false
     and hh.breeding_retired_at is null
     and hh.npc_owner_id is not null and hh.age_years between 2 and 10
     and not exists (
       select 1 from my_derby.race_entries e
       join my_derby.races rr on rr.id=e.race_id
       where rr.race_day=p_game_day and rr.world_id=w
       and rr.status<>'CANCELLED' and e.horse_id=hh.id
       and e.status in ('APPLIED','CONFIRMED','COMPLETED')
     )
   order by md5(hh.id::text||':'||r.id::text)
   limit greatest(0,required-entry_count)
  loop
   select j.id into jockey from my_derby.npc_jockeys j
   where j.world_id=w and j.home_track=r.track and j.is_active
     and not exists(select 1 from my_derby.race_entries e
       where e.race_id=r.id and e.jockey_id=j.id and e.status in ('APPLIED','CONFIRMED','COMPLETED'))
     and (select count(*) from my_derby.race_entries e
       join my_derby.races rr on rr.id=e.race_id
       where e.jockey_id=j.id and rr.race_day=p_game_day and rr.world_id=w
         and rr.status<>'CANCELLED' and e.status in ('CONFIRMED','COMPLETED'))<j.max_daily_rides
   order by (select count(*) from my_derby.race_entries e
      join my_derby.races rr on rr.id=e.race_id
      where e.jockey_id=j.id and rr.race_day=p_game_day and rr.world_id=w
        and rr.status<>'CANCELLED'),md5(j.id::text||r.id::text)
   limit 1;
   if jockey is null then continue;end if;
   strategies:=case when (h.current_stats->>'start')::numeric>(h.current_stats->>'finishing')::numeric
      then '["FRONT","PRESS","SAVE"]'::jsonb
      else '["SAVE","MOVE","CLOSER"]'::jsonb end;
   gate:=gate+1;
   insert into my_derby.race_entries
     (race_id,horse_id,owner_user_id,jockey_id,gate_no,weight_kg,status,snapshot)
   values(r.id,h.id,null,jockey,gate,54,'CONFIRMED',
      jsonb_build_object('strategies',strategies,
       'trainerReadiness',75,'entry_source','NPC_AUTOFILL_DUSU_V1',
       'required_dusu',required,
       'source_meet',r.prize_policy->>'source_meet',
       'source_rank',r.class_name));
   entry_count:=entry_count+1;
   total_added:=total_added+1;
  end loop;
  if entry_count=required then
    ready:=ready+1;
    update my_derby.races set prize_policy=prize_policy||
      jsonb_build_object('entry_status','READY','actual_starters',entry_count)
    where id=r.id;
  else
    missing:=missing+1;
    update my_derby.races set prize_policy=prize_policy||
      jsonb_build_object('entry_status','INSUFFICIENT_ELIGIBLE_HORSES',
       'actual_starters',entry_count,'missing_starters',required-entry_count)
    where id=r.id;
  end if;
 end loop;
 return jsonb_build_object('gameDay',p_game_day,'addedEntries',total_added,
  'readyRaces',ready,'insufficientRaces',missing);
end $function$;
