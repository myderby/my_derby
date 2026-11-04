-- Only horses already converted to breeding stock should be labelled as sires.
DO $migration$
DECLARE definition text;
BEGIN
 SELECT pg_get_functiondef('my_derby.world_horse_offspring_profile(uuid,integer,integer)'::regprocedure)
 INTO definition;
 definition:=replace(definition,
  'CASE WHEN h.sex=''MALE'' THEN ''씨수말'' WHEN h.sex=''FEMALE'' AND h.life_stage=''BROODMARE''',
  'CASE WHEN h.sex=''MALE'' AND h.life_stage=''STALLION'' THEN ''씨수말'' WHEN h.sex=''FEMALE'' AND h.life_stage=''BROODMARE''');
 IF position('CASE WHEN h.sex=''MALE'' AND h.life_stage=''STALLION'' THEN ''씨수말''' in definition)=0
  THEN RAISE EXCEPTION 'OFFSPRING_STATUS_PATCH_FAILED';
 END IF;
 EXECUTE definition;
END
$migration$;
NOTIFY pgrst,'reload schema';
