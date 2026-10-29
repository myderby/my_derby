-- Non-destructive MY DERBY V4 roster checks.
select w.world_key,w.status,w.automatic_processing_enabled,w.game_days_per_real_day,
 w.real_days_per_season,w.race_slots,
 (select count(*)::int from my_derby.npc_owners n where n.world_id=w.id) as npc_owner_count,
 (select count(*)::int from my_derby.horses h where h.world_id=w.id and h.npc_owner_id is not null) as npc_horses,
 (select count(*)::int from my_derby.horses h where h.world_id=w.id and h.owner_user_id is null and h.npc_owner_id is null) as player_reserve,
 (select count(*)::int from my_derby.horses h where h.world_id=w.id and h.owner_user_id is not null) as player_horses
from my_derby.worlds w where w.world_key='kra_roster_v1';

select my_derby.world_overview();
select my_derby.world_npc_standings();

select has_function_privilege('anon','my_derby.join_world(text)','EXECUTE') as anon_cannot_join,
 has_function_privilege('authenticated','my_derby.join_world(text)','EXECUTE') as authenticated_can_join,
 has_column_privilege('authenticated','my_derby.horse_abilities','current_stats','SELECT') as current_visible,
 has_column_privilege('authenticated','my_derby.horse_abilities','potential_stats','SELECT') as hidden_potential_visible,
 has_column_privilege('authenticated','my_derby.horse_abilities','hidden_traits','SELECT') as hidden_traits_visible;
-- Expected: anon_cannot_join=false, authenticated_can_join=true,
-- current_visible=true, hidden_potential_visible=false, hidden_traits_visible=false.
