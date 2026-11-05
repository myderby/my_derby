import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(request:Request){
 try{
  const {db,user}=await requireUser(request);
  const api=db.schema("my_derby");
  const profileRes=await api.from("profiles")
   .select("nickname,world_id,initial_setup_complete,starting_region,silks_design")
   .eq("user_id",user.id).maybeSingle();
  if(profileRes.error)throw profileRes.error;
  const joined=!!profileRes.data?.initial_setup_complete;
  if(!joined)return NextResponse.json({
   mode:"PLAYER_RANCH",joined:false,profile:profileRes.data??null,horses:[],raceSchedule:{},
   note:"Actual horse abilities, gene data and hidden traits are private. Use the owner-only discovery report for estimates."
  },{headers:{"Cache-Control":"no-store"}});
  const horsesRes=await api.from("horses")
   .select("id,source_hr_no,name,sex,age_years,life_stage,condition_score,fatigue,source_record_count,source_meet")
   .eq("owner_user_id",user.id).order("name").limit(60);
  if(horsesRes.error)throw horsesRes.error;
  const scheduleRes=await api.rpc("player_horse_race_schedule");
  if(scheduleRes.error)console.error("Owned horse race schedule lookup failed",scheduleRes.error.message);
  return NextResponse.json({
   mode:"PLAYER_RANCH",joined:true,profile:profileRes.data??null,
   horses:horsesRes.data??[],raceSchedule:scheduleRes.data?.horses??{},
   note:"Actual horse abilities, gene data and hidden traits are private. Use the owner-only discovery report for estimates."
  },{headers:{"Cache-Control":"no-store"}});
 }catch(e){
  const status=(e as {status?:number}).status===401?401:500;
  return NextResponse.json({error:e instanceof Error?e.message:"내 말 조회 실패"},
   {status,headers:{"Cache-Control":"no-store"}});
 }
}
