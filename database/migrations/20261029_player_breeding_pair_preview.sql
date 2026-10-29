CREATE OR REPLACE FUNCTION my_derby.player_breeding_pair_preview(p_mare_id uuid,p_sire_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid(); w uuid; mare my_derby.horses%rowtype;
 sire my_derby.horses%rowtype; a jsonb; c jsonb;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT world_id INTO w FROM my_derby.profiles WHERE user_id=u AND initial_setup_complete;
 IF w IS NULL THEN RAISE EXCEPTION 'JOIN_WORLD_FIRST' USING ERRCODE='42501';END IF;
 SELECT * INTO mare FROM my_derby.horses WHERE id=p_mare_id;
 SELECT * INTO sire FROM my_derby.horses WHERE id=p_sire_id;
 IF mare.id IS NULL OR mare.world_id IS DISTINCT FROM w OR mare.owner_user_id IS DISTINCT FROM u
  THEN RAISE EXCEPTION 'MARE_NOT_OWNED' USING ERRCODE='42501';END IF;
 IF mare.sex<>'FEMALE' THEN RAISE EXCEPTION 'MARE_NOT_ELIGIBLE'; END IF;
 IF sire.id IS NULL OR sire.world_id IS DISTINCT FROM w
  OR (sire.owner_user_id IS DISTINCT FROM u
   AND sire.source_model_version IS DISTINCT FROM 'MY_DERBY_SYSTEM_STUD_V1')
  OR sire.sex<>'MALE' OR sire.life_stage<>'STALLION'
  THEN RAISE EXCEPTION 'SIRE_NOT_AVAILABLE';END IF;
 a:=my_derby.breeding_pair_assessment(mare.id,sire.id);
 c:=my_derby.world_clock(w);
 RETURN a||jsonb_build_object('mareName',mare.name,'sireName',sire.name,
  'mareEligible',mare.age_years BETWEEN 4 AND 18 AND mare.life_stage='BROODMARE'
   AND mare.breeding_state IN ('AVAILABLE','COOLDOWN')
   AND NOT EXISTS(SELECT 1 FROM my_derby.breeding_requests br
      WHERE br.mare_id=mare.id AND br.season_number=(c->>'season')::int)
   AND NOT EXISTS(SELECT 1 FROM my_derby.pregnancies pr
      WHERE pr.mare_id=mare.id AND pr.status='PREGNANT'),
  'warning','Compatibility and kinship use estimated or incomplete pedigree.');
END $fn$;
REVOKE ALL ON FUNCTION my_derby.player_breeding_pair_preview(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_breeding_pair_preview(uuid,uuid) TO authenticated;