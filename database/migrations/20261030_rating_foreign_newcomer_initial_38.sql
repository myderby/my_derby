-- 2025 KRA guide section 9: new foreign entrants in mixed grade 4
-- are assigned 38 rating; earlier imports are assigned 40.
-- Do not infer foreign origin from horse names, breeds or track.
ALTER TABLE my_derby.horses
 ADD COLUMN IF NOT EXISTS imported_foreign boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS foreign_import_year integer;
ALTER TABLE my_derby.horses DROP CONSTRAINT IF EXISTS horse_foreign_import_year_ck;
ALTER TABLE my_derby.horses ADD CONSTRAINT horse_foreign_import_year_ck
 CHECK(foreign_import_year IS NULL OR foreign_import_year BETWEEN 1900 AND 2100);

CREATE OR REPLACE FUNCTION my_derby_private.apply_foreign_newcomer_initial_rating()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE previous_event boolean;
BEGIN
 IF NEW.imported_foreign IS DISTINCT FROM true OR NEW.foreign_import_year IS NULL
   OR NEW.source_grade_no IS DISTINCT FROM 4 OR NEW.life_stage<>'RACING'
 THEN RETURN NEW;END IF;
 IF NEW.rating_seed_source NOT IN (
   'LEGACY_GRADE_ESTIMATE_NOT_KRA_OFFICIAL',
   'KRA_2025_FOREIGN_NEWCOMER_GAME_38',
   'KRA_PRE2025_FOREIGN_NEWCOMER_GAME_40')
   AND NEW.rating_seed_source IS NOT NULL THEN RETURN NEW; END IF;
 -- Preserve established race-adjusted ratings even if imported metadata changes.
 IF TG_OP='UPDATE' AND EXISTS(SELECT 1 FROM my_derby.horse_rating_events e
   WHERE e.horse_id=NEW.id) THEN RETURN NEW;END IF;
 NEW.domestic_rating:=CASE WHEN NEW.foreign_import_year>=2025 THEN 38 ELSE 40 END;
 NEW.rating_derived_grade:=4;
 NEW.rating_pending_grade:=false;
 NEW.rating_seed_source:=CASE WHEN NEW.foreign_import_year>=2025
 THEN 'KRA_2025_FOREIGN_NEWCOMER_GAME_38'
 ELSE 'KRA_PRE2025_FOREIGN_NEWCOMER_GAME_40' END;
 RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS horse_foreign_newcomer_rating ON my_derby.horses;
CREATE TRIGGER horse_foreign_newcomer_rating
 BEFORE INSERT OR UPDATE OF imported_foreign,foreign_import_year,source_grade_no,life_stage
 ON my_derby.horses
 FOR EACH ROW
 EXECUTE FUNCTION my_derby_private.apply_foreign_newcomer_initial_rating();
REVOKE ALL ON FUNCTION my_derby_private.apply_foreign_newcomer_initial_rating()
 FROM PUBLIC,anon,authenticated;
