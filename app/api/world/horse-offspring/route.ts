import {NextResponse} from "next/server";
import {createPublicDb,requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
export async function GET(request:Request){
 const url=new URL(request.url),horseId=url.searchParams.get("horseId")||"";
 const page=Number(url.searchParams.get("page")||1);
 if(!uuid.test(horseId)||!Number.isInteger(page)||page<1||page>10000)
  return NextResponse.json({error:"말 또는 페이지 정보가 올바르지 않습니다."},{status:400});
 try{
  const db=request.headers.get("authorization")?(await requireUser(request)).db:createPublicDb();
  const {data,error}=await db.schema("my_derby").rpc("world_horse_offspring_profile",{
   p_horse_id:horseId,p_page:page,p_page_size:20});
  if(error)throw error;
  if(!data||data.status!=="OK")return NextResponse.json({error:"자마 정보를 찾을 수 없습니다."},{status:404});
  return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){
  const message=e instanceof Error?e.message:"자마 정보를 불러오지 못했습니다.";
  return NextResponse.json({error:message},{status:503});
 }
}
