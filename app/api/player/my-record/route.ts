import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const chunk = <T,>(items:T[], size=100) => Array.from({length:Math.ceil(items.length/size)},(_,i)=>items.slice(i*size,(i+1)*size));
const openRace=(s:string)=>/OPEN|대상|그레이드|\bG[1-3]\b/i.test(s||"");
export async function GET(request:Request){
 try{
  const {db,user}=await requireUser(request);
  const schema=db.schema("my_derby");
  const {data:profile,error:pe}=await schema.from("profiles").select("nickname,world_id").eq("user_id",user.id).maybeSingle();
  if(pe)throw pe;
  const empty={profile:{nickname:profile?.nickname||"마주"},total:{starts:0,wins:0,seconds:0,thirds:0,prize:0},open:{starts:0,wins:0,seconds:0,thirds:0,prize:0},seasons:[],trophies:[],incomplete:false};
  // Historical entry ownership is authoritative: a horse may have changed owners after a race.
  const entries:any[]=[];
  for(let offset=0;offset<20000;offset+=1000){
   const {data,error}=await schema.from("race_entries").select("race_id,horse_id").eq("owner_user_id",user.id).range(offset,offset+999);
   if(error)throw error;
   entries.push(...(data||[]));
   if((data||[]).length<1000)break;
  }
  if(!entries.length)return NextResponse.json(empty,{headers:{"Cache-Control":"no-store"}});
  if(entries.length>=20000)return NextResponse.json({error:"출전 기록이 조회 한도를 초과했습니다. 관리자에게 문의해 주세요."},{status:422});
  const raceIds=[...new Set(entries.map(x=>x.race_id))];
  const races:any[]=[];
  for(const ids of chunk(raceIds)){const {data,error}=await schema.from("races").select("id,world_id,race_day,track,race_no,class_name").in("id",ids);if(error)throw error;races.push(...data||[]);}
  const raceMap=new Map(races.map(x=>[x.id,x]));
  const worlds=[...new Set(races.map(x=>x.world_id).filter(Boolean))];
  const worldMap=new Map<string,any>();
  for(const ids of chunk(worlds)){const {data,error}=await schema.from("worlds").select("id,real_days_per_season,game_days_per_real_day").in("id",ids);if(error)throw error;(data||[]).forEach((x:any)=>worldMap.set(x.id,x));}
  const runs:any[]=[];
  for(const ids of chunk(raceIds)){const {data,error}=await schema.from("race_runs").select("id,race_id,status,result_applied_at").in("race_id",ids).eq("status","FINISHED").not("result_applied_at","is",null);if(error)throw error;runs.push(...data||[]);}
  const runMap=new Map(runs.map(x=>[x.id,x]));
  const entriesSet=new Set(entries.map(x=>x.race_id+"|"+x.horse_id));
  const rows:any[]=[];
  for(const ids of chunk(runs.map(x=>x.id))){const {data,error}=await schema.from("race_results").select("race_run_id,horse_id,finishing_rank,prize_amount").in("race_run_id",ids);if(error)throw error;rows.push(...data||[]);}
  const summary=()=>({starts:0,wins:0,seconds:0,thirds:0,prize:0});
  const total=summary(),open=summary(),seasonMap=new Map<number,ReturnType<typeof summary>>();
  const trophies:any[]=[];
  const seen=new Set<string>();
  for(const result of rows){
   const run=runMap.get(result.race_run_id);if(!run||!entriesSet.has(run.race_id+"|"+result.horse_id))continue;
   const key=result.race_run_id+"|"+result.horse_id;if(seen.has(key))continue;seen.add(key);
   const race=raceMap.get(run.race_id);if(!race)continue;
   const world=worldMap.get(race.world_id);
   const days=Math.max(1,Number(world?.real_days_per_season||52)*Number(world?.game_days_per_real_day||7));
   const season=Math.floor(Math.max(0,Number(race.race_day||1)-1)/days)+1;
   if(!seasonMap.has(season))seasonMap.set(season,summary());
   const rank=Number(result.finishing_rank),prize=Number(result.prize_amount)||0;
   const apply=(x:ReturnType<typeof summary>)=>{x.starts++;if(rank===1)x.wins++;if(rank===2)x.seconds++;if(rank===3)x.thirds++;x.prize+=prize;};
   apply(total);apply(seasonMap.get(season)!);
   if(openRace(race.class_name)){
    apply(open);
    if(rank===1)trophies.push({raceId:race.id,season,track:race.track,raceNo:race.race_no,name:race.class_name,day:race.race_day});
   }
  }
  trophies.sort((a,b)=>b.day-a.day);
  const seasons=[...seasonMap.entries()].map(([season,stats])=>({season,...stats})).sort((a,b)=>b.season-a.season);
  return NextResponse.json({profile:{nickname:profile?.nickname||"마주"},total,open,seasons,trophies,incomplete:false},{headers:{"Cache-Control":"no-store"}});
 }catch(error){return NextResponse.json({error:(error as Error).message||"전적 조회 실패"},{status:(error as any).status||500,headers:{"Cache-Control":"no-store"}});}
}
