-- Game ages advance once for every completed season transition, not on real birthdays.
CREATE OR REPLACE FUNCTION my_derby_private.ensure_horse_birth_date_and_age()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_today date:=(now() AT TIME ZONE 'Asia/Seoul')::date;
  v_age integer:=greatest(coalesce(NEW.age_years,0),0);
  v_first date;
  v_last date;
BEGIN
  IF NEW.source_birth_date IS NULL THEN
    v_first:=(v_today-make_interval(years=>v_age+1)+interval '1 day')::date;
    v_last:=(v_today-make_interval(years=>v_age))::date;
    NEW.source_birth_date:=v_first+
      floor(random()*(v_last-v_first+1))::integer;
  END IF;
  -- Birth date is descriptive source data. It does not drive the game's age.
  NEW.age_years:=v_age;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS horses_birth_date_on_insert ON my_derby.horses;
CREATE TRIGGER horses_birth_date_on_insert
BEFORE INSERT ON my_derby.horses
FOR EACH ROW EXECUTE FUNCTION my_derby_private.ensure_horse_birth_date_and_age();

DROP TRIGGER IF EXISTS horses_age_from_birth_date_on_update ON my_derby.horses;
CREATE TRIGGER horses_age_from_birth_date_on_update
BEFORE UPDATE OF source_birth_date,age_years ON my_derby.horses
FOR EACH ROW EXECUTE FUNCTION my_derby_private.ensure_horse_birth_date_and_age();

CREATE OR REPLACE FUNCTION my_derby_private.progress_world_lifecycle()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  w my_derby.worlds%rowtype;
  v_clock jsonb;
  v_target integer;
  v_day integer;
  v_year integer;
  h record;
  v_age integer;
  v_stage text;
  v_n integer:=0;
  v_transitions integer:=0;
  v_stat jsonb;
  v_potential jsonb;
  v_name text;
  v_growth numeric;
BEGIN
  FOR w IN SELECT * FROM my_derby.worlds
    WHERE status='ACTIVE' AND automatic_processing_enabled
    FOR UPDATE
  LOOP
    v_clock:=my_derby.world_clock(w.id);
    v_target:=(v_clock->>'season')::integer;
    v_day:=(v_clock->>'gameDayStart')::integer;

    -- Apply one age increment per season crossed, including catch-up transitions.
    FOR v_year IN (w.season_number+1)..v_target LOOP
      FOR h IN
        SELECT horse.id,horse.age_years,horse.life_stage,horse.owner_user_id,
          horse.source_meet,horse.source_grade_no,horse.mother_id
        FROM my_derby.horses horse
        WHERE horse.world_id=w.id
        ORDER BY horse.id
        FOR UPDATE OF horse SKIP LOCKED
      LOOP
        v_age:=greatest(0,h.age_years)+1;
        v_stage:=h.life_stage;

        IF h.life_stage='FOAL' AND v_age>=2 AND
          coalesce(h.source_meet,(SELECT mother.source_meet FROM my_derby.horses mother
            WHERE mother.id=h.mother_id)) IS NOT NULL THEN
          v_stage:='RACING';
        ELSIF h.life_stage='FOAL' AND v_age>=1 THEN
          v_stage:='YEARLING';
        ELSIF h.life_stage='YEARLING' AND v_age>=2 AND
          coalesce(h.source_meet,(SELECT mother.source_meet FROM my_derby.horses mother
            WHERE mother.id=h.mother_id)) IS NOT NULL THEN
          v_stage:='RACING';
        END IF;

        IF h.life_stage='RACING' AND v_age>=11 AND h.owner_user_id IS NOT NULL
          AND NOT EXISTS(
            SELECT 1 FROM my_derby.race_entries entry
            JOIN my_derby.races race ON race.id=entry.race_id
            WHERE entry.horse_id=h.id AND entry.status IN('APPLIED','CONFIRMED')
              AND race.status IN('OPEN','CLOSED','RUNNING')
          ) THEN
          v_stage:='RETIRED';
        END IF;

        UPDATE my_derby.horses horse SET age_years=v_age,life_stage=v_stage,
          source_meet=CASE WHEN v_stage='RACING' THEN coalesce(h.source_meet,
            (SELECT mother.source_meet FROM my_derby.horses mother
             WHERE mother.id=h.mother_id)) ELSE h.source_meet END,
          source_grade_no=CASE WHEN v_stage='RACING' THEN coalesce(h.source_grade_no,6)
            ELSE h.source_grade_no END
        WHERE horse.id=h.id;

        INSERT INTO my_derby.season_age_events
          (horse_id,season_number,old_age,new_age,old_stage,new_stage)
        VALUES(h.id,v_year,h.age_years,v_age,h.life_stage,v_stage)
        ON CONFLICT(horse_id,season_number) DO UPDATE SET
          old_age=excluded.old_age,new_age=excluded.new_age,
          old_stage=excluded.old_stage,new_stage=excluded.new_stage,changed_at=now();
        v_n:=v_n+1;

        IF h.life_stage='YEARLING' AND v_stage='RACING' THEN
          SELECT current_stats,potential_stats INTO v_stat,v_potential
          FROM my_derby.horse_abilities WHERE horse_id=h.id FOR UPDATE;
          IF v_stat IS NOT NULL THEN
            FOREACH v_name IN ARRAY ARRAY['start','speed','acceleration','stamina',
              'finishing','power','grit','stability','recovery'] LOOP
              v_growth:=greatest(coalesce((v_stat->>v_name)::numeric,0),
                round(coalesce((v_potential->>v_name)::numeric,50)*0.60,2));
              v_stat:=jsonb_set(v_stat,ARRAY[v_name],
                to_jsonb(least(coalesce((v_potential->>v_name)::numeric,v_growth),v_growth)),true);
            END LOOP;
            UPDATE my_derby.horse_abilities SET current_stats=v_stat,updated_at=now()
            WHERE horse_id=h.id;
          END IF;
        END IF;
      END LOOP;
      v_transitions:=v_transitions+1;
    END LOOP;

    UPDATE my_derby.worlds SET game_day=(v_clock->>'gameDayStart')::integer,
      season_number=v_target WHERE id=w.id;
  END LOOP;

  RETURN jsonb_build_object('status','OK','horsesAged',v_n,
    'seasonTransitions',v_transitions,'ageBasis','SEASON_START');
END
$function$;

REVOKE ALL ON FUNCTION my_derby_private.ensure_horse_birth_date_and_age() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby_private.progress_world_lifecycle() FROM PUBLIC,anon,authenticated;
NOTIFY pgrst,'reload schema';
