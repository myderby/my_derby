-- Keep 20 selectable trainers per region. Existing contracts on the
-- additional legacy trainers remain intact and continue to provide training.
DO $roster$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM my_derby.npc_stables s
    JOIN my_derby.worlds w ON w.id=s.world_id
    LEFT JOIN my_derby.npc_trainers t ON t.stable_id=s.id
    WHERE w.status='ACTIVE'
    GROUP BY s.world_id,s.track
    HAVING count(t.id)<20
  ) THEN
    RAISE EXCEPTION 'An active regional stable has fewer than 20 trainer records';
  END IF;
END;
$roster$;

WITH trainer_load AS (
  SELECT t.id,s.world_id,s.track,
    count(tc.id) FILTER (WHERE tc.status='ACTIVE')::integer AS contract_count
  FROM my_derby.npc_trainers t
  JOIN my_derby.npc_stables s ON s.id=t.stable_id
  LEFT JOIN my_derby.trainer_contracts tc ON tc.trainer_id=t.id
  GROUP BY t.id,s.world_id,s.track
), ranked_base AS (
  SELECT trainer_load.*,
    row_number() OVER (
      PARTITION BY world_id,track
      ORDER BY contract_count,md5(id::text||':trainer-active-roster-v1')
    ) AS active_rank,
    row_number() OVER (
      PARTITION BY world_id,track
      ORDER BY md5(id::text||':trainer-name-roster-v1')
    ) AS name_rank,
    count(*) OVER (PARTITION BY world_id)::integer AS world_trainer_count
  FROM trainer_load
), ranked AS (
  SELECT ranked_base.*,
    row_number() OVER (
      PARTITION BY world_id
      ORDER BY CASE WHEN active_rank=1 THEN 0
        WHEN active_rank>20 THEN 1 ELSE 2 END,
        md5(id::text||':trainer-foreign-roster-v1')
    ) AS foreign_rank
  FROM ranked_base
), korean_names AS (
  SELECT surname||given_name AS name,
    row_number() OVER (ORDER BY md5(surname||given_name||':trainer-name-pool-v1')) AS name_rank
  FROM unnest(ARRAY[
    '김','이','박','최','정','강','조','윤','장','임','한','오','신','서','권',
    '황','송','전','홍','안','문','류','백','남','노','배','유','고','심','변','하','차'
  ]) AS family(surname)
  CROSS JOIN unnest(ARRAY[
    '서준','하준','도윤','시우','주원','지호','민재','예준','수연','예린','서연','지우',
    '채원','태현','준혁','유진','민석','선우','주영','동현','지훈','아린','도현','승우',
    '세진','윤호','지원','현우','수빈','준서','태윤','준호','민서','은우','지안','은서',
    '시현','서율','태민','연우','하린','수현','지민','민준','예성','수호','유찬','준영',
    '소윤','유나','나연','도연','예진','유정','규민','승현','성민','준수','현서','정우',
    '진우','원준','현준','범준','동하','시온','다은','지율','아윤','서우'
  ]) AS given(given_name)
), foreign_names AS (
  SELECT ARRAY[
    '제임스 윌슨','마이클 브라운','올리버 케인','다니엘 밀러','루카스 로시',
    '에밀리 파커','소피아 클라크','노아 베넷','에단 콜린스','엘리자베스 모건',
    '리암 스미스','그레이스 테일러','벤자민 리','이사벨라 로페즈','헨리 워커',
    '샬럿 영','알렉산더 리','빅토리아 그린','세바스찬 코스타','나탈리 리드'
  ]::text[] AS names
), assigned AS (
  SELECT r.*,
    names.names[1+((('x'||substr(md5(r.world_id::text||r.track||':foreign-name-v1'),1,8))
      ::bit(32)::bigint & 2147483647) % cardinality(names.names))::integer] AS foreign_name,
    k.name AS korean_name
  FROM ranked r
  JOIN korean_names k ON k.name_rank=r.name_rank
  CROSS JOIN foreign_names names
)
UPDATE my_derby.npc_trainers t SET
  is_active=(a.active_rank<=20),
  name=CASE
    WHEN a.foreign_rank<=greatest(3,floor(a.world_trainer_count*0.04)::integer) THEN a.foreign_name
    ELSE a.korean_name
  END
FROM assigned a
WHERE t.id=a.id;

-- Random full names for the NPC owners, preserving all owner IDs and policies.
UPDATE my_derby.npc_owners
SET name='임시마주-'||id::text;

WITH owner_order AS (
  SELECT o.id,o.world_id,
    row_number() OVER (
      PARTITION BY o.world_id
      ORDER BY md5(o.id::text||':npc-owner-name-order-v1')
    ) AS owner_rank
  FROM my_derby.npc_owners o
), owner_name_pool AS (
  SELECT surname||given_name AS name,
    row_number() OVER (ORDER BY md5(surname||given_name||':npc-owner-name-pool-v1')) AS name_rank
  FROM unnest(ARRAY[
    '김','이','박','최','정','강','조','윤','장','임','한','오','신','서','권',
    '황','송','전','홍','안','문','류','백','남','노','배','유','고','심','변','하','차'
  ]) AS family(surname)
  CROSS JOIN unnest(ARRAY[
    '서준','하준','도윤','시우','주원','지호','민재','예준','수연','예린','서연','지우',
    '채원','태현','준혁','유진','민석','선우','주영','동현','지훈','아린','도현','승우',
    '세진','윤호','지원','현우','수빈','준서','태윤','준호','민서','은우','지안','은서',
    '시현','서율','태민','연우','하린','수현','지민','민준','예성','수호','유찬','준영',
    '소윤','유나','나연','도연','예진','유정','규민','승현','성민','준수','현서','정우',
    '진우','원준','현준','범준','동하','시온','다은','지율','아윤','서우'
  ]) AS given(given_name)
)
UPDATE my_derby.npc_owners o SET name=p.name
FROM owner_order ord
JOIN owner_name_pool p ON p.name_rank=ord.owner_rank
WHERE o.id=ord.id;

-- Existing active contracts to archived trainers remain valid and retain
-- trainer skill/specialty effects. New contracts still require an active
-- trainer through player_apply_trainer and the stable board.
DO $patch$
DECLARE
  v_definition text;
  v_join text := 'JOIN my_derby.npc_trainers nt ON nt.id=c.trainer_id AND nt.is_active';
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'my_derby_private.process_training_for_horse_day(uuid,integer)'::regprocedure
  ) INTO v_definition;
  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'process_training_for_horse_day was not found';
  END IF;
  IF position(v_join IN v_definition)>0 THEN
    v_definition:=replace(v_definition,v_join,
      'JOIN my_derby.npc_trainers nt ON nt.id=c.trainer_id');
    EXECUTE v_definition;
  ELSIF position('JOIN my_derby.npc_trainers nt ON nt.id=c.trainer_id' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely retain training for existing trainer contracts';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(
    'my_derby.apply_player_race_entry(uuid,uuid)'::regprocedure
  ) INTO v_definition;
  v_join := 'JOIN my_derby.npc_trainers nt ON nt.id=tc.trainer_id AND nt.is_active';
  IF position(v_join IN v_definition)>0 THEN
    v_definition:=replace(v_definition,v_join,
      'JOIN my_derby.npc_trainers nt ON nt.id=tc.trainer_id');
    EXECUTE v_definition;
  ELSIF position('JOIN my_derby.npc_trainers nt ON nt.id=tc.trainer_id' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not safely retain race eligibility for existing trainer contracts';
  END IF;
END;
$patch$;
