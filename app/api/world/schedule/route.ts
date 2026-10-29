import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(){
 try{
  const api=createPublicDb().schema("my_derby");
  const {data:summary,error:summaryError}=await api.rpc("world_overview");
  if(summaryError||!summary?.ready)throw summaryError||new Error("월드가 없습니다.");
  const day=summary.world.gameDayStart;
  const {data:cards,error}=await api.from("races")
    .select("id,track,distance_m,class_name,start_time,status,prize_policy,race_day,target_runner_count")
    .eq("world_id",summary.world.worldId).eq("race_day",day)
    .eq("prize_policy->>schedule_version","csv2025_rank_sttime_v2")
    .order("start_time",{ascending:true}).limit(100);
  if(error)throw error;
  return NextResponse.json({mode:"RANK_STTIME_MULTI_RACE",world:summary.world,
   rules:{intervalMinutes:3,resultDelayMinutes:3,sourceRankPreserved:true,
    sourceTimeRebased:true,sourceMeetMap:{"서울":"서울","부산경남":"부산","제주":"영천"}},
   raceCount:(cards||[]).length,
   races:(cards||[]).map(r=>({id:r.id,track:r.track,
    distance_m:r.distance_m,class_name:r.class_name,
    start_time:r.start_time,result_time:r.prize_policy?.result_kst_time,
    status:r.status,source_meet:r.prize_policy?.source_meet,
    source_st_time:r.prize_policy?.source_st_time,
    source_rc_no:r.prize_policy?.source_rc_no,
    slot_index:r.prize_policy?.slot_index,
    slot_sequence:r.prize_policy?.slot_sequence,
    entry_status:r.prize_policy?.entry_status,
    race_day:r.race_day,dusu:r.target_runner_count,actual_starters:r.prize_policy?.actual_starters??0}))},{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Schedule unavailable"},
   {status:503,headers:{"Cache-Control":"no-store"}})}
}
