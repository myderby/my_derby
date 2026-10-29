import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const distance=["SPRINT","MILE","MIDDLE","LONG"];
const styles=["FRONT_ESCAPE","LEAD","PRESS","MID_MOVE","CLOSER","FREE"];
const intensity=["REST","LIGHT","NORMAL","HARD"];
function result(payload:unknown,status=200){
 return NextResponse.json(payload,{status,headers:{"Cache-Control":"no-store"}});
}
function error(e:unknown){
 const obj=e as {status?:number;code?:string;message?:string};
 const message=obj?.message||"훈련을 처리하지 못했습니다.";
 const status=obj?.status===401||obj?.code==="42501"?401:
   (obj?.code==="PGRST116"?404:400);
 return result({error:message},status);
}
export async function GET(request:Request){
 try{
  const {db}=await requireUser(request);
  const {data,error:e}=await db.schema("my_derby").rpc("player_training_dashboard");
  if(e)throw e;
  return result(data);
 }catch(e){return error(e)}
}
export async function POST(request:Request){
 try{
  if(Number(request.headers.get("content-length")||0)>1024)
   return result({error:"요청 크기를 초과했습니다."},413);
  const {db}=await requireUser(request);
  const body=await request.json();
  if(!body||typeof body!=="object"||Array.isArray(body)||!uuid.test(body.horseId))
   return result({error:"경주마를 올바르게 선택하세요."},400);
  let response;
  if(body.action==="SAVE"){
   if(Object.keys(body).sort().join(",")!=="action,distance,horseId,intensity,style"
      ||!distance.includes(body.distance)||!styles.includes(body.style)
      ||!intensity.includes(body.intensity))
    return result({error:"훈련계획 값이 올바르지 않습니다."},400);
   response=await db.schema("my_derby").rpc("player_save_training_plan",
    {p_horse_id:body.horseId,p_distance:body.distance,p_style:body.style,p_intensity:body.intensity});
  }else if(body.action==="PROCESS"){
   if(Object.keys(body).sort().join(",")!=="action,horseId")
     return result({error:"허용되지 않은 요청입니다."},400);
   response=await db.schema("my_derby").rpc("player_generate_training_reports",
    {p_horse_id:body.horseId});
  }else return result({error:"알 수 없는 훈련 요청입니다."},400);
  if(response.error)throw response.error;
  return result(response.data);
 }catch(e){return error(e)}
}
