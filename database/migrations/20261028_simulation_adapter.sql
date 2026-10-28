-- MY DERBY: non-official racing connector. Run after base my_derby schema migration.
-- This file is idempotent. It deliberately does not alter any official race results or economics.
create table if not exists my_derby.race_test_fixtures(
 slot smallint primary key check(slot between 0 and 2),
 label text not null,
 race_input jsonb not null,
 is_test_only boolean not null default true,
 updated_at timestamptz not null default now(),
 constraint fixture_structure check(race_input ? 'runners' and race_input ? 'distanceM' and race_input ? 'seed')
);
comment on table my_derby.race_test_fixtures is 'Test-only inputs; never official race or prizes.';
alter table my_derby.race_test_fixtures enable row level security;
grant usage on schema my_derby to anon,authenticated,service_role;
grant select on my_derby.race_test_fixtures to anon,authenticated;
drop policy if exists public_test_fixture_read on my_derby.race_test_fixtures;
create policy public_test_fixture_read on my_derby.race_test_fixtures
 for select to anon,authenticated using(is_test_only=true);

create table if not exists my_derby.race_simulation_previews(
 id uuid primary key default gen_random_uuid(),
 owner_user_id uuid not null references auth.users(id) on delete cascade,
 race_id uuid not null references my_derby.races(id) on delete cascade,
 input_snapshot jsonb not null,
 result_snapshot jsonb not null,
 engine_version text not null,
 random_seed bigint not null,
 created_at timestamptz not null default now()
);
comment on table my_derby.race_simulation_previews is 'User-owned NON-OFFICIAL simulation history; no purse or points.';
create index if not exists idx_race_sim_preview_owner on my_derby.race_simulation_previews(owner_user_id,created_at desc);
create index if not exists idx_race_sim_preview_race on my_derby.race_simulation_previews(race_id);
alter table my_derby.race_simulation_previews enable row level security;
grant select,insert on my_derby.race_simulation_previews to authenticated;
drop policy if exists own_sim_previews_read on my_derby.race_simulation_previews;
create policy own_sim_previews_read on my_derby.race_simulation_previews
 for select to authenticated using(owner_user_id=(select auth.uid()));
drop policy if exists own_sim_previews_insert on my_derby.race_simulation_previews;
create policy own_sim_previews_insert on my_derby.race_simulation_previews
 for insert to authenticated with check(
  owner_user_id=(select auth.uid())
  and exists(select 1 from my_derby.race_entries e
    where e.race_id=my_derby.race_simulation_previews.race_id
      and e.owner_user_id=(select auth.uid()))
 );

create or replace function my_derby.race_entry_count_for_participant(p_race_id uuid)
returns integer language plpgsql security definer set search_path = ''
as $$
begin
 if auth.uid() is null or not exists(
   select 1 from my_derby.race_entries e
   where e.race_id=p_race_id and e.owner_user_id=auth.uid()
 ) then
   return null;
 end if;
 return (select count(*)::int from my_derby.race_entries e
         where e.race_id=p_race_id and e.status in('CONFIRMED','COMPLETED'));
end;
$$;
revoke all on function my_derby.race_entry_count_for_participant(uuid) from public,anon;
grant execute on function my_derby.race_entry_count_for_participant(uuid) to authenticated;
grant all on my_derby.race_test_fixtures,my_derby.race_simulation_previews to service_role;
notify pgrst, 'reload schema';

-- IMPORTANT! Expose my_derby via Supabase Dashboard > Data API > Exposed schemas.
-- Existing project also has horse_media_ai exposed. Never overwrite other exposed schemas.
-- In this project's managed authenticator role the following was applied separately:
-- ALTER ROLE authenticator SET pgrst.db_schemas='public, graphql_public, horse_media_ai, my_derby';
-- NOTIFY pgrst, 'reload config';
-- The three initial TEST fixtures are seeded in the connected project, but are not recreated here.
-- Under no circumstances treat race_simulation_previews as race_results.
