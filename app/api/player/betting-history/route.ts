import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const dynamic="force-dynamic";
export const runtime="nodejs";
export async function GET(req:Request){
 try{
  const {db}=await requireUser(req);
  const url=new URL(req.url);
  const offset=Math.max(0,Math.min(100000,Number(url.searchParams.get("offset")||"0")||0));
  const limit=Math.max(1,Math.min(100,Number(url.searchParams.get("limit")||"30")||30));
  const {data,error}=await db.schema("my_derby").rpc("player_betting_history",{
   p_limit:limit,p_offset:offset});
  if(error)throw error;
  return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){
  return NextResponse.json({error:e instanceof Error?e.message:"베팅 이력 조회 실패"},
   {status:400,headers:{"Cache-Control":"no-store"}});
 }
}
