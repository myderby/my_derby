import {NextResponse} from "next/server";
import {randomInt} from "node:crypto";
import {requireUser} from "../../../../lib/server/supabase";
import {makeRaceInputFromDatabase} from "../../../../lib/racing/db-adapter";
import {simulateRace} from "../../../../lib/racing/engine";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fail=(message:string,status:number)=>NextResponse.json({error:message},
 {status,headers:{"Cache-Control":"no-store"}});
export async function GET(request:Request){
 try{
  const {db,user}=await requireUser(request);
  const {data,error}=await db.schema("my_derby").from("race_simulation_previews")
   .select("id,race_id,engine_version,random_seed,created_at,result_snapshot")
   .eq("owner_user_id",user.id).order("created_at",{ascending:false}).limit(20);
  if(error)throw error;
  return NextResponse.json({mode:"NON_OFFICIAL",previews:data??[]},
   {headers:{"Cache-Control":"no-store"}});
 }catch(e){return fail(e instanceof Error?e.message:"Failed to load previews",(e as {status?:number}).status??500)}
}
export async function POST(request:Request){
 try{
  const {db,user}=await requireUser(request);
  if(Number(request.headers.get("content-length")||0)>512)return fail("요청 크기를 초과했습니다.",413);
  const body=await request.json();
  if(!body||typeof body!=="object"||!uuid.test(body.raceId)||Object.keys(body).some(k=>k!=="raceId"))
   return fail("올바른 경주 ID가 필요합니다.",400);
  const api=db.schema("my_derby");
  const {data:race,error:raceError}=await api.from("races").select("id,track,distance_m,status")
   .eq("id",body.raceId).single();
  if(raceError||!race)return fail("경주를 찾을 수 없습니다.",404);
  if(!["CLOSED","FINISHED"].includes(race.status))
   return fail("접수 마감 후 미리보기를 실행할 수 있습니다.",409);
  const {data:entries,error:entryError}=await api.from("race_entries")
   .select("id,horse_id,owner_user_id,jockey_id,gate_no,weight_kg,status,snapshot")
   .eq("race_id",body.raceId).in("status",["CONFIRMED","COMPLETED"]);
  if(entryError)throw entryError;
  const {data:count,error:countError}=await api.rpc("race_entry_count_for_participant",{p_race_id:body.raceId});
  if(countError)throw countError;
  if(count===null)return fail("해당 경주의 출전 마주만 미리보기를 요청할 수 있습니다.",403);
  if(!entries||entries.length!==count)return fail("다른 마주의 출전마가 포함되어 있습니다. 공식 서버 계산 권한 연결 전까지 경주 전체를 미리볼 수 없습니다.",409);
  if(entries.length<2||entries.length>12)return fail("2~12두의 확정 출전마가 필요합니다.",409);
  if(entries.some(e=>e.owner_user_id!==user.id))return fail("미리보기 접근이 제한되었습니다.",403);
  const horseIds=entries.map(e=>e.horse_id),jockeyIds=entries.map(e=>e.jockey_id).filter(Boolean);
  if(jockeyIds.length!==entries.length)return fail("기수가 미배정된 출전마가 있습니다.",409);
  const [horses,abilities,jockeys,strategies]=await Promise.all([
   api.from("horses").select("id,name,condition_score,fatigue").in("id",horseIds),
   api.from("horse_abilities").select("horse_id,current_stats,distance_affinity").in("horse_id",horseIds),
   api.from("npc_jockeys").select("id,skill_stats").in("id",jockeyIds),
   api.from("race_strategies").select("race_entry_id,plan_no,strategy_code").in("race_entry_id",entries.map(e=>e.id))
  ]);
  const queryError=[horses,abilities,jockeys,strategies].find(r=>r.error)?.error;
  if(queryError)throw queryError;
  const seed=randomInt(1,2147483647);
  const input=makeRaceInputFromDatabase({
   race,entries,seed,
   horses:horses.data??[],abilities:abilities.data??[],
   jockeys:jockeys.data??[],strategies:strategies.data??[]
  });
  const result=simulateRace(input);
  const {data:saved,error:saveError}=await api.from("race_simulation_previews").insert({
   race_id:race.id,owner_user_id:user.id,input_snapshot:input,
   result_snapshot:result,engine_version:result.version,random_seed:result.seed
  }).select("id,created_at").single();
  if(saveError)throw saveError;
  return NextResponse.json({
   mode:"NON_OFFICIAL",source:"my_derby.races + race_entries + horses + horse_abilities + npc_jockeys + race_strategies",
   savedPreviewId:saved?.id,createdAt:saved?.created_at,result
  },{headers:{"Cache-Control":"no-store"}});
 }catch(e){return fail(e instanceof Error?e.message:"Failed to simulate database race",(e as {status?:number}).status??500)}
}
