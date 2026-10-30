import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
import {simulateRace} from "../../../../lib/racing/engine";
import type {RaceInput} from "../../../../lib/racing/types";

export const runtime="nodejs";
export const dynamic="force-dynamic";
export const maxDuration=60;

async function fixture(){
  const {data,error}=await createPublicDb().schema("my_derby")
    .from("race_test_fixtures")
    .select("slot,label,race_input,is_test_only")
    .eq("slot",0).eq("is_test_only",true).single();
  if(error||!data)throw new Error("19시 테스트 경주 데이터를 불러올 수 없습니다.");
  const runners=data.race_input?.runners;
  if(!Array.isArray(runners)||runners.length!==10||
     runners.filter((r: {gradeNo:number})=>r.gradeNo===1).length!==5||
     runners.filter((r: {gradeNo:number})=>r.gradeNo===5).length!==5)
    throw new Error("19시 테스트 출전마의 등급별 구성이 올바르지 않습니다.");
  return data;
}
const response=(data:unknown,status=200)=>NextResponse.json(data,{
  status,headers:{"Cache-Control":"no-store"}});
export async function GET(){
  try{
    const data=await fixture();
    return response({mode:"FIXTURE_TEST_ONLY",label:data.label,slot:0,
      race:data.race_input,officialStateChanged:false});
  }catch(e){return response({error:e instanceof Error?e.message:"테스트 경주 조회 실패"},503)}
}
export async function POST(request:Request){
  try{
    if(Number(request.headers.get("content-length")||0)>512)
      return response({error:"요청이 너무 큽니다."},413);
    const body=await request.json();
    if(!body||Array.isArray(body)||typeof body!=="object"||
      Object.keys(body).some(k=>k!=="seed")||
      (body.seed!==undefined&&(!Number.isInteger(body.seed)||body.seed<1||body.seed>2147483646)))
      return response({error:"올바른 시드가 아닙니다."},400);
    const data=await fixture();
    const input:RaceInput={...data.race_input,seed:body.seed??data.race_input.seed};
    const result=simulateRace(input);
    return response({mode:"FIXTURE_TEST_ONLY",label:data.label,slot:0,
      officialStateChanged:false,officialRaceRecorded:false,
      prizeSettlementApplied:false,result});
  }catch(e){return response({error:e instanceof Error?e.message:"테스트 시뮬레이션 실패"},400)}
}
