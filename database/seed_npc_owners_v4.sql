-- Run once after calendar/RPC migration. Reruns intentionally preserve the player reserve.
with w as (select id from my_derby.worlds where world_key='kra_roster_v1')
insert into my_derby.npc_owners(world_id,name,reputation,policy)
select w.id,'시스템 마주 '||lpad(gs::text,3,'0'),40+((gs*17)%51),
  jsonb_build_object('agentType','RULE_BASED','worldRulesVersion','v4_world_v1',
    'risk',(array['CONSERVATIVE','BALANCED','AGGRESSIVE'])[1+((gs-1)%3)],
    'distancePreference',(array['SPRINT','MILE','MIDDLE','LONG'])[1+((gs-1)%4)],
    'entryPolicy','FIT_CONDITION_FIRST','active',false,
    'explanation','No autonomous bids, race entry or economics before weekly processor verification')
from w cross join generate_series(1,80) gs
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
