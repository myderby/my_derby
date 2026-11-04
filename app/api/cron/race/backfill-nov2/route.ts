import {NextResponse} from "next/server";
import {timingSafeEqual} from "node:crypto";
import {createPublicDb} from "../../../../../lib/server/supabase";
import {simulateRace} from "../../../../../lib/racing/engine";

export const runtime="nodejs";
export const dynamic="force-dynamic";
export const maxDuration=60;

const out=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{"Cache-Control":"no-store"}});
const errorInfo=(error:unknown)=>{
 const e=error&&typeof error==="object"?error as Record<string,unknown>:{};
 return {name:String(e.name||"Error"),message:String(e.message||error||"Unknown error"),
  code:e.code?String(e.code):null,details:e.details?String(e.details):null,hint:e.hint?String(e.hint):null};
};
function verified(request:Request,secret:string){
 const a=Buffer.from(request.headers.get("authorization")||"");
 const b=Buffer.from("Bearer "+secret);
 return a.length===b.length&&timingSafeEqual(a,b);
}

export async function GET(request:Request){
 const secret=process.env.CRON_SECRET;
 if(!secret||!verified(request,secret))return out({error:"Unauthorized"},401);
 const api=createPublicDb().schema("my_derby");
 const processed:Array<{slot:number;raceId:string;winner:string;finishers:number}>=[];
 const alreadyPublished:Array<{slot:number;count:number}>=[];
 let phase="finalize_pending",slot=0,raceId:string|null=null,runId:string|null=null;
 try{
  for(slot of [0,1,2]){
   phase="finalize_pending";raceId=null;runId=null;
   const {data:published,error:publishError}=await api.rpc("secure_backfill_finalize_pending_nov2",
    {p_secret:secret,p_slot:slot});
   if(publishError)throw publishError;
   if(Number(published?.count)>0)alreadyPublished.push({slot,count:Number(published.count)});
   while(processed.length<3){
    phase="claim_next";
    const {data:claimed,error:claimError}=await api.rpc("secure_backfill_claim_nov2",
     {p_secret:secret,p_slot:slot});
    if(claimError)throw claimError;
    if(claimed?.status!=="CLAIMED")break;
    raceId=String(claimed.raceId||"")||null;runId=String(claimed.runId||"")||null;
    phase="simulate";
    const result=simulateRace(claimed.input);
    phase="finalize_result";
    const {data:finished,error:finishError}=await api.rpc("secure_backfill_finalize_race_nov2",
     {p_secret:secret,p_run_id:claimed.runId,p_result:result});
    if(finishError)throw finishError;
    if(!["FINISHED","ALREADY_FINISHED"].includes(finished?.status))
     throw new Error("Unexpected official race finalization status");
    processed.push({slot,raceId:claimed.raceId,winner:result.results[0]?.name||"",finishers:result.results.length});
   }
  }
  return out({date:"2026-11-02",mode:"NOV2_OFFICIAL_BACKFILL",processed:processed.length,
   alreadyPublished, races:processed});
 }catch(error){
  const info=errorInfo(error);
  console.error("My Derby Nov 2 official race backfill failed",JSON.stringify({slot,raceId,runId,phase,...info}));
  try{
   const {error:logError}=await api.rpc("secure_log_race_processing_error",{
    p_secret:secret,p_race_id:raceId,p_slot:slot,p_phase:phase,p_message:info.message,
    p_error_code:info.code,p_details:info.details,p_hint:info.hint,
    p_context:{runId,route:"/api/cron/race/backfill-nov2",kstDate:"2026-11-02"}
   });
   if(logError)console.error("My Derby Nov 2 error audit write failed",JSON.stringify(errorInfo(logError)));
  }catch(logError){console.error("My Derby Nov 2 error audit write threw",JSON.stringify(errorInfo(logError)));}
  return out({error:"Nov 2 race backfill failed",slot,raceId,phase},503);
 }
}
