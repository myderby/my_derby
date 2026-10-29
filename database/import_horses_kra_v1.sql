-- Run this after uploading the result JSONL to my_derby.horse_import_stage.
-- This import does NOT create official races, race entries, wallet transactions or prize payouts.
insert into my_derby.worlds(name,game_day,season_number,balance_version,status)
select '실경주 기록 기반 경주마 능력치 검증 월드 (kra_v1)',1,1,'economy_v2','PAUSED'
where not exists (select 1 from my_derby.worlds where name='실경주 기록 기반 경주마 능력치 검증 월드 (kra_v1)');

with w as (select id from my_derby.worlds where name='실경주 기록 기반 경주마 능력치 검증 월드 (kra_v1)' limit 1)
insert into my_derby.horses
(world_id,source_hr_no,source_meet,source_birth_date,source_last_race_date,
 source_record_count,source_model_version,name,sex,age_years,life_stage,location,condition_score,fatigue)
select w.id,s.hr_no,s.payload->>'meet',
 case when s.payload->>'birthday' ~ '^[0-9]{8}$'
  then to_date(s.payload->>'birthday','YYYYMMDD') else null end,
 to_date(s.payload->>'lastRaceDate','YYYYMMDD'),(s.payload->>'runs')::integer,
 'kra_v1',s.payload->>'hrName',s.payload->>'sex',
 (s.payload->>'age')::integer,
 'RACING','NPC_STABLE',80,0
from my_derby.horse_import_stage s cross join w
where s.import_version='kra_v1'
on conflict (world_id,source_hr_no) where source_hr_no is not null do nothing;

insert into my_derby.horse_abilities
(horse_id,current_stats,potential_stats,gene_stats,public_estimates,distance_affinity,
 hidden_traits,estimation_metadata,updated_at)
select h.id,
 s.payload->'current',s.payload->'potential','{}'::jsonb,
 s.payload->'current',s.payload->'distanceAffinity',s.payload->'hiddenTraits',
 (s.payload->'metadata') ||
 jsonb_build_object('source_hr_no',s.hr_no,
  'source_name',s.payload->>'hrName',
  'first_race_date',s.payload->>'firstRaceDate',
  'last_race_date',s.payload->>'lastRaceDate',
  'wins',(s.payload->>'wins')::integer,
  'top3',(s.payload->>'top3')::integer,
  'birth_date',s.payload->>'birthday',
  'source_last_class',s.payload->>'lastRank',
  'reference_world_only',true,
  'current_condition_is_placeholder',true,
  'growth_potential_is_estimated',true),now()
from my_derby.horse_import_stage s
join my_derby.horses h on h.source_hr_no=s.hr_no
join my_derby.worlds w on w.id=h.world_id
where s.import_version='kra_v1'
 and w.name='실경주 기록 기반 경주마 능력치 검증 월드 (kra_v1)'
on conflict (horse_id)
do update set current_stats=excluded.current_stats,
 potential_stats=excluded.potential_stats,
 public_estimates=excluded.public_estimates,
 distance_affinity=excluded.distance_affinity,
 hidden_traits=excluded.hidden_traits,
 estimation_metadata=excluded.estimation_metadata,
 updated_at=now();
