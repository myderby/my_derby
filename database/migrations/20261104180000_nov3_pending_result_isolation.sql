-- Finalize only already-staged results from the requested historical date.
-- Other days' pending results remain untouched.
CREATE OR REPLACE FUNCTION my_derby.secure_backfill_finalize_pending_nov3(p_secret text,p_slot integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_row record;
 v_result jsonb;
 v_n integer:=0;
 v_ids jsonb:='[]'::jsonb;
BEGIN
 IF p_secret IS NULL OR p_secret IS DISTINCT FROM
   (SELECT secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner')
   THEN RAISE EXCEPTION 'OFFICIAL_AUTH_REQUIRED' USING errcode='42501'; END IF;
 IF p_slot NOT BETWEEN 0 AND 2 THEN RAISE EXCEPTION 'INVALID_SLOT'; END IF;
 FOR v_row IN
   SELECT p.race_id,p.run_id,p.result
   FROM my_derby_private.race_pending_results p
   JOIN my_derby.races r ON r.id=p.race_id
   WHERE p.due_at<=now() AND r.status='RUNNING'
     AND r.prize_policy->>'kst_date'='2026-11-03'
     AND (r.prize_policy->>'slot_index')::integer=p_slot
   ORDER BY p.due_at LIMIT 4 FOR UPDATE OF p SKIP LOCKED
 LOOP
   v_result:=my_derby.secure_official_race_finalize(p_secret,v_row.run_id,v_row.result);
   DELETE FROM my_derby_private.race_pending_results WHERE race_id=v_row.race_id;
   v_ids:=v_ids||jsonb_build_array(jsonb_build_object('raceId',v_row.race_id,'result',v_result));
   v_n:=v_n+1;
 END LOOP;
 RETURN jsonb_build_object('status',CASE WHEN v_n>0 THEN 'PUBLISHED' ELSE 'WAITING' END,
   'count',v_n,'results',v_ids);
END;
$function$;

REVOKE ALL ON FUNCTION my_derby.secure_backfill_finalize_pending_nov3(text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.secure_backfill_finalize_pending_nov3(text,integer) TO anon,authenticated;
NOTIFY pgrst,'reload schema';
