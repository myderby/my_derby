import {NextResponse} from "next/server";
import {requireUser} from "../../../../../lib/server/supabase";
export const dynamic="force-dynamic";
export const runtime="nodejs";
const uuid=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const operations=["EXPAND","UPGRADE_FACILITY","HIRE_STAFF","FIRE_STAFF","HIRE_VET","FIRE_VET"];
export async function GET(req:Request){
 try{
  const {db}=await requireUser(req);
  const {data,error}=await db.schema("my_derby").rpc("player_ranch_management_board");
  if(error)throw error;return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}
export async function POST(req:Request){
 try{
  const {db}=await requireUser(req);const x=await req.json();
  if(!x||!operations.includes(x.operation)||!uuid.test(x.requestId)||
    (x.operation==="UPGRADE_FACILITY"&&!uuid.test(x.facilityId)))
   return NextResponse.json({error:"요청 내용을 확인해주세요."},{status:400});
  const {data,error}=await db.schema("my_derby").rpc("player_ranch_manage",{
    p_operation:x.operation,p_request_id:x.requestId,p_facility:x.facilityId||null});
  if(error)throw error;return NextResponse.json(data);
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}