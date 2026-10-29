CREATE OR REPLACE FUNCTION my_derby.official_public_race_result(p_race_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_r my_derby.races%rowtype;v_run my_derby.race_runs%rowtype;
begin
 select * into v_r from my_derby.races where id=p_race_id;
 if not found then return null;end if;
 if v_r.status<>'FINISHED' then
  return jsonb_build_object('raceId',v_r.id,'status',v_r.status,
   'track',v_r.track,'className',v_r.class_name,'distanceM',v_r.distance_m,
   'startTime',v_r.start_time);end if;
 select * into v_run from my_derby.race_runs where race_id=v_r.id and status='FINISHED';
 if not found then return jsonb_build_object('raceId',v_r.id,'status','RESULT_NOT_AVAILABLE');end if;
 return jsonb_build_object(
  'raceId',v_r.id,'status','FINISHED','track',v_r.track,'distanceM',v_r.distance_m,
  'className',v_r.class_name,'startTime',v_r.start_time,
  'kstDate',v_r.prize_policy->>'kst_date','prizeStatus',v_r.prize_policy->>'prize_status',
  'engineVersion',v_run.engine_version,'completedAt',v_run.result_applied_at,
  'results',(select coalesce(jsonb_agg(
    jsonb_build_object('rank',res.finishing_rank,'number',ent.gate_no,
      'name',horse.name,'horseId',horse.id,'timeSec',res.finish_time_sec)
     order by res.finishing_rank),'[]'::jsonb)
   from my_derby.race_results res
   join my_derby.horses horse on horse.id=res.horse_id
   join my_derby.race_entries ent on ent.race_id=v_r.id and ent.horse_id=horse.id
   where res.race_run_id=v_run.id),
  'sections',(select coalesce(jsonb_agg(entry order by (entry->>'distanceM')::integer),'[]'::jsonb) from
    (select jsonb_build_object('distanceM',sec.distance_m,
        'ranks',jsonb_agg(jsonb_build_object('rank',sec.ranking,'name',h.name,
          'number',ent.gate_no,'gapM',sec.gap_m) order by sec.ranking)) as entry
     from my_derby.race_section_ranks sec
     join my_derby.horses h on h.id=sec.horse_id
     join my_derby.race_entries ent on ent.race_id=v_r.id and ent.horse_id=h.id
     where sec.race_run_id=v_run.id
     group by sec.distance_m) groups),
  'events',(select coalesce(jsonb_agg(jsonb_build_object('seq',e.seq,
      'timeSec',e.time_sec,'distanceM',e.distance_m,'eventType',e.event_type,
      'text',e.params->>'text') order by e.seq),'[]'::jsonb)
   from my_derby.race_event_logs e where e.race_run_id=v_run.id)
 );
end;$function$
; 
revoke all on function my_derby.official_public_race_result(uuid) from public;
grant execute on function my_derby.official_public_race_result(uuid) to anon,authenticated;
notify pgrst, 'reload schema';