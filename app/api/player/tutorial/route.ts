import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const reply=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{"Cache-Control":"no-store"}});
const topics=["training","racing","results","ranch","betting","breeding","achievements"] as const;

export async function GET(request:Request){
 try{
  const {db,user}=await requireUser(request),api=db.schema("my_derby");
  const [profile,state]=await Promise.all([
   api.from("profiles").select("nickname,initial_setup_complete").eq("user_id",user.id).maybeSingle(),
   api.from("player_tutorial_progress").select("story_stage,seen_topics,completed").eq("user_id",user.id).maybeSingle()
  ]);
  if(profile.error||state.error)throw profile.error||state.error;
  return reply({joined:!!profile.data?.initial_setup_complete,nickname:profile.data?.nickname||"",
   storyStage:state.data?.story_stage||0,seenTopics:Array.isArray(state.data?.seen_topics)?state.data.seen_topics:[],
   completed:state.data?.completed||false});
 }catch(e){return reply({error:e instanceof Error?e.message:"튜토리얼 상태 조회 실패"},(e as {status?:number}).status===401?401:500)}
}

export async function POST(request:Request){
 try{
  const {db,user}=await requireUser(request),body=await request.json(),api=db.schema("my_derby");
  if(!body||typeof body!=="object"||Array.isArray(body))return reply({error:"잘못된 요청입니다."},400);
  const keys=Object.keys(body);
  if(keys.length!==1||!(["topic","storyStage","completeStory"] as string[]).includes(keys[0]))
   return reply({error:"잘못된 튜토리얼 요청입니다."},400);
  const {data:current,error:readError}=await api.from("player_tutorial_progress")
   .select("story_stage,seen_topics,completed").eq("user_id",user.id).maybeSingle();
  if(readError)throw readError;
  const currentStage=Number(current?.story_stage||0),seen=Array.isArray(current?.seen_topics)?current.seen_topics:[];
  let nextStage=currentStage,nextSeen=seen,completed=!!current?.completed;
  if(typeof body.topic==="string"){
   if(!(topics as readonly string[]).includes(body.topic))return reply({error:"알 수 없는 기능 안내입니다."},400);
   nextSeen=seen.includes(body.topic)?seen:[...seen,body.topic];
  }else if(body.storyStage===3){
   if(currentStage<2)return reply({error:"이야기 진행 조건이 아직 완료되지 않았습니다."},409);
   nextStage=3;completed=false;
  }else if(body.completeStory===true){
   if(currentStage<3)return reply({error:"첫 시작 이야기를 먼저 진행해주세요."},409);
   completed=true;
  }else return reply({error:"잘못된 튜토리얼 요청입니다."},400);
  const {error}=await api.from("player_tutorial_progress").upsert({
   user_id:user.id,current_step:nextStage,story_stage:nextStage,seen_topics:nextSeen,
   completed,updated_at:new Date().toISOString()
  },{onConflict:"user_id"});
  if(error)throw error;
  return reply({storyStage:nextStage,seenTopics:nextSeen,completed});
 }catch(e){return reply({error:e instanceof Error?e.message:"튜토리얼 저장 실패"},(e as {status?:number}).status===401?401:500)}
}
