import {NextResponse} from "next/server";
import {createPublicDb,requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
function fail(message:string,status=400){return NextResponse.json({error:message},{status,headers:{"Cache-Control":"no-store"}})}
export async function GET(req:Request){
 try{
  const raceId=new URL(req.url).searchParams.get("raceId")||"";
  if(!uuid.test(raceId))return fail("잘못된 경주 정보입니다.");
  const token=(req.headers.get("authorization")||"").match(/^Bearer\s+(.+)$/i)?.[1];
  if(token){
   const {db}=await requireUser(req);
   const {data,error}=await db.schema("my_derby").rpc("player_race_bet_board",{p_race:raceId});
   if(error)throw error;
   if(!data)return fail("경주를 찾을 수 없습니다.",404);
   return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
  }
  const {data,error}=await createPublicDb().schema("my_derby").rpc("public_race_odds",{p_race:raceId});
  if(error)throw error;
  if(!data)return fail("경주를 찾을 수 없습니다.",404);
  return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return fail(e instanceof Error?e.message:"배당 조회 실패",503)}
}
export async function POST(req:Request){
 try{
  const {db}=await requireUser(req);
  if(Number(req.headers.get("content-length")||0)>500)return fail("요청이 너무 큽니다.",413);
  const b=await req.json();
  if(!b||!uuid.test(b.raceId)||!uuid.test(b.horseId)||!uuid.test(b.requestId)||
    !Number.isInteger(b.amount)||b.amount<100||b.amount>10000)
   return fail("경주마와 베팅 금액을 확인해주세요.");
  const {data,error}=await db.schema("my_derby").rpc("player_place_win_bet",{
   p_race:b.raceId,p_horse:b.horseId,p_amount:b.amount,p_request_id:b.requestId
  });
  if(error)throw error;
  return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return fail(e instanceof Error?e.message:"베팅 실패")}
}
