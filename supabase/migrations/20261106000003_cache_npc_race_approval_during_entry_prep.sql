-- Cache the once-per-horse NPC owner decision during one day’s race field preparation.
-- The decision depends on the horse and game day, not the individual race.
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
 if exists(select 1 from my_derby.races x where x.world_id=w and x.race_day=p_game_day and x.status='OPEN'
  and (x.prize_policy->>'kst_date')::timestamp+interval '7 hours 59 minutes'>(now() at time zone 'Asia/Seoul'))
 then return jsonb_build_object('status','AWAITING_0759','addedEntries',0);end if;

 create temp table if not exists pg_temp.npc_program_owner_decisions(
   horse_id uuid primary key,
   decision jsonb not null
 ) on commit drop;
 truncate table pg_temp.npc_program_owner_decisions;

 insert into pg_temp.npc_program_owner_decisions(horse_id,decision)
 select hh.id,my_derby_private.npc_owner_race_preference(hh.id,p_game_day)
 from my_derby.horses hh
 where hh.world_id=w
   and hh.npc_owner_id is not null
   and hh.life_stage='RACING'
   and hh.health_state='HEALTHY'
   and hh.injury_prognosis<>'RACING_UNFIT'
   and hh.racing_retired_permanently=false
   and hh.breeding_retired_at is null
   and hh.age_years between 2 and 10
   and exists(
     select 1 from my_derby.races candidate_race
     where candidate_race.world_id=w
       and candidate_race.race_day=p_game_day
       and candidate_race.status='OPEN'
       and candidate_race.prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
       and candidate_race.prize_policy->>'source_meet'=hh.source_meet
       and (candidate_race.prize_policy->>'grade_no')::smallint=hh.source_grade_no
   )
   and not exists(
     select 1
     from my_derby.race_entries existing_entry
     join my_derby.races existing_race on existing_race.id=existing_entry.race_id
     where existing_race.race_day=p_game_day
       and existing_race.world_id=w
       and existing_race.status<>'CANCELLED'
       and existing_entry.horse_id=hh.id
       and existing_entry.status in ('APPLIED','CONFIRMED','COMPLETED')
   );

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
   select hh.id,hh.name,hh.source_meet,a.current_stats,
          cached_decision.decision as owner_decision
   from my_derby.horses hh
   join my_derby.horse_abilities a on a.horse_id=hh.id
   join pg_temp.npc_program_owner_decisions cached_decision
     on cached_decision.horse_id=hh.id
    and cached_decision.decision->>'accepted'='true'
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
   order by hh.condition_score desc,hh.fatigue,md5(hh.id::text||':'||r.id::text)
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
        and rr.status<>'CANCELLED'),my_derby_private.jockey_offer_score(r.id,h.id,j.id) desc nulls last,md5(j.id::text||r.id::text)
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
       'ownerDecision',h.owner_decision,
       'npcJockeySelection','AUTO_HOME_TRACK_PREFERENCE_V2',
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
  PERFORM my_derby_private.recalculate_official_handicap_race(r.id);
 end loop;
 return jsonb_build_object('gameDay',p_game_day,'addedEntries',total_added,
  'readyRaces',ready,'insufficientRaces',missing);
end $function$;
