import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const dynamic="force-dynamic";
export const runtime="nodejs";
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
function respond(body:unknown,status=200){return NextResponse.json(body,{status,headers:{"Cache-Control":"no-store"}})}
export async function GET(req:Request){
 try{const {db}=await requireUser(req);
  const r=await db.schema("my_derby").rpc("player_market_board");
  if(r.error)throw r.error;return respond(r.data)
 }catch(e){return respond({error:(e as Error).message},400)}
}
export async function POST(req:Request){
 try{
  const {db}=await requireUser(req);const body=await req.json();
  if(!body||typeof body!=="object"||Array.isArray(body))
    return respond({error:"올바른 거래 정보를 입력해주세요."},400);
  let rpc:string;let args:Record<string,unknown>;
  if(body.action==="BUY"&&uuid.test(body.listingId)){
   rpc="player_market_buy";args={p_listing:body.listingId};
  }else if(body.action==="CANCEL"&&uuid.test(body.listingId)){
   rpc="player_market_cancel";args={p_listing:body.listingId};
  }else if(body.action==="LIST"&&uuid.test(body.horseId)&&
    Number.isSafeInteger(body.price)&&body.price>=50000&&body.price<=20000000){
   rpc="player_market_list";args={p_horse_id:body.horseId,p_price:body.price};
  }else return respond({error:"거래 요청 형식이나 가격을 확인해주세요."},400);
  const r=await db.schema("my_derby").rpc(rpc,args);
  if(r.error)throw r.error;return respond(r.data);
 }catch(e){return respond({error:(e as Error).message},400)}
}
