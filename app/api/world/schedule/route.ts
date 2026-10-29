import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(){
 try{
  const db=createPublicDb().schema("my_derby");
  const {data:summary,error:summaryError}=await db.rpc("world_overview");
  if(summaryError||!summary?.ready)throw summaryError??new Error("월드 정보가 없습니다.");
  const gameDay=summary.world.gameDayStart;
  const {data:cards,error}=await db.from("races")
   .select("id,track,distance_m,class_name,start_time,status,prize_policy,race_day")
   .eq("world_id",summary.world.worldId).eq("race_day",gameDay)
   .order("start_time",{ascending:true});
  if(error)throw error;
  return NextResponse.json({mode:"OFFICIAL_PROGRAM",world:summary.world,
   races:(cards??[]).map(r=>({id:r.id,track:r.track,distance_m:r.distance_m,
    class_name:r.class_name,start_time:r.start_time,status:r.status,
    source_meet:r.prize_policy?.source_meet,prize_status:r.prize_policy?.prize_status,
    race_day:r.race_day}))},{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Schedule unavailable"},
  {status:503,headers:{"Cache-Control":"no-store"}})}
}
