import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const pattern=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const output=(body:unknown,status=200)=>NextResponse.json(body,{status,headers:{"Cache-Control":"no-store"}});
export async function GET(req:Request){try{const {db}=await requireUser(req);
 const {data,error}=await db.schema("my_derby").rpc("player_stable_board");
 if(error)throw error;return output(data);
}catch(e){return output({error:(e as Error).message},400)}}
export async function POST(req:Request){try{
 const {db}=await requireUser(req);const data=await req.json();
 if(!data||Object.keys(data).sort().join(",")!=="horseId,trainerId"||
  !pattern.test(data.horseId)||!pattern.test(data.trainerId))
  return output({error:"마필과 조교사를 올바르게 선택하세요."},400);
 const {data:response,error}=await db.schema("my_derby").rpc("player_apply_trainer",
  {p_horse_id:data.horseId,p_trainer_id:data.trainerId});
 if(error)throw error;return output(response);
}catch(e){return output({error:(e as Error).message},400)}}
