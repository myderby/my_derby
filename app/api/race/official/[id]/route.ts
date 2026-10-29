import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(_request:Request,context:{params:Promise<{id:string}>}){
 try{
  const {id}=await context.params;
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))
    return NextResponse.json({error:"Invalid race ID"},{status:400});
  const {data,error}=await createPublicDb().schema("my_derby")
    .rpc("official_public_race_detail",{p_race_id:id});
  if(error)throw error;
  if(!data)return NextResponse.json({error:"경주를 찾을 수 없습니다."},{status:404});
  return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Result unavailable"},
  {status:503,headers:{"Cache-Control":"no-store"}})}
}
