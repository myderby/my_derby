import {NextResponse} from "next/server";
import {requireUser} from "../../../../../lib/server/supabase";
export const dynamic="force-dynamic";
export const runtime="nodejs";
const uuid=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const specialties=["PASTURE_CARETAKER","RECOVERY_CARETAKER","REHAB_CARETAKER","VET","YOUNG_HORSE_CARETAKER"];
const workerActions=["HIRE_WORKER","FIRE_WORKER","ASSIGN_WORKER"];
const operations=["EXPAND","UPGRADE_FACILITY",...workerActions];
export async function GET(req:Request){
 try{
  const {db}=await requireUser(req);
  const specialty=new URL(req.url).searchParams.get("specialty");
  if(specialty){
   if(!specialties.includes(specialty))return NextResponse.json({error:"직원 구분을 확인해주세요."},{status:400});
   const {data,error}=await db.schema("my_derby").rpc("player_ranch_worker_candidates",{p_specialty:specialty});
   if(error)throw error;
   return NextResponse.json({candidates:data||[]},{headers:{"Cache-Control":"no-store"}});
  }
  const {data,error}=await db.schema("my_derby").rpc("player_ranch_management_board");
  if(error)throw error;return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}
export async function POST(req:Request){
 try{
  const {db}=await requireUser(req);const x=await req.json();
  if(!x||!operations.includes(x.operation)||!uuid.test(x.requestId||"")||
    (x.operation==="UPGRADE_FACILITY"&&!uuid.test(x.facilityId||""))||
    (x.operation==="HIRE_WORKER"&&!uuid.test(x.candidateId||""))||
    ((x.operation==="FIRE_WORKER"||x.operation==="ASSIGN_WORKER")&&!uuid.test(x.workerId||""))||
    (x.operation==="ASSIGN_WORKER"&&x.facilityId!=null&&!uuid.test(x.facilityId)))
   return NextResponse.json({error:"요청 내용을 확인해주세요."},{status:400});
  if(workerActions.includes(x.operation)){
   const {data,error}=await db.schema("my_derby").rpc("player_ranch_worker_manage",{
    p_action:x.operation,p_request_id:x.requestId,p_candidate_id:x.candidateId||null,
    p_worker_id:x.workerId||null,p_facility_id:x.facilityId||null});
   if(error)throw error;return NextResponse.json(data);
  }
  const {data,error}=await db.schema("my_derby").rpc("player_ranch_manage",{
   p_operation:x.operation,p_request_id:x.requestId,p_facility:x.facilityId||null});
  if(error)throw error;return NextResponse.json(data);
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}
