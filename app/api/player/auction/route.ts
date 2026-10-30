import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
export async function GET(req:Request){
 try{
  const {db}=await requireUser(req);
  const [auctions,market]=await Promise.all([
   db.schema("my_derby").rpc("player_auction_board"),
   db.schema("my_derby").rpc("player_market_board")]);
  if(auctions.error)throw auctions.error;
  if(market.error)throw market.error;
  return NextResponse.json({...auctions.data,myHorses:market.data?.horses??[]},
   {headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}
export async function POST(req:Request){
 try{
  const {db}=await requireUser(req);const b=await req.json();
  let rpc:string;let params:Record<string,unknown>;
  if(b?.action==="BID"&&uuid.test(b.listingId)&&
   Number.isSafeInteger(b.amount)&&b.amount>=50000&&b.amount<=20000000){
    rpc="player_auction_bid";params={p_listing:b.listingId,p_amount:b.amount};
  }else if(b?.action==="CREATE"&&uuid.test(b.horseId)&&
   Number.isSafeInteger(b.price)&&b.price>=50000&&b.price<=20000000&&
   [7,14,21].includes(b.days)){
    rpc="player_auction_create";params={p_horse:b.horseId,p_start:b.price,p_days:b.days};
  }else if(b?.action==="CANCEL"&&uuid.test(b.listingId)){
    rpc="player_auction_cancel";params={p_listing:b.listingId};
  }else return NextResponse.json({error:"입찰 정보 또는 판매 기간을 확인해주세요."},{status:400});
  const {data,error}=await db.schema("my_derby").rpc(rpc,params);
  if(error)throw error;
  return NextResponse.json(data);
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}