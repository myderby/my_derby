import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const respond=(body:unknown,status=200)=>NextResponse.json(body,{status,headers:{"Cache-Control":"no-store"}});
const err=(e:unknown)=>respond({error:e instanceof Error?e.message:"기수 신청 실패"},(e as {status?:number})?.status===401?401:400);
export async function GET(request:Request){
 try{
  const {db}=await requireUser(request);
  const {searchParams}=new URL(request.url);
  const raceId=searchParams.get("raceId"),horseId=searchParams.get("horseId");
  if(!raceId||!horseId||!uuid.test(raceId)||!uuid.test(horseId))return respond({error:"경주와 경주마를 선택하세요."},400);
  const {data,error}=await db.schema("my_derby").rpc("player_race_jockey_options",
   {p_race_id:raceId,p_horse_id:horseId});
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
    Object.keys(body).sort().join(",")!=="horseId,jockeyId,raceId"||
    ![body.horseId,body.raceId,body.jockeyId].every(x=>typeof x==="string"&&uuid.test(x)))
   return respond({error:"올바른 기수를 선택하세요."},400);
  const {data,error}=await db.schema("my_derby").rpc("apply_player_jockey",
   {p_race_id:body.raceId,p_horse_id:body.horseId,p_jockey_id:body.jockeyId});
  if(error)throw error;
  return respond(data);
 }catch(e){return err(e)}
}
