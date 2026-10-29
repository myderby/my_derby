
-- Player training: choose 4 distance x 6 styles; seven game days per real date.
-- Player-owned horses can train without an NPC trainer at a smaller rate.
ALTER TABLE my_derby.training_plans
 ADD COLUMN IF NOT EXISTS intensity text NOT NULL DEFAULT 'NORMAL';
ALTER TABLE my_derby.training_plans
 DROP CONSTRAINT IF EXISTS training_plans_intensity_check;
ALTER TABLE my_derby.training_plans
 ADD CONSTRAINT training_plans_intensity_check
 CHECK (intensity IN ('REST','LIGHT','NORMAL','HARD'));

-- All plan/report writes go through validated RPC; prevent clients from bypassing cooldowns.
DROP POLICY IF EXISTS own_training_plans_insert ON my_derby.training_plans;
DROP POLICY IF EXISTS own_training_plans_update ON my_derby.training_plans;

CREATE OR REPLACE FUNCTION my_derby.player_training_dashboard()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 u uuid := auth.uid();
 w uuid;
 clock jsonb;
 v_horses jsonb;
 v_reports jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT world_id INTO w FROM my_derby.profiles
  WHERE user_id=u AND initial_setup_complete=true;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501'; END IF;
 clock:=my_derby.world_clock(w);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',h.id,'name',h.name,'age',h.age_years,'sex',h.sex,
  'lifeStage',h.life_stage,'health',h.health_state,
  'location',h.location,'condition',h.condition_score,
  'fatigue',h.fatigue,'retired',h.racing_retired_permanently,
  'currentStats',a.current_stats,
  'plan',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object(
     'distance',p.distance_focus,'style',p.run_style,'intensity',p.intensity,'updatedAt',p.updated_at) END,
  'trainer',CASE WHEN t.id IS NULL THEN NULL ELSE jsonb_build_object(
     'name',t.name,'specialties',t.specialties,'skills',t.skill_stats) END
 ) ORDER BY h.name),'[]'::jsonb) INTO v_horses
 FROM my_derby.horses h
 LEFT JOIN my_derby.horse_abilities a ON a.horse_id=h.id
 LEFT JOIN my_derby.training_plans p ON p.horse_id=h.id AND p.owner_user_id=u
 LEFT JOIN my_derby.trainer_contracts c ON c.horse_id=h.id AND c.status='ACTIVE'
 LEFT JOIN my_derby.npc_trainers t ON t.id=c.trainer_id AND t.is_active
 WHERE h.owner_user_id=u AND h.world_id=w;

 SELECT coalesce(jsonb_agg(x.entry ORDER BY x.game_day DESC,x.horse_name,x.id DESC),'[]'::jsonb) INTO v_reports
 FROM (
   SELECT tr.id,tr.game_day,h.name horse_name,jsonb_build_object(
     'id',tr.id,'horseId',tr.horse_id,'horseName',h.name,
     'gameDay',tr.game_day,'trainerName',t.name,
     'changeStats',tr.change_stats,'fatigueChange',tr.fatigue_change,
     'conditionChange',tr.condition_change,'text',tr.report_text) entry
   FROM my_derby.training_reports tr
   JOIN my_derby.horses h ON h.id=tr.horse_id
   LEFT JOIN my_derby.npc_trainers t ON t.id=tr.trainer_id
   WHERE h.owner_user_id=u AND h.world_id=w
     AND tr.game_day>=greatest(1,(clock->>'gameDayStart')::int-35)
   ORDER BY tr.game_day DESC,tr.id DESC LIMIT 150
 ) x;
 RETURN jsonb_build_object(
   'world',clock,'horses',v_horses,'reports',v_reports,
   'weeklyDays',jsonb_build_array(
    (clock->>'gameDayStart')::int,(clock->>'gameDayStart')::int+1,
    (clock->>'gameDayStart')::int+2,(clock->>'gameDayStart')::int+3,
    (clock->>'gameDayStart')::int+4,(clock->>'gameDayStart')::int+5,
    (clock->>'gameDayStart')::int+6),
   'weekSettlementTime','22:20 KST',
   'manualSettlementAfter','22:05 KST'
 );
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_save_training_plan(
 p_horse_id uuid,p_distance text,p_style text,p_intensity text DEFAULT 'NORMAL')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 u uuid:=auth.uid(); h my_derby.horses%rowtype;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id FOR UPDATE;
 IF NOT FOUND OR h.owner_user_id IS DISTINCT FROM u THEN
   RAISE EXCEPTION 'NOT_YOUR_HORSE' USING ERRCODE='42501'; END IF;
 IF h.life_stage<>'RACING' OR h.age_years NOT BETWEEN 2 AND 10
  OR h.racing_retired_permanently OR h.breeding_retired_at IS NOT NULL
  OR h.health_state='INJURED' OR h.sale_state<>'NOT_LISTED' THEN
    RAISE EXCEPTION 'HORSE_NOT_TRAINABLE'; END IF;
 IF p_distance NOT IN ('SPRINT','MILE','MIDDLE','LONG')
  OR p_style NOT IN ('FRONT_ESCAPE','LEAD','PRESS','MID_MOVE','CLOSER','FREE')
  OR p_intensity NOT IN ('REST','LIGHT','NORMAL','HARD')
  THEN RAISE EXCEPTION 'TRAINING_PLAN_INVALID'; END IF;
 INSERT INTO my_derby.training_plans(horse_id,owner_user_id,distance_focus,run_style,intensity,updated_at)
 VALUES(p_horse_id,u,p_distance,p_style,p_intensity,now())
 ON CONFLICT(horse_id) DO UPDATE SET
  owner_user_id=excluded.owner_user_id,
  distance_focus=excluded.distance_focus,run_style=excluded.run_style,
  intensity=excluded.intensity,updated_at=now();
 RETURN jsonb_build_object('status','SAVED','horseId',p_horse_id,
  'distance',p_distance,'style',p_style,'intensity',p_intensity,
  'effectiveFrom','NEXT_UNPROCESSED_GAME_DAY');
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.process_training_for_horse_day(p_horse_id uuid,p_day integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
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
 RETURN jsonb_build_object('status',v_mode,'day',p_day,'horseId',h.id,
   'changes',v_total,'fatigueChange',v_fatigue,'conditionChange',v_condition);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.process_training_for_horse_week(p_horse_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_day int; v_first int; v_item jsonb; v_done int:=0; v_items jsonb:='[]'::jsonb;
BEGIN
 SELECT (my_derby.world_clock(h.world_id)->>'gameDayStart')::int INTO v_first
  FROM my_derby.horses h WHERE h.id=p_horse_id;
 IF v_first IS NULL THEN RAISE EXCEPTION 'HORSE_NOT_FOUND';END IF;
 FOR v_day IN v_first..v_first+6 LOOP
  v_item:=my_derby_private.process_training_for_horse_day(p_horse_id,v_day);
  v_items:=v_items||jsonb_build_array(v_item);
  IF v_item->>'status' IN('TRAINED','RECOVERY','INELIGIBLE_REST','RACE_DAY_REST') THEN
    v_done:=v_done+1;
  END IF;
 END LOOP;
 RETURN jsonb_build_object('horseId',p_horse_id,'processedDays',v_done,
   'weekStart',v_first,'items',v_items);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby.player_generate_training_reports(p_horse_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE h my_derby.horses%rowtype; u uuid:=auth.uid(); v_local timestamp:=now() at time zone 'Asia/Seoul';
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id;
 IF NOT FOUND OR h.owner_user_id IS DISTINCT FROM u THEN
  RAISE EXCEPTION 'NOT_YOUR_HORSE' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM my_derby.training_plans WHERE horse_id=p_horse_id AND owner_user_id=u) THEN
  RAISE EXCEPTION 'TRAINING_PLAN_REQUIRED';END IF;
 IF v_local::time<'22:05'::time THEN RAISE EXCEPTION 'TRAINING_SETTLEMENT_OPENS_2205';END IF;
 RETURN my_derby_private.process_training_for_horse_week(p_horse_id);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.process_training_weekly_auto()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE rec record; v_n int:=0; v_horses int:=0;
BEGIN
 -- Backstop for the daily cron (22:20 Korean time). No premature processing.
 IF (now() at time zone 'Asia/Seoul')::time<'22:05'::time THEN
  RETURN jsonb_build_object('status','NOT_DUE'); END IF;
 FOR rec IN
  SELECT h.id FROM my_derby.training_plans p JOIN my_derby.horses h ON h.id=p.horse_id
  JOIN my_derby.worlds w ON w.id=h.world_id
  WHERE h.owner_user_id=p.owner_user_id AND w.status='ACTIVE'
  ORDER BY h.id
 LOOP
  PERFORM my_derby_private.process_training_for_horse_week(rec.id);
  v_horses:=v_horses+1;
 END LOOP;
 RETURN jsonb_build_object('status','PROCESSED','horsesWithPlans',v_horses,
  'kstDate',(now() at time zone 'Asia/Seoul')::date);
END $fn$;

REVOKE ALL ON FUNCTION my_derby.player_training_dashboard() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_save_training_plan(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_generate_training_reports(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_training_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_save_training_plan(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_generate_training_reports(uuid) TO authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_training_for_horse_day(uuid,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_training_for_horse_week(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_training_weekly_auto() FROM PUBLIC,anon,authenticated;

-- Schedule once after all 19-21 KST official race slots have finished and
-- their results have been published, without changing any race jobs.
SELECT cron.schedule('my-derby-training-weekly','20 13 * * *',
 'select my_derby_private.process_training_weekly_auto();');
