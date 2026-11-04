-- Run once after calendar/RPC migration. Reruns intentionally preserve the player reserve.
with w as (select id from my_derby.worlds where world_key='kra_roster_v1'),
name_pool as (
 select w.id world_id,s.surname||g.given_name name,
  row_number() over(partition by w.id order by md5(w.id::text||s.surname||g.given_name||':npc-owner-v4')) rn
 from w
 cross join unnest(array[
  '김','이','박','최','정','강','조','윤','장','임','한','오','신','서','권',
  '황','송','전','홍','안','문','류','백','남','노','배','유','고','심','변','하','차'
 ]) as s(surname)
 cross join unnest(array[
  '서준','하준','도윤','시우','주원','지호','민재','예준','수연','예린','서연','지우',
  '채원','태현','준혁','유진','민석','선우','주영','동현','지훈','아린','도현','승우',
  '세진','윤호','지원','현우','수빈','준서','태윤','준호','민서','은우','지안','은서',
  '시현','서율','태민','연우','하린','수현','지민','민준','예성','수호','유찬','준영',
  '소윤','유나','나연','도연','예진','유정','규민','승현','성민','준수','현서','정우',
  '진우','원준','현준','범준','동하','시온','다은','지율','아윤','서우'
 ]) as g(given_name)
)
insert into my_derby.npc_owners(world_id,name,reputation,policy)
select w.id,p.name,40+((gs*17)%51),
  jsonb_build_object('agentType','RULE_BASED','worldRulesVersion','v4_world_v1',
    'risk',(array['CONSERVATIVE','BALANCED','AGGRESSIVE'])[1+((gs-1)%3)],
    'distancePreference',(array['SPRINT','MILE','MIDDLE','LONG'])[1+((gs-1)%4)],
    'entryPolicy','FIT_CONDITION_FIRST','active',false,
    'explanation','No autonomous bids, race entry or economics before weekly processor verification')
from w cross join generate_series(1,80) gs
join name_pool p on p.world_id=w.id and p.rn=gs
on conflict(world_id,name) do nothing;

with w as (select id from my_derby.worlds where world_key='kra_roster_v1'),
pool as (
 select h.id,
  row_number() over (order by md5(h.source_hr_no||':myderby-owners-20261029'),h.id)::int rn,
  count(*) over()::int cnt
 from my_derby.horses h cross join w
 where h.world_id=w.id and h.source_model_version='kra_v1'
 and h.owner_user_id is null and h.npc_owner_id is null
 and not exists (
   select 1 from my_derby.horses existing
   where existing.world_id=w.id and existing.npc_owner_id is not null
 )
),owners as (
 select n.id,row_number() over (order by n.name)::int owner_rank,
  count(*) over()::int owner_count
 from my_derby.npc_owners n cross join w where n.world_id=w.id
),assigned as (
 select pool.id horse_id,owners.id npc_owner_id
 from pool join owners on owners.owner_rank=1+((pool.rn-1)%owners.owner_count)
 where pool.rn<=ceil(pool.cnt*0.8)
)
update my_derby.horses h set npc_owner_id=a.npc_owner_id,location='NPC_STABLE'
from assigned a where h.id=a.horse_id and h.owner_user_id is null and h.npc_owner_id is null;

-- NPC roster: 80 agents, 1,109 horses (13/14 each), 277 starter reserves
-- when run on the original 1,386 unowned source horses. Do not re-run the
-- percentage allocation after player sign-ups; the guard prevents this. Future initializations should
-- use an explicit batch ID or seed a separate world.
