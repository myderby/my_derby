-- New-player story: award tutorial horses only after the player completes each
-- relevant action. Existing players keep their current horses and tutorial state.

ALTER TABLE my_derby.horses
  ADD COLUMN IF NOT EXISTS tutorial_starter_type text,
  ADD COLUMN IF NOT EXISTS tutorial_entry_fee_waived boolean NOT NULL DEFAULT false;
ALTER TABLE my_derby.horses DROP CONSTRAINT IF EXISTS horses_tutorial_starter_type_check;
ALTER TABLE my_derby.horses ADD CONSTRAINT horses_tutorial_starter_type_check
  CHECK (tutorial_starter_type IS NULL OR tutorial_starter_type IN ('YOUNG','GRADE6','US_GRADE4'));

ALTER TABLE my_derby.player_tutorial_progress
  ADD COLUMN IF NOT EXISTS story_stage integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS seen_topics jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE my_derby.player_tutorial_progress DROP CONSTRAINT IF EXISTS player_tutorial_progress_story_stage_check;
ALTER TABLE my_derby.player_tutorial_progress ADD CONSTRAINT player_tutorial_progress_story_stage_check
  CHECK (story_stage BETWEEN 0 AND 3);
ALTER TABLE my_derby.player_tutorial_progress DROP CONSTRAINT IF EXISTS player_tutorial_progress_seen_topics_check;
ALTER TABLE my_derby.player_tutorial_progress ADD CONSTRAINT player_tutorial_progress_seen_topics_check
  CHECK (jsonb_typeof(seen_topics)='array');

-- Existing joined users have already received the prior starter package.
INSERT INTO my_derby.player_tutorial_progress(user_id,current_step,completed,story_stage)
SELECT user_id,5,true,3 FROM my_derby.profiles WHERE initial_setup_complete
ON CONFLICT(user_id) DO NOTHING;

-- Preserve the existing validated setup RPC, but assign only the 2-year-old
-- horse and persist a tutorial marker for its first-entry fee waiver.
DO $migration$
DECLARE
  v_def text;
  v_old text;
BEGIN
  SELECT pg_catalog.pg_get_functiondef('my_derby.join_world(text,text,jsonb)'::regprocedure)
    INTO v_def;
  v_old := v_def;
  v_def := replace(v_def,
    '    location=CASE WHEN selected.starter_type=''YOUNG'' THEN ''OWNER_RANCH'' ELSE ''NPC_STABLE'' END,',
    '    location=''OWNER_RANCH'', tutorial_starter_type=''YOUNG'', tutorial_entry_fee_waived=true,');
  v_def := replace(v_def,
    '  WHERE h.id=selected.id;',
    '  WHERE h.id=selected.id AND selected.starter_type=''YOUNG'';');
  v_def := replace(v_def,'IF v_assigned<>3 THEN','IF v_assigned<>1 THEN');
  v_def := replace(v_def,
    '''starterPackage'',jsonb_build_array(''2세 육성마'',''3세 6등급 신마'',''3세 미국산 외국 4등급 신마''),',
    '''starterPackage'',jsonb_build_array(''2세 육성마''),''storyStage'',0,');
  v_def := replace(v_def,
    '  UPDATE my_derby.profiles' || chr(10) ||
    '    SET initial_setup_complete=true,updated_at=now()' || chr(10) ||
    '    WHERE user_id=v_uid;',
    '  UPDATE my_derby.profiles' || chr(10) ||
    '    SET initial_setup_complete=true,updated_at=now()' || chr(10) ||
    '    WHERE user_id=v_uid;' || chr(10) || chr(10) ||
    '  INSERT INTO my_derby.player_tutorial_progress(user_id,story_stage,completed)' || chr(10) ||
    '    VALUES(v_uid,0,false) ON CONFLICT(user_id) DO NOTHING;');
  IF v_def=v_old
    OR position('tutorial_starter_type=''YOUNG''' in v_def)=0
    OR position('v_assigned<>1' in v_def)=0
    OR position('VALUES(v_uid,0,false)' in v_def)=0 THEN
    RAISE EXCEPTION 'Could not safely patch join_world for staged tutorial onboarding';
  END IF;
  EXECUTE v_def;
END
$migration$;

CREATE OR REPLACE FUNCTION my_derby_private.award_tutorial_grade6_after_course()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_world uuid;
  v_horse uuid;
BEGIN
  IF NEW.status<>'ACTIVE' OR NEW.course_type<>'YOUNG_BASIC' THEN RETURN NEW; END IF;
  SELECT p.world_id INTO v_world FROM my_derby.profiles p
    WHERE p.user_id=NEW.owner_user_id AND p.initial_setup_complete;
  IF v_world IS NULL THEN RETURN NEW; END IF;
  IF NOT EXISTS(SELECT 1 FROM my_derby.player_tutorial_progress t
    WHERE t.user_id=NEW.owner_user_id AND t.story_stage=0) THEN RETURN NEW; END IF;

  SELECT h.id INTO v_horse
  FROM my_derby.horses h
  WHERE h.world_id=v_world AND h.owner_user_id IS NULL AND h.npc_owner_id IS NULL
    AND h.source_model_version='kra_v1' AND h.life_stage='RACING'
    AND h.racing_retired_permanently=false AND h.breeding_retired_at IS NULL
    AND h.age_years=3 AND h.source_grade_no=6
  ORDER BY h.id LIMIT 1 FOR UPDATE OF h SKIP LOCKED;
  IF v_horse IS NULL THEN RAISE EXCEPTION 'STARTER_GRADE6_UNAVAILABLE'; END IF;

  UPDATE my_derby.horses SET owner_user_id=NEW.owner_user_id,
    location='NPC_STABLE',tutorial_starter_type='GRADE6',tutorial_entry_fee_waived=true
    WHERE id=v_horse;
  UPDATE my_derby.player_tutorial_progress SET story_stage=1,completed=false,updated_at=now()
    WHERE user_id=NEW.owner_user_id AND story_stage=0;
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION my_derby_private.award_tutorial_grade6_after_course() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS trg_award_tutorial_grade6_after_course ON my_derby.ranch_course_requests;
CREATE TRIGGER trg_award_tutorial_grade6_after_course
AFTER INSERT ON my_derby.ranch_course_requests
FOR EACH ROW EXECUTE FUNCTION my_derby_private.award_tutorial_grade6_after_course();

CREATE OR REPLACE FUNCTION my_derby_private.award_tutorial_foreign_horse_after_entry()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_world uuid;
  v_horse uuid;
BEGIN
  IF NEW.status<>'CONFIRMED' OR NEW.owner_user_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND OLD.status='CONFIRMED' THEN RETURN NEW; END IF;
  SELECT p.world_id INTO v_world FROM my_derby.profiles p
    WHERE p.user_id=NEW.owner_user_id AND p.initial_setup_complete;
  IF v_world IS NULL OR NOT EXISTS(SELECT 1 FROM my_derby.player_tutorial_progress t
    WHERE t.user_id=NEW.owner_user_id AND t.story_stage=1) THEN RETURN NEW; END IF;

  SELECT h.id INTO v_horse
  FROM my_derby.horses h
  JOIN my_derby.horse_source_profiles sp ON sp.horse_id=h.id
  WHERE h.world_id=v_world AND h.owner_user_id IS NULL AND h.npc_owner_id IS NULL
    AND h.source_model_version='kra_v1' AND h.life_stage='RACING'
    AND h.racing_retired_permanently=false AND h.breeding_retired_at IS NULL
    AND h.age_years=3 AND h.source_grade_no=4
    AND lower(btrim(sp.country)) IN ('미국','usa','united states','united states of america')
  ORDER BY h.id LIMIT 1 FOR UPDATE OF h SKIP LOCKED;
  IF v_horse IS NULL THEN RAISE EXCEPTION 'STARTER_US_GRADE4_UNAVAILABLE'; END IF;

  UPDATE my_derby.horses SET owner_user_id=NEW.owner_user_id,
    location='NPC_STABLE',imported_foreign=true,foreign_import_year=2026,
    tutorial_starter_type='US_GRADE4',tutorial_entry_fee_waived=true
    WHERE id=v_horse;
  UPDATE my_derby.player_tutorial_progress SET story_stage=2,completed=false,updated_at=now()
    WHERE user_id=NEW.owner_user_id AND story_stage=1;
  RETURN NEW;
END
$function$;
REVOKE ALL ON FUNCTION my_derby_private.award_tutorial_foreign_horse_after_entry() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS trg_award_tutorial_foreign_horse_after_entry ON my_derby.race_entries;
CREATE TRIGGER trg_award_tutorial_foreign_horse_after_entry
AFTER INSERT OR UPDATE OF status ON my_derby.race_entries
FOR EACH ROW EXECUTE FUNCTION my_derby_private.award_tutorial_foreign_horse_after_entry();

-- Replace only the entry-fee section of the current validated race-entry RPC.
-- Each of the three tutorial horses gets exactly one free entry application.
DO $migration$
DECLARE
  v_def text;
  v_old text;
  v_fee text := $fee$
 PERFORM my_derby_private.wallet_mutate(
   v_user,v_world,v_r.race_day,
   -floor(my_derby_private.economy_grade_pool((v_r.prize_policy->>'grade_no')::int)
     * (SELECT amount FROM my_derby.economy_config
        WHERE key='ENTRY_FEE_BASIS_POINTS')/10000.0)::bigint,
   'RACE_ENTRY_FEE','RACE_ENTRY',md5(p_race_id::text||':'||p_horse_id::text)::uuid);
$fee$;
  v_waiver text := $waiver$
 IF v_h.tutorial_entry_fee_waived THEN
   UPDATE my_derby.horses SET tutorial_entry_fee_waived=false WHERE id=p_horse_id;
 ELSE
  PERFORM my_derby_private.wallet_mutate(
   v_user,v_world,v_r.race_day,
   -floor(my_derby_private.economy_grade_pool((v_r.prize_policy->>'grade_no')::int)
     * (SELECT amount FROM my_derby.economy_config
        WHERE key='ENTRY_FEE_BASIS_POINTS')/10000.0)::bigint,
   'RACE_ENTRY_FEE','RACE_ENTRY',md5(p_race_id::text||':'||p_horse_id::text)::uuid);
 END IF;
$waiver$;
BEGIN
  SELECT pg_catalog.pg_get_functiondef('my_derby.apply_player_race_entry(uuid,uuid)'::regprocedure)
    INTO v_def;
  v_old := v_def;
  v_def := replace(v_def,v_fee,v_waiver);
  IF v_def=v_old OR position('tutorial_entry_fee_waived' in v_def)=0 THEN
    RAISE EXCEPTION 'Could not safely patch apply_player_race_entry fee handling';
  END IF;
  EXECUTE v_def;
END
$migration$;
