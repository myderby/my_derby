alter table my_derby.races
  add column if not exists competition_name text,
  add column if not exists is_stakes boolean not null default false;

create table if not exists my_derby.player_tutorial_progress (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_step integer not null default 0 check (current_step between 0 and 5),
  completed boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table my_derby.player_tutorial_progress enable row level security;
drop policy if exists player_tutorial_progress_owner_all on my_derby.player_tutorial_progress;
create policy player_tutorial_progress_owner_all on my_derby.player_tutorial_progress
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
grant select, insert, update on my_derby.player_tutorial_progress to authenticated;

create table if not exists my_derby.achievement_definitions (
  achievement_key text primary key,
  category text not null,
  title text not null,
  description text not null,
  threshold numeric not null check (threshold > 0),
  subject_kind text not null default 'OWNER'
    check (subject_kind in ('OWNER','HORSE','TITLE')),
  competition_name text,
  display_order integer not null default 0
);
alter table my_derby.achievement_definitions enable row level security;
drop policy if exists achievement_definitions_read on my_derby.achievement_definitions;
create policy achievement_definitions_read on my_derby.achievement_definitions
  for select to authenticated using (true);
grant select on my_derby.achievement_definitions to authenticated;

create table if not exists my_derby.player_achievement_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_key text not null references my_derby.achievement_definitions(achievement_key) on delete cascade,
  subject_id uuid not null default '00000000-0000-0000-0000-000000000000',
  progress numeric not null default 0,
  unlocked_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, achievement_key, subject_id)
);
alter table my_derby.player_achievement_progress enable row level security;
drop policy if exists player_achievement_progress_owner_read on my_derby.player_achievement_progress;
create policy player_achievement_progress_owner_read on my_derby.player_achievement_progress
  for select to authenticated using ((select auth.uid()) = user_id);
grant select on my_derby.player_achievement_progress to authenticated;

create table if not exists my_derby_private.player_horse_achievement_stats (
  user_id uuid not null references auth.users(id) on delete cascade,
  horse_id uuid not null references my_derby.horses(id) on delete cascade,
  win_count integer not null default 0,
  current_streak integer not null default 0,
  best_streak integer not null default 0,
  last_race_day integer not null default 0,
  primary key (user_id, horse_id)
);
create table if not exists my_derby_private.achievement_processed_events (
  event_key text primary key,
  processed_at timestamptz not null default now()
);
create table if not exists my_derby_private.player_achievement_owner_stats (
  user_id uuid primary key references auth.users(id) on delete cascade,
  total_wins integer not null default 0,
  grade_wins jsonb not null default '{}'::jsonb,
  stakes_wins integer not null default 0
);

create or replace function my_derby_private.populate_race_competition()
returns trigger language plpgsql security definer set search_path=''
as $fn$
declare v_source_name text;v_year integer;v_day integer;
begin
  if new.competition_name is not null then return new;end if;
  v_year:=coalesce(nullif(new.prize_policy->>'template_year','')::integer,2025);
  v_day:=nullif(new.prize_policy->>'legacy_race_day','')::integer;
  if v_day is null then return new;end if;
  select s.original_rc_name into v_source_name
  from my_derby.race_program_source_2025 s
  where s.source_date=make_date(v_year,1,1)+(v_day-1)
    and s.source_meet=coalesce(new.prize_policy->>'source_meet',new.track)
    and s.source_rc_no=new.race_no
  limit 1;
  if v_source_name is null or btrim(v_source_name)='일반' then return new;end if;
  v_source_name:=btrim(split_part(v_source_name,'(',1));
  if v_source_name='코리아 스프린트' then v_source_name:='코리아스프린트';
  elsif v_source_name='부산광역시 강서구청장배' then v_source_name:='강서구청장배';
  elsif v_source_name like 'Rookie Stakes@%' then v_source_name:='브리더스컵 루키';
  end if;
  new.competition_name:=v_source_name;
  new.is_stakes:=v_source_name ~ '(컵|배|스테이크스|Stakes|더비|오크스|그랑프리|스프린트)';
  return new;
end
$fn$;
revoke all on function my_derby_private.populate_race_competition() from public,anon,authenticated;
drop trigger if exists trg_populate_race_competition on my_derby.races;
create trigger trg_populate_race_competition before insert on my_derby.races
  for each row execute function my_derby_private.populate_race_competition();

with mapped as (
  select r.id,
    case
      when s.original_rc_name ilike '코리아 스프린트%' then '코리아스프린트'
      when s.original_rc_name ilike '부산광역시 강서구청장배%' then '강서구청장배'
      when s.original_rc_name ilike 'Rookie Stakes@%' then '브리더스컵 루키'
      else btrim(split_part(s.original_rc_name,'(',1))
    end as competition_name,
    (s.original_rc_name ~ '(컵|배|스테이크스|Stakes|더비|오크스|그랑프리|스프린트)') as is_stakes
  from my_derby.races r
  join my_derby.race_program_source_2025 s
    on s.source_date=make_date(coalesce(nullif(r.prize_policy->>'template_year','')::integer,2025),1,1)
       +(nullif(r.prize_policy->>'legacy_race_day','')::integer-1)
   and s.source_meet=coalesce(r.prize_policy->>'source_meet',r.track)
   and s.source_rc_no=r.race_no
  where r.competition_name is null and s.original_rc_name is not null
)
update my_derby.races r set competition_name=m.competition_name,is_stakes=m.is_stakes
from mapped m where r.id=m.id and m.competition_name<>'일반';

insert into my_derby.achievement_definitions
  (achievement_key,category,title,description,threshold,subject_kind,display_order)
select 'career_wins_'||n,'CAREER_WINS',n||'승 마주','통산 우승 '||n||'회 달성',n,'OWNER',n
from (select 10 n union all select 50 union all select generate_series(100,5000,100)) s
on conflict (achievement_key) do update set title=excluded.title,description=excluded.description,threshold=excluded.threshold;

insert into my_derby.achievement_definitions
  (achievement_key,category,title,description,threshold,subject_kind,display_order)
select 'grade_'||g||'_wins_'||n,'GRADE_WINS',g||'등급 '||n||'승','해당 등급 통산 우승 '||n||'회 달성',n,'OWNER',g*10000+n
from generate_series(1,6) g
cross join (select 10 n union all select 50 union all select generate_series(100,5000,100)) t
on conflict (achievement_key) do update set title=excluded.title,description=excluded.description,threshold=excluded.threshold;

insert into my_derby.achievement_definitions
  (achievement_key,category,title,description,threshold,subject_kind,display_order)
select 'horse_wins_'||n,'HORSE_WINS','마필 '||n||'승','보유마가 통산 '||n||'승 달성',n,'HORSE',n
from (select 1 n union all select generate_series(5,500,5)) s
on conflict (achievement_key) do update set title=excluded.title,description=excluded.description,threshold=excluded.threshold;

insert into my_derby.achievement_definitions
  (achievement_key,category,title,description,threshold,subject_kind,display_order)
select 'horse_streak_'||n,'HORSE_STREAK','마필 '||n||'연승','보유마가 '||n||'연승 달성',n,'HORSE',n
from (select 2 n union all select generate_series(5,100,5)) s
on conflict (achievement_key) do update set title=excluded.title,description=excluded.description,threshold=excluded.threshold;

insert into my_derby.achievement_definitions
  (achievement_key,category,title,description,threshold,subject_kind,display_order)
select 'win_odds_'||n,'WIN_ODDS','단승 '||n||'배','단승식 적중 배당 '||n||'배 이상 달성',n,'OWNER',n
from (select 5 n union all select generate_series(10,1000,10)) s
on conflict (achievement_key) do update set title=excluded.title,description=excluded.description,threshold=excluded.threshold;

insert into my_derby.achievement_definitions
  (achievement_key,category,title,description,threshold,subject_kind,display_order)
select 'place_odds_'||n,'PLACE_ODDS','연승 '||n||'배','연승식 적중 배당 '||n||'배 이상 달성',n,'OWNER',n
from generate_series(3,100,1) n
on conflict (achievement_key) do update set title=excluded.title,description=excluded.description,threshold=excluded.threshold;

insert into my_derby.achievement_definitions
  (achievement_key,category,title,description,threshold,subject_kind,display_order)
select 'stakes_wins_'||n,'STAKES_WINS','대상경주 '||n||'승','대상경주 통산 우승 '||n||'회 달성',n,'OWNER',n
from generate_series(1,500,1) n
on conflict (achievement_key) do update set title=excluded.title,description=excluded.description,threshold=excluded.threshold;

insert into my_derby.achievement_definitions
  (achievement_key,category,title,description,threshold,subject_kind,competition_name,display_order)
values
('title_owners_cup','COMPETITION_TITLE','오너스 컵 우승자','오너스 컵 우승 호칭','1','TITLE','오너스 컵',1),
('title_korea_cup','COMPETITION_TITLE','코리아컵 우승자','코리아컵 우승 호칭','1','TITLE','코리아컵',2),
('title_presidents_cup','COMPETITION_TITLE','대통령배 우승자','대통령배 우승 호칭','1','TITLE','대통령배',3),
('title_dh_sprint','COMPETITION_TITLE','DH컵 스프린트 우승자','DH컵 스프린트 우승 호칭','1','TITLE','DH컵 스프린트',4),
('title_dh_classic','COMPETITION_TITLE','DH컵 클래식 우승자','DH컵 클래식 우승 호칭','1','TITLE','DH컵 클래식',5),
('title_korea_sprint','COMPETITION_TITLE','코리아스프린트 우승자','코리아스프린트 우승 호칭','1','TITLE','코리아스프린트',6),
('title_international_news','COMPETITION_TITLE','국제신문배 우승자','국제신문배 우승 호칭','1','TITLE','국제신문배',7),
('title_grand_prix','COMPETITION_TITLE','그랑프리 우승자','그랑프리 우승 호칭','1','TITLE','그랑프리',8),
('title_dh_mile','COMPETITION_TITLE','DH컵 마일 우승자','DH컵 마일 우승 호칭','1','TITLE','DH컵 마일',9),
('title_korean_derby','COMPETITION_TITLE','코리안더비 우승자','코리안더비 우승 호칭','1','TITLE','코리안더비',10),
('title_ministry_agriculture','COMPETITION_TITLE','농림축산식품부장관배 우승자','농림축산식품부장관배 우승 호칭','1','TITLE','농림축산식품부장관배',11),
('title_luna_stakes','COMPETITION_TITLE','루나 Stakes 우승자','루나 Stakes 우승 호칭','1','TITLE','루나Stakes',12),
('title_korean_oaks','COMPETITION_TITLE','코리안오크스 우승자','코리안오크스 우승 호칭','1','TITLE','코리안오크스',13),
('title_gyeonggi_governor','COMPETITION_TITLE','경기도지사배 우승자','경기도지사배 우승 호칭','1','TITLE','경기도지사배',14),
('title_busan_ilbo','COMPETITION_TITLE','부산일보배 우승자','부산일보배 우승 호칭','1','TITLE','부산일보배',15),
('title_sbs_sprint','COMPETITION_TITLE','SBS스포츠 스프린트 우승자','SBS스포츠 스프린트 우승 호칭','1','TITLE','SBS스포츠 스프린트',16),
('title_seoul_owners_assoc','COMPETITION_TITLE','서울마주협회장배 우승자','서울마주협회장배 우승 호칭','1','TITLE','서울마주협회장배',17),
('title_herald_economy','COMPETITION_TITLE','헤럴드경제배 우승자','헤럴드경제배 우승 호칭','1','TITLE','헤럴드 경제배',18),
('title_ytn','COMPETITION_TITLE','YTN배 우승자','YTN배 우승 호칭','1','TITLE','YTN배',19),
('title_busan_mayor','COMPETITION_TITLE','부산광역시장배 우승자','부산광역시장배 우승 호칭','1','TITLE','부산광역시장배',20),
('title_dong_a_ilbo','COMPETITION_TITLE','동아일보배 우승자','동아일보배 우승 호칭','1','TITLE','동아일보배',21),
('title_ttukseom','COMPETITION_TITLE','뚝섬배 우승자','뚝섬배 우승 호칭','1','TITLE','뚝섬배',22),
('title_knn','COMPETITION_TITLE','KNN배 우승자','KNN배 우승 호칭','1','TITLE','KNN배',23),
('title_jeju_governor','COMPETITION_TITLE','제주특별자치도지사배 우승자','제주특별자치도지사배 우승 호칭','1','TITLE','제주특별자치도지사배',24),
('title_gyeongsang_governor','COMPETITION_TITLE','경상남도지사배 우승자','경상남도지사배 우승 호칭','1','TITLE','경상남도지사배',25),
('title_breeders_queen','COMPETITION_TITLE','브리더스컵 퀸 우승자','브리더스컵 퀸 우승 호칭','1','TITLE','브리더스컵 퀸',26),
('title_gwacheon_market','COMPETITION_TITLE','과천시장배 우승자','과천시장배 우승 호칭','1','TITLE','과천시장배',27),
('title_nonghyup','COMPETITION_TITLE','농협중앙회장배 우승자','농협중앙회장배 우승 호칭','1','TITLE','농협중앙회장배',28),
('title_breeders_rookie','COMPETITION_TITLE','브리더스컵 루키 우승자','브리더스컵 루키 우승 호칭','1','TITLE','브리더스컵 루키',29),
('title_gangseo_gu','COMPETITION_TITLE','강서구청장배 우승자','강서구청장배 우승 호칭','1','TITLE','강서구청장배',30),
('title_gimhae_mayor','COMPETITION_TITLE','김해시장배 우승자','김해시장배 우승 호칭','1','TITLE','김해시장배',31)
on conflict (achievement_key) do update set title=excluded.title,description=excluded.description,
  competition_name=excluded.competition_name,category=excluded.category,threshold=excluded.threshold;

create or replace function my_derby_private.set_player_achievement_progress(
  p_user_id uuid,p_key text,p_subject_id uuid,p_value numeric
) returns void language plpgsql security definer set search_path=''
as $fn$
declare v_threshold numeric;
begin
  select threshold into v_threshold from my_derby.achievement_definitions
    where achievement_key=p_key;
  if v_threshold is null then return; end if;
  insert into my_derby.player_achievement_progress(user_id,achievement_key,subject_id,progress,unlocked_at)
    values(p_user_id,p_key,coalesce(p_subject_id,'00000000-0000-0000-0000-000000000000'),greatest(0,p_value),
      case when p_value>=v_threshold then now() else null end)
  on conflict(user_id,achievement_key,subject_id) do update set
    progress=greatest(my_derby.player_achievement_progress.progress,excluded.progress),
    unlocked_at=coalesce(my_derby.player_achievement_progress.unlocked_at,
      case when excluded.progress>=v_threshold then now() else null end),
    updated_at=now();
end
$fn$;
revoke all on function my_derby_private.set_player_achievement_progress(uuid,text,uuid,numeric) from public,anon,authenticated;

create or replace function my_derby_private.record_player_race_result()
returns trigger language plpgsql security definer set search_path=''
as $fn$
declare
  v_user uuid;v_race_id uuid;v_grade integer;v_day integer;v_stakes boolean;
  v_competition text;v_wins integer;v_streak integer;v_best integer;v_last_day integer;
  v_event_key text;v_total integer;v_grade_wins integer;v_stakes_wins integer;
  v_key text;v_threshold numeric;
begin
  select e.owner_user_id,r.id,coalesce(nullif(r.prize_policy->>'grade_no','')::integer,
      nullif(regexp_replace(r.class_name,'[^0-9]','','g'),'')::integer),
      r.race_day,r.is_stakes,r.competition_name
    into v_user,v_race_id,v_grade,v_day,v_stakes,v_competition
  from my_derby.race_runs rr
  join my_derby.races r on r.id=rr.race_id
  join my_derby.race_entries e on e.race_id=r.id and e.horse_id=new.horse_id
  where rr.id=new.race_run_id
  order by e.owner_user_id nulls last limit 1;
  if v_user is null then return new; end if;
  v_event_key:='result:'||new.id::text;
  insert into my_derby_private.achievement_processed_events(event_key)
    values(v_event_key) on conflict do nothing;
  if not found then return new; end if;

  insert into my_derby_private.player_horse_achievement_stats(user_id,horse_id)
    values(v_user,new.horse_id) on conflict do nothing;
  select win_count,current_streak,best_streak,last_race_day
    into v_wins,v_streak,v_best,v_last_day
    from my_derby_private.player_horse_achievement_stats
    where user_id=v_user and horse_id=new.horse_id for update;
  if v_day < v_last_day then return new; end if;

  if new.finishing_rank=1 then
    v_wins:=v_wins+1;
    v_streak:=case when v_day>v_last_day then v_streak+1 else greatest(v_streak,1) end;
    v_best:=greatest(v_best,v_streak);
    update my_derby_private.player_horse_achievement_stats
      set win_count=v_wins,current_streak=v_streak,best_streak=v_best,last_race_day=v_day
      where user_id=v_user and horse_id=new.horse_id;

    insert into my_derby_private.player_achievement_owner_stats(user_id) values(v_user)
      on conflict(user_id) do nothing;
    update my_derby_private.player_achievement_owner_stats s
      set total_wins=s.total_wins+1,
          grade_wins=case when v_grade between 1 and 6 then
            jsonb_set(s.grade_wins,array[v_grade::text],
              to_jsonb(coalesce((s.grade_wins->>v_grade::text)::integer,0)+1),true)
            else s.grade_wins end
      where s.user_id=v_user
      returning total_wins,coalesce((grade_wins->>v_grade::text)::integer,0)
      into v_total,v_grade_wins;
    for v_key in select achievement_key from my_derby.achievement_definitions where category='CAREER_WINS' loop
      perform my_derby_private.set_player_achievement_progress(v_user,v_key,null,v_total);
    end loop;
    if v_grade between 1 and 6 then
      for v_key in select achievement_key from my_derby.achievement_definitions
        where category='GRADE_WINS' and achievement_key like 'grade_'||v_grade||'_wins_%' loop
        perform my_derby_private.set_player_achievement_progress(v_user,v_key,null,v_grade_wins);
      end loop;
    end if;
    for v_key in select achievement_key from my_derby.achievement_definitions where category='HORSE_WINS' loop
      perform my_derby_private.set_player_achievement_progress(v_user,v_key,new.horse_id,v_wins);
    end loop;
    for v_key in select achievement_key from my_derby.achievement_definitions where category='HORSE_STREAK' loop
      perform my_derby_private.set_player_achievement_progress(v_user,v_key,new.horse_id,v_best);
    end loop;

    if v_stakes then
      update my_derby_private.player_achievement_owner_stats
        set stakes_wins=stakes_wins+1 where user_id=v_user returning stakes_wins into v_stakes_wins;
      for v_key in select achievement_key from my_derby.achievement_definitions where category='STAKES_WINS' loop
        perform my_derby_private.set_player_achievement_progress(v_user,v_key,null,v_stakes_wins);
      end loop;
      if v_competition is not null then
        for v_key in select achievement_key from my_derby.achievement_definitions
          where category='COMPETITION_TITLE' and lower(competition_name)=lower(v_competition) loop
          perform my_derby_private.set_player_achievement_progress(v_user,v_key,null,1);
        end loop;
      end if;
    end if;
  else
    update my_derby_private.player_horse_achievement_stats
      set current_streak=0,last_race_day=v_day
      where user_id=v_user and horse_id=new.horse_id;
  end if;
  return new;
end
$fn$;
revoke all on function my_derby_private.record_player_race_result() from public,anon,authenticated;
drop trigger if exists trg_player_achievement_race_result on my_derby.race_results;
create trigger trg_player_achievement_race_result after insert or update of finishing_rank on my_derby.race_results
  for each row execute function my_derby_private.record_player_race_result();

-- Backfill previously recorded player results once, in race order. Event keys make reruns idempotent.
do $backfill$
declare v record;
begin
  for v in
    select rr.id,rr.finishing_rank
    from my_derby.race_results rr
    join my_derby.race_runs ru on ru.id=rr.race_run_id
    join my_derby.races r on r.id=ru.race_id
    join my_derby.race_entries e on e.race_id=r.id and e.horse_id=rr.horse_id
    where e.owner_user_id is not null
    order by r.race_day,r.start_time,rr.id
  loop
    update my_derby.race_results set finishing_rank=v.finishing_rank where id=v.id;
  end loop;
end
$backfill$;

create or replace function my_derby_private.record_player_bet_achievement()
returns trigger language plpgsql security definer set search_path=''
as $fn$
declare v_odds numeric;v_category text;v_key text;v_threshold numeric;
begin
  if new.owner_user_id is null or new.status<>'WON' or new.amount<=0 or new.payout<=0 then return new;end if;
  if tg_op='UPDATE' and old.status='WON' then return new;end if;
  v_category:=case new.bet_type when 'WIN' then 'WIN_ODDS' when 'PLACE' then 'PLACE_ODDS' else null end;
  if v_category is null then return new;end if;
  v_odds:=new.payout::numeric/new.amount::numeric;
  for v_key,v_threshold in select achievement_key,threshold from my_derby.achievement_definitions
    where category=v_category and threshold<=v_odds loop
    perform my_derby_private.set_player_achievement_progress(new.owner_user_id,v_key,null,v_odds);
  end loop;
  return new;
end
$fn$;
revoke all on function my_derby_private.record_player_bet_achievement() from public,anon,authenticated;
drop trigger if exists trg_player_bet_achievement on my_derby.race_bets;
create trigger trg_player_bet_achievement after insert or update of status on my_derby.race_bets
  for each row execute function my_derby_private.record_player_bet_achievement();

notify pgrst,'reload schema';