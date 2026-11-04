-- The public API role has a short default statement timeout. Raise it only for
-- the Nov 3 date-locked backfill routines, and cap each operation at 30 seconds.
ALTER FUNCTION my_derby.secure_backfill_claim_nov3(text,integer)
  SET statement_timeout TO '30s';
ALTER FUNCTION my_derby.secure_backfill_finalize_pending_nov3(text,integer)
  SET statement_timeout TO '30s';

CREATE OR REPLACE FUNCTION my_derby.secure_backfill_finalize_race_nov3(
  p_secret text,p_run_id uuid,p_result jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
SET statement_timeout TO '30s'
AS $function$
DECLARE v_race_date text;
BEGIN
 IF p_secret IS NULL OR p_secret IS DISTINCT FROM
   (SELECT secret FROM my_derby_private.dispatch_credentials WHERE key='race_runner')
   THEN RAISE EXCEPTION 'OFFICIAL_AUTH_REQUIRED' USING errcode='42501'; END IF;
 SELECT r.prize_policy->>'kst_date' INTO v_race_date
 FROM my_derby.race_runs rr JOIN my_derby.races r ON r.id=rr.race_id
 WHERE rr.id=p_run_id AND rr.status='RUNNING' AND r.status='RUNNING';
 IF v_race_date IS DISTINCT FROM '2026-11-03'
   THEN RAISE EXCEPTION 'BACKFILL_DATE_NOT_ALLOWED' USING errcode='42501'; END IF;
 RETURN my_derby.secure_official_race_finalize(p_secret,p_run_id,p_result);
END;
$function$;

REVOKE ALL ON FUNCTION my_derby.secure_backfill_finalize_race_nov3(text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.secure_backfill_finalize_race_nov3(text,uuid,jsonb) TO anon,authenticated;
NOTIFY pgrst,'reload schema';
