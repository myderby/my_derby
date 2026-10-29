import {NextResponse} from "next/server";
import {timingSafeEqual} from "node:crypto";
import {createPublicDb} from "../../../../lib/server/supabase";
import {simulateRace} from "../../../../lib/racing/engine";
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
 const value=new URL(request.url).searchParams.get("slot");
 const slot=value!==null?Number(value):NaN;
 if(!Number.isInteger(slot)||slot<0||slot>2)return out({error:"Invalid schedule slot"},400);
 const api=createPublicDb().schema("my_derby");
 try{
  // Publish only pending results whose official stTime + 3 minutes has elapsed.
  const {data:published,error:pubError}=await api.rpc("secure_program_publish_due",
   {p_secret:secret,p_slot:slot});
  if(pubError)throw pubError;
  const {data:claimed,error:claimError}=await api.rpc("secure_program_claim_next",
   {p_secret:secret,p_slot:slot});
  if(claimError)throw claimError;
  if(claimed?.status!=="CLAIMED"){
   return out({mode:"MULTI_RACE_CRON",slot,published,claimed:claimed?.status||"WAITING"});
  }
  const result=simulateRace(claimed.input);
  const {data:staged,error:stageError}=await api.rpc("secure_program_stage_result",
   {p_secret:secret,p_run_id:claimed.runId,p_result:result});
  if(stageError)throw stageError;
  return out({mode:"MULTI_RACE_CRON",slot,published,claimed:"CALCULATED",
   raceId:claimed.raceId,rank:claimed.rank,runnerCount:result.results.length,
   resultDueAt:staged.scheduledResultAt,resultPublic:false});
 }catch(error){
  console.error("My Derby scheduled race processor failed",
   error instanceof Error?error.message:"Unknown error");
  return out({error:"Scheduled race processor failed",slot},503);
 }
}
