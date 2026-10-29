-- MY DERBY V4 world owner distribution & player onboarding (designed to run once).
-- Core tables horses/worlds/npc_owners/profiles/ranches must already exist.
-- Calendar configuration: 1 real KST day = 1 simulation week (7 game days); season = 52 real days.
-- NOTE: operational economy_v2 tick and automatic races are NOT enabled.
alter table my_derby.worlds
 add column if not exists world_key text,
 add column if not exists season_anchor_date date,
 add column if not exists timezone text not null default 'Asia/Seoul',
 add column if not exists real_days_per_season integer not null default 52,
 add column if not exists game_days_per_real_day integer not null default 7,
 add column if not exists race_slots time[] not null default array['19:00'::time,'20:00'::time,'21:00'::time],
 add column if not exists automatic_processing_enabled boolean not null default false;
create unique index if not exists ux_myderby_world_key on my_derby.worlds(world_key) where world_key is not null;
update my_derby.worlds set world_key='kra_roster_v1',
 season_anchor_date=(now() at time zone 'Asia/Seoul')::date,automatic_processing_enabled=false
where name='실경주 기록 기반 경주마 능력치 검증 월드 (kra_v1)' and world_key is null;
create unique index if not exists ux_myderby_npc_owner_world_name on my_derby.npc_owners(world_id,name);

create or replace function my_derby.world_clock(p_world_id uuid)
returns jsonb language plpgsql stable security invoker set search_path=''
as $fn$
declare
 v_world my_derby.worlds%rowtype;
 v_today date:=((now() at time zone 'Asia/Seoul')::date);
 v_elapsed int;v_live boolean;v_game_day int;v_season int;v_week int;
begin
 select * into v_world from my_derby.worlds where id=p_world_id;
 if not found then return null;end if;
 v_live:=(v_world.status='ACTIVE' and v_world.season_anchor_date is not null);
 v_elapsed:=greatest(0,v_today-coalesce(v_world.season_anchor_date,v_today));
 v_season:=case when v_live then (v_elapsed/52)+1 else v_world.season_number end;
 v_week:=case when v_live then (v_elapsed%52)+1 else (((v_world.game_day-1)/7)%52)+1 end;
 v_game_day:=case when v_live then v_elapsed*7+1 else v_world.game_day end;
 return jsonb_build_object(
  'worldId',v_world.id,'worldKey',v_world.world_key,'status',v_world.status,
  'timezone','Asia/Seoul','kstDate',v_today,'anchorDate',v_world.season_anchor_date,
  'season',v_season,'week',v_week,'gameDayStart',v_game_day,
  'gameDaysPerRealDay',7,'realDaysPerSeason',52,
  'raceSlots',jsonb_build_array('19:00','20:00','21:00'),
  'calendarAdvancing',v_live,'automaticProcessingEnabled',v_world.automatic_processing_enabled,
  'schedulerConfigured',false,
  'seasonTransitionPolicy','52 Korean calendar days => next season; aging and economics require server processor');
end $fn$;
revoke all on function my_derby.world_clock(uuid) from public;
grant execute on function my_derby.world_clock(uuid) to anon,authenticated;

create or replace function my_derby.world_overview()
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_world uuid;v_clock jsonb;v_total int;v_npc int;v_players int;v_reserved int;v_owners int;
begin
 select id into v_world from my_derby.worlds where world_key='kra_roster_v1';
 if v_world is null then return jsonb_build_object('ready',false);end if;
 select count(*)::int,count(*) filter(where npc_owner_id is not null)::int,
  count(*) filter(where owner_user_id is not null)::int,
  count(*) filter(where owner_user_id is null and npc_owner_id is null)::int
 into v_total,v_npc,v_players,v_reserved from my_derby.horses where world_id=v_world;
 select count(*)::int into v_owners from my_derby.npc_owners where world_id=v_world;
 v_clock:=my_derby.world_clock(v_world);
 return jsonb_build_object('ready',true,'world',v_clock,'horseCount',v_total,
  'npcOwnedHorses',v_npc,'playerOwnedHorses',v_players,
  'reservedHorses',v_reserved,'npcOwnerCount',v_owners,'starterHorsesPerPlayer',3);
end $fn$;
revoke all on function my_derby.world_overview() from public;
grant execute on function my_derby.world_overview() to anon,authenticated;

create or replace function my_derby.join_world(p_nickname text)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_uid uuid:=(select auth.uid());v_world uuid;v_prev my_derby.profiles%rowtype;v_existing int;v_assigned int;
begin
 if v_uid is null then raise exception 'LOGIN_REQUIRED' using errcode='42501';end if;
 if p_nickname is null or char_length(btrim(p_nickname))<2 or char_length(btrim(p_nickname))>32
 then raise exception 'NICKNAME_LENGTH_2_32' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('myderby-world-join:'||v_uid::text,0));
 select id into v_world from my_derby.worlds where world_key='kra_roster_v1';
 if v_world is null then raise exception 'WORLD_NOT_READY' using errcode='23514';end if;
 select * into v_prev from my_derby.profiles where user_id=v_uid for update;
 if found and v_prev.world_id is not null and v_prev.world_id<>v_world then
   raise exception 'ALREADY_JOINED_ANOTHER_WORLD' using errcode='23514';end if;
 if found and v_prev.initial_setup_complete then
   select count(*)::int into v_existing from my_derby.horses where owner_user_id=v_uid and world_id=v_world;
   return jsonb_build_object('joined',true,'alreadyJoined',true,'worldId',v_world,'ownedHorses',v_existing);
 end if;
 select count(*)::int into v_existing from my_derby.horses where owner_user_id=v_uid and world_id=v_world;
 if v_existing<>0 then raise exception 'PARTIAL_ONBOARDING_REQUIRES_REVIEW' using errcode='23514';end if;
 insert into my_derby.profiles(user_id,nickname,world_id,initial_setup_complete)
 values(v_uid,btrim(p_nickname),v_world,false)
 on conflict(user_id) do update set world_id=excluded.world_id,
 nickname=excluded.nickname,updated_at=now();
 with selected as (
   select id from my_derby.horses where world_id=v_world
   and owner_user_id is null and npc_owner_id is null
   and source_model_version='kra_v1' and life_stage='RACING'
   and racing_retired_permanently=false and breeding_retired_at is null
   and age_years between 2 and 6
   order by pg_catalog.random() limit 3 for update skip locked
 )
 update my_derby.horses h set owner_user_id=v_uid,location='NPC_STABLE'
 from selected s where h.id=s.id;
 get diagnostics v_assigned=row_count;
 if v_assigned<>3 then raise exception 'STARTER_HORSES_UNAVAILABLE' using errcode='23514';end if;
 insert into my_derby.ranches(owner_user_id,name)
 values(v_uid,btrim(p_nickname)||' 목장')
 on conflict(owner_user_id) do nothing;
 update my_derby.profiles set initial_setup_complete=true,updated_at=now() where user_id=v_uid;
 return jsonb_build_object('joined',true,'alreadyJoined',false,'worldId',v_world,'ownedHorses',v_assigned);
end $fn$;
revoke all on function my_derby.join_world(text) from public,anon;
grant execute on function my_derby.join_world(text) to authenticated;

create or replace function my_derby.create_initial_ranch_facilities()
returns trigger language plpgsql set search_path=''
as $fn$
begin
 insert into my_derby.ranch_facilities(ranch_id,facility_type,level,capacity)
 select new.id,facility_type,1,case when facility_type='PASTURE' then 3 else 1 end
 from unnest(array['PASTURE','RECOVERY_STABLE','REHAB_TRACK','VET_CLINIC','YOUNG_HORSE_AREA']) facility_type
 on conflict(ranch_id,facility_type) do nothing;
 return new;
end $fn$;
drop trigger if exists trg_initial_ranch_facilities on my_derby.ranches;
create trigger trg_initial_ranch_facilities after insert on my_derby.ranches
 for each row execute function my_derby.create_initial_ranch_facilities();

create or replace function my_derby.world_npc_standings()
returns jsonb language sql stable security definer set search_path=''
as $fn$
 select coalesce(jsonb_agg(jsonb_build_object('ownerName',ranked.name,'horseCount',ranked.horses,
   'risk',ranked.policy->>'risk') order by ranked.horses desc,ranked.name),'[]'::jsonb)
 from (select o.name,o.policy,count(h.id)::int horses from my_derby.npc_owners o
  join my_derby.worlds w on w.id=o.world_id and w.world_key='kra_roster_v1'
  left join my_derby.horses h on h.npc_owner_id=o.id
  group by o.id,o.name,o.policy order by horses desc,o.name limit 15) ranked;
$fn$;
revoke all on function my_derby.world_npc_standings() from public;
grant execute on function my_derby.world_npc_standings() to anon,authenticated;
revoke select on my_derby.horse_abilities from authenticated;
grant select(horse_id,current_stats,public_estimates,distance_affinity) on my_derby.horse_abilities to authenticated;

-- To (re)seed the NPC owners and ~80% allocation on a fresh project:
-- See database/seed_npc_owners_v4.sql.
-- Keep the world PAUSED with automatic_processing_enabled=false until
-- server-authoritative economy_v2 + training + season aging + slot scheduler ship.
notify pgrst,'reload schema';
