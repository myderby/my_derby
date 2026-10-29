
-- NPC owner temperament drives genuine pre-race declarations; DUSU fallback stays.
ALTER TABLE my_derby.npc_owners
 ALTER COLUMN policy SET DEFAULT '{}'::jsonb;
UPDATE my_derby.npc_owners
 SET policy=jsonb_set(jsonb_set(policy,'{active}','true'::jsonb,true),
  '{autonomousEntryEnabled}','true'::jsonb,true);

CREATE TABLE IF NOT EXISTS my_derby.npc_owner_entry_decisions(
 race_id uuid NOT NULL REFERENCES my_derby.races(id),
 horse_id uuid NOT NULL REFERENCES my_derby.horses(id),
 npc_owner_id uuid NOT NULL REFERENCES my_derby.npc_owners(id),
 game_day integer NOT NULL,
 status text NOT NULL CHECK(status IN('APPLIED','DECLINED','FALLBACK')),
 reason text NOT NULL,
 rule_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(race_id,horse_id)
);
ALTER TABLE my_derby.npc_owner_entry_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.npc_owner_entry_decisions FROM anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.npc_owner_race_preference(
 p_horse_id uuid,p_race_day integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE h my_derby.horses%rowtype;o my_derby.npc_owners%rowtype;
 v_last int;v_min_condition int;v_max_fatigue int;v_cooldown int;
 v_risk text;v_ok boolean;
BEGIN
 SELECT * INTO h FROM my_derby.horses WHERE id=p_horse_id;
 SELECT * INTO o FROM my_derby.npc_owners WHERE id=h.npc_owner_id;
 IF h.id IS NULL OR o.id IS NULL OR h.npc_owner_id IS NULL OR
  coalesce(o.policy->>'autonomousEntryEnabled','false')<>'true'
 THEN RETURN jsonb_build_object('accepted',false,'reason','OWNER_NOT_AUTONOMOUS');END IF;
 v_risk:=coalesce(o.policy->>'risk','BALANCED');
 v_min_condition:=CASE v_risk WHEN 'CONSERVATIVE' THEN 75 WHEN 'AGGRESSIVE' THEN 55 ELSE 65 END;
 v_max_fatigue:=CASE v_risk WHEN 'CONSERVATIVE' THEN 35 WHEN 'AGGRESSIVE' THEN 75 ELSE 55 END;
 v_cooldown:=CASE v_risk WHEN 'CONSERVATIVE' THEN 14 WHEN 'AGGRESSIVE' THEN 0 ELSE 7 END;
 SELECT max(r.race_day) INTO v_last FROM my_derby.race_results rr
 JOIN my_derby.race_runs run ON run.id=rr.race_run_id
 JOIN my_derby.races r ON r.id=run.race_id
 WHERE rr.horse_id=h.id AND r.status='FINISHED' AND r.race_day<p_race_day;
 v_ok:=h.life_stage='RACING' AND h.health_state='HEALTHY'
  AND h.age_years BETWEEN 2 AND 10 AND NOT h.racing_retired_permanently
  AND h.sale_state='NOT_LISTED'
  AND h.breeding_retired_at IS NULL
  AND h.condition_score>=v_min_condition
  AND h.fatigue<=v_max_fatigue
  AND (v_last IS NULL OR p_race_day-v_last>=v_cooldown);
 RETURN jsonb_build_object('accepted',coalesce(v_ok,false),
   'risk',v_risk,'minCondition',v_min_condition,'maxFatigue',v_max_fatigue,
   'minDaysBetweenRaces',v_cooldown,'lastOfficialRaceDay',v_last,
   'reason',CASE WHEN v_ok THEN 'NPC_OWNER_APPROVED'
    WHEN h.health_state<>'HEALTHY' THEN 'HEALTH_BLOCK'
    WHEN h.fatigue>v_max_fatigue THEN 'OWNER_REST_PRIORITY'
    WHEN h.condition_score<v_min_condition THEN 'OWNER_CONDITION_PRIORITY'
    WHEN v_last IS NOT NULL AND p_race_day-v_last<v_cooldown THEN 'OWNER_RECOVERY_INTERVAL'
    ELSE 'HORSE_INELIGIBLE' END);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.process_npc_owner_race_entries(p_game_day integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE w uuid;v_day int;r my_derby.races%rowtype; e my_derby.race_entries%rowtype;
 v_judgement jsonb;v_alt record; v_owner uuid;v_count int:=0;
 v_replacements int:=0;v_fallback int:=0;v_considered int:=0;
 v_clock jsonb;v_now timestamp:=now() at time zone 'Asia/Seoul';
BEGIN
 SELECT id INTO w FROM my_derby.worlds WHERE world_key='kra_roster_v1' AND status='ACTIVE';
 IF w IS NULL THEN RAISE EXCEPTION 'WORLD_NOT_ACTIVE';END IF;
 v_clock:=my_derby.world_clock(w);
 v_day:=coalesce(p_game_day,(v_clock->>'gameDayStart')::int);
 IF v_day<(v_clock->>'gameDayStart')::int THEN RAISE EXCEPTION 'ENTRY_DAY_ALREADY_PASSED';END IF;
 FOR r IN SELECT * FROM my_derby.races WHERE world_id=w AND race_day=v_day
  AND status='OPEN' AND prize_policy->>'schedule_version'='csv2025_rank_sttime_v2'
  AND ((prize_policy->>'kst_date')::date>v_now::date
       OR ((prize_policy->>'kst_date')::date=v_now::date
         AND v_now::time<coalesce(entry_deadline,start_time-interval '10 minutes')))
  ORDER BY start_time,id FOR UPDATE
 LOOP
  FOR e IN SELECT * FROM my_derby.race_entries
   WHERE race_id=r.id AND owner_user_id IS NULL AND status='CONFIRMED'
    AND snapshot->>'entry_source' IS DISTINCT FROM 'NPC_OWNER_APPLICATION_V1'
   ORDER BY gate_no FOR UPDATE
  LOOP
   SELECT npc_owner_id INTO v_owner FROM my_derby.horses WHERE id=e.horse_id;
   IF v_owner IS NULL THEN CONTINUE;END IF;
   v_considered:=v_considered+1;
   v_judgement:=my_derby_private.npc_owner_race_preference(e.horse_id,r.race_day);
   IF (v_judgement->>'accepted')::boolean THEN
    UPDATE my_derby.race_entries SET snapshot=snapshot||
      jsonb_build_object('entry_source','NPC_OWNER_APPLICATION_V1',
        'ownerDecision',v_judgement,'npcOwnerId',v_owner)
    WHERE id=e.id;
    INSERT INTO my_derby.npc_owner_entry_decisions
       (race_id,horse_id,npc_owner_id,game_day,status,reason,rule_snapshot)
    VALUES(r.id,e.horse_id,v_owner,v_day,'APPLIED','NPC_OWNER_APPROVED',v_judgement)
    ON CONFLICT DO NOTHING;
    v_count:=v_count+1;
    CONTINUE;
   END IF;
   -- Replaced horse is offered by a different NPC owner who voluntarily
   -- enters based on its own risk, fatigue, fitness and recovery rules.
   SELECT horse.id,horse.npc_owner_id,horse.name,ability.current_stats
    INTO v_alt FROM my_derby.horses horse
    JOIN my_derby.npc_owners owner ON owner.id=horse.npc_owner_id
    JOIN my_derby.horse_abilities ability ON ability.horse_id=horse.id
   WHERE horse.world_id=w AND horse.id<>e.horse_id
    AND horse.source_meet=r.prize_policy->>'source_meet'
    AND horse.source_grade_no=(r.prize_policy->>'grade_no')::smallint
    AND horse.life_stage='RACING' AND horse.health_state='HEALTHY'
    AND horse.age_years BETWEEN 2 AND 10
    AND horse.sale_state='NOT_LISTED'
    AND NOT horse.racing_retired_permanently
    AND horse.breeding_retired_at IS NULL
    AND horse.condition_score>=CASE owner.policy->>'risk'
       WHEN 'CONSERVATIVE' THEN 75 WHEN 'AGGRESSIVE' THEN 55 ELSE 65 END
    AND horse.fatigue<=CASE owner.policy->>'risk'
       WHEN 'CONSERVATIVE' THEN 35 WHEN 'AGGRESSIVE' THEN 75 ELSE 55 END
    AND NOT EXISTS(
      SELECT 1 FROM my_derby.race_entries exist
      JOIN my_derby.races rr ON rr.id=exist.race_id
      WHERE exist.horse_id=horse.id AND rr.world_id=w
       AND rr.race_day=v_day AND rr.status<>'CANCELLED'
       AND exist.status IN('APPLIED','CONFIRMED','COMPLETED')
    )
    AND (owner.policy->>'autonomousEntryEnabled')='true'
    AND coalesce((SELECT r.race_day-max(last_r.race_day)
       FROM my_derby.race_results result
       JOIN my_derby.race_runs run ON run.id=result.race_run_id
       JOIN my_derby.races last_r ON last_r.id=run.race_id
       WHERE result.horse_id=horse.id AND last_r.status='FINISHED'
        AND last_r.race_day<r.race_day),999)
       >=CASE owner.policy->>'risk'
          WHEN 'CONSERVATIVE' THEN 14 WHEN 'AGGRESSIVE' THEN 0 ELSE 7 END
   ORDER BY horse.condition_score DESC,horse.fatigue,
    md5(horse.id::text||r.id::text)
   LIMIT 1 FOR UPDATE OF horse SKIP LOCKED;
   IF v_alt.id IS NULL THEN
    INSERT INTO my_derby.npc_owner_entry_decisions
      (race_id,horse_id,npc_owner_id,game_day,status,reason,rule_snapshot)
    VALUES(r.id,e.horse_id,v_owner,v_day,'FALLBACK',
       'DUSU_FALLBACK_NO_ALTERNATIVE',v_judgement)
    ON CONFLICT DO NOTHING;
    v_fallback:=v_fallback+1;
   ELSE
    INSERT INTO my_derby.npc_owner_entry_decisions
      (race_id,horse_id,npc_owner_id,game_day,status,reason,rule_snapshot)
    VALUES(r.id,e.horse_id,v_owner,v_day,'DECLINED',
      v_judgement->>'reason',v_judgement) ON CONFLICT DO NOTHING;
    UPDATE my_derby.race_entries SET horse_id=v_alt.id,
      snapshot=snapshot||jsonb_build_object(
       'entry_source','NPC_OWNER_APPLICATION_V1',
       'ownerDecision',my_derby_private.npc_owner_race_preference(v_alt.id,v_day),
       'npcOwnerId',v_alt.npc_owner_id,'replacedHorseId',e.horse_id,
       'strategies',CASE WHEN coalesce((v_alt.current_stats->>'start')::numeric,0)>
          coalesce((v_alt.current_stats->>'finishing')::numeric,0)
          THEN '["FRONT","PRESS","SAVE"]'::jsonb
          ELSE '["SAVE","MOVE","CLOSER"]'::jsonb END)
    WHERE id=e.id;
    INSERT INTO my_derby.npc_owner_entry_decisions
      (race_id,horse_id,npc_owner_id,game_day,status,reason,rule_snapshot)
    VALUES(r.id,v_alt.id,v_alt.npc_owner_id,v_day,'APPLIED','NPC_OWNER_CHOSE_HORSE',
       my_derby_private.npc_owner_race_preference(v_alt.id,v_day))
    ON CONFLICT DO NOTHING;
    v_replacements:=v_replacements+1;v_count:=v_count+1;
   END IF;
  END LOOP;
 END LOOP;
 RETURN jsonb_build_object('status','OK','gameDay',v_day,
   'considered',v_considered,'ownerApproved',v_count,
   'replaced',v_replacements,'retainedFallback',v_fallback);
END $fn$;

REVOKE ALL ON FUNCTION my_derby_private.npc_owner_race_preference(uuid,integer)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_npc_owner_race_entries(integer)
 FROM PUBLIC,anon,authenticated;
SELECT cron.schedule('my-derby-npc-owner-entries','40 23 * * *',
 'select my_derby_private.process_npc_owner_race_entries();');
