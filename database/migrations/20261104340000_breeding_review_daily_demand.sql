-- Run the crowded-demand breeding board review from the 10th same-day
-- application to a stallion. The real day is measured in Korea time and
-- includes both player requests and NPC applications.
CREATE OR REPLACE FUNCTION my_derby_private.stud_applications_today(
 p_sire_id uuid,p_at timestamptz DEFAULT now()
) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 WITH day_window AS (
  SELECT date_trunc('day',p_at AT TIME ZONE 'Asia/Seoul') AS local_day
 )
 SELECT
  (SELECT count(*)::integer FROM my_derby.breeding_requests br,day_window d
   WHERE br.sire_id=p_sire_id
    AND br.created_at >= (d.local_day AT TIME ZONE 'Asia/Seoul')
    AND br.created_at < ((d.local_day+interval '1 day') AT TIME ZONE 'Asia/Seoul'))
  +
  (SELECT count(*)::integer FROM my_derby.npc_breeding_cycles bc,day_window d
   WHERE bc.sire_id=p_sire_id
    AND bc.created_at >= (d.local_day AT TIME ZONE 'Asia/Seoul')
    AND bc.created_at < ((d.local_day+interval '1 day') AT TIME ZONE 'Asia/Seoul'));
$fn$;
REVOKE ALL ON FUNCTION my_derby_private.stud_applications_today(uuid,timestamptz)
 FROM PUBLIC,anon,authenticated;

DO $patch$
DECLARE v_definition text;v_original text;v_updated text;v_function regprocedure;
BEGIN
 v_function:='my_derby_private.review_breeding_pair(uuid,uuid,integer)'::regprocedure;
 v_definition:=pg_catalog.pg_get_functiondef(v_function);
 IF position('v_daily_count integer;' IN v_definition)=0 THEN
  v_definition:=replace(v_definition,'v_booked integer;v_shared integer;',
   'v_booked integer;v_daily_count integer;v_shared integer;');
 END IF;
 IF position('v_daily_count:=my_derby_private.stud_applications_today' IN v_definition)=0 THEN
  v_definition:=replace(v_definition,' RETURN jsonb_build_object(''required'',v_booked>=150,',
   ' v_daily_count:=my_derby_private.stud_applications_today(sire.id,now());'||E'\n'::text||
   ' RETURN jsonb_build_object(''required'',v_daily_count>=9,');
  v_definition:=replace(v_definition,
   '''demandBeforeRequest'',v_booked,',
   '''demandBeforeRequest'',v_booked,'||E'\n'::text||
   '  ''dailyApplicationsBeforeRequest'',v_daily_count,'||E'\n'::text||
   '  ''dailyApplicationNumber'',v_daily_count+1,'||E'\n'::text||
   '  ''dailyReviewThreshold'',10,');
  IF position('v_daily_count:=my_derby_private.stud_applications_today' IN v_definition)=0
   OR position('dailyReviewThreshold'',10' IN v_definition)=0 THEN
   RAISE EXCEPTION 'Could not safely update breeding review response';
  END IF;
  EXECUTE v_definition;
 END IF;

 v_function:='my_derby.player_breeding_pair_preview(uuid,uuid)'::regprocedure;
 v_definition:=pg_catalog.pg_get_functiondef(v_function);
 v_original:='v_booked:=my_derby_private.stud_booked_slots(sire.id,(c->>''season'')::int);';
 v_updated:='v_booked:=my_derby_private.stud_applications_today(sire.id,now());';
 IF position(v_original IN v_definition)>0 THEN
  v_definition:=replace(v_definition,v_original,v_updated);
 ELSIF position(v_updated IN v_definition)=0 THEN
  RAISE EXCEPTION 'Could not safely update breeding preview daily count';
 END IF;
 v_original:='v_booked>=150';
 v_updated:='v_booked>=9';
 IF position(v_original IN v_definition)>0 THEN
  v_definition:=replace(v_definition,v_original,v_updated);
 ELSIF position(v_updated IN v_definition)=0 THEN
  RAISE EXCEPTION 'Could not safely update breeding preview threshold';
 END IF;
 EXECUTE v_definition;

 v_function:='my_derby.player_apply_breeding(uuid,uuid)'::regprocedure;
 v_definition:=pg_catalog.pg_get_functiondef(v_function);
 v_original:='IF v_booked>=150 THEN';
 v_updated:='IF my_derby_private.stud_applications_today(sire.id,now())>=9 THEN';
 IF position(v_original IN v_definition)>0 THEN
  v_definition:=replace(v_definition,v_original,v_updated);
 ELSIF position(v_updated IN v_definition)=0 THEN
  RAISE EXCEPTION 'Could not safely update player breeding review threshold';
 END IF;
 EXECUTE v_definition;

 v_function:='my_derby_private.process_npc_breeding_pairs()'::regprocedure;
 v_definition:=pg_catalog.pg_get_functiondef(v_function);
 IF position('v_daily_count int;' IN v_definition)=0 THEN
  v_definition:=replace(v_definition,'v_count int:=0;',
   'v_count int:=0;v_daily_count int;');
 END IF;
 v_original:=$sql$v_count:=my_derby_private.stud_booked_slots(sire.id,v_season);
  IF v_count>=150 THEN$sql$;
 v_updated:=$sql$v_count:=my_derby_private.stud_booked_slots(sire.id,v_season);
  v_daily_count:=my_derby_private.stud_applications_today(sire.id,now());
  IF v_daily_count>=9 THEN$sql$;
 IF position(v_original IN v_definition)>0 THEN
  v_definition:=replace(v_definition,v_original,v_updated);
 ELSIF position('v_daily_count>=9' IN v_definition)=0 THEN
  RAISE EXCEPTION 'Could not safely update NPC breeding review threshold';
 END IF;
 EXECUTE v_definition;

 v_function:='my_derby.player_breeding_dashboard()'::regprocedure;
 v_definition:=pg_catalog.pg_get_functiondef(v_function);
 v_original:='demandReviewThreshold'',150';
 v_updated:='demandReviewThreshold'',10';
 IF position(v_original IN v_definition)>0 THEN
  EXECUTE replace(v_definition,v_original,v_updated);
 ELSIF position(v_updated IN v_definition)=0 THEN
  RAISE EXCEPTION 'Could not safely update displayed daily review threshold';
 END IF;
END;
$patch$;

NOTIFY pgrst,'reload schema';
