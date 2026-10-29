import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(){
 try{
  const api=createPublicDb().schema("my_derby");
  const {data:overview,error:overviewError}=await api.rpc("world_overview");
  if(overviewError||!overview?.ready)throw overviewError??new Error("월드 미등록");
  const gameDay=overview.world.gameDayStart;
  const {data:events,error}=await api.from("races")
   .select("id,track,race_day,start_time,class_name,distance_m,status,prize_policy")
   .eq("world_id",overview.world.worldId)
   .gte("race_day",gameDay).lte("race_day",gameDay+(52*7))
   .order("race_day",{ascending:true}).order("start_time",{ascending:true}).limit(160);
  if(error)throw error;
  return NextResponse.json({
   mode:"OFFICIAL_REGION_PROGRAM",world:overview.world,
   sourceMeetMap:{"서울":"서울","부산경남":"부산","부경":"부산","제주":"영천"},
   races:(events??[]).map(r=>({
    id:r.id,date:r.prize_policy?.kst_date,week:r.prize_policy?.week||
     Math.floor((r.race_day-1)/7)%52+1,
    season:r.prize_policy?.season||Math.floor((r.race_day-1)/364)+1,
    raceDay:r.race_day,time:r.start_time?.slice(0,5),track:r.track,
    grade:r.class_name,distance:r.distance_m,status:r.status,
    sourceMeet:r.prize_policy?.source_meet,
    prizesSettled:r.prize_policy?.prize_status==="SETTLED"
   }))
  },{headers:{"Cache-Control":"no-store"}});
 }catch(err){return NextResponse.json({error:err instanceof Error?err.message:"Program unavailable"},
  {status:503,headers:{"Cache-Control":"no-store"}})}
}
