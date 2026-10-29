-- Permanent racing unfitness does not imply permanent physical illness.
-- After 14 game days of rest, breeding stock recovers clinically but the
-- RACING_UNFIT prognosis and irreversible racing retirement remain unchanged.
CREATE OR REPLACE FUNCTION my_derby_private.recover_npc_breeding_health()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE rec record; v_n int:=0; v_clock jsonb; v_day int;
BEGIN
 FOR rec IN
  SELECT h.id,h.world_id,h.injury_assessed_game_day,h.life_stage
  FROM my_derby.horses h
  JOIN my_derby.worlds w ON w.id=h.world_id
  WHERE w.status='ACTIVE' AND w.automatic_processing_enabled
   AND h.npc_owner_id IS NOT NULL AND h.owner_user_id IS NULL
   AND h.life_stage IN('STALLION','BROODMARE')
   AND h.racing_retired_permanently
   AND h.injury_prognosis='RACING_UNFIT'
   AND h.health_state='INJURED'
   AND h.injury_assessed_game_day IS NOT NULL
  ORDER BY h.id FOR UPDATE OF h SKIP LOCKED
 LOOP
  v_clock:=my_derby.world_clock(rec.world_id);
  v_day:=(v_clock->>'gameDayStart')::int+6;
  IF rec.injury_assessed_game_day+14<=v_day THEN
   UPDATE my_derby.horses SET health_state='HEALTHY'
   WHERE id=rec.id AND health_state='INJURED'
    AND life_stage IN('STALLION','BROODMARE')
    AND racing_retired_permanently;
   INSERT INTO my_derby.horse_state_history(horse_id,game_day,event_code,new_state)
   VALUES(rec.id,v_day,'NPC_BREEDER_CLINICALLY_RECOVERED',
    jsonb_build_object('lifeStage',rec.life_stage,
      'health','HEALTHY','racingUnfit',true,'restDays',14));
   v_n:=v_n+1;
  END IF;
 END LOOP;
 RETURN jsonb_build_object('status','OK','clinicallyRecovered',v_n,
  'racingReinstated',0);
END $fn$;
REVOKE ALL ON FUNCTION my_derby_private.recover_npc_breeding_health()
 FROM PUBLIC,anon,authenticated;
SELECT cron.schedule('my-derby-npc-breeding-recovery','20 0 * * *',
 'select my_derby_private.recover_npc_breeding_health();');
