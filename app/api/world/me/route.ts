import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(request:Request){
 try{
  const {db,user}=await requireUser(request);
  const api=db.schema("my_derby");
  const [profile,owned]=await Promise.all([
   api.from("profiles").select("nickname,world_id,initial_setup_complete").eq("user_id",user.id).maybeSingle(),
   api.from("horses").select("id,source_hr_no,name,sex,age_years,life_stage,condition_score,fatigue,racing_retired_permanently,horse_abilities(current_stats,potential_stats,hidden_traits)").eq("owner_user_id",user.id).order("name").limit(40)
  ]);
  if(profile.error||owned.error)throw profile.error||owned.error;
  return NextResponse.json({joined:!!profile.data?.initial_setup_complete,profile:profile.data??null,
    horses:owned.data??[],userHorseCount:(owned.data??[]).length},
   {headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Failed to read owner roster"},
   {status:(e as {status?:number}).status===401?401:500,headers:{"Cache-Control":"no-store"}})}
}
