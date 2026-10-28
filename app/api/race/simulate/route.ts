import {NextResponse} from "next/server";
import {simulateRace} from "../../../../lib/racing/engine";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
// Strict test-only path; inputs fetched from my_derby.race_test_fixtures.
// No official race runs, rankings, money or world state are ever updated here.
export async function POST(request:Request){
 try {
  if(Number(request.headers.get("content-length")||0)>1024)
   return NextResponse.json({error:"Request too large"},{status:413});
  const body=await request.json();
  if(!body||Object.keys(body).some(k=>k!=="slot"&&k!=="seed")||
    !Number.isInteger(body.slot)||body.slot<0||body.slot>2||
    (body.seed!==undefined&&(!Number.isInteger(body.seed)||body.seed<0||body.seed>2147483647)))
   return NextResponse.json({error:"Invalid test slot or seed"},{status:400});
  const client=createPublicDb();
  const {data,error}=await client.schema("my_derby").from("race_test_fixtures")
   .select("label,race_input,is_test_only").eq("slot",body.slot).single();
  if(error||!data||data.is_test_only!==true)
   return NextResponse.json({error:"경주 테스트 DB 입력을 불러올 수 없습니다."},{status:503});
  const input={...data.race_input,seed:body.seed??data.race_input.seed};
  const result=simulateRace(input);
  return NextResponse.json({mode:"TEST_ONLY",source:"my_derby.race_test_fixtures",
   label:data.label,result},{headers:{"Cache-Control":"no-store"}});
 }catch(err){
  return NextResponse.json({error:err instanceof Error?err.message:"Simulation error"},
   {status:400,headers:{"Cache-Control":"no-store"}});
 }
}
