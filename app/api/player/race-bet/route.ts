import {NextResponse} from "next/server";
import {createPublicDb,requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const types=["WIN","PLACE","QUINELLA","QUINELLA_PLACE","EXACTA","TRIO","TRIFECTA"];
function failure(message:string,status=400){
 return NextResponse.json({error:message},{status,headers:{"Cache-Control":"no-store"}});
}
export async function GET(req:Request){
 try{
  const url=new URL(req.url),raceId=url.searchParams.get("raceId")||"";
  if(!uuid.test(raceId))return failure("잘못된 경주 정보입니다.");
  const bearer=(req.headers.get("authorization")||"").match(/^Bearer\s+(.+)$/i)?.[1];
  let board;
  if(bearer){
   const {db}=await requireUser(req);
   const {data,error}=await db.schema("my_derby").rpc("player_race_bet_board",{p_race:raceId});
   if(error)throw error;board=data;
  }else{
   const {data,error}=await createPublicDb().schema("my_derby").rpc("public_race_odds",{p_race:raceId});
   if(error)throw error;board=data;
  }
  if(!board)return failure("경주를 찾을 수 없습니다.",404);
  const type=url.searchParams.get("betType"),selection=url.searchParams.get("selection");
  if(type&&selection){
   const picks=selection.split(",").filter(Boolean);
   if(!types.includes(type)||picks.length<1||picks.length>3||picks.some(x=>!uuid.test(x)))
    return failure("선택마 조합이 올바르지 않습니다.");
   const {data:quote,error}=await createPublicDb().schema("my_derby").rpc("public_race_bet_quote",{
    p_race:raceId,p_type:type,p_selection:picks
   });
   if(error)throw error;
   return NextResponse.json({...board,quote},{headers:{"Cache-Control":"no-store"}});
  }
  return NextResponse.json(board,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return failure(e instanceof Error?e.message:"배당 조회 실패",503)}
}
export async function POST(req:Request){
 try{
  const {db}=await requireUser(req);
  if(Number(req.headers.get("content-length")||0)>1500)return failure("요청이 너무 큽니다.",413);
  const x=await req.json();
  const type=x?.betType||"WIN";
  const picks=x?.selections|| (x?.horseId?[x.horseId]:[]);
  if(!x||!uuid.test(x.raceId)||!uuid.test(x.requestId)||!types.includes(type)||
    !Array.isArray(picks)||!picks.length||picks.length>3||picks.some((h:unknown)=>typeof h!=="string"||!uuid.test(h))||
    !Number.isInteger(x.amount)||x.amount<100||x.amount>10000)
    return failure("경주마·승식·베팅 금액을 확인해주세요.");
  const {data,error}=await db.schema("my_derby").rpc("player_place_race_bet",{
   p_race:x.raceId,p_type:type,p_selection:picks,p_amount:x.amount,p_request_id:x.requestId
  });
  if(error)throw error;
  return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return failure(e instanceof Error?e.message:"베팅 실패")}
}
