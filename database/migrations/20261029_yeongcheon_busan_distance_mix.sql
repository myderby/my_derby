-- My Derby: Yeongcheon uses Busan's race-distance mix (2025 programme v1).
-- The original 제주 distance_m is immutable; game_distance_m is a virtual game override.
alter table my_derby.race_program_source_2025
  add column if not exists game_distance_m integer;
alter table my_derby.race_program_source_2025
  drop constraint if exists game_distance_jeju_only;
alter table my_derby.race_program_source_2025
  add constraint game_distance_jeju_only
  check(game_distance_m is null or
     (source_meet='제주' and game_distance_m in(1000,1200,1300,1400,1600,1800,2000)));
comment on column my_derby.race_program_source_2025.game_distance_m
 is 'Game distance for Yeongcheon, using Busan 2025 proportions. Original CSV distance_m is preserved.';

do $block$
declare n_busan integer;n_jeju integer;n_ran integer;
begin
 select count(*) into n_busan from my_derby.race_program_source_2025 where source_meet='부산경남';
 select count(*) into n_jeju from my_derby.race_program_source_2025 where source_meet='제주';
 if n_busan<>703 or n_jeju<>707 then
   raise exception 'UNEXPECTED_SOURCE_COUNTS Busan %, Jeju %',n_busan,n_jeju;
 end if;
 select count(*) into n_ran from my_derby.races r
 where r.track='영천' and r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
   and (r.status in ('RUNNING','FINISHED')
     or exists(select 1 from my_derby.race_runs rr where rr.race_id=r.id));
 if n_ran>0 then raise exception 'CANNOT_MODIFY_STARTED_RACES count %',n_ran;end if;
end $block$;

-- Largest-remainder proportional quota: 13/192/96/150/128/114/14 = 707.
-- Deterministic rank-by-original-distance assignment minimizes rank inversions.
with totals as(
 select (select count(*)::numeric from my_derby.race_program_source_2025
          where source_meet='제주') as jeju_n,
        (select count(*)::numeric from my_derby.race_program_source_2025
          where source_meet='부산경남') as busan_n
), busan as(
 select distance_m,count(*)::int as n from my_derby.race_program_source_2025
 where source_meet='부산경남' group by distance_m
), quotas as(
 select b.distance_m,
  floor(b.n*t.jeju_n/t.busan_n)::int as initial,
  b.n*t.jeju_n/t.busan_n-floor(b.n*t.jeju_n/t.busan_n) as remainder,
  t.jeju_n::int as total
 from busan b cross join totals t
), ranked as(
 select *,row_number() over(order by remainder desc,distance_m) as remainder_order from quotas
), targets as(
 select distance_m,initial+
  case when remainder_order<=(max(total) over()-sum(initial) over()) then 1 else 0 end as quota
 from ranked
), boundaries as(
 select distance_m,
   (sum(quota) over(order by distance_m)-quota)::int as start_no,
   sum(quota) over(order by distance_m)::int as end_no
 from targets
), originals as(
 select source_date,source_rc_no,
  row_number() over(order by distance_m,source_date,source_rc_no)::int as ordinal
 from my_derby.race_program_source_2025 where source_meet='제주'
)
update my_derby.race_program_source_2025 s
set game_distance_m=b.distance_m
from originals o join boundaries b on o.ordinal>b.start_no and o.ordinal<=b.end_no
where s.source_meet='제주'
 and s.source_date=o.source_date and s.source_rc_no=o.source_rc_no
 and s.game_distance_m is distinct from b.distance_m;

-- Keep the same virtual distance for future copies of a CSV programme race.
create or replace function my_derby_private.apply_yeongcheon_game_distance()
returns trigger language plpgsql set search_path=''
as $fn$
declare source_distance integer;game_distance integer;
begin
 if new.track='영천'
   and new.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2' then
   select s.distance_m,s.game_distance_m into source_distance,game_distance
   from my_derby.race_program_source_2025 s
   where s.source_meet='제주'
     and s.source_date=(new.prize_policy->>'source_date')::date
     and s.source_rc_no=(new.prize_policy->>'source_rc_no')::smallint;
   if game_distance is null then
     raise exception 'MISSING_YEONGCHEON_DISTANCE source race %',new.id;
   end if;
   new.distance_m:=game_distance;
   new.prize_policy:=new.prize_policy||
     jsonb_build_object('source_distance_m',source_distance,
                        'game_distance_m',game_distance,
                        'distance_policy','busan_7_distance_proportions_v1');
 end if;
 return new;
end $fn$;
drop trigger if exists trg_yeongcheon_distance_policy on my_derby.races;
create trigger trg_yeongcheon_distance_policy
before insert or update of prize_policy on my_derby.races
for each row execute function my_derby_private.apply_yeongcheon_game_distance();

-- Update only unstarted active programme races; never touch entries, dusu or results.
update my_derby.races r
set prize_policy=r.prize_policy||
    jsonb_build_object('distance_policy','busan_7_distance_proportions_v1')
where r.track='영천'
  and r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  and r.status='OPEN';

do $verify$
declare count_source int;count_bad int;
begin
 select count(*) into count_source from my_derby.race_program_source_2025
  where source_meet='제주' and game_distance_m is not null;
 if count_source<>707 then raise exception 'INCOMPLETE_MAPPING %',count_source;end if;
 select count(*) into count_bad from my_derby.races r
  join my_derby.race_program_source_2025 s
    on s.source_meet='제주'
    and s.source_date=(r.prize_policy->>'source_date')::date
    and s.source_rc_no=(r.prize_policy->>'source_rc_no')::int
  where r.track='영천' and r.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
    and (r.distance_m is distinct from s.game_distance_m
      or (r.prize_policy->>'source_distance_m')::int is distinct from s.distance_m);
 if count_bad<>0 then raise exception 'SCHEDULE_DISTANCE_MISMATCH %',count_bad;end if;
end $verify$;
