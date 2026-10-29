import {NextResponse} from "next/server";
import {randomInt} from "node:crypto";
import {createPublicDb} from "../../../../lib/server/supabase";
import {simulateRace} from "../../../../lib/racing/engine";
export const runtime="nodejs";
export const dynamic="force-dynamic";
// Manual override of WHEN the calculation runs. Does NOT mutate official races.
export async function POST(request:Request){
 try{
  if(Number(request.headers.get("content-length")||0)>1024)
   return NextResponse.json({error:"Payload too large"},{status:413});
  const body=await request.json();
  if(!body||typeof body!=="object"||Array.isArray(body)||
   !Number.isInteger(body.slot)||body.slot<0||body.slot>2||
   Object.keys(body).some(k=>k!=="slot"&&k!=="seed")||
   (body.seed!==undefined&&(!Number.isInteger(body.seed)||body.seed<1||body.seed>2147483646)))
   return NextResponse.json({error:"Invalid slot/seed"},{status:400});
  const secret=process.env.CRON_SECRET;
  if(!secret)throw new Error("Race processor credentials not configured");
  const {data:claim,error}=await createPublicDb().schema("my_derby")
    .rpc("secure_official_race_input",{p_secret:secret,p_slot:body.slot,
      p_force:true,p_preview:true});
  if(error||claim?.status!=="PREVIEW")throw error??new Error("No scheduled race");
  const input={...claim.input,seed:body.seed??randomInt(1,2147483647)};
  const result=simulateRace(input);
  return NextResponse.json({mode:"SCHEDULE_BASED_TEST",source:"my_derby.races + race_entries",
   officialStateChanged:false,result,
   program:{raceId:claim.raceId,track:result.track,distanceM:result.distanceM}},
   {headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Failed to simulate"},
   {status:400,headers:{"Cache-Control":"no-store"}})}
}
