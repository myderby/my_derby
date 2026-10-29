-- Ensure the strictly bottom-40-percent category never contains more than 40% of the field.
CREATE OR REPLACE FUNCTION my_derby_private.npc_retirement_candidates(p_world_id uuid)
RETURNS TABLE(horse_id uuid, reason text, evidence jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 WITH finishes AS (
  SELECT rr.horse_id,rr.finishing_rank,r.race_day,r.id race_id,
    count(*) OVER (PARTITION BY rr.race_run_id) field_size,
    row_number() OVER (PARTITION BY rr.horse_id ORDER BY r.race_day DESC, r.start_time DESC, rr.id DESC) row_no
  FROM my_derby.race_results rr
  JOIN my_derby.race_runs run ON run.id=rr.race_run_id AND run.status='FINISHED'
  JOIN my_derby.races r ON r.id=run.race_id AND r.status='FINISHED'
  WHERE r.world_id=p_world_id
 ), form AS (
  SELECT f.horse_id,count(*) n,
    count(*) FILTER(WHERE f.finishing_rank>3) unplaced,
    count(*) FILTER(WHERE f.finishing_rank>ceil(f.field_size*0.6)) bottom_40,
    round(avg((f.finishing_rank-1)::numeric/greatest(f.field_size-1,1)),3) avg_relative
  FROM finishes f WHERE f.row_no<=6 AND f.field_size>=5
  GROUP BY f.horse_id
 )
 SELECT h.id,
  CASE WHEN h.health_state='INJURED' AND h.injury_prognosis='RACING_UNFIT'
       THEN 'PERMANENT_INJURY' ELSE 'POOR_FORM' END,
  CASE WHEN h.health_state='INJURED' AND h.injury_prognosis='RACING_UNFIT'
       THEN jsonb_build_object('prognosis',h.injury_prognosis,'assessedDay',h.injury_assessed_game_day)
       ELSE jsonb_build_object('window',6,'unplaced',f.unplaced,
        'bottom40',f.bottom_40,'avgRelativeRank',f.avg_relative,
        'minEligibleRuns',6,'ruleVersion','NPC_RETIRE_V1') END
 FROM my_derby.horses h
 LEFT JOIN form f ON f.horse_id=h.id
 WHERE h.world_id=p_world_id AND h.npc_owner_id IS NOT NULL AND h.owner_user_id IS NULL
  AND h.life_stage='RACING' AND NOT h.racing_retired_permanently
  AND h.breeding_retired_at IS NULL
  AND h.source_model_version IS DISTINCT FROM 'MY_DERBY_SYSTEM_STUD_V1'
  AND NOT EXISTS (SELECT 1 FROM my_derby.npc_retirement_decisions d WHERE d.horse_id=h.id)
  AND (
   (h.health_state='INJURED' AND h.injury_prognosis='RACING_UNFIT')
   OR (h.age_years>=4 AND f.n=6 AND f.unplaced=6
     AND f.bottom_40>=5 AND f.avg_relative>=0.72)
  );
$fn$;