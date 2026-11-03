-- Only 0.1% of generated starters receive the target-class potential tier.
-- Each stat is then rolled within the horse's shared tier with per-stat noise.
DO $patch_lottery$
DECLARE
  v_def text;
  v_old text;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'my_derby_private.create_tutorial_starter(uuid,uuid,text,text)'::regprocedure
  ) INTO v_def;
  v_old:=v_def;
  v_def:=replace(v_def,
    $old$  IF v_quality_roll<0.03 THEN
    v_quality_tier:='ELITE'; v_growth_low:=0.82; v_growth_high:=1.00;
  ELSIF v_quality_roll<0.15 THEN
    v_quality_tier:='HIGH'; v_growth_low:=0.62; v_growth_high:=0.82;
  ELSIF v_quality_roll<0.70 THEN
    v_quality_tier:='AVERAGE'; v_growth_low:=0.30; v_growth_high:=0.62;
  ELSE
    v_quality_tier:='LOW'; v_growth_low:=0.05; v_growth_high:=0.30;
  END IF;$old$,
    $new$  IF v_quality_roll<0.001 THEN
    v_quality_tier:='TARGET'; v_growth_low:=0.94; v_growth_high:=1.00;
  ELSIF v_quality_roll<0.01 THEN
    v_quality_tier:='EXCELLENT'; v_growth_low:=0.78; v_growth_high:=0.94;
  ELSIF v_quality_roll<0.05 THEN
    v_quality_tier:='HIGH'; v_growth_low:=0.58; v_growth_high:=0.80;
  ELSIF v_quality_roll<0.30 THEN
    v_quality_tier:='AVERAGE'; v_growth_low:=0.30; v_growth_high:=0.60;
  ELSE
    v_quality_tier:='LOW'; v_growth_low:=0.05; v_growth_high:=0.30;
  END IF;$new$);
  IF v_def=v_old OR position('v_quality_roll<0.001' in v_def)=0
    OR position('v_quality_tier:=''TARGET''' in v_def)=0 THEN
    RAISE EXCEPTION 'Could not safely update tutorial horse lottery odds';
  END IF;
  EXECUTE v_def;
END
$patch_lottery$;
