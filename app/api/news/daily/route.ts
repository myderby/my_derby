import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";

export const runtime="nodejs";
export const dynamic="force-dynamic";
const json=(value:unknown,status=200)=>NextResponse.json(value,{status,headers:{"Cache-Control":"no-store"}});
const validDate=(s:string)=>/^\d{4}-\d{2}-\d{2}$/.test(s)&&!Number.isNaN(Date.parse(s+"T00:00:00Z"))
 &&new Date(s+"T00:00:00Z").toISOString().slice(0,10)===s;

export async function GET(request:Request){
 try{
  const date=new URL(request.url).searchParams.get("date");
  if(date!==null&&!validDate(date))return json({error:"날짜 형식은 YYYY-MM-DD여야 합니다."},400);
  const {db}=await requireUser(request);
  const {data,error}=await db.schema("my_derby")
   .rpc("player_daily_news",{p_date:date||null});
  if(error)throw error;
  return json(data||{error:"소식지를 조회할 수 없습니다."},data?200:404);
 }catch(e){
  const err=e as {status?:number;message?:string;code?:string};
  return json({error:err.message||"소식지 조회 실패"},
    err.status===401?401:err.code==="22023"||err.message?.includes("NEWS_DATE_OUT_OF_RANGE")?400:500);
 }
}
