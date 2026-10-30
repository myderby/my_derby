import {NextResponse} from "next/server";
import {requireUser} from "../../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(request:Request,context:{params:Promise<{id:string}>}){
 try{
  const {id}=await context.params;
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))return NextResponse.json({error:"경주 정보 오류"},{status:400});
  const {db,user}=await requireUser(request);
  const {data,error}=await db.schema("my_derby").from("race_entries")
   .select("horse_id").eq("race_id",id).eq("owner_user_id",user.id);
  if(error)throw error;
  return NextResponse.json({horseIds:(data||[]).map(e=>e.horse_id)},{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:(e as any).status||500,headers:{"Cache-Control":"no-store"}})}
}