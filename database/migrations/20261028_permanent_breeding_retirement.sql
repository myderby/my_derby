-- Irreversible racing retirement for breeding horses; applied to Supabase my_derby.
alter table my_derby.horses add column if not exists racing_retired_permanently boolean not null default false;
update my_derby.horses set racing_retired_permanently=true where life_stage in ('RETIRED','STALLION','BROODMARE');
create or replace function my_derby.enforce_irreversible_racing_retirement()
returns trigger language plpgsql set search_path = '' as $$
begin
 if tg_op='UPDATE' and old.racing_retired_permanently and
   (not new.racing_retired_permanently or new.life_stage='RACING') then
  raise exception 'RACING_RETIREMENT_PERMANENT: retired breeding horses cannot race.' using errcode='23514';
 end if;
 if new.life_stage in ('RETIRED','STALLION','BROODMARE') then
  new.racing_retired_permanently := true;
 end if;
 if new.racing_retired_permanently and new.life_stage='RACING' then
  raise exception 'RACING_RETIREMENT_PERMANENT: retired breeding horses cannot race.' using errcode='23514';
 end if;
 return new;
end $$;
drop trigger if exists trg_irreversible_racing_retirement on my_derby.horses;
create trigger trg_irreversible_racing_retirement before insert or update on my_derby.horses
for each row execute function my_derby.enforce_irreversible_racing_retirement();
create or replace function my_derby.reject_retired_race_entries()
returns trigger language plpgsql set search_path = '' as $$
declare v_stage text;v_locked boolean;
begin
 select h.life_stage,h.racing_retired_permanently into v_stage,v_locked
 from my_derby.horses h where h.id=new.horse_id for share;
 if not found or v_stage <> 'RACING' or v_locked then
  raise exception 'RACE_ENTRY_NOT_ELIGIBLE: only active racing horses can enter.' using errcode='23514';
 end if;
 return new;
end $$;
drop trigger if exists trg_reject_retired_race_entries on my_derby.race_entries;
create trigger trg_reject_retired_race_entries before insert or update of horse_id,status on my_derby.race_entries
for each row when (new.status in ('APPLIED','CONFIRMED')) execute function my_derby.reject_retired_race_entries();
create or replace function my_derby.reject_retired_breeding_mismatch()
returns trigger language plpgsql set search_path = '' as $$
declare v_stage text;v_sex text;v_locked boolean;
begin
 select h.life_stage,h.sex,h.racing_retired_permanently into v_stage,v_sex,v_locked
 from my_derby.horses h where h.id=new.mare_id for share;
 if v_stage is distinct from 'BROODMARE' or v_sex is distinct from 'FEMALE' or not coalesce(v_locked,false) then
  raise exception 'BREEDING_REQUIRES_RETIRED_BROODMARE: only retired broodmares can breed.' using errcode='23514';
 end if;
 return new;
end $$;
drop trigger if exists trg_breeding_requires_retired_mare on my_derby.breeding_requests;
create trigger trg_breeding_requires_retired_mare before insert or update of mare_id on my_derby.breeding_requests
for each row execute function my_derby.reject_retired_breeding_mismatch();
