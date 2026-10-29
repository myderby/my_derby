CREATE OR REPLACE FUNCTION my_derby_private.process_training_for_horse_day(p_horse_id uuid, p_day integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 h my_derby.horses%rowtype;
 a my_derby.horse_abilities%rowtype;
 p my_derby.training_plans%rowtype;
 t my_derby.npc_trainers%rowtype;
 w my_derby.worlds%rowtype;
 primary_key text;
 secondary_key text;
 helper_key text;
 v_key text;
 v_gain numeric;
 v_total jsonb:='{}'::jsonb;
 v_stats jsonb;
 v_stat numeric;
 v_potential numeric;
 v_age numeric;
 v_trainer numeric;
 v_specific numeric;
 v_random numeric;
 v_intensity numeric;
 v_fatigue numeric:=0;
 v_condition numeric:=0;
 v_mode text;
 v_report text;
 v_base numeric;
 v_n int;
 v_current_week_day integer;
BEGIN
 IF p_day<1 THEN RAISE EXCEPTION 'INVALID_GAME_DAY';END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id FOR UPDATE;
 IF NOT FOUND OR h.owner_user_id IS NULL THEN RETURN jsonb_build_object('status','SKIPPED_NO_OWNER');END IF;
 SELECT * INTO p FROM my_derby.training_plans WHERE horse_id=h.id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','SKIPPED_NO_PLAN');END IF;
 SELECT * INTO w FROM my_derby.worlds WHERE id=h.world_id;
 v_current_week_day:=(my_derby.world_clock(w.id)->>'gameDayStart')::int;
 IF p_day < v_current_week_day OR p_day>v_current_week_day+6 THEN
  RAISE EXCEPTION 'TRAINING_DAY_OUTSIDE_CURRENT_WEEK';
 END IF;
 IF EXISTS(SELECT 1 FROM my_derby.training_reports WHERE horse_id=h.id AND game_day=p_day) THEN
  RETURN jsonb_build_object('status','ALREADY_PROCESSED','day',p_day);
 END IF;
 SELECT * INTO a FROM my_derby.horse_abilities WHERE horse_id=h.id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','SKIPPED_NO_ABILITY');END IF;

 SELECT nt.* INTO t FROM my_derby.trainer_contracts c
 JOIN my_derby.npc_trainers nt ON nt.id=c.trainer_id AND nt.is_active
 WHERE c.horse_id=h.id AND c.status='ACTIVE' ORDER BY c.start_game_day DESC LIMIT 1;
 v_mode:='TRAINED';
 IF h.life_stage<>'RACING' OR h.racing_retired_permanently OR h.breeding_retired_at IS NOT NULL
    OR h.health_state='INJURED' OR h.sale_state<>'NOT_LISTED' THEN
  v_mode:='INELIGIBLE_REST';
 ELSIF EXISTS(SELECT 1 FROM my_derby.ranch_course_requests rc
   WHERE rc.horse_id=h.id AND rc.status='ACTIVE'
   AND p_day BETWEEN rc.start_game_day AND rc.end_game_day)
 THEN
   v_mode:='RANCH_STAY_REST';
  ELSIF EXISTS(
    SELECT 1 FROM my_derby.race_entries e
    JOIN my_derby.races r ON r.id=e.race_id
    WHERE e.horse_id=h.id AND r.race_day=p_day AND r.world_id=h.world_id
      AND r.status<>'CANCELLED' AND e.status IN ('APPLIED','CONFIRMED','COMPLETED')
 ) THEN v_mode:='RACE_DAY_REST';
 ELSIF p.intensity='REST' OR h.fatigue>=75 OR h.condition_score<48 THEN
  v_mode:='RECOVERY';
 END IF;

 v_stats:=a.current_stats;
 v_base:=CASE p.intensity WHEN 'LIGHT' THEN 0.06 WHEN 'HARD' THEN 0.16 ELSE 0.105 END;
 v_age:=CASE WHEN h.age_years=2 THEN 1.2 WHEN h.age_years=3 THEN 1.1
   WHEN h.age_years BETWEEN 4 AND 6 THEN 1.0
   WHEN h.age_years BETWEEN 7 AND 8 THEN 0.8 ELSE 0.6 END;
 v_trainer:=CASE WHEN t.id IS NULL THEN 0.65
   ELSE least(1.2,greatest(0.75,(coalesce((t.skill_stats->>'stability')::numeric,70)+
    coalesce((t.skill_stats->>'recovery')::numeric,70))/150)) END;
 v_specific:=CASE WHEN t.id IS NULL THEN 1
  WHEN (p.distance_focus='SPRINT' AND '단거리'=ANY(t.specialties))
    OR (p.distance_focus='MILE' AND '마일'=ANY(t.specialties))
    OR (p.distance_focus='MIDDLE' AND '중거리'=ANY(t.specialties))
    OR (p.distance_focus='LONG' AND '장거리'=ANY(t.specialties)) THEN 1.12 ELSE 1 END;

 primary_key:=CASE p.distance_focus
   WHEN 'SPRINT' THEN 'speed' WHEN 'MILE' THEN 'stamina'
   WHEN 'MIDDLE' THEN 'stamina' ELSE 'stamina' END;
 secondary_key:=CASE p.run_style
   WHEN 'FRONT_ESCAPE' THEN 'start' WHEN 'LEAD' THEN 'acceleration'
   WHEN 'PRESS' THEN 'power' WHEN 'MID_MOVE' THEN 'finishing'
   WHEN 'CLOSER' THEN 'finishing' ELSE 'stability' END;
 helper_key:=CASE p.distance_focus
   WHEN 'SPRINT' THEN 'acceleration' WHEN 'MILE' THEN 'recovery'
   WHEN 'MIDDLE' THEN 'finishing' ELSE 'grit' END;
 v_random:=0.9+((('x'||substr(md5(h.id::text||':'||p_day::text),1,8))::bit(32)::bigint % 21)::numeric/100);
 IF v_mode='TRAINED' THEN
  FOREACH v_key IN ARRAY ARRAY[primary_key,secondary_key,helper_key] LOOP
    v_stat:=coalesce((v_stats->>v_key)::numeric,0);
    v_potential:=coalesce((a.potential_stats->>v_key)::numeric,v_stat);
    v_n:=CASE WHEN v_key=primary_key THEN 1 WHEN v_key=secondary_key THEN 2 ELSE 3 END;
    v_gain:=round(least(greatest(0,v_potential-v_stat),
      v_base * v_age * v_trainer * v_specific * v_random *
      (CASE WHEN v_n=1 THEN 1 WHEN v_n=2 THEN 0.7 ELSE 0.45 END)),3);
    -- The same ability may be targeted by multiple directions.
    -- Each target is applied sequentially, never passing estimated potential.
    IF v_gain>0 THEN
      v_stats:=jsonb_set(v_stats,ARRAY[v_key],to_jsonb(v_stat+v_gain),true);
      v_total:=jsonb_set(v_total,ARRAY[v_key],
        to_jsonb(round(coalesce((v_total->>v_key)::numeric,0)+v_gain,3)),true);
    END IF;
  END LOOP;
  v_fatigue:=CASE p.intensity WHEN 'HARD' THEN 5 WHEN 'LIGHT' THEN -2 ELSE 2 END;
  v_condition:=CASE p.intensity WHEN 'HARD' THEN -1.2 WHEN 'LIGHT' THEN 0.5 ELSE -0.35 END;
  v_report:='훈련 완료 · '||p.distance_focus||' / '||p.run_style||
    ' · '||CASE p.intensity WHEN 'HARD' THEN '강훈련' WHEN 'LIGHT' THEN '가벼운 훈련' ELSE '일반 훈련' END||
    CASE WHEN t.id IS NULL THEN ' · 조교사 미계약: 기본 훈련 효과 적용'
     ELSE ' · 조교사 '||t.name||' 전문성 반영' END;
 ELSIF v_mode='RANCH_STAY_REST' THEN
   v_fatigue:=0;v_condition:=0;
   v_report:='개인목장 입소일 · 조교 생략 (목장 코스 효과 별도 정산)';
  ELSIF v_mode='RACE_DAY_REST' THEN
  v_fatigue:=-2;v_condition:=0.5;
  v_report:='공식 경주 출전일 · 훈련 생략, 기본 회복만 적용';
 ELSIF v_mode='INELIGIBLE_REST' THEN
  v_fatigue:=-4;v_condition:=1;
  v_report:='훈련 자격 미충족(은퇴·부상·판매 상태 등) · 휴식 처리';
 ELSE
  v_fatigue:=-8;v_condition:=2;
  v_report:=CASE WHEN p.intensity='REST' THEN '휴식 훈련계획 · 피로 회복'
   ELSE '피로 또는 컨디션 저하로 자동 회복 전환' END;
 END IF;
 v_fatigue:=round(least(100,greatest(0,h.fatigue+v_fatigue))-h.fatigue,2);
 v_condition:=round(least(100,greatest(0,h.condition_score+v_condition))-h.condition_score,2);
 UPDATE my_derby.horse_abilities
    SET current_stats=v_stats,updated_at=now() WHERE horse_id=h.id;
 UPDATE my_derby.horses SET fatigue=h.fatigue+v_fatigue,
   condition_score=h.condition_score+v_condition WHERE id=h.id;
 INSERT INTO my_derby.training_reports
   (horse_id,trainer_id,game_day,change_stats,fatigue_change,condition_change,report_text)
 VALUES(h.id,t.id,p_day,v_total||jsonb_build_object('_meta',jsonb_build_object(
   'mode',v_mode,'distance',p.distance_focus,'style',p.run_style,
   'intensity',p.intensity,'trainerless',t.id IS NULL)),
   v_fatigue,v_condition,v_report);
 -- Trainer/horse familiarity increases only once per processed training day.
 IF v_mode='TRAINED' AND t.id IS NOT NULL THEN
  UPDATE my_derby.trainer_contracts
    SET familiarity=least(100,familiarity+1)
    WHERE horse_id=h.id AND trainer_id=t.id AND status='ACTIVE';
 END IF;
  RETURN jsonb_build_object('status',v_mode,'day',p_day,'horseId',h.id,
   'changes',v_total,'fatigueChange',v_fatigue,'conditionChange',v_condition);
END $function$;