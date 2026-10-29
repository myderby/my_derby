import {NextResponse} from "next/server";
import {timingSafeEqual} from "node:crypto";
import {createPublicDb} from "../../../../lib/server/supabase";
import {simulateRace} from "../../../../lib/racing/engine";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export const maxDuration=60;
const json=(v:unknown,status=200)=>NextResponse.json(v,{status,headers:{"Cache-Control":"no-store"}});
function authorized(request:Request,secret:string){
 const value=request.headers.get("authorization")??"";
 const required="Bearer "+secret;
 const a=Buffer.from(value),b=Buffer.from(required);
 return a.length===b.length&&timingSafeEqual(a,b);
}
export async function GET(request:Request){
 const secret=process.env.CRON_SECRET;
 if(!secret||!authorized(request,secret))return json({error:"Not authorized"},401);
 const slot=Number(new URL(request.url).searchParams.get("slot"));
 if(!Number.isInteger(slot)||slot<0||slot>2)return json({error:"Invalid slot"},400);
 try{
  const api=createPublicDb().schema("my_derby");
  const {data:claim,error:claimError}=await api.rpc("secure_official_race_input",
   {p_secret:secret,p_slot:slot,p_force:false,p_preview:false});
  if(claimError)throw claimError;
  if(claim.status==="ALREADY_FINISHED"||claim.status==="ALREADY_RUNNING")
   return json({mode:"OFFICIAL",...claim,slot});
  if(claim.status!=="CLAIMED"||!claim.runId||!claim.input)
   throw new Error("Race not claimed");
  const result=simulateRace(claim.input);
  const {data:finish,error:finishError}=await api.rpc("secure_official_race_finalize",
   {p_secret:secret,p_run_id:claim.runId,p_result:result});
  if(finishError)throw finishError;
  return json({mode:"OFFICIAL",...finish,slot});
 }catch(e){console.error("My Derby official race error",e instanceof Error?e.message:e);
  return json({error:"Official race processing failed",slot},503)}
}
