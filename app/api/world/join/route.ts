import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const regions=["SEOUL","BUSAN","YEONGCHEON"];
const regionAliases={
 SEOUL:"SEOUL","서울":"SEOUL",
 BUSAN:"BUSAN",BUSAN_GYEONGNAM:"BUSAN","부산":"BUSAN","부산경남":"BUSAN",
 YEONGCHEON:"YEONGCHEON","영천":"YEONGCHEON",
 JEJU:"YEONGCHEON","제주":"YEONGCHEON"
};
const normalizeRegion=(value:unknown)=>{
 if(typeof value!=="string")return null;
 const key=value.trim().toUpperCase();
 return regionAliases[key as keyof typeof regionAliases]||
  regionAliases[value.trim() as keyof typeof regionAliases]||null;
};
const patterns=["solid","stripe","check","diamond","dot","star"];
const hexColor=(value:unknown):value is string=>
 typeof value==="string"&&/^#[0-9a-fA-F]{6}$/.test(value);
export async function POST(request:Request){
 try{
  const {db}=await requireUser(request);
  if(Number(request.headers.get("content-length")||0)>2048)
   return NextResponse.json({error:"요청 본문이 너무 큽니다."},{status:413});
  const body=await request.json();
  const startingRegion=body&&typeof body==="object"&&!Array.isArray(body)
   ?normalizeRegion((body as {startingRegion?:unknown}).startingRegion):null;
  if(!body||typeof body!=="object"||Array.isArray(body)||
     Object.keys(body).some(k=>!["nickname","startingRegion","silksDesign"].includes(k))||
     typeof body.nickname!=="string"||body.nickname.trim().length<2||body.nickname.trim().length>32||
     !startingRegion||!body.silksDesign||typeof body.silksDesign!=="object"||
     Array.isArray(body.silksDesign)||
     Object.keys(body.silksDesign).some(k=>!["bodyColor","sleeveColor","pattern","patternColor"].includes(k))||
     !hexColor(body.silksDesign.bodyColor)||!hexColor(body.silksDesign.sleeveColor)||
     !hexColor(body.silksDesign.patternColor)||!patterns.includes(body.silksDesign.pattern))
   return NextResponse.json({error:"닉네임, 시작 지역, 마주복 설정을 확인하세요."},{status:400});
  // The Postgres RPC binds auth.uid() server-side and allocates the fixed starter package atomically.
  const {data,error}=await db.schema("my_derby").rpc("join_world",{
   p_nickname:body.nickname.trim(),
   p_starting_region:startingRegion,
   p_silks_design:body.silksDesign,
  });
  if(error)throw error;
  return NextResponse.json({mode:"WORLD_PLAYER_ONBOARDING",...data},
   {headers:{"Cache-Control":"no-store"}});
 }catch(e){
  const message=e instanceof Error?e.message:"마주 등록 실패";
  const status=(e as {status?:number}).status===401?401:
   /STARTER_(HORSES|PACKAGE)_UNAVAILABLE/.test(message)?409:400;
  const error=/STARTER_(HORSES|PACKAGE)_UNAVAILABLE/.test(message)?
   "시작 말 구성을 배정할 수 없습니다. 잠시 후 다시 시도해주세요.":message;
  return NextResponse.json({error},{status,headers:{"Cache-Control":"no-store"}});
 }
}
