import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const reply=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{"Cache-Control":"no-store"}});
export async function GET(request:Request){
 try{
  const {db,user}=await requireUser(request);
  const api=db.schema("my_derby");
  const [profile,state]=await Promise.all([
   api.from("profiles").select("nickname,initial_setup_complete").eq("user_id",user.id).maybeSingle(),
   api.from("player_tutorial_progress").select("current_step,completed").eq("user_id",user.id).maybeSingle()
  ]);
  if(profile.error||state.error)throw profile.error||state.error;
  return reply({joined:!!profile.data?.initial_setup_complete,nickname:profile.data?.nickname||"",
   currentStep:state.data?.current_step||0,completed:state.data?.completed||false});
 }catch(e){return reply({error:e instanceof Error?e.message:"튜토리얼 상태 조회 실패"},(e as {status?:number}).status===401?401:500)}
}
export async function POST(request:Request){
 try{
  const {db,user}=await requireUser(request);
  const body=await request.json();
  const step=Number(body?.step);
  const skipped=body?.skip===true;
  if(!skipped&&(!Number.isInteger(step)||step<0||step>5))
   return reply({error:"잘못된 튜토리얼 단계입니다."},400);
  const api=db.schema("my_derby");
  const {data:current,error:readError}=await api.from("player_tutorial_progress")
   .select("current_step,completed").eq("user_id",user.id).maybeSingle();
  if(readError)throw readError;
  const nextStep=skipped?5:Math.max(current?.current_step||0,step);
  const {error}=await api.from("player_tutorial_progress").upsert({
    user_id:user.id,current_step:nextStep,completed:skipped||nextStep>=5,updated_at:new Date().toISOString()
  },{onConflict:"user_id"});
  if(error)throw error;
  return reply({currentStep:nextStep,completed:skipped||nextStep>=5});
 }catch(e){return reply({error:e instanceof Error?e.message:"튜토리얼 저장 실패"},(e as {status?:number}).status===401?401:500)}
}
