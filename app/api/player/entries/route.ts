import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const respond=(body:unknown,status=200)=>NextResponse.json(body,{status,headers:{"Cache-Control":"no-store"}});
const err=(e:unknown)=>respond({error:e instanceof Error?e.message:"출전 처리 실패"},(e as {status?:number})?.status===401?401:400);
export async function GET(request:Request){
 try {
  const {db,user}=await requireUser(request);
  const raw=new URL(request.url).searchParams.get("week");
  const week=raw===null?null:Number(raw);
  if(raw!==null&&(!Number.isInteger(week)||Number(week)<1||Number(week)>52))return respond({error:"주차가 잘못되었습니다."},400);
  const {data,error}=await db.schema("my_derby").rpc("player_race_board",{p_week:week});
  if(error)throw error;
  // The RPC determines eligibility. Add dates and assignments required by the UI.
  const board=data as Record<string,any>;
  const ids=(board.races||[]).map((race:any)=>race.id).filter((id:any)=>typeof id==="string");
  if(!ids.length)return respond(board);
  const api=db.schema("my_derby");
  const horseIds=(board.horses||[]).map((horse:any)=>horse.id).filter((id:any)=>typeof id==="string");
  const [raceRows,entryRows,horses]=await Promise.all([
   api.from("races").select("id,race_day,track,race_no,distance_m,class_name,start_time,status,target_runner_count,prize_policy").in("id",ids),
   api.from("race_entries").select("race_id,horse_id,owner_user_id,jockey_id,gate_no,status,snapshot").in("race_id",ids),
   horseIds.length?api.from("horses").select("id,tutorial_starter_type").in("id",horseIds):Promise.resolve({data:[],error:null})
  ]);
  for(const result of [raceRows,entryRows,horses])if(result.error)throw result.error;
  const raceById=new Map((raceRows.data||[]).map((race:any)=>[race.id,race]));
  const assigned=entryRows.data||[];
  const jockeyIds=[...new Set(assigned.map((entry:any)=>entry.jockey_id).filter(Boolean))];
  const jockeys=jockeyIds.length?await api.from("npc_jockeys").select("id,name,display_name").in("id",jockeyIds):{data:[],error:null};
  if(jockeys.error)throw jockeys.error;
  const jockeyById=new Map((jockeys.data||[]).map((jockey:any)=>[jockey.id,jockey]));
  const starterById=new Map((horses.data||[]).map((horse:any)=>[horse.id,horse.tutorial_starter_type]));
  const countable=(entry:any)=>["APPLIED","CONFIRMED"].includes(entry.status);
  const mapped=(board.races||[]).map((race:any)=>{
   const source=raceById.get(race.id) as any;
   if(!source)return race;
   const policy=source.prize_policy||{};
   const entries=assigned.filter((entry:any)=>entry.race_id===race.id&&countable(entry));
   const npcSlots=entries.filter((entry:any)=>!entry.owner_user_id&&["NPC_AUTOFILL_DUSU_V1","NPC_OWNER_APPLICATION_V1"].includes(entry.snapshot?.entry_source)).length;
   const myEntries=entries.filter((entry:any)=>entry.owner_user_id===user.id).map((entry:any)=>{
    const jockey=jockeyById.get(entry.jockey_id) as any;
    return {horseId:entry.horse_id,jockeyId:entry.jockey_id,gateNo:entry.gate_no,status:entry.status,jockeyName:jockey?.display_name||jockey?.name||null,jockeyOfferStatus:"AUTO",jockeyOfferName:null};
   });
   const entryOpenDate=policy.kst_date?(()=>{
    const date=new Date(`${policy.kst_date}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate()-(race.isSpecialRace?4:2));
    return date.toISOString().slice(0,10);
   })():null;
   return {...race,track:source.track,grade:source.class_name,gradeNo:Number(policy.grade_no??race.gradeNo),
    sourceMeet:policy.source_meet??race.sourceMeet,distance:source.distance_m,raceDay:source.race_day,
    kstDate:policy.kst_date||null,raceNo:policy.source_rc_no||source.race_no,
    startTime:String(source.start_time||race.startTime||"").slice(0,5),status:source.status,
    capacity:Number(source.target_runner_count||12),confirmedCount:entries.filter((entry:any)=>entry.status==="CONFIRMED").length,
    npcReplaceableCount:npcSlots,entryOpenDate,myEntries};
  });
  board.races=mapped;
  board.horses=(board.horses||[]).map((horse:any)=>({...horse,tutorialStarterType:starterById.get(horse.id)||null}));
  return respond(board);
 }catch(e){return err(e)}
}
export async function POST(request:Request){
 try{
  if(Number(request.headers.get("content-length")||0)>512)return respond({error:"요청 크기 초과"},413);
  const {db}=await requireUser(request);
  const body=await request.json();
  if(!body||typeof body!=="object"||Array.isArray(body)||
   Object.keys(body).sort().join(",")!=="horseId,raceId"||
   typeof body.raceId!=="string"||typeof body.horseId!=="string"||
   !uuid.test(body.raceId)||!uuid.test(body.horseId))return respond({error:"올바른 경주마와 경주를 선택하세요."},400);
  const {data,error}=await db.schema("my_derby").rpc("apply_player_race_entry",
   {p_race_id:body.raceId,p_horse_id:body.horseId});
  if(error)throw error;
  return respond(data);
 }catch(e){return err(e)}
}

export async function DELETE(request:Request){
 try{
  const {db}=await requireUser(request);
  const body=await request.json();
  if(!body||typeof body!=="object"||Array.isArray(body)||
   Object.keys(body).sort().join(",")!=="horseId,raceId"||
   !uuid.test(body.raceId)||!uuid.test(body.horseId))
   return respond({error:"올바른 출전 취소 정보가 아닙니다."},400);
  const {data,error}=await db.schema("my_derby").rpc("player_withdraw_race_entry",
   {p_race_id:body.raceId,p_horse_id:body.horseId});
  if(error)throw error;
  return respond(data);
 }catch(e){return err(e)}
}
