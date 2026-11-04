import {NextResponse} from "next/server";
import {timingSafeEqual} from "node:crypto";
import {createPublicDb} from "../../../../../lib/server/supabase";
import {simulateRace} from "../../../../../lib/racing/engine";

export const runtime="nodejs";
export const dynamic="force-dynamic";
export const maxDuration=60;

const out=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{"Cache-Control":"no-store"}});
function verified(request:Request,secret:string){
 const a=Buffer.from(request.headers.get("authorization")||"");
 const b=Buffer.from("Bearer "+secret);
 return a.length===b.length&&timingSafeEqual(a,b);
}

export async function GET(request:Request){
 const secret=process.env.CRON_SECRET;
 if(!secret||!verified(request,secret))return out({error:"Unauthorized"},401);
 const api=createPublicDb().schema("my_derby");
 try{
  const processed:Array<{slot:number;raceId:string;winner:string;finishers:number}>=[];
  const alreadyPublished:Array<{slot:number;count:number}>=[];
  for(const slot of [0,1,2]){
   const {data:published,error:publishError}=await api.rpc("secure_program_publish_due",
    {p_secret:secret,p_slot:slot});
   if(publishError)throw publishError;
   if(Number(published?.count)>0)alreadyPublished.push({slot,count:Number(published.count)});
   for(let n=0;n<20;n++){
    const {data:claimed,error:claimError}=await api.rpc("secure_backfill_claim_nov3",
     {p_secret:secret,p_slot:slot});
    if(claimError)throw claimError;
    if(claimed?.status!=="CLAIMED")break;
    const result=simulateRace(claimed.input);
    const {data:finished,error:finishError}=await api.rpc("secure_official_race_finalize",
     {p_secret:secret,p_run_id:claimed.runId,p_result:result});
    if(finishError)throw finishError;
    if(!["FINISHED","ALREADY_FINISHED"].includes(finished?.status))
     throw new Error("Unexpected official race finalization status");
    processed.push({slot,raceId:claimed.raceId,winner:result.results[0]?.name||"",finishers:result.results.length});
   }
  }
  return out({date:"2026-11-03",mode:"NOV3_OFFICIAL_BACKFILL",processed:processed.length,
   alreadyPublished, races:processed});
 }catch(error){
  const detail=error&&typeof error==="object"&&"message" in error?String((error as {message:unknown}).message):"Unknown error";
  console.error("My Derby Nov 3 official race backfill failed",detail);
  return out({error:"Nov 3 race backfill failed",detail},503);
 }
}
