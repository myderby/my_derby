import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const response=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{"Cache-Control":"no-store"}});
export async function GET(request:Request){
 try{
  const {db,user}=await requireUser(request);
  const api=db.schema("my_derby");
  const [profile,world,horses,jockeys]=await Promise.all([
   api.from("profiles").select("world_id,initial_setup_complete").eq("user_id",user.id).maybeSingle(),
   api.rpc("world_overview"),
   api.from("horses").select("id,name,age_years,sex,source_meet,source_grade_no,life_stage,health_state,fatigue,racing_retired_permanently").eq("owner_user_id",user.id).order("name"),
   api.from("npc_jockeys").select("id,name,home_track,max_daily_rides,skill_stats,specialties").eq("is_active",true).order("name")
  ]);
  for(const r of [profile,world,horses,jockeys])if(r.error)throw r.error;
  if(!profile.data?.initial_setup_complete)return response({joined:false,races:[],horses:[],jockeys:[],entries:[]});
  const start=Number(world.data?.world?.gameDayStart||1);
  const {data:races,error:racesError}=await api.from("races").select("id,race_day,track,race_no,distance_m,class_name,start_time,status,target_runner_count")
  .eq("world_id",profile.data.world_id).gte("race_day",start+1).lte("race_day",start+21).eq("status","OPEN").order("race_day").order("start_time").limit(250);
  if(racesError)throw racesError;
  const ids=(races||[]).map(r=>r.id);
  const [entries,slots]=await Promise.all([ids.length?api.from("race_entries").select("id,race_id,horse_id,jockey_id,owner_user_id,status,snapshot").in("race_id",ids):Promise.resolve({data:[],error:null}),ids.length?api.rpc("player_entry_slots",{p_race_ids:ids}):Promise.resolve({data:[],error:null})]);
  if(entries.error||slots.error)throw entries.error||slots.error;
  const byRace=new Map<string,{confirmed:number,npcSlots:number}>((slots.data||[]).map((s:{race_id:string;confirmed_count:number;replaceable_npc_count:number})=>[s.race_id,{confirmed:Number(s.confirmed_count),npcSlots:Number(s.replaceable_npc_count)}]));
  const list=(entries.data||[]) as Array<{race_id:string;horse_id:string;jockey_id:string;owner_user_id:string|null;status:string;snapshot:Record<string,unknown>}>;
  return response({joined:true,currentDay:start,horses:horses.data||[],jockeys:jockeys.data||[],
   races:(races||[]).map(r=>({...r,confirmedCount:byRace.get(r.id)?.confirmed||0,replaceableNpcCount:byRace.get(r.id)?.npcSlots||0})),
   entries:list.filter(e=>e.owner_user_id===user.id).map(e=>({id:e.race_id,horseId:e.horse_id,jockeyId:e.jockey_id,status:e.status}))});
 }catch(e){const status=(e as {status?:number}).status===401?401:503;return response({error:e instanceof Error?e.message:"신청 현황 조회 실패"},status)}
}
export async function POST(request:Request){
 try{
  const {db}=await requireUser(request);
  const body=await request.json();
  const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
  if(!uuid.test(body.raceId||"")||!uuid.test(body.horseId||""))return response({error:"경주와 경주마를 선택하세요."},400);
  const op=body.action==="race"?"player_apply_race":body.action==="jockey"?"player_apply_jockey":null;
  if(!op||(op==="player_apply_jockey"&&!uuid.test(body.jockeyId||"")))return response({error:"잘못된 신청 요청입니다."},400);
  const args=op==="player_apply_race"?{p_race_id:body.raceId,p_horse_id:body.horseId}:{p_race_id:body.raceId,p_horse_id:body.horseId,p_jockey_id:body.jockeyId};
  const {data,error}=await db.schema("my_derby").rpc(op,args);
  if(error)return response({error:error.message},409);
  return response(data);
 }catch(e){return response({error:e instanceof Error?e.message:"신청 실패"},(e as {status?:number}).status===401?401:500)}
}
