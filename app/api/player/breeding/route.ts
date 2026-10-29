import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const output=(value:unknown,status=200)=>NextResponse.json(value,{status,headers:{"Cache-Control":"no-store"}});
const fail=(e:unknown)=>{
 const value=e as {message?:string;code?:string;status?:number};
 return output({error:value?.message||"교배 요청을 처리할 수 없습니다."},
  value?.status===401||value?.code==="42501"?401:400);
};
export async function GET(request:Request){
 try{
  const {db}=await requireUser(request);
  const {data,error}=await db.schema("my_derby").rpc("player_breeding_dashboard");
  if(error)throw error;
  return output(data);
 }catch(e){return fail(e);}
}
export async function POST(request:Request){
 try{
  if(Number(request.headers.get("content-length")||0)>512)
   return output({error:"요청 크기 초과"},413);
  const {db}=await requireUser(request);
  const body=await request.json();
  if(!body||Array.isArray(body)||typeof body!=="object")
   return output({error:"신청 정보가 올바르지 않습니다."},400);
  let result;
  if(body.action==="RETIRE"){
   if(Object.keys(body).sort().join(",")!=="action,horseId"||!uuid.test(body.horseId))
    return output({error:"번식용 은퇴 대상이 잘못되었습니다."},400);
   result=await db.schema("my_derby").rpc("retire_horse_for_breeding",
    {p_horse_id:body.horseId});
  }else if(body.action==="PREVIEW"||body.action==="APPLY"){
   if(Object.keys(body).sort().join(",")!=="action,mareId,sireId"||
     !uuid.test(body.mareId)||!uuid.test(body.sireId))
    return output({error:"암말과 씨수말을 선택하세요."},400);
   result=await db.schema("my_derby").rpc(
    body.action==="PREVIEW"?"player_breeding_pair_preview":"player_apply_breeding",
    {p_mare_id:body.mareId,p_sire_id:body.sireId});
  }else return output({error:"지원하지 않는 교배 작업입니다."},400);
  if(result.error)throw result.error;
  return output(result.data);
 }catch(e){return fail(e);}
}
