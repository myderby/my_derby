import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function GET(request:Request){
 const params=new URL(request.url).searchParams;
 const kind=params.get("kind"),id=params.get("id");
 if(!["jockey","trainer"].includes(kind||"")||!uuid.test(id||""))
  return NextResponse.json({error:"유효하지 않은 관계자 식별정보입니다."},{status:400});
 try{
  const {data,error}=await createPublicDb().schema("my_derby").rpc("public_staff_profile",{p_kind:kind,p_id:id});
  if(error)throw error;
  if(!data||data.status==="NOT_FOUND")return NextResponse.json({error:"해당 관계자를 찾을 수 없습니다."},{status:404});
  return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){
  console.error("Staff profile query error",e instanceof Error?e.message:"unknown");
  return NextResponse.json({error:"관계자 상세정보를 불러오지 못했습니다."},{status:503,headers:{"Cache-Control":"no-store"}});
 }
}
