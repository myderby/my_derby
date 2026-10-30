ALTER TABLE my_derby.jockey_applications
 ADD COLUMN IF NOT EXISTS decision_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE OR REPLACE FUNCTION my_derby.apply_player_jockey(p_race_id uuid, p_horse_id uuid, p_jockey_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_user uuid:=auth.uid();
 v_r my_derby.races%rowtype;
 v_entry my_derby.race_entries%rowtype;
 v_j my_derby.npc_jockeys%rowtype;
 v_kst timestamp:=now() AT TIME ZONE 'Asia/Seoul';
 v_rides integer;
 v_chance numeric;v_roll numeric;v_preference text;v_existing text;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_r FROM my_derby.races WHERE id=p_race_id FOR UPDATE;
 IF NOT FOUND OR v_r.status<>'OPEN' THEN RAISE EXCEPTION 'RACE_NOT_OPEN'; END IF;
 IF (v_r.prize_policy->>'kst_date')::date<v_kst::date OR
  ((v_r.prize_policy->>'kst_date')::date=v_kst::date AND
    v_kst::time>=coalesce(v_r.entry_deadline,v_r.start_time-interval '10 minutes')) THEN
  RAISE EXCEPTION 'ENTRY_DEADLINE_PASSED';
 END IF;
 SELECT * INTO v_entry FROM my_derby.race_entries
 WHERE race_id=p_race_id AND horse_id=p_horse_id AND owner_user_id=v_user AND status='CONFIRMED'
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'OWN_CONFIRMED_ENTRY_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_j FROM my_derby.npc_jockeys
 WHERE id=p_jockey_id AND world_id=v_r.world_id AND home_track=v_r.track AND is_active FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'JOCKEY_NOT_ELIGIBLE'; END IF;
 IF EXISTS(SELECT 1 FROM my_derby.race_entries e
    WHERE e.race_id=p_race_id AND e.jockey_id=p_jockey_id AND e.horse_id<>p_horse_id
    AND e.status IN ('APPLIED','CONFIRMED','COMPLETED')) THEN
   RAISE EXCEPTION 'JOCKEY_ALREADY_BOOKED_FOR_RACE';
 END IF;
 SELECT count(*) INTO v_rides FROM my_derby.race_entries e
  JOIN my_derby.races rr ON rr.id=e.race_id
  WHERE rr.world_id=v_r.world_id AND rr.race_day=v_r.race_day AND rr.status<>'CANCELLED'
   AND e.jockey_id=p_jockey_id AND e.status IN ('APPLIED','CONFIRMED','COMPLETED')
   AND e.id<>v_entry.id;
 IF v_rides>=v_j.max_daily_rides THEN RAISE EXCEPTION 'JOCKEY_DAILY_LIMIT'; END IF;

 SELECT status INTO v_existing FROM my_derby.jockey_applications
  WHERE race_id=p_race_id AND horse_id=p_horse_id AND jockey_id=p_jockey_id;
 IF v_existing='REJECTED' THEN
  RETURN jsonb_build_object('status','REJECTED','jockeyId',p_jockey_id,
    'jockeyName',v_j.name,'reason','ALREADY_DECLINED_THIS_RACE');
 END IF;
 IF v_existing='ACCEPTED' THEN
  RETURN jsonb_build_object('status','ALREADY_ACCEPTED','jockeyId',p_jockey_id,
    'jockeyName',v_j.name,'dailyRidesAfter',v_rides+1,
    'maxDailyRides',v_j.max_daily_rides);
 END IF;
 -- Each NPC jockey has a stable, deterministic preference.
 v_preference:=CASE (('x'||substr(md5(v_j.id::text),1,2))::bit(8)::int%3)
   WHEN 0 THEN 'PRUDENT' WHEN 1 THEN 'BALANCED' ELSE 'CHALLENGER' END;
 v_chance:=least(96,greatest(55,CASE v_preference
    WHEN 'PRUDENT' THEN 73 WHEN 'CHALLENGER' THEN 89 ELSE 83 END
    -v_rides*3
    +CASE WHEN v_r.track=v_j.home_track THEN 4 ELSE -15 END
    +CASE WHEN (SELECT source_grade_no FROM my_derby.horses
      WHERE id=p_horse_id)<=3 THEN 5 ELSE 0 END
    +CASE WHEN (v_j.skill_stats->>'judgment')::numeric>=82 THEN -4 ELSE 0 END));
 v_roll:=(('x'||substr(md5(p_race_id::text||p_horse_id::text||
   p_jockey_id::text||':ACCEPT_V1'),1,8))::bit(32)::bigint%10000)::numeric/100;
 IF v_roll>=v_chance THEN
  INSERT INTO my_derby.jockey_applications(race_id,horse_id,owner_user_id,jockey_id,status)
  VALUES(p_race_id,p_horse_id,v_user,p_jockey_id,'REJECTED')
  ON CONFLICT(race_id,horse_id,jockey_id) DO UPDATE SET status='REJECTED';
  UPDATE my_derby.jockey_applications
  SET decision_snapshot=jsonb_build_object('chance',v_chance,'roll',v_roll,
    'preference',v_preference,'reason','NPC_JOCKEY_DECLINED')
  WHERE race_id=p_race_id AND horse_id=p_horse_id AND jockey_id=p_jockey_id;
  RETURN jsonb_build_object('status','REJECTED','jockeyName',v_j.name,
    'reason','NPC_JOCKEY_DECLINED','acceptanceChance',v_chance,
    'jockeyPreference',v_preference);
 END IF;
  UPDATE my_derby.jockey_applications SET status='WITHDRAWN'
 WHERE race_id=p_race_id AND horse_id=p_horse_id AND owner_user_id=v_user
  AND status IN ('PENDING','ACCEPTED','AUTO_ASSIGNED') AND jockey_id<>p_jockey_id;
 INSERT INTO my_derby.jockey_applications(race_id,horse_id,owner_user_id,jockey_id,status)
 VALUES(p_race_id,p_horse_id,v_user,p_jockey_id,'ACCEPTED')
 ON CONFLICT(race_id,horse_id,jockey_id) DO UPDATE SET status='ACCEPTED';
 UPDATE my_derby.jockey_applications
  SET decision_snapshot=jsonb_build_object('chance',v_chance,'roll',v_roll,
    'preference',v_preference,'reason','NPC_JOCKEY_ACCEPTED')
  WHERE race_id=p_race_id AND horse_id=p_horse_id AND jockey_id=p_jockey_id;
 UPDATE my_derby.race_entries SET jockey_id=p_jockey_id,
  snapshot=jsonb_set(snapshot,'{autoAssignedJockey}','false'::jsonb,true)
 WHERE id=v_entry.id;
 RETURN jsonb_build_object('status','ACCEPTED','raceId',p_race_id,
  'horseId',p_horse_id,'jockeyId',p_jockey_id,'jockeyName',v_j.name,
  'dailyRidesAfter',v_rides+1,'maxDailyRides',v_j.max_daily_rides,
  'acceptanceChance',v_chance,'jockeyPreference',v_preference);
END $function$;