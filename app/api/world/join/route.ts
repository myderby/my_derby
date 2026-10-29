import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function POST(request:Request){
 try{
  const {db}=await requireUser(request);
  if(Number(request.headers.get("content-length")||0)>512)
   return NextResponse.json({error:"요청 본문이 너무 큽니다."},{status:413});
  const body=await request.json();
  if(!body||typeof body!=="object"||Array.isArray(body)||
     Object.keys(body).some(k=>k!=="nickname")||
     typeof body.nickname!=="string"||body.nickname.trim().length<2||body.nickname.trim().length>32)
   return NextResponse.json({error:"닉네임은 2~32자로 입력하세요."},{status:400});
  // The Postgres RPC binds auth.uid() server-side, locks rows, and allocates at most 3.
  const {data,error}=await db.schema("my_derby").rpc("join_world",{p_nickname:body.nickname.trim()});
  if(error)throw error;
  return NextResponse.json({mode:"WORLD_PLAYER_ONBOARDING",...data},
   {headers:{"Cache-Control":"no-store"}});
 }catch(e){
  const message=e instanceof Error?e.message:"마주 등록 실패";
  const status=(e as {status?:number}).status===401?401:/STARTER_HORSES_UNAVAILABLE/.test(message)?409:400;
  return NextResponse.json({error:message},{status,headers:{"Cache-Control":"no-store"}});
 }
}
