-- KRA 2025 handicap game implementation. The race-type mix (4/5)
-- is a game scheduling choice; historical KRA race conditions aren't inferred.
CREATE OR REPLACE FUNCTION my_derby_private.recalculate_official_handicap_race(p_race_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE r my_derby.races%rowtype;v_grade integer;v_high integer;v_quarter int;
 v_count int:=0;h record;v_kg numeric;
BEGIN
 SELECT * INTO r FROM my_derby.races WHERE id=p_race_id FOR UPDATE;
 IF NOT FOUND OR r.status<>'OPEN' THEN RETURN jsonb_build_object('status','SKIPPED_RACE_NOT_OPEN');END IF;
 v_grade:=coalesce((r.prize_policy->>'grade_no')::int,0);
 IF v_grade NOT BETWEEN 1 AND 5 THEN
 RETURN jsonb_build_object('status','SPECIAL_WEIGHT_NOT_RATED');END IF;
 IF (r.prize_policy->>'kst_date')::date<(now() AT TIME ZONE 'Asia/Seoul')::date
 THEN RETURN jsonb_build_object('status','RACE_DAY_PASSED');END IF;
 IF r.prize_policy->>'weight_mode' IS NULL THEN
  UPDATE my_derby.races
   SET prize_policy=prize_policy||
   jsonb_build_object('weight_mode',CASE WHEN race_no%5=0 THEN 'SPECIAL' ELSE 'HANDICAP' END,
      'game_weight_plan','KRA_2025_GAME_V1','weight_plan_auto_generated',true)
  WHERE id=r.id;
  r.prize_policy:=r.prize_policy||
   jsonb_build_object('weight_mode',CASE WHEN r.race_no%5=0 THEN 'SPECIAL' ELSE 'HANDICAP' END);
 END IF;
 IF r.prize_policy->>'weight_mode'<>'HANDICAP' THEN
 RETURN jsonb_build_object('status','SPECIAL_WEIGHT_UNCHANGED');END IF;
 SELECT max(h.domestic_rating) INTO v_high
 FROM my_derby.race_entries e JOIN my_derby.horses h ON h.id=e.horse_id
 WHERE e.race_id=r.id AND e.status IN('APPLIED','CONFIRMED');
 IF v_high IS NULL THEN
  RETURN jsonb_build_object('status','UNRATED_FIELD');END IF;
 v_quarter:=ceil(extract(month from (r.prize_policy->>'kst_date')::date)/3.0)::int;
 FOR h IN SELECT e.id entry_id,e.snapshot,e.weight_kg,
  horse.domestic_rating,horse.age_years,horse.sex
  FROM my_derby.race_entries e JOIN my_derby.horses horse ON horse.id=e.horse_id
  WHERE e.race_id=r.id AND e.status IN('APPLIED','CONFIRMED')
  FOR UPDATE OF e
 LOOP
  IF h.domestic_rating IS NULL THEN CONTINUE;END IF;
  v_kg:=my_derby_private.kra_handicap_weight(h.domestic_rating,v_high,
   v_grade,h.age_years,h.sex,v_quarter,false,0);
  UPDATE my_derby.race_entries SET weight_kg=v_kg,
   snapshot=coalesce(snapshot,'{}'::jsonb)||
     jsonb_build_object('weightMode','KRA_2025_GAME_HANDICAP',
      'ratingAtEntry',h.domestic_rating,'highestFieldRating',v_high,
      'weightKg',v_kg,'weightDecision','AUTOMATED_GAME_MODEL')
  WHERE id=h.entry_id;
  v_count:=v_count+1;
 END LOOP;
 RETURN jsonb_build_object('status','HANDICAP_APPLIED','raceId',r.id,
  'updatedEntries',v_count,'topRating',v_high);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.refresh_next_official_handicaps()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE r record;result jsonb;v_total int:=0;v_changed int:=0;
BEGIN
 FOR r IN SELECT id FROM my_derby.races
  WHERE status='OPEN'
   AND (prize_policy->>'grade_no')::int BETWEEN 1 AND 5
   AND (prize_policy->>'kst_date')::date >= (now() AT TIME ZONE 'Asia/Seoul')::date
   AND (prize_policy->>'kst_date')::date<=
     (now() AT TIME ZONE 'Asia/Seoul')::date+7
  ORDER BY race_day,race_no LOOP
  result:=my_derby_private.recalculate_official_handicap_race(r.id);
  v_total:=v_total+1;
  v_changed:=v_changed+coalesce((result->>'updatedEntries')::int,0);
 END LOOP;
 RETURN jsonb_build_object('status','OK','racesExamined',v_total,
    'entriesAdjusted',v_changed);
END $fn$;
REVOKE ALL ON FUNCTION my_derby_private.recalculate_official_handicap_race(uuid)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.refresh_next_official_handicaps()
 FROM PUBLIC,anon,authenticated;
SELECT cron.schedule('my-derby-handicap-weights','10 0 * * *',
 'select my_derby_private.refresh_next_official_handicaps();');
