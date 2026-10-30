import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const dynamic="force-dynamic";
export const runtime="nodejs";
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const reply=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{"Cache-Control":"no-store"}});
function statusFor(e:unknown){
 const err=e as {status?:number;message?:string;code?:string};
 if(err?.status===401)return 401;
 if(err?.message?.includes("NOT_YOUR_HORSE")||err?.code==="42501")return 403;
 return 400;
}
export async function GET(request:Request){
 try{
  const horseId=new URL(request.url).searchParams.get("horseId");
  if(!UUID.test(horseId||""))return reply({error:"유효한 경주마를 선택해 주세요."},400);
  const {db}=await requireUser(request);
  const {data,error}=await db.schema("my_derby")
   .rpc("player_horse_report_history",{p_horse_id:horseId});
  if(error)throw error;
  return reply(data);
 }catch(e){
  const error=e as Error;
  return reply({error:error.message||"분석 리포트를 읽지 못했습니다."},statusFor(e));
 }
}
export async function POST(request:Request){
 try{
  if(Number(request.headers.get("content-length")||0)>1000)
   return reply({error:"요청 크기가 너무 큽니다."},413);
  const input=await request.json();
  if(!input||typeof input!=="object"||Array.isArray(input)
   ||Object.keys(input).length!==1||!UUID.test(input.horseId||""))
   return reply({error:"경주마를 올바르게 선택해 주세요."},400);
  const {db}=await requireUser(request);
  const {data,error}=await db.schema("my_derby").rpc("player_issue_horse_report",
   {p_horse_id:input.horseId});
  if(error)throw error;
  return reply(data);
 }catch(e){
  const error=e as Error;
  return reply({error:error.message||"분석 리포트 발급에 실패했습니다."},statusFor(e));
 }
}
