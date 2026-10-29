import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
import {simulateRace} from "../../../../lib/racing/engine";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export const maxDuration=60;
// Read-only integration smoke test: no result/entry/economy writes.
export async function GET(){
 try{
  const secret=process.env.CRON_SECRET;
  if(!secret)throw new Error("Processor configuration missing");
  const db=createPublicDb().schema("my_derby");
  const {data:world,error:worldError}=await db.rpc("world_overview");
  if(worldError||!world?.ready)throw worldError||new Error("No world");
  const {data:race,error:raceError}=await db.from("races").select("id,track,distance_m,start_time")
   .eq("world_id",world.world.worldId).eq("race_day",world.world.gameDayStart)
   .eq("prize_policy->>schedule_version","csv2025_rank_sttime_v2")
   .order("start_time",{ascending:true}).limit(1).single();
  if(raceError||!race)throw raceError||new Error("No race today");
  const {data:input,error:inputError}=await db.rpc("secure_program_preview_race",
   {p_secret:secret,p_race_id:race.id});
  if(inputError||input?.status!=="PREVIEW")throw inputError||new Error("No confirmed runners");
  const result=simulateRace(input.input);
  return NextResponse.json({ok:true,mode:"READ_ONLY_SMOKE",source:"my_derby",
   raceId:race.id,track:race.track,distanceM:race.distance_m,
   actualRunners:result.results.length,sections:result.sections.length,
   resultEngineVersion:result.version,
   officialResultsChanged:false},{headers:{"Cache-Control":"no-store"}});
 }catch(error){
  return NextResponse.json({ok:false,error:error instanceof Error?error.message:"Test failed"},
    {status:503,headers:{"Cache-Control":"no-store"}});
 }
}
