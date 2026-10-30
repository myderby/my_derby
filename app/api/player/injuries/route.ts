import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(req:Request){
 try{
  const {db}=await requireUser(req);
  const {data,error}=await db.schema("my_derby").rpc("player_horse_injury_board");
  if(error)throw error;
  return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}