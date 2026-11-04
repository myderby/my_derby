-- Expand the selectable NPC trainer roster to the requested regional sizes.
-- Existing trainer contracts and skill data are preserved.
DO $guard$
BEGIN
  IF EXISTS (
    WITH desired(track,target) AS (
      VALUES ('부산',40),('서울',60),('영천',30)
    )
    SELECT 1
    FROM my_derby.worlds w
    CROSS JOIN desired d
    LEFT JOIN my_derby.npc_stables s ON s.world_id=w.id AND s.track=d.track
    LEFT JOIN my_derby.npc_trainers t ON t.stable_id=s.id
    WHERE w.status='ACTIVE'
    GROUP BY w.id,d.track,d.target
    HAVING count(t.id)>d.target OR count(s.id)=0
  ) THEN
    RAISE EXCEPTION 'Active regional trainer roster exceeds its target or has no stable';
  END IF;
END;
$guard$;

WITH desired(track,target) AS (
  VALUES ('부산',40),('서울',60),('영천',30)
), active_worlds AS (
  SELECT id AS world_id FROM my_derby.worlds WHERE status='ACTIVE'
), regional_counts AS (
  SELECT w.world_id,d.track,d.target,count(t.id)::integer AS current_count
  FROM active_worlds w
  CROSS JOIN desired d
  LEFT JOIN my_derby.npc_stables s ON s.world_id=w.world_id AND s.track=d.track
  LEFT JOIN my_derby.npc_trainers t ON t.stable_id=s.id
  GROUP BY w.world_id,d.track,d.target
), stable_order AS (
  SELECT s.id AS stable_id,s.world_id,s.track,
    row_number() OVER (
      PARTITION BY s.world_id,s.track
      ORDER BY md5(s.id::text||':trainer-roster-v2-stable')
    ) AS stable_rank,
    count(*) OVER (PARTITION BY s.world_id,s.track)::integer AS stable_count
  FROM my_derby.npc_stables s
  JOIN active_worlds w ON w.world_id=s.world_id
  JOIN desired d ON d.track=s.track
), slots AS (
  SELECT rc.world_id,rc.track,gs.slot_number,
    row_number() OVER (
      PARTITION BY rc.world_id ORDER BY md5(rc.world_id::text||rc.track||gs.slot_number||':trainer-roster-v2-slot')
    ) AS name_rank,
    so.stable_id
  FROM regional_counts rc
  CROSS JOIN LATERAL generate_series(1,rc.target-rc.current_count) AS gs(slot_number)
  JOIN stable_order so ON so.world_id=rc.world_id AND so.track=rc.track
    AND so.stable_rank=1+((gs.slot_number-1)%so.stable_count)
), name_pool AS (
  SELECT s.surname||g.given_name AS name,
    row_number() OVER (ORDER BY md5(s.surname||g.given_name||':trainer-roster-v2-name')) AS name_rank
  FROM unnest(ARRAY[
    '김','이','박','최','정','강','조','윤','장','임','한','오','신','서','권',
    '황','송','전','홍','안','문','류','백','남','노','배','유','고','심','변','하','차'
  ]) AS s(surname)
  CROSS JOIN unnest(ARRAY[
    '서준','하준','도윤','시우','주원','지호','민재','예준','수연','예린','서연','지우',
    '채원','태현','준혁','유진','민석','선우','주영','동현','지훈','아린','도현','승우',
    '세진','윤호','지원','현우','수빈','준서','태윤','준호','민서','은우','지안','은서',
    '시현','서율','태민','연우','하린','수현','지민','민준','예성','수호','유찬','준영',
    '소윤','유나','나연','도연','예진','유정','규민','승현','성민','준수','현서','정우',
    '진우','원준','현준','범준','동하','시온','다은','지율','아윤','서우'
  ]) AS g(given_name)
), available_names AS (
  SELECT np.name,
    row_number() OVER (ORDER BY md5(np.name||':trainer-roster-v2-available')) AS name_rank
  FROM name_pool np
  WHERE NOT EXISTS (
    SELECT 1 FROM my_derby.npc_trainers t WHERE t.name=np.name
  )
), new_trainers AS (
  SELECT sl.world_id,sl.track,sl.slot_number,sl.stable_id,an.name,
    55+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-speed'),1,8))::bit(32)::bigint & 2147483647)%31)::integer AS speed,
    55+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-stamina'),1,8))::bit(32)::bigint & 2147483647)%31)::integer AS stamina,
    55+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-power'),1,8))::bit(32)::bigint & 2147483647)%31)::integer AS power,
    55+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-grit'),1,8))::bit(32)::bigint & 2147483647)%31)::integer AS grit,
    55+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-start'),1,8))::bit(32)::bigint & 2147483647)%31)::integer AS start,
    55+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-finish'),1,8))::bit(32)::bigint & 2147483647)%31)::integer AS finishing,
    55+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-recovery'),1,8))::bit(32)::bigint & 2147483647)%31)::integer AS recovery,
    55+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-acceleration'),1,8))::bit(32)::bigint & 2147483647)%31)::integer AS acceleration,
    55+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-stability'),1,8))::bit(32)::bigint & 2147483647)%31)::integer AS stability,
    (ARRAY['단거리','마일','중거리','장거리'])[1+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-distance'),1,8))::bit(32)::bigint & 2147483647)%4)::integer] AS distance_specialty,
    (ARRAY['도주','선행','선입','추입'])[1+((('x'||substr(md5(sl.world_id::text||sl.track||sl.slot_number||':trainer-v2-style'),1,8))::bit(32)::bigint & 2147483647)%4)::integer] AS style_specialty
  FROM slots sl
  JOIN available_names an ON an.name_rank=sl.name_rank
)
INSERT INTO my_derby.npc_trainers(stable_id,name,skill_stats,specialties,capacity,is_active)
SELECT stable_id,name,
  jsonb_build_object('speed',speed,'stamina',stamina,'power',power,'grit',grit,
    'start',start,'finishing',finishing,'recovery',recovery,'acceleration',acceleration,'stability',stability),
  ARRAY[distance_specialty,style_specialty],40,true
FROM new_trainers;

-- Make the entire requested roster selectable, including pre-existing
-- trainers whose legacy contracts remain attached to them.
UPDATE my_derby.npc_trainers t
SET is_active=true
FROM my_derby.npc_stables s
JOIN my_derby.worlds w ON w.id=s.world_id
WHERE t.stable_id=s.id
  AND w.status='ACTIVE'
  AND s.track IN ('부산','서울','영천');

-- Keep foreign-name trainers between 3% and 5% within each regional roster.
WITH regional_foreign AS (
  SELECT s.world_id,s.track,count(*)::integer AS trainer_count,
    count(*) FILTER (WHERE t.name ~ ' ')::integer AS foreign_count
  FROM my_derby.npc_trainers t
  JOIN my_derby.npc_stables s ON s.id=t.stable_id
  JOIN my_derby.worlds w ON w.id=s.world_id
  WHERE w.status='ACTIVE' AND t.is_active AND s.track IN ('부산','서울','영천')
  GROUP BY s.world_id,s.track
), needed AS (
  SELECT *,greatest(0,ceil(trainer_count*0.03)::integer-foreign_count) AS additions
  FROM regional_foreign
), trainer_candidates AS (
  SELECT t.id,s.world_id,s.track,
    row_number() OVER (PARTITION BY s.world_id,s.track ORDER BY md5(t.id::text||':foreign-trainer-v2')) AS local_rank
  FROM my_derby.npc_trainers t
  JOIN my_derby.npc_stables s ON s.id=t.stable_id
  JOIN needed n ON n.world_id=s.world_id AND n.track=s.track
  WHERE t.is_active AND t.name !~ ' '
), foreign_names AS (
  SELECT name,row_number() OVER (ORDER BY md5(name||':foreign-trainer-v2')) AS name_rank
  FROM unnest(ARRAY[
    '제임스 윌슨','마이클 브라운','올리버 케인','다니엘 밀러','루카스 로시',
    '에밀리 파커','소피아 클라크','노아 베넷','에단 콜린스','엘리자베스 모건',
    '리암 스미스','그레이스 테일러','벤자민 리','이사벨라 로페즈','헨리 워커',
    '샬럿 영','알렉산더 리','빅토리아 그린','세바스찬 코스타','나탈리 리드'
  ]) AS pool(name)
  WHERE NOT EXISTS (SELECT 1 FROM my_derby.npc_trainers t WHERE t.name=pool.name)
), assignments AS (
  SELECT tc.id,fn.name,
    row_number() OVER (PARTITION BY tc.world_id ORDER BY tc.track,tc.local_rank) AS global_rank
  FROM trainer_candidates tc
  JOIN needed n ON n.world_id=tc.world_id AND n.track=tc.track
    AND tc.local_rank<=n.additions
  JOIN foreign_names fn ON fn.name_rank=1+(
    SELECT count(*) FROM trainer_candidates prior
    JOIN needed pn ON pn.world_id=prior.world_id AND pn.track=prior.track
    WHERE prior.world_id=tc.world_id AND prior.local_rank<=pn.additions
      AND (prior.track,prior.local_rank)<(tc.track,tc.local_rank)
  )
)
UPDATE my_derby.npc_trainers t SET name=a.name
FROM assignments a
WHERE t.id=a.id;
