import {NextResponse} from "next/server";
import {randomInt} from "node:crypto";
import {createPublicDb} from "../../../../lib/server/supabase";
import {simulateRace} from "../../../../lib/racing/engine";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export const maxDuration=60;
const validUuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function POST(request:Request){
 try{
  if(Number(request.headers.get("content-length")||0)>512)
   return NextResponse.json({error:"요청이 너무 큽니다."},{status:413});
  const body=await request.json();
  if(!body||typeof body!=="object"||Array.isArray(body)||
    Object.keys(body).some(k=>!["raceId","seed"].includes(k))||
    typeof body.raceId!=="string"||!validUuid.test(body.raceId)||
    (body.seed!==undefined&&(!Number.isInteger(body.seed)||body.seed<1||body.seed>2147483646)))
   return NextResponse.json({error:"경주 ID 또는 시드가 올바르지 않습니다."},{status:400});
  const secret=process.env.CRON_SECRET;
  if(!secret)throw new Error("경주 계산 설정을 사용할 수 없습니다.");
  const {data:claim,error}=await createPublicDb().schema("my_derby")
    .rpc("secure_program_preview_race",{p_secret:secret,p_race_id:body.raceId});
  if(error||claim?.status!=="PREVIEW")throw error||new Error("경주 편성이나 출전마가 없습니다.");
  const input={...claim.input,seed:body.seed??randomInt(1,2147483647)};
  const result=simulateRace(input);
  return NextResponse.json({mode:"SCHEDULE_BASED_TEST",source:"my_derby.races",
   schedule:{raceId:body.raceId,startTime:claim.startTime,resultTime:claim.resultTime,
      rank:claim.rank,displayRaceNo:claim.displayRaceNo},
   officialStateChanged:false,result},{headers:{"Cache-Control":"no-store"}});
 }catch(e){
  return NextResponse.json({error:e instanceof Error?e.message:"계산에 실패했습니다."},
   {status:400,headers:{"Cache-Control":"no-store"}});
 }
}
