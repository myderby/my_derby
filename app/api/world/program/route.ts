import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(request:Request){
 try{
  const api=createPublicDb().schema("my_derby");
  const {data:overview,error:e1}=await api.rpc("world_overview");
  if(e1||!overview?.ready)throw e1||new Error("월드 정보가 없습니다.");
  const param=new URL(request.url).searchParams.get("week");
  const week=param?Number(param):Number(overview.world.week);
  if(!Number.isInteger(week)||week<1||week>52)
   return NextResponse.json({error:"주차는 1~52 사이여야 합니다."},{status:400});
  const gameDay=(week-1)*7+1;
  const {data:events,error}=await api.from("races")
   .select("id,track,race_day,start_time,class_name,distance_m,status,prize_policy,target_runner_count")
   .eq("world_id",overview.world.worldId).eq("race_day",gameDay)
   .eq("prize_policy->>schedule_version","csv2025_rank_sttime_v2")
   .order("start_time",{ascending:true}).limit(100);
  if(error)throw error;
  return NextResponse.json({
   mode:"RANK_STTIME_WEEKLY_PROGRAM",world:overview.world,
   requestedWeek:week,gameDay,raceCount:(events||[]).length,
   timeRule:"Source stTime order, 3-minute start intervals and 3-minute result delay",
   sourceMeetMap:{"서울":"서울","부산경남":"부산","제주":"영천"},
   races:(events||[]).map(r=>({
    id:r.id,date:r.prize_policy?.kst_date,week:r.prize_policy?.game_week,
    season:r.prize_policy?.season,raceDay:r.race_day,
    time:r.start_time?.slice(0,5),resultTime:r.prize_policy?.result_kst_time,
    track:r.track,grade:r.class_name,distance:r.distance_m,status:r.status,
    sourceMeet:r.prize_policy?.source_meet,
    sourceStTime:r.prize_policy?.source_st_time,
    sourceDistance:r.prize_policy?.source_distance_m??null,
    distancePolicy:r.prize_policy?.distance_policy??null,
    sourceDate:r.prize_policy?.source_date,
    sourceRaceNo:r.prize_policy?.source_rc_no,
    sourceWeekReused:r.prize_policy?.source_week_reused,
    dusu:r.target_runner_count,actualStarters:r.prize_policy?.actual_starters??0,
    entryStatus:r.prize_policy?.entry_status,
    prizesSettled:r.prize_policy?.prize_status==="SETTLED"
   }))
  },{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:"Program unavailable"},
  {status:503,headers:{"Cache-Control":"no-store"}})}
}
