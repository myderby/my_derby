import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(){
 try{
  const db=createPublicDb().schema("my_derby");
  const [trainers,stables,counts]=await Promise.all([
   db.from("npc_trainers").select("id,stable_id,name,capacity,specialties,is_active").eq("is_active",true).order("name"),
   db.from("npc_stables").select("id,name,track"),
   db.rpc("world_trainer_public_counts")
  ]);
  if(trainers.error||stables.error||counts.error)throw trainers.error||stables.error||counts.error;
  const stableMap=new Map((stables.data||[]).map(s=>[s.id,s]));
  const countMap=new Map((counts.data||[]).map(c=>[c.trainer_id,Number(c.horse_count)]));
  return NextResponse.json({trainers:(trainers.data||[]).map(t=>({id:t.id,name:t.name,track:stableMap.get(t.stable_id)?.track||"기타",stableName:stableMap.get(t.stable_id)?.name||"",capacity:t.capacity,horseCount:countMap.get(t.id)||0,specialties:t.specialties||[]}))},{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"NPC trainer list unavailable"},{status:503,headers:{"Cache-Control":"no-store"}})}
}
