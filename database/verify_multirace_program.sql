-- Read-only schedule checks.
select count(*) source_races from my_derby.race_program_source_2025;
select count(*) scheduled_races,count(distinct race_day) days from my_derby.races
 where prize_policy->>'schedule_version'='csv2025_rank_sttime_v2';
with x as(select r.*,prize_policy->>'slot_index' slot,
 lag(start_time) over(partition by race_day,prize_policy->>'slot_index' order by start_time) previous
 from my_derby.races r where prize_policy->>'schedule_version'='csv2025_rank_sttime_v2')
select count(*) filter(where previous is not null and start_time-previous<>interval '3 minutes') spacing_errors,
count(*) filter(where (prize_policy->>'result_kst_time')::time<>start_time+interval '3 minutes') result_delay_errors,
count(*) filter(where slot='0' and track not in ('부산','영천')
 or slot='1' and track not in ('서울','영천') or slot='2' and track not in ('서울','부산')) region_errors from x;
select jobname,schedule,active from cron.job where jobname like 'my-derby-%' order by jobname;
select world_key,status,automatic_processing_enabled from my_derby.worlds where world_key='kra_roster_v1';
