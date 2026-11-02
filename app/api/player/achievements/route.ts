import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(request:Request){
 try{
  const {db,user}=await requireUser(request);
  const api=db.schema("my_derby");
  const [definitions,progress,profile,horsesOwned]=await Promise.all([
   api.from("achievement_definitions").select("achievement_key,category,title,description,threshold,subject_kind,competition_name,display_order").order("display_order"),
   api.from("player_achievement_progress").select("achievement_key,subject_id,progress,unlocked_at,updated_at").eq("user_id",user.id),
   api.from("profiles").select("nickname").eq("user_id",user.id).maybeSingle(),
   api.from("horses").select("id,name").eq("owner_user_id",user.id).order("name").limit(40)
  ]);
  if(definitions.error||progress.error||profile.error||horsesOwned.error)throw definitions.error||progress.error||profile.error||horsesOwned.error;
  const horseIds=[...new Set([...(horsesOwned.data||[]).map(h=>h.id),...(progress.data||[]).filter(x=>x.subject_id!=="00000000-0000-0000-0000-000000000000").map(x=>x.subject_id)])];
  const horses=horseIds.length?await api.from("horses").select("id,name").in("id",horseIds):{data:[],error:null};
  if(horses.error)throw horses.error;
  const horseNames=new Map((horses.data||[]).map(h=>[h.id,h.name]));
  return NextResponse.json({nickname:profile.data?.nickname||"",definitions:definitions.data||[],
   horses:horseIds.map(id=>({id,name:horseNames.get(id)||"이전 보유마"})),
   progress:(progress.data||[]).map(p=>({...p,horseName:horseNames.get(p.subject_id)||null}))},
   {headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"업적 조회 실패"},
  {status:(e as {status?:number}).status===401?401:500,headers:{"Cache-Control":"no-store"}})}
}
