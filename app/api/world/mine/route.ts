import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(request:Request){
 try{
  const {db,user}=await requireUser(request);
  const api=db.schema("my_derby");
  const [profileRes,horsesRes]=await Promise.all([
   api.from("profiles").select("nickname,world_id,initial_setup_complete").eq("user_id",user.id).maybeSingle(),
   api.from("horses").select("id,source_hr_no,name,sex,age_years,life_stage,condition_score,fatigue,source_record_count,source_meet")
    .eq("owner_user_id",user.id).order("name").limit(60),
  ]);
  if(profileRes.error||horsesRes.error)throw profileRes.error||horsesRes.error;
  const horses=horsesRes.data??[];
  return NextResponse.json({
   mode:"PLAYER_RANCH",joined:!!profileRes.data?.initial_setup_complete,
   profile:profileRes.data??null,
   horses,
   note:"Actual horse abilities, gene data and hidden traits are private. Use the owner-only discovery report for estimates."
  },{headers:{"Cache-Control":"no-store"}});
 }catch(e){
  const status=(e as {status?:number}).status===401?401:500;
  return NextResponse.json({error:e instanceof Error?e.message:"내 말 조회 실패"},
   {status,headers:{"Cache-Control":"no-store"}});
 }
}
