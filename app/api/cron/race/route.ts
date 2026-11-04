import {NextResponse} from "next/server";
import {timingSafeEqual} from "node:crypto";
import {createPublicDb} from "../../../../lib/server/supabase";
import {simulateRace} from "../../../../lib/racing/engine";
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
 const value=new URL(request.url).searchParams.get("slot");
 const slot=value!==null?Number(value):NaN;
 if(!Number.isInteger(slot)||slot<0||slot>2)return out({error:"Invalid schedule slot"},400);
 const api=createPublicDb().schema("my_derby");
 let phase="publish_due",raceId:string|null=null,runId:string|null=null;
 try{
  // Publish only pending results whose official stTime + 3 minutes has elapsed.
  const {data:published,error:pubError}=await api.rpc("secure_program_publish_due",
   {p_secret:secret,p_slot:slot});
  if(pubError)throw pubError;
  phase="claim_next";
  const {data:claimed,error:claimError}=await api.rpc("secure_program_claim_next",
   {p_secret:secret,p_slot:slot});
  if(claimError)throw claimError;
  if(claimed?.status!=="CLAIMED"){
   return out({mode:"MULTI_RACE_CRON",slot,published,claimed:claimed?.status||"WAITING"});
  }
  raceId=String(claimed.raceId||"")||null;runId=String(claimed.runId||"")||null;
  phase="simulate";
  const result=simulateRace(claimed.input);
  phase="stage_result";
  const {data:staged,error:stageError}=await api.rpc("secure_program_stage_result",
   {p_secret:secret,p_run_id:claimed.runId,p_result:result});
  if(stageError)throw stageError;
  return out({mode:"MULTI_RACE_CRON",slot,published,claimed:"CALCULATED",
   raceId:claimed.raceId,rank:claimed.rank,runnerCount:result.results.length,
   resultDueAt:staged.scheduledResultAt,resultPublic:false});
 }catch(error){
  const info=errorInfo(error);
  console.error("My Derby scheduled race processor failed",JSON.stringify({slot,raceId,runId,phase,...info}));
  try{
   const {error:logError}=await api.rpc("secure_log_race_processing_error",{
    p_secret:secret,p_race_id:raceId,p_slot:slot,p_phase:phase,p_message:info.message,
    p_error_code:info.code,p_details:info.details,p_hint:info.hint,
    p_context:{runId,route:"/api/cron/race"}
   });
   if(logError)console.error("My Derby race error audit write failed",JSON.stringify(errorInfo(logError)));
  }catch(logError){console.error("My Derby race error audit write threw",JSON.stringify(errorInfo(logError)));}
  return out({error:"Scheduled race processor failed",slot,raceId,phase},503);
 }
}
