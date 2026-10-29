import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(){
 try{
  const db=createPublicDb().schema("my_derby");
  const [summary,topOwners]=await Promise.all([
   db.rpc("world_overview"),db.rpc("world_npc_standings")
  ]);
  if(summary.error||topOwners.error)throw summary.error||topOwners.error;
  if(!summary.data?.ready)throw new Error("Game world is not initialized.");
  return NextResponse.json({mode:"WORLD_OVERVIEW",...summary.data,topNpcOwners:topOwners.data??[]},
   {headers:{"Cache-Control":"no-store"}});
 }catch(e){
  return NextResponse.json({error:e instanceof Error?e.message:"World unavailable"},
   {status:503,headers:{"Cache-Control":"no-store"}});
 }
}
