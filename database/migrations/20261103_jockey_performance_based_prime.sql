-- Jockey prime ages are discovered from results instead of assigned at creation.
ALTER TABLE my_derby_private.staff_development_profiles
  ALTER COLUMN peak_age DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS peak_performance_score numeric,
  ADD COLUMN IF NOT EXISTS last_performance_score numeric,
  ADD COLUMN IF NOT EXISTS performance_declining_weeks integer NOT NULL DEFAULT 0;

UPDATE my_derby_private.staff_development_profiles
SET peak_age = NULL,
    peak_performance_score = NULL,
    last_performance_score = NULL,
    performance_declining_weeks = 0,
    updated_at = now()
WHERE staff_kind = 'jockey';

-- Keep the existing trainer age curve. Jockeys start without an assumed peak.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$
 v_peak:=CASE WHEN v_kind='jockey'
  THEN 32+(('x'||substr(md5(NEW.id::text||':peak'),1,8))::bit(32)::bigint%11)::int
  ELSE 46+(('x'||substr(md5(NEW.id::text||':peak'),1,8))::bit(32)::bigint%13)::int END;
$old$;
  v_new text := $new$
 v_peak:=CASE WHEN v_kind='jockey' THEN NULL::int
  ELSE 46+(('x'||substr(md5(NEW.id::text||':peak'),1,8))::bit(32)::bigint%13)::int END;
$new$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_definition
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='my_derby_private' AND p.proname='initialize_staff_development';
  IF v_definition IS NULL OR position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not find jockey peak initialization block';
  END IF;
  EXECUTE replace(v_definition,v_old,v_new);
END
$migration$;

-- Evaluate the jockey's latest and prior 52-week result windows at settlement.
DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_definition
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='my_derby_private' AND p.proname='settle_staff_development_week';
  IF v_definition IS NULL THEN RAISE EXCEPTION 'Weekly staff settlement function is missing'; END IF;

  v_old := $old$ v_skills jsonb;
BEGIN$old$;
  v_new := $new$ v_skills jsonb;
 v_recent_rides integer;
 v_recent_wins integer;
 v_recent_placings integer;
 v_previous_rides integer;
 v_previous_wins integer;
 v_previous_placings integer;
 v_current_score numeric;
 v_previous_score numeric;
 v_peak_score numeric;
 v_decline_weeks integer;
 v_trend text;
BEGIN$new$;
  IF position(v_old IN v_definition)=0 THEN RAISE EXCEPTION 'Could not add performance variables'; END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  v_old := $old$p.initial_age,p.age_anchor_game_day,p.peak_age,p.growth_multiplier,
    p.potential_skills,p.floor_skills,p.completed_weeks,$old$;
  v_new := $new$p.initial_age,p.age_anchor_game_day,p.peak_age,p.growth_multiplier,
    p.peak_performance_score,p.performance_declining_weeks,
    p.potential_skills,p.floor_skills,p.completed_weeks,$new$;
  IF position(v_old IN v_definition)=0 THEN RAISE EXCEPTION 'Could not select performance profile fields'; END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  v_old := $old$  v_placings:=row_staff.placings;
  v_xp:=CASE WHEN row_staff.staff_kind='jockey' THEN$old$;
  v_new := $new$  v_placings:=row_staff.placings;
  v_current_score:=NULL;v_previous_score:=NULL;v_trend:='INSUFFICIENT';
  v_peak_score:=row_staff.peak_performance_score;
  v_decline_weeks:=coalesce(row_staff.performance_declining_weeks,0);
  IF row_staff.staff_kind='jockey' THEN
    SELECT
      coalesce(sum(h.rides) FILTER (WHERE h.week_end_game_day>p_week_end-364 AND h.week_end_game_day<p_week_end),0)::int,
      coalesce(sum(h.wins) FILTER (WHERE h.week_end_game_day>p_week_end-364 AND h.week_end_game_day<p_week_end),0)::int,
      coalesce(sum(h.placings) FILTER (WHERE h.week_end_game_day>p_week_end-364 AND h.week_end_game_day<p_week_end),0)::int,
      coalesce(sum(h.rides) FILTER (WHERE h.week_end_game_day>p_week_end-728 AND h.week_end_game_day<=p_week_end-364),0)::int,
      coalesce(sum(h.wins) FILTER (WHERE h.week_end_game_day>p_week_end-728 AND h.week_end_game_day<=p_week_end-364),0)::int,
      coalesce(sum(h.placings) FILTER (WHERE h.week_end_game_day>p_week_end-728 AND h.week_end_game_day<=p_week_end-364),0)::int
    INTO v_recent_rides,v_recent_wins,v_recent_placings,
      v_previous_rides,v_previous_wins,v_previous_placings
    FROM my_derby_private.staff_development_history h
    WHERE h.world_id=p_world AND h.staff_kind='jockey' AND h.staff_id=row_staff.staff_id;
    v_recent_rides:=v_recent_rides+v_rides;
    v_recent_wins:=v_recent_wins+v_wins;
    v_recent_placings:=v_recent_placings+v_placings;
    IF v_recent_rides>=20 THEN
      v_current_score:=round((2.0*v_recent_wins+v_recent_placings)/(3.0*v_recent_rides),4);
    END IF;
    IF v_previous_rides>=20 THEN
      v_previous_score:=round((2.0*v_previous_wins+v_previous_placings)/(3.0*v_previous_rides),4);
    END IF;
    IF v_current_score IS NOT NULL THEN
      IF v_peak_score IS NULL OR v_current_score>v_peak_score+0.005 THEN
        v_peak_score:=v_current_score;
        UPDATE my_derby_private.staff_development_profiles
        SET peak_age=v_age,peak_performance_score=v_current_score
        WHERE staff_kind='jockey' AND staff_id=row_staff.staff_id;
      END IF;
      IF v_previous_score IS NULL THEN
        v_trend:='BASELINE';v_decline_weeks:=0;
      ELSIF v_current_score>=v_previous_score+0.02 THEN
        v_trend:='RISING';v_decline_weeks:=0;
      ELSIF v_current_score<=v_previous_score-0.02 THEN
        v_trend:='FALLING';v_decline_weeks:=v_decline_weeks+1;
      ELSE
        v_trend:='STABLE';v_decline_weeks:=0;
      END IF;
      UPDATE my_derby_private.staff_development_profiles
      SET last_performance_score=v_current_score,
          performance_declining_weeks=v_decline_weeks,
          updated_at=now()
      WHERE staff_kind='jockey' AND staff_id=row_staff.staff_id;
    ELSE
      v_decline_weeks:=0;
      UPDATE my_derby_private.staff_development_profiles
      SET performance_declining_weeks=0,updated_at=now()
      WHERE staff_kind='jockey' AND staff_id=row_staff.staff_id;
    END IF;
  END IF;
  v_xp:=CASE WHEN row_staff.staff_kind='jockey' THEN$old$;
  IF position(v_old IN v_definition)=0 THEN RAISE EXCEPTION 'Could not add rolling performance scoring'; END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  v_old := $old$  IF v_age>row_staff.peak_age+5 AND
    (v_rides+v_training>0 OR row_staff.completed_weeks>=8) THEN
    v_delta:=-least(0.020,round((0.008+least(15,v_age-row_staff.peak_age-5)*0.0008)
       *(0.7+0.3*v_luck),3));
    v_reason:='GRADUAL_AGE_DECLINE';
    -- Senior professionals tend to retain tactics and mental skill longer.
    IF v_focus IN('judgment','control','stability') THEN
      v_delta:=round(v_delta*0.45,3);
    END IF;
  ELSIF v_rides+v_training=0 AND
    row_staff.completed_weeks>=8 AND
    p_week_end-coalesce(row_staff.last_active_game_day,p_week_end)>=56 THEN
    v_delta:=-round(least(0.014,0.006+0.008*v_luck),3);
    v_reason:='EXTENDED_INACTIVITY';
  ELSIF v_rides+v_training>0 AND v_age<=row_staff.peak_age+5 THEN
    v_rate:=least(0.035,
      (0.012+least(9,v_rides+v_training)*0.0015+
       least(3,v_wins)*0.0015)
      *row_staff.growth_multiplier*(0.8+0.2*v_luck));
    v_delta:=round(greatest(0,v_rate),3);
    v_reason:='EXPERIENCE_GROWTH';
  END IF;$old$;
  v_new := $new$  IF row_staff.staff_kind='jockey' THEN
    IF v_age>50 THEN
      v_delta:=-least(0.020,round((0.008+least(15,greatest(0,v_age-51))*0.0008)
        *(0.7+0.3*v_luck),3));
      v_reason:='GRADUAL_AGE_DECLINE';
    ELSIF v_decline_weeks>=8 THEN
      v_delta:=-round(least(0.014,0.006+0.008*v_luck),3);
      v_reason:='PERFORMANCE_DECLINE';
    ELSIF v_rides>0 AND v_trend IN('RISING','BASELINE','INSUFFICIENT') AND v_age<=50 THEN
      v_rate:=least(0.035,
        (0.012+least(9,v_rides)*0.0015+least(3,v_wins)*0.0015)
        *row_staff.growth_multiplier*(0.8+0.2*v_luck));
      v_delta:=round(greatest(0,v_rate),3);
      v_reason:=CASE WHEN v_trend='RISING' THEN 'PERFORMANCE_GROWTH' ELSE 'EXPERIENCE_GROWTH' END;
    ELSIF v_rides=0 AND v_training=0 AND row_staff.completed_weeks>=8
      AND p_week_end-coalesce(row_staff.last_active_game_day,p_week_end)>=56 THEN
      v_delta:=-round(least(0.014,0.006+0.008*v_luck),3);
      v_reason:='EXTENDED_INACTIVITY';
    ELSE
      v_reason:=CASE WHEN v_trend='STABLE' THEN 'PERFORMANCE_STABLE'
        WHEN v_trend='FALLING' THEN 'PERFORMANCE_DECLINE_WAIT'
        ELSE 'NO_ACTIVITY' END;
    END IF;
    IF v_delta<0 AND v_focus IN('judgment','control','stability') THEN
      v_delta:=round(v_delta*0.45,3);
    END IF;
  ELSE
    IF v_age>row_staff.peak_age+5 AND
      (v_rides+v_training>0 OR row_staff.completed_weeks>=8) THEN
      v_delta:=-least(0.020,round((0.008+least(15,v_age-row_staff.peak_age-5)*0.0008)
         *(0.7+0.3*v_luck),3));
      v_reason:='GRADUAL_AGE_DECLINE';
      IF v_focus IN('judgment','control','stability') THEN
        v_delta:=round(v_delta*0.45,3);
      END IF;
    ELSIF v_rides+v_training=0 AND row_staff.completed_weeks>=8
      AND p_week_end-coalesce(row_staff.last_active_game_day,p_week_end)>=56 THEN
      v_delta:=-round(least(0.014,0.006+0.008*v_luck),3);
      v_reason:='EXTENDED_INACTIVITY';
    ELSIF v_rides+v_training>0 AND v_age<=row_staff.peak_age+5 THEN
      v_rate:=least(0.035,
        (0.012+least(9,v_rides+v_training)*0.0015+least(3,v_wins)*0.0015)
        *row_staff.growth_multiplier*(0.8+0.2*v_luck));
      v_delta:=round(greatest(0,v_rate),3);
      v_reason:='EXPERIENCE_GROWTH';
    END IF;
  END IF;$new$;
  IF position(v_old IN v_definition)=0 THEN RAISE EXCEPTION 'Could not replace staff growth and decline rules'; END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  v_old := $old$  IF v_delta=0 THEN
    v_reason:=CASE WHEN v_rides+v_training=0 THEN 'NO_ACTIVITY'
      WHEN v_age>row_staff.peak_age+5 THEN 'DECLINE_FLOOR_REACHED'
      ELSE 'GROWTH_POTENTIAL_REACHED' END;$old$;
  v_new := $new$  IF v_delta=0 THEN
    IF row_staff.staff_kind='jockey' THEN
      v_reason:=CASE WHEN v_age>50 THEN 'DECLINE_FLOOR_REACHED'
        WHEN v_trend='STABLE' THEN 'PERFORMANCE_STABLE'
        WHEN v_trend='FALLING' THEN 'PERFORMANCE_DECLINE_WAIT'
        WHEN v_rides+v_training=0 THEN 'NO_ACTIVITY'
        ELSE 'GROWTH_POTENTIAL_REACHED' END;
    ELSE
      v_reason:=CASE WHEN v_rides+v_training=0 THEN 'NO_ACTIVITY'
        WHEN v_age>row_staff.peak_age+5 THEN 'DECLINE_FLOOR_REACHED'
        ELSE 'GROWTH_POTENTIAL_REACHED' END;
    END IF;$new$;
  IF position(v_old IN v_definition)=0 THEN RAISE EXCEPTION 'Could not update unchanged performance reason'; END IF;
  v_definition:=replace(v_definition,v_old,v_new);
  EXECUTE v_definition;
END
$migration$;

-- Keep the profile's displayed prime age tied to observed performance.
DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_definition
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='my_derby' AND p.proname='public_staff_profile';
  IF v_definition IS NULL THEN RAISE EXCEPTION 'Public staff profile function is missing'; END IF;
  v_old := $old$    'peakAge',p.peak_age,
    'careerStage',CASE
      WHEN p.initial_age+greatest(0,(v_today-p.age_anchor_game_day)/364)<p.peak_age-4 THEN '성장기'
      WHEN p.initial_age+greatest(0,(v_today-p.age_anchor_game_day)/364)<=p.peak_age+5 THEN '전성기'
      ELSE '노련기' END,$old$;
  v_new := $new$    'peakAge',p.peak_age,
    'peakPerformanceScore',p.peak_performance_score,
    'performanceScore',p.last_performance_score,
    'performanceDecliningWeeks',p.performance_declining_weeks,
    'careerStage',CASE
      WHEN least(85,p.initial_age+greatest(0,(v_today-p.age_anchor_game_day)/364))>50 THEN '연령 하락기'
      WHEN p.peak_age IS NULL THEN '성적 분석 중'
      WHEN p.initial_age+greatest(0,(v_today-p.age_anchor_game_day)/364)<p.peak_age-4 THEN '성장기'
      WHEN p.initial_age+greatest(0,(v_today-p.age_anchor_game_day)/364)<=p.peak_age+5 THEN '전성기'
      ELSE '성적 하락기' END,$new$;
  IF position(v_old IN v_definition)=0 THEN RAISE EXCEPTION 'Could not update dynamic prime-age display'; END IF;
  EXECUTE replace(v_definition,v_old,v_new);
END
$migration$;
