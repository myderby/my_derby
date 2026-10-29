-- My Derby official scheduler and race game: reproducible schema and functions.
-- Generated from the active Supabase database on 2026-10-29.
-- IMPORTANT: Original my_derby base schema, KRA horse importer and owner creation must run first.
-- IMPORTANT: Production CRON_SECRET in Vercel must match my_derby_private.dispatch_credentials.secret.
-- Never commit an actual dispatch secret.

create schema if not exists my_derby_private;
revoke all on schema my_derby_private from public,anon,authenticated;
create table if not exists my_derby_private.dispatch_credentials(
 key text primary key,secret text not null check(length(secret)>=48),
 created_at timestamptz not null default now()
);
revoke all on my_derby_private.dispatch_credentials from public,anon,authenticated;
insert into my_derby_private.dispatch_credentials(key,secret)
values('race_runner',encode(gen_random_bytes(32),'hex'))
on conflict(key) do nothing;
create extension if not exists pg_net with schema extensions;
alter table my_derby.horses add column if not exists source_grade_no smallint;
create index if not exists idx_myderby_race_pools on my_derby.horses(world_id,source_meet,source_grade_no,life_stage);
alter table my_derby.npc_jockeys add column if not exists home_track text;
create unique index if not exists uq_npc_jockeys_world_name on my_derby.npc_jockeys(world_id,name);
create index if not exists idx_npc_jockeys_home on my_derby.npc_jockeys(world_id,home_track);
create table if not exists my_derby.race_program_templates (
 id bigint generated always as identity primary key,source_meet text not null,
 track text not null,grade_no smallint not null check(grade_no between 1 and 6),
 distance_m integer not null check(distance_m between 800 and 3200),
 class_name text not null,slot_time time not null,source_year integer not null default 2025,
 constraint program_one_grade unique(track,grade_no)
);
alter table my_derby.race_program_templates enable row level security;
grant select on my_derby.race_program_templates to anon,authenticated;
drop policy if exists templates_read on my_derby.race_program_templates;
create policy templates_read on my_derby.race_program_templates
 for select to anon,authenticated using(true);
create table if not exists my_derby.official_race_process_audit (
 id bigint generated always as identity primary key,
 race_id uuid references my_derby.races(id),slot_time time,action text not null,
 event_detail jsonb not null default '{}'::jsonb,created_at timestamptz not null default now()
);
alter table my_derby.official_race_process_audit enable row level security;
revoke all on my_derby.official_race_process_audit from public,anon,authenticated;
alter table my_derby.race_runs add column if not exists claimed_at timestamptz;
alter table my_derby.race_runs add column if not exists engine_version text;

insert into my_derby.race_program_templates(source_meet,track,grade_no,distance_m,class_name,slot_time)
values
('서울','서울',1,1200,'1등급','19:00'),('서울','서울',2,1600,'2등급','19:00'),
('서울','서울',3,1800,'국3등급','19:00'),('서울','서울',4,1400,'국4등급','19:00'),
('서울','서울',5,1400,'국5등급','19:00'),('서울','서울',6,1200,'국6등급','19:00'),
('부산경남','부산',1,1200,'1등급','20:00'),('부산경남','부산',2,1600,'2등급','20:00'),
('부산경남','부산',3,1800,'혼3등급','20:00'),('부산경남','부산',4,1600,'국4등급','20:00'),
('부산경남','부산',5,1200,'국5등급','20:00'),('부산경남','부산',6,1200,'국6등급','20:00'),
('제주','영천',1,1400,'제1등급','21:00'),('제주','영천',2,1300,'제2등급','21:00'),
('제주','영천',3,1200,'제3등급','21:00'),('제주','영천',4,1110,'제4등급','21:00'),
('제주','영천',5,1000,'제5등급','21:00'),('제주','영천',6,900,'제6등급','21:00')
on conflict(track,grade_no) do update set distance_m=excluded.distance_m,
class_name=excluded.class_name,slot_time=excluded.slot_time,source_meet=excluded.source_meet;

CREATE OR REPLACE FUNCTION my_derby.world_scheduler_configured()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select (select count(*)=3 from cron.job j
 where j.jobname in ('my-derby-1900','my-derby-2000','my-derby-2100') and j.active);
$function$
;

CREATE OR REPLACE FUNCTION my_derby.world_clock(p_world_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
 v_world my_derby.worlds%rowtype;
 v_today date:=((now() at time zone 'Asia/Seoul')::date);
 v_elapsed integer;
 v_live boolean;
 v_game_day integer;
 v_season integer;
 v_week integer;
begin
 select * into v_world from my_derby.worlds where id=p_world_id;
 if not found then return null; end if;
 v_live:=(v_world.status='ACTIVE' and v_world.season_anchor_date is not null);
 v_elapsed:=greatest(0,v_today-coalesce(v_world.season_anchor_date,v_today));
 v_season:=case when v_live then (v_elapsed / 52)+1 else v_world.season_number end;
 v_week:=case when v_live then (v_elapsed % 52)+1 else (((v_world.game_day-1)/7)%52)+1 end;
 v_game_day:=case when v_live then v_elapsed*7+1 else v_world.game_day end;
 return jsonb_build_object(
   'worldId',v_world.id,'worldKey',v_world.world_key,'status',v_world.status,
   'timezone','Asia/Seoul','kstDate',v_today,'anchorDate',v_world.season_anchor_date,
   'season',v_season,'week',v_week,'gameDayStart',v_game_day,
   'gameDaysPerRealDay',7,'realDaysPerSeason',52,
   'raceSlots',jsonb_build_array('19:00','20:00','21:00'),
   'calendarAdvancing',v_live,'automaticProcessingEnabled',v_world.automatic_processing_enabled,
   'schedulerConfigured',my_derby.world_scheduler_configured(),
   'seasonTransitionPolicy','52 Korean calendar days => next season; aging and economics require server processor'
 );
end $function$
;

CREATE OR REPLACE FUNCTION my_derby_private.extend_official_race_program(p_days_ahead integer DEFAULT 21)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_world my_derby.worlds%rowtype;v_start int;v_end int;v_created int;v_entries int;
begin
 select * into v_world from my_derby.worlds where world_key='kra_roster_v1';
 if not found then raise exception 'WORLD_MISSING';end if;
 v_start:=greatest(0,((now() at time zone 'Asia/Seoul')::date-v_world.season_anchor_date));
 v_end:=v_start+least(greatest(p_days_ahead,7),30);
 with future as(
  select v_world.id as world_id,v_world.season_anchor_date+days.day as kst_date,
   days.day*7+1 as race_day,
   (days.day/52)+1 as season,
   1+(days.day%52) as week,
   t.* from generate_series(v_start,v_end) as days(day)
  join my_derby.race_program_templates t on t.grade_no=6-((days.day%52)%6)
 )
 insert into my_derby.races(world_id,race_day,track,race_no,distance_m,class_name,
  start_time,entry_deadline,status,prize_policy)
 select world_id,race_day,track,1,distance_m,class_name,slot_time,
  (slot_time-interval '30 minutes')::time,'OPEN',
  jsonb_build_object('source_meet',source_meet,'grade_no',grade_no,'kst_date',kst_date::text,
   'source_template_year',2025,'season',season,'week',week,'prize_status','NOT_SETTLED')
 from future on conflict(world_id,race_day,track,race_no) do nothing;
 get diagnostics v_created=row_count;

 with r as(
 select races.id,races.track,races.world_id,races.race_day,
  races.prize_policy->>'source_meet' as source_meet,
  (races.prize_policy->>'grade_no')::int as grade_no
 from my_derby.races races
 where races.world_id=v_world.id
  and races.race_day between (v_start*7+1) and (v_end*7+1)
  and races.status='OPEN'
  and not exists(select 1 from my_derby.race_entries e where e.race_id=races.id)
 ),
 selected as(
  select r.id race_id,r.track,h.id horse_id,h.owner_user_id,
    row_number() over(partition by r.id order by md5(h.id::text||r.id::text)) gate_no
  from r join my_derby.horses h on h.world_id=r.world_id
  and h.source_meet=r.source_meet and h.source_grade_no=r.grade_no
  and h.life_stage='RACING' and not h.racing_retired_permanently
  and h.breeding_retired_at is null and h.age_years between 2 and 10
  and (h.owner_user_id is not null or h.npc_owner_id is not null)
 ),
 jockeys as(
  select id,home_track,row_number() over(partition by home_track order by name,id) rn
  from my_derby.npc_jockeys where is_active
 )
 insert into my_derby.race_entries(race_id,horse_id,owner_user_id,jockey_id,
 gate_no,weight_kg,status,snapshot)
 select s.race_id,s.horse_id,s.owner_user_id,j.id,s.gate_no::smallint,54,'CONFIRMED',
 jsonb_build_object('scheduler_source','official_daily_v1',
 'strategies',jsonb_build_array('FREE','PRESS','CLOSER'),'registration_type','npc_preseason_auto')
 from selected s join jockeys j on j.home_track=s.track and j.rn=s.gate_no
 where s.gate_no<=12
 on conflict(race_id,horse_id) do nothing;
 get diagnostics v_entries=row_count;

 return jsonb_build_object('status','OK','startOffset',v_start,'endOffset',v_end,
 'newRaces',v_created,'newEntries',v_entries);
end;
$function$
;

CREATE OR REPLACE FUNCTION my_derby_private.send_race_slot(p_slot integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_secret text;v_request bigint;
begin
 if p_slot not between 0 and 2 then raise exception 'INVALID_SLOT';end if;
 perform my_derby_private.extend_official_race_program(21);
 select secret into v_secret from my_derby_private.dispatch_credentials
 where key='race_runner';
 if v_secret is null then raise exception 'DISPATCH_SECRET_MISSING';end if;
 select net.http_get(
  url:='https://my-derby.vercel.app/api/cron/race?slot='||p_slot::text,
  headers:=jsonb_build_object('Authorization','Bearer '||v_secret),
  timeout_milliseconds:=45000
 ) into v_request;
 return v_request;
end;
$function$
;

CREATE OR REPLACE FUNCTION my_derby_private.send_upcoming_program()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin return my_derby_private.extend_official_race_program(21);end;$function$
;

CREATE OR REPLACE FUNCTION my_derby.secure_official_race_input(p_secret text, p_slot integer, p_force boolean DEFAULT false, p_preview boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_world my_derby.worlds%rowtype;
 v_date date:=(now() at time zone 'Asia/Seoul')::date;
 v_hour time;
 v_game_day integer;
 v_race my_derby.races%rowtype;
 v_run my_derby.race_runs%rowtype;
 v_entries jsonb;
 v_count int;
 v_seed int;
 v_input jsonb;
begin
 if p_secret is null or p_secret is distinct from
    (select secret from my_derby_private.dispatch_credentials where key='race_runner')
 then raise exception 'OFFICIAL_AUTH_REQUIRED' using errcode='42501'; end if;
 if p_slot not between 0 and 2 then raise exception 'INVALID_SLOT' using errcode='22023';end if;
 select * into v_world from my_derby.worlds where world_key='kra_roster_v1';
 if not found or v_world.status<>'ACTIVE' then
  raise exception 'WORLD_NOT_ACTIVE' using errcode='23514'; end if;
 if not v_world.automatic_processing_enabled and not p_preview then
  raise exception 'OFFICIAL_PROCESSING_DISABLED' using errcode='23514';end if;
 v_hour:=(array['19:00','20:00','21:00'])[p_slot+1]::time;
 v_game_day:=greatest(0,v_date-v_world.season_anchor_date)*7+1;
 select * into v_race from my_derby.races r
 where r.world_id=v_world.id and r.race_day=v_game_day and r.start_time=v_hour
   and r.prize_policy->>'kst_date'=v_date::text
 for update;
 if not found then raise exception 'SCHEDULE_NOT_FOUND_FOR_DATE_SLOT' using errcode='23514';end if;
 if not p_force and not p_preview and (now() at time zone 'Asia/Seoul')::time < v_hour
 then raise exception 'NOT_YET_SCHEDULED_TIME' using errcode='23514';end if;
 if v_race.status='CANCELLED' then raise exception 'RACE_CANCELLED' using errcode='23514';end if;
 if v_race.status='FINISHED' and not p_preview then
  return jsonb_build_object('status','ALREADY_FINISHED','raceId',v_race.id);end if;
 if not p_preview and v_race.status='RUNNING' and exists(
  select 1 from my_derby.race_runs r where r.race_id=v_race.id and
   r.status='RUNNING' and r.claimed_at>now()-interval '4 minutes'
 ) then return jsonb_build_object('status','ALREADY_RUNNING','raceId',v_race.id);end if;
 select count(*)::int into v_count from my_derby.race_entries
 where race_id=v_race.id and status in ('CONFIRMED','COMPLETED');
 if v_count<2 or v_count>12 then raise exception 'NEED_2_TO_12_CONFIRMED_HORSES' using errcode='23514';end if;
 if exists(
  select 1 from my_derby.race_entries e
  join my_derby.horses h on h.id=e.horse_id
  where e.race_id=v_race.id and e.status in ('CONFIRMED','COMPLETED')
    and (h.life_stage<>'RACING' or h.racing_retired_permanently
       or h.breeding_retired_at is not null
       or h.source_meet is distinct from (v_race.prize_policy->>'source_meet'))
 ) then raise exception 'ENTRY_INELIGIBLE_RETIRED_OR_WRONG_REGION' using errcode='23514';end if;
 select jsonb_agg(jsonb_build_object(
  'id',h.id::text,'number',e.gate_no,'name',h.name,'gate',e.gate_no,
  'horse',a.current_stats,'jockey',j.skill_stats,
  'strategies',coalesce(e.snapshot->'strategies','["FREE"]'::jsonb),
  'condition',h.condition_score,'fatigue',h.fatigue,'weightKg',e.weight_kg,
  'distanceFit',coalesce(nullif(a.distance_affinity->>(v_race.distance_m::text),'')::numeric,75),
  'trainerReadiness',coalesce((e.snapshot->>'trainerReadiness')::numeric,75)
 ) order by e.gate_no)
 into v_entries from my_derby.race_entries e
 join my_derby.horses h on h.id=e.horse_id
 join my_derby.horse_abilities a on a.horse_id=e.horse_id
 join my_derby.npc_jockeys j on j.id=e.jockey_id and j.is_active
 where e.race_id=v_race.id and e.status in ('CONFIRMED','COMPLETED')
   and e.gate_no is not null and e.weight_kg is not null;
 if v_entries is null or jsonb_array_length(v_entries)<>v_count then
  raise exception 'MISSING_RACE_ABILITY_JOCKEY_OR_GATE' using errcode='23514';end if;
 if p_preview then v_seed:=floor(random()*2147483646)::int+1;
  return jsonb_build_object('status','PREVIEW','raceId',v_race.id,'input',
   jsonb_build_object('raceId',v_race.id,'track',v_race.track,
    'distanceM',v_race.distance_m,'seed',v_seed,'runners',v_entries));
 end if;
 select * into v_run from my_derby.race_runs where race_id=v_race.id for update;
 if found then
  if v_run.status='FINISHED' then
   return jsonb_build_object('status','ALREADY_FINISHED','raceId',v_race.id);end if;
  v_input:=v_run.race_input;
  update my_derby.race_runs
   set status='RUNNING',claimed_at=now() where id=v_run.id;
 else
  v_seed:=floor(random()*2147483646)::integer+1;
  v_input:=jsonb_build_object('raceId',v_race.id,'track',v_race.track,
   'distanceM',v_race.distance_m,'seed',v_seed,'runners',v_entries);
  insert into my_derby.race_runs(race_id,race_input,random_seed,balance_version,
   tick_seconds,status,claimed_at,engine_version)
  values(v_race.id,v_input,v_seed,v_world.balance_version,0.2,'RUNNING',now(),'0.1.0')
  returning * into v_run;
 end if;
 update my_derby.races set status='RUNNING' where id=v_race.id;
 insert into my_derby.official_race_process_audit(race_id,slot_time,action,event_detail)
 values(v_race.id,v_hour,case when p_force then 'MANUAL_FORCE_CLAIM' else 'CRON_CLAIM' end,
  jsonb_build_object('runId',v_run.id,'seed',v_run.random_seed));
 return jsonb_build_object('status','CLAIMED','raceId',v_race.id,'runId',v_run.id,'input',v_input);
end;
$function$
;

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
 if jsonb_array_length(p_result->'results')<>v_count or v_count<2 or v_count>12
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
$function$
;

revoke all on function my_derby.secure_official_race_input(text,integer,boolean,boolean) from public;
grant execute on function my_derby.secure_official_race_input(text,integer,boolean,boolean) to anon;
revoke all on function my_derby.secure_official_race_finalize(text,uuid,jsonb) from public;
grant execute on function my_derby.secure_official_race_finalize(text,uuid,jsonb) to anon;
revoke all on function my_derby.world_scheduler_configured() from public;
grant execute on function my_derby.world_scheduler_configured() to anon,authenticated;
revoke all on function my_derby_private.extend_official_race_program(integer) from public,anon,authenticated;
revoke all on function my_derby_private.send_race_slot(integer) from public,anon,authenticated;
revoke all on function my_derby_private.send_upcoming_program() from public,anon,authenticated;
select cron.schedule('my-derby-1900','0,5,10,15 10 * * *','select my_derby_private.send_race_slot(0);');
select cron.schedule('my-derby-2000','0,5,10,15 11 * * *','select my_derby_private.send_race_slot(1);');
select cron.schedule('my-derby-2100','0,5,10,15 12 * * *','select my_derby_private.send_race_slot(2);');
select cron.schedule('my-derby-program-refresh','5 0 * * *','select my_derby_private.send_upcoming_program();');
notify pgrst,'reload schema';
