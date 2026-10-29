import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(){
 try{
  const {data,error}=await createPublicDb().schema("my_derby")
    .rpc("npc_retirement_public_summary");
  if(error)throw error;
  return NextResponse.json({mode:"NPC_OWNER_RETIREMENT_POLICY_V1",...data},
   {headers:{"Cache-Control":"no-store"}});
 }catch(e){
  return NextResponse.json({error:"NPC 은퇴 기록을 조회하지 못했습니다."},
   {status:503,headers:{"Cache-Control":"no-store"}});
 }
}
