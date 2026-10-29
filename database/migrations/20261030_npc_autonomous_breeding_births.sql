
CREATE TABLE IF NOT EXISTS my_derby.npc_breeding_cycles(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 world_id uuid NOT NULL REFERENCES my_derby.worlds(id),
 npc_owner_id uuid NOT NULL REFERENCES my_derby.npc_owners(id),
 mare_id uuid NOT NULL REFERENCES my_derby.horses(id),
 sire_id uuid NOT NULL REFERENCES my_derby.horses(id),
 season_number integer NOT NULL CHECK(season_number>=1),
 conceived_game_day integer NOT NULL,
 due_game_day integer,
 conception_chance numeric NOT NULL,
 status text NOT NULL CHECK(status IN('PREGNANT','FAILED','BORN')),
 foal_id uuid REFERENCES my_derby.horses(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(mare_id,season_number)
);
ALTER TABLE my_derby.npc_breeding_cycles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON my_derby.npc_breeding_cycles FROM anon,authenticated;

CREATE OR REPLACE FUNCTION my_derby_private.process_npc_breeding_pairs()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE mare record; sire my_derby.horses%rowtype;
 v_season int;v_day int;v_assessment jsonb;v_roll numeric;v_chance numeric;
 v_conceived boolean; v_count int:=0;v_pregnant int:=0;v_failed int:=0;
BEGIN
 FOR mare IN SELECT h.id,h.world_id,h.npc_owner_id,
    (my_derby.world_clock(h.world_id)->>'season')::int season,
    (my_derby.world_clock(h.world_id)->>'gameDayStart')::int game_day
  FROM my_derby.horses h
  JOIN my_derby.npc_owners o ON o.id=h.npc_owner_id
  JOIN my_derby.worlds w ON w.id=h.world_id
  WHERE w.status='ACTIVE' AND w.automatic_processing_enabled
   AND (o.policy->>'active')='true'
   AND h.sex='FEMALE' AND h.age_years BETWEEN 4 AND 18
   AND h.life_stage='BROODMARE'
   AND h.breeding_retired_at IS NOT NULL
   AND h.health_state='HEALTHY' AND h.sale_state='NOT_LISTED'
   AND h.breeding_state IN ('AVAILABLE','COOLDOWN')
   AND NOT EXISTS(SELECT 1 FROM my_derby.npc_breeding_cycles bc
    WHERE bc.mare_id=h.id AND bc.season_number=
     (my_derby.world_clock(h.world_id)->>'season')::int)
  ORDER BY h.id FOR UPDATE OF h SKIP LOCKED
 LOOP
  v_season:=mare.season;v_day:=mare.game_day;
  SELECT h.* INTO sire FROM my_derby.horses h
  WHERE h.world_id=mare.world_id AND h.npc_owner_id IS NOT NULL
   AND h.sex='MALE' AND h.age_years BETWEEN 4 AND 25
   AND h.life_stage='STALLION' AND h.breeding_retired_at IS NOT NULL
   AND h.health_state='HEALTHY'
   AND h.sale_state='NOT_LISTED'
   AND (h.source_model_version='MY_DERBY_SYSTEM_STUD_V1'
    OR EXISTS(SELECT 1 FROM my_derby.npc_retirement_decisions dec
     WHERE dec.horse_id=h.id AND dec.converted_to='STALLION'))
   AND ((SELECT count(*) FROM my_derby.npc_breeding_cycles bc
        WHERE bc.sire_id=h.id AND bc.season_number=v_season)
        +(SELECT count(*) FROM my_derby.breeding_requests br
          WHERE br.sire_id=h.id AND br.season_number=v_season))<40
  ORDER BY md5(mare.id::text||h.id::text||v_season::text)
  LIMIT 1 FOR UPDATE OF h SKIP LOCKED;
  IF sire.id IS NULL THEN CONTINUE; END IF;
  v_assessment:=my_derby.breeding_pair_assessment(mare.id,sire.id);
  v_chance:=(v_assessment->>'chance')::numeric;
  v_roll:=(('x'||substr(md5(mare.id::text||sire.id::text||v_season::text),1,8))
     ::bit(32)::bigint % 10000)::numeric/100;
  v_conceived:=v_roll<v_chance;
  INSERT INTO my_derby.npc_breeding_cycles
   (world_id,npc_owner_id,mare_id,sire_id,season_number,conceived_game_day,
    due_game_day,conception_chance,status)
  VALUES(mare.world_id,mare.npc_owner_id,mare.id,sire.id,v_season,v_day,
   CASE WHEN v_conceived THEN v_day+330 ELSE NULL END,
   v_chance,CASE WHEN v_conceived THEN 'PREGNANT' ELSE 'FAILED' END)
  ON CONFLICT(mare_id,season_number) DO NOTHING;
  UPDATE my_derby.horses SET breeding_state=CASE WHEN v_conceived THEN 'PREGNANT' ELSE 'COOLDOWN' END
  WHERE id=mare.id;
  v_count:=v_count+1;
  IF v_conceived THEN v_pregnant:=v_pregnant+1;ELSE v_failed:=v_failed+1;END IF;
 END LOOP;
 RETURN jsonb_build_object('status','OK','paired',v_count,'pregnancies',v_pregnant,'failed',v_failed);
END $fn$;

CREATE OR REPLACE FUNCTION my_derby_private.process_npc_due_births()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE bc my_derby.npc_breeding_cycles%rowtype;
 m my_derby.horses%rowtype;s my_derby.horses%rowtype;v_foal uuid;
 v_ma jsonb;v_pa jsonb;v_gen jsonb:='{}'::jsonb;
 v_potential jsonb:='{}'::jsonb;v_current jsonb:='{}'::jsonb;
 k text; v_gene numeric; v_n int:=0;
BEGIN
 FOR bc IN SELECT q.* FROM my_derby.npc_breeding_cycles q
  JOIN my_derby.worlds w ON w.id=q.world_id
  WHERE q.status='PREGNANT' AND w.status='ACTIVE'
  AND q.due_game_day <= (my_derby.world_clock(w.id)->>'gameDayStart')::int+6
  ORDER BY q.due_game_day,q.id FOR UPDATE OF q SKIP LOCKED
 LOOP
  SELECT * INTO m FROM my_derby.horses WHERE id=bc.mare_id FOR UPDATE;
  SELECT * INTO s FROM my_derby.horses WHERE id=bc.sire_id;
  IF m.id IS NULL OR s.id IS NULL OR m.npc_owner_id IS DISTINCT FROM bc.npc_owner_id
   THEN CONTINUE;END IF;
  SELECT CASE WHEN gene_stats<>'{}'::jsonb THEN gene_stats ELSE potential_stats END
   INTO v_ma FROM my_derby.horse_abilities WHERE horse_id=m.id;
  SELECT CASE WHEN gene_stats<>'{}'::jsonb THEN gene_stats ELSE potential_stats END
   INTO v_pa FROM my_derby.horse_abilities WHERE horse_id=s.id;
  v_gen:='{}'::jsonb;v_potential:='{}'::jsonb;v_current:='{}'::jsonb;
  FOREACH k IN ARRAY ARRAY['start','speed','acceleration','stamina',
   'finishing','power','grit','stability','recovery'] LOOP
   v_gene:=round(least(100,greatest(10,
     coalesce((v_ma->>k)::numeric,65)*0.45+
     coalesce((v_pa->>k)::numeric,65)*0.45+
     (50+((('x'||substring(md5(bc.id::text||k),1,8))::bit(32)::bigint%5100)::numeric/100))*0.10
   )),2);
   v_gen:=jsonb_set(v_gen,ARRAY[k],to_jsonb(v_gene),true);
   v_potential:=jsonb_set(v_potential,ARRAY[k],to_jsonb(round(v_gene*.94,2)),true);
   v_current:=jsonb_set(v_current,ARRAY[k],to_jsonb(round(v_gene*.35,2)),true);
  END LOOP;
  INSERT INTO my_derby.horses
    (world_id,npc_owner_id,name,sex,age_years,father_id,mother_id,life_stage,
     location,health_state,race_entry_state,breeding_state,condition_score,
     fatigue,source_model_version,source_meet,source_grade_no)
  VALUES(m.world_id,m.npc_owner_id,'NPC새별-'||upper(substring(bc.id::text,1,6)),
    CASE WHEN (('x'||substring(md5(bc.id::text),1,2))::bit(8)::int%2)=0
      THEN 'MALE' ELSE 'FEMALE' END,
    0,s.id,m.id,'FOAL','NPC_STABLE','HEALTHY','NONE','AVAILABLE',
    85,0,'MY_DERBY_NPC_BREEDING_V1',m.source_meet,6)
  RETURNING id INTO v_foal;
  INSERT INTO my_derby.horse_abilities
   (horse_id,current_stats,potential_stats,gene_stats,estimation_metadata)
  VALUES(v_foal,v_current,v_potential,v_gen,
   jsonb_build_object('model','MY_DERBY_NPC_BREEDING_V1','birthGameDay',bc.due_game_day,
     'estimatedGenetics',true));
  UPDATE my_derby.npc_breeding_cycles
   SET status='BORN',foal_id=v_foal WHERE id=bc.id AND status='PREGNANT';
  UPDATE my_derby.horses SET breeding_state='COOLDOWN' WHERE id=m.id;
  INSERT INTO my_derby.horse_state_history(horse_id,game_day,event_code,new_state)
   VALUES(v_foal,bc.due_game_day,'NPC_FOAL_BORN',
    jsonb_build_object('mareId',m.id,'sireId',s.id,'ownerNpcId',m.npc_owner_id));
  v_n:=v_n+1;
 END LOOP;
 RETURN jsonb_build_object('status','OK','npcFoalsBorn',v_n);
END $fn$;

REVOKE ALL ON FUNCTION my_derby_private.process_npc_breeding_pairs() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.process_npc_due_births() FROM PUBLIC,anon,authenticated;
SELECT cron.schedule('my-derby-npc-pairings','25 0 * * *',
 'select my_derby_private.process_npc_breeding_pairs();');
SELECT cron.schedule('my-derby-npc-births','30 0 * * *',
 'select my_derby_private.process_npc_due_births();');
