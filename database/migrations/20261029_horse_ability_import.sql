-- MY DERBY historical race horse ability import v1
-- One imported horse per (world_id, source_hr_no) and privacy-safe hidden attributes.
alter table my_derby.horses
 add column if not exists source_hr_no text,
 add column if not exists source_meet text,
 add column if not exists source_birth_date date,
 add column if not exists source_last_race_date date,
 add column if not exists source_record_count integer,
 add column if not exists source_model_version text;
create unique index if not exists uq_my_derby_horses_world_hr_no
 on my_derby.horses(world_id,source_hr_no) where source_hr_no is not null;
alter table my_derby.horse_abilities
 add column if not exists hidden_traits jsonb not null default '{}'::jsonb,
 add column if not exists estimation_metadata jsonb not null default '{}'::jsonb;
comment on column my_derby.horse_abilities.hidden_traits is
 'Private inferred abilities from performance history; not proven genetic traits';
comment on column my_derby.horse_abilities.potential_stats is
 'Potential growth forecast from observed historical results; not a guaranteed ceiling.';
create table if not exists my_derby.horse_import_stage (
 hr_no text primary key,
 payload jsonb not null,
 import_version text not null default 'kra_v1',
 updated_at timestamptz not null default now(),
 constraint horse_import_stage_numeric_id check (hr_no ~ '^[0-9]{7,}$'),
 constraint horse_import_stage_name_present check (length(trim(payload->>'hrName')) > 0)
);
alter table my_derby.horse_import_stage enable row level security;
revoke all on my_derby.horse_import_stage from public,anon,authenticated;
grant all on my_derby.horse_import_stage to service_role;
