import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
const pattern=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const allowed=["FRONT","PRESS","SAVE","MOVE","CLOSER","FREE"];
export async function POST(req:Request){try{
 const {db}=await requireUser(req);const input=await req.json();
 if(!input||Object.keys(input).sort().join(",")!=="horseId,raceId,strategies"||
 !pattern.test(input.horseId)||!pattern.test(input.raceId)||
 !Array.isArray(input.strategies)||input.strategies.length!==3||
 input.strategies.some((v:unknown)=>!allowed.includes(v as string)))
  return NextResponse.json({error:"1·2·3안 전략을 올바르게 설정해주세요."},{status:400});
 const {data,error}=await db.schema("my_derby").rpc("player_save_race_strategies",
  {p_race_id:input.raceId,p_horse_id:input.horseId,p_codes:input.strategies});
 if(error)throw error;
 return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
}catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}}
