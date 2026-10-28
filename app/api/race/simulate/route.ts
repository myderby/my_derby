import {NextResponse} from "next/server";
import {simulateRace} from "../../../../lib/racing/engine";
import {makeTestRace,TEST_SLOTS} from "../../../../lib/racing/demo";
export const runtime="nodejs";
export const dynamic="force-dynamic";
// Intentionally test-only. Never writes to Supabase, money, results or live race schedules.
export async function POST(request:Request){
  try {
    if(Number(request.headers.get("content-length")||0)>1024)
      return NextResponse.json({error:"Request too large"},{status:413});
    const data=await request.json();
    if(!data||Object.keys(data).some(k=>k!=="slot"&&k!=="seed")||
        !Number.isInteger(data.slot)||data.slot<0||data.slot>2||
        (data.seed!==undefined&&(!Number.isInteger(data.seed)||data.seed<0||data.seed>2147483647)))
      return NextResponse.json({error:"Invalid test slot or seed"},{status:400});
    const input=makeTestRace(data.slot,data.seed??6281+data.slot*101);
    const result=simulateRace(input);
    return NextResponse.json({mode:"TEST_ONLY",slot:TEST_SLOTS[data.slot],result},
      {headers:{"Cache-Control":"no-store"}});
  } catch(err) {
    return NextResponse.json({error:err instanceof Error?err.message:"Simulation failed"},{status:400});
  }
}
