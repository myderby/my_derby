-- Safeguard: diagnosed permanent injury horses cannot be selected by the legacy
-- NPC auto-fill functions. Their existing race slots are protected until a safe
-- replacement can be found; horse retirement is only for valid breeding conversion.
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
  and h.life_stage='RACING'
  and h.health_state='HEALTHY' and h.injury_prognosis<>'RACING_UNFIT' and not h.racing_retired_permanently
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
     and hh.health_state='HEALTHY' and hh.injury_prognosis<>'RACING_UNFIT'
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
end $function$
