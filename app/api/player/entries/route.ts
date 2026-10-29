import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const respond=(body:unknown,status=200)=>NextResponse.json(body,{status,headers:{"Cache-Control":"no-store"}});
const err=(e:unknown)=>respond({error:e instanceof Error?e.message:"출전 처리 실패"},(e as {status?:number})?.status===401?401:400);
export async function GET(request:Request){
 try {
  const {db}=await requireUser(request);
  const raw=new URL(request.url).searchParams.get("week");
  const week=raw===null?null:Number(raw);
  if(raw!==null&&(!Number.isInteger(week)||week!<1||week!>52))return respond({error:"주차가 잘못되었습니다."},400);
  const {data,error}=await db.schema("my_derby").rpc("player_race_board",{p_week:week});
  if(error)throw error;
  return respond(data);
 }catch(e){return err(e)}
}
export async function POST(request:Request){
 try{
  if(Number(request.headers.get("content-length")||0)>512)return respond({error:"요청 크기 초과"},413);
  const {db}=await requireUser(request);
  const body=await request.json();
  if(!body||typeof body!=="object"||Array.isArray(body)||
   Object.keys(body).sort().join(",")!=="horseId,raceId"||
   typeof body.raceId!=="string"||typeof body.horseId!=="string"||
   !uuid.test(body.raceId)||!uuid.test(body.horseId))return respond({error:"올바른 경주마와 경주를 선택하세요."},400);
  const {data,error}=await db.schema("my_derby").rpc("apply_player_race_entry",
   {p_race_id:body.raceId,p_horse_id:body.horseId});
  if(error)throw error;
  return respond(data);
 }catch(e){return err(e)}
}
