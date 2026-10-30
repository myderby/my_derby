"use client";
import HorseLink from "./components/HorseLink";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import {selectRaceCommentary} from "../lib/racing/commentary";
import {officialSlotSummaries} from "../lib/racing/slot-status";
const horses=[{id:1,name:"가을바람",age:4,sex:"수",stage:"현역",condition:82,fatigue:18,stats:[81,74,68,76,70,73]},{id:2,name:"골든레이스",age:3,sex:"수",stage:"현역",condition:77,fatigue:22,stats:[74,76,69,72,70,66]},{id:3,name:"작은별",age:1,sex:"암",stage:"목장",condition:93,fatigue:4,stats:[35,39,42,32,36,41]},{id:4,name:"여왕의꿈",age:6,sex:"암",stage:"교배",breedingRetired:true,condition:89,fatigue:9,stats:[80,78,82,76,73,77]},{id:5,name:"블랙스톰",age:5,sex:"거",stage:"재활",condition:58,fatigue:42,stats:[83,73,77,82,69,74]}];
const trainers=[["김도윤","스피드·가속",14],["박수진","지구력·회복",8],["이민호","파워·근성",19],["최은영","컨디션·기질",6],["정우석","마일·선입",20]];
const jockeys=[["박준호","마일·선입",3],["김하늘","중거리·페이스",5],["이승민","출발·단거리",8],["정다은","추입·안정성",2]];
const raceData=[["서울",1200,"6등급"],["서울",1400,"5등급"],["서울",1400,"4등급"],["서울",1800,"3등급"],["서울",1600,"OPEN"]];
const events=[["START",200,"출발과 함께 3번 실버윈드가 빠르게 선두로 나섭니다!"],["PACE",400,"400m 지점, 3번 실버윈드가 앞서고 7번 블루라이트가 따라붙습니다."],["LANE_CHANGE",600,"7번 블루라이트, 외곽으로 진로를 빼며 앞말을 추격합니다."],["OVERTAKE",800,"7번 블루라이트, 5번 레드스타를 제치고 선두권으로 올라섭니다!"],["PACE",1000,"3번 실버윈드와 7번 블루라이트, 나란히 결승선으로 향합니다!"],["FINISH",1200,"7번 블루라이트, 가장 먼저 결승선을 통과합니다!"]];

export default function Home(){const [screen,S]=useState("home"),[selected,H]=useState(horses[0]),[filter,F]=useState("전체"),[race,R]=useState(2),[trainer,T]=useState(0),[jockey,J]=useState(0),[plans,P]=useState(["선입 대기","외곽 선입","후방 추입"]),[pos,E]=useState(0),[playing,Play]=useState(false),[testRuns,SetTestRuns]=useState([]),[testResults,SetTestResults]=useState({}),[activeTestIndex,SetActiveTestIndex]=useState(-1),[gradeFixtureResult,SetGradeFixtureResult]=useState(null),[testBusy,SetTestBusy]=useState(false),[raceSchedule,SetRaceSchedule]=useState(null),[scheduleError,SetScheduleError]=useState(""),[dbStatus,SetDbStatus]=useState(null),[dbBusy,SetDbBusy]=useState(false),[dbRaceId,SetDbRaceId]=useState(""),[dbHistory,SetDbHistory]=useState([]),[dbPreview,SetDbPreview]=useState(null),[breedingHorses,SetBreedingHorses]=useState([]),[breedingLoading,SetBreedingLoading]=useState(false),[breedingMessage,SetBreedingMessage]=useState(""),[toast,Q]=useState(""),[email,Mail]=useState(""),[password,Pass]=useState("");
useEffect(()=>{if(!playing||pos>=events.length)return;const id=setTimeout(()=>E(x=>x+1),1200);return()=>clearTimeout(id)},[playing,pos]);
const liveSlots=(raceSchedule?.races||[]).map(r=>({
 id:r.id,time:r.start_time?.slice(0,5)||"--:--",resultTime:r.result_time,
 track:r.track,distance:r.distance_m,grade:r.class_name,
 displayNo:r.race_no,status:r.status,entryStatus:r.entry_status,
 dusu:r.dusu,actual:r.actual_starters
}));
const todaySlotSummaries=officialSlotSummaries(raceSchedule?.races||[]);
// Same authenticated finance endpoint as /finance: never display fake balances.
const [walletBalance,SetWalletBalance]=useState({status:"LOADING",balance:null});
useEffect(()=>{
 let mounted=true;
 let requestNumber=0;
 let client;
 try{
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if(!url||!key)throw new Error("Supabase 설정이 없습니다.");
  client=createClient(url,key);
 }catch(_error){
  SetWalletBalance({status:"ERROR",balance:null});
  return;
 }
 const refreshWallet=async()=>{
  const request=++requestNumber;
  try{
   const {data:sessionData,error:sessionError}=await client.auth.getSession();
   if(!mounted||request!==requestNumber)return;
   if(sessionError)throw sessionError;
   const token=sessionData.session?.access_token;
   if(!token){
    SetWalletBalance({status:"SIGNED_OUT",balance:null});
    return;
   }
   const response=await fetch("/api/player/finance",{
    headers:{Authorization:"Bearer "+token},
    cache:"no-store"
   });
   const result=await response.json();
   if(!mounted||request!==requestNumber)return;
   if(!response.ok){
    if(result.error==="JOIN_WORLD_FIRST"){
     SetWalletBalance({status:"NOT_JOINED",balance:null});
     return;
    }
    throw new Error(result.error||"잔액 조회 실패");
   }
   // Response comes from the very same player_finance_dashboard RPC as /finance.
   if(!/^-?\d+$/.test(String(result.balance)))
    throw new Error("잔액 데이터 형식이 올바르지 않습니다.");
   SetWalletBalance({status:"READY",balance:String(result.balance)});
  }catch(_error){
   if(mounted&&request===requestNumber)
    SetWalletBalance({status:"ERROR",balance:null});
  }
 };
 void refreshWallet();
 const handleFocus=()=>{if(document.visibilityState==="visible")void refreshWallet()};
 window.addEventListener("focus",handleFocus);
 document.addEventListener("visibilitychange",handleFocus);
 const {data:{subscription}}=client.auth.onAuthStateChange(()=>{
  // Avoid making an awaited Supabase call inside its auth callback.
  setTimeout(()=>{if(mounted)void refreshWallet()},0);
 });
 const timer=setInterval(()=>{
  if(document.visibilityState==="visible")void refreshWallet();
 },30000);
 return ()=>{
  mounted=false;
  requestNumber++;
  subscription.unsubscribe();
  window.removeEventListener("focus",handleFocus);
  document.removeEventListener("visibilitychange",handleFocus);
  clearInterval(timer);
 };
},[]);
const walletText=walletBalance.status==="READY"
 ?"◉ "+BigInt(walletBalance.balance).toLocaleString("ko-KR")+" G"
 :walletBalance.status==="SIGNED_OUT"?"◉ 로그인 후 확인"
 :walletBalance.status==="NOT_JOINED"?"◉ 마주 등록 필요"
 :walletBalance.status==="ERROR"?"◉ 잔액 조회 실패"
 :"◉ 잔액 조회 중";

const go=x=>{const routes={testFixture:"/test-race",allHorses:"/horses",allJockeys:"/jockeys",ratings:"/ratings",auction:"/auction",injuries:"/injuries",ranchManagement:"/ranch/management",notifications:"/notifications",races:"/schedule",training:"/training",breeding:"/breeding",horses:"/world",trainers:"/stable",ranch:"/ranch",market:"/market",finance:"/finance",entry:"/entries",jockey:"/entries",strategy:"/entries",results:"/schedule"};if(routes[x]&&typeof window!=="undefined"){window.location.assign(routes[x]);return;}S(x);if(typeof window!=="undefined")window.scrollTo(0,0)},msg=x=>{Q(x);setTimeout(()=>Q(""),3500)};
const title=(x,sub)=><div className="pageTitle"><button className="back" onClick={()=>go("home")}>‹</button><div><h1>{x}</h1><div className="sub">{sub}</div></div></div>;
const section=(x,next)=><div className="section"><h2>{x}</h2>{next&&<button onClick={()=>go(next)}>전체 보기 ›</button>}</div>;
const box=(a,b,d,right)=><div className="card action row" onClick={d}><div><b>{a}</b><div className="muted">{b}</div></div><span className="tag">{right||"›"}</span></div>;
const notReady=x=>msg(x+"은(는) 아직 시연 화면입니다. 실제 서버에 기록되지 않습니다.");
const runTestAt=async index=>{
 const race=liveSlots[index];
 if(!race?.id)throw new Error("경주시간표를 먼저 불러와야 합니다.");
 const response=await fetch("/api/race/scheduled-test",{
  method:"POST",headers:{"Content-Type":"application/json"},
  body:JSON.stringify({raceId:race.id}),cache:"no-store"
 });
 const payload=await response.json();
 if(!response.ok||!payload.result||payload.mode!=="SCHEDULE_BASED_TEST")
  throw new Error(payload.error||"경주 계산 실패");
 SetTestResults(previous=>({...previous,[index]:payload.result}));
 SetTestRuns(previous=>previous.includes(index)?previous:[...previous,index]);
 SetActiveTestIndex(index);
 return payload.result;
};
const runGradeFixture=async()=>{
 if(testBusy)return;
 SetTestBusy(true);SetGradeFixtureResult(null);
 try{
  const response=await fetch("/api/race/test-19",{method:"POST",
   headers:{"Content-Type":"application/json"},body:"{}",cache:"no-store"});
  const data=await response.json();
  if(!response.ok||data.mode!=="FIXTURE_TEST_ONLY"||!data.result)
   throw new Error(data.error||"19시 등급 비교 경주 계산 실패");
  SetGradeFixtureResult(data.result);
  msg("19시 서울 1경주 테스트 완료 · 1등급 5두 / 5등급 5두 · 우승 "+data.result.results[0].name);
 }catch(e){msg("19시 테스트 실패: "+e.message)}
 finally{SetTestBusy(false)}
};
const runNextTestRace=async()=>{
 if(testBusy||!liveSlots.length||testRuns.length>=liveSlots.length)return;
 const index=testRuns.length;
 SetTestBusy(true);
 try{
  const result=await runTestAt(index);
  msg(liveSlots[index].time+" "+liveSlots[index].track+" "+liveSlots[index].displayNo+
   "경주 테스트 완료 · "+result.results.length+"두 · 우승 "+result.results[0].name);
 }catch(e){msg("경주 테스트 실패: "+e.message)}
 finally{SetTestBusy(false)}
};
const runAllTestRaces=async()=>{
 if(testBusy||!liveSlots.length||testRuns.length>=liveSlots.length)return;
 SetTestBusy(true);
 let finished=0;
 try{
  for(let index=testRuns.length;index<liveSlots.length;index++){
   await runTestAt(index);
   finished++;
  }
  msg("오늘 전체 "+finished+"경주 순차 계산 완료 · 공식 기록은 변경되지 않습니다.");
 }catch(e){msg("연속 테스트 중단 ("+finished+"경주 완료): "+e.message)}
 finally{SetTestBusy(false)}
};
const resetTestRaces=()=>{
 SetTestRuns([]);SetTestResults({});SetActiveTestIndex(-1);
 msg("비공식 테스트 결과만 초기화했습니다. 정식 전적·상금은 그대로입니다.");
};
const getDbToken=async()=>{
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!url||!key)throw new Error("Supabase 설정이 없습니다.");
 const {data,error}=await createClient(url,key).auth.getSession();
 if(error||!data.session?.access_token)throw new Error("먼저 계정 메뉴에서 로그인해야 합니다.");
 return data.session.access_token;
};
const fetchDbStatus=async()=>{
 go("database");SetDbBusy(true);
 try{
  const res=await fetch("/api/race/db-status",{cache:"no-store"});const data=await res.json();
  if(!res.ok||!data.connected)throw new Error(data.error||"연결 실패");
  SetDbStatus(data);
 }catch(e){msg("DB 오류: "+e.message)}finally{SetDbBusy(false)}
};
const loadDbHistory=async()=>{
 SetDbBusy(true);
 try{
  const token=await getDbToken();
  const res=await fetch("/api/race/preview",{headers:{Authorization:"Bearer "+token},cache:"no-store"});
  const data=await res.json();if(!res.ok)throw new Error(data.error||"조회 실패");
  SetDbHistory(data.previews||[]);msg("내 비공식 경주 기록 "+(data.previews||[]).length+"건");
 }catch(e){msg("기록 조회: "+e.message)}finally{SetDbBusy(false)}
};
const runDbPreview=async()=>{
 SetDbBusy(true);
 try{
  const token=await getDbToken();
  const res=await fetch("/api/race/preview",{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+token},
    body:JSON.stringify({raceId:dbRaceId.trim()}),cache:"no-store"});
  const data=await res.json();if(!res.ok)throw new Error(data.error||"계산 실패");
  SetDbPreview(data.result);msg("DB 출전마로 계산하고 비공식 기록을 저장했습니다.");
 }catch(e){msg("DB 경주: "+e.message)}finally{SetDbBusy(false)}
};

const loadBreedingHorses=async()=>{
 SetBreedingLoading(true);
 try{
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if(!url||!key)throw new Error("Supabase 설정이 없습니다.");
  const client=createClient(url,key);
  const {data:{session}}=await client.auth.getSession();
  if(!session){SetBreedingHorses([]);SetBreedingMessage("로그인 후 본인 소유마를 확인할 수 있습니다.");return;}
  const {data,error}=await client.schema("my_derby").from("horses").select("id,name,sex,age_years,life_stage,breeding_retired_at,racing_retired_permanently,race_entry_state").order("created_at",{ascending:true});
  if(error)throw error;
  SetBreedingHorses(data||[]);SetBreedingMessage(data?.length?"":"아직 등록된 본인 소유마가 없습니다.");
 }catch(e){SetBreedingHorses([]);SetBreedingMessage("조회 실패: "+e.message)}finally{SetBreedingLoading(false)}
};
const canBreedRetire=h=>!h.breeding_retired_at&&!h.racing_retired_permanently&&["RACING","RETIRED"].includes(h.life_stage)&&
  (h.sex==="MALE"&&h.age_years>=2||h.sex==="FEMALE"&&h.age_years>=4&&h.age_years<=18);
const retireBreeder=async(h)=>{
 if(!window.confirm(h.name+"을(를) 교배용으로 영구 은퇴시키겠습니까?\n다시는 경주마로 복귀할 수 없습니다."))return;
 SetBreedingLoading(true);
 try{
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  const client=createClient(url,key);
  const {data:{session}}=await client.auth.getSession();if(!session)throw new Error("로그인해야 합니다.");
  const {error}=await client.schema("my_derby").rpc("retire_horse_for_breeding",{p_horse_id:h.id});
  if(error)throw error;
  msg(h.name+" 번식마 영구 은퇴 완료 · 경주 복귀 불가");
  await loadBreedingHorses();
 }catch(e){SetBreedingMessage("은퇴 처리 오류: "+e.message);msg("은퇴 처리 오류: "+e.message)}finally{SetBreedingLoading(false)}
};
const auth=async signup=>{const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;if(!url||!key)return msg("Supabase 환경 설정이 필요합니다.");const c=createClient(url,key);try{const {error}=signup?await c.auth.signUp({email,password}):await c.auth.signInWithPassword({email,password});msg(error?error.message:signup?"이메일 가입 요청 완료":"로그인 완료 (게임 데이터 저장 미연동)")}catch(e){msg(e.message)}};
useEffect(()=>{if(screen==="breeding"){void loadBreedingHorses()}},[screen]);
useEffect(()=>{
 if(screen!=="home"&&screen!=="testRaces")return;
 let alive=true;
 const refresh=()=>fetch("/api/world/schedule",{cache:"no-store"}).then(async r=>{
  const data=await r.json();if(!r.ok)throw new Error(data.error||"경주 일정 조회 실패");
  if(alive){SetRaceSchedule(data);SetScheduleError("");}
 }).catch(e=>{if(alive)SetScheduleError(e.message)});
 void refresh();
 const timer=setInterval(refresh,15000);
 return ()=>{alive=false;clearInterval(timer)};
},[screen]);
return <main className="shell"><header className="header"><div onClick={()=>go("home")}><div className="brand">MY DERBY</div><div className="sub">{raceSchedule?.world?`${raceSchedule.world.season}시즌 · ${raceSchedule.world.week}주차 · ${raceSchedule.world.status==="ACTIVE"?"월드 운영 중":"운영 대기"}`:"경주 일정 조회 중"}</div></div><a className="coin" href={walletBalance.status==="READY"?"/finance":"/world"}
 title={walletBalance.status==="READY"?"내 실제 게임머니 잔액 · 재무 관리로 이동":"로그인 또는 마주 등록 후 잔액을 확인할 수 있습니다."}
 style={{textDecoration:"none",whiteSpace:"nowrap"}} aria-live="polite">{walletText}</a></header><div className="disclaimer">월드 시간표는 운영 중 · 일반 관리화면은 체험 UI 포함 · 공식 경기 결과는 별도 저장</div>
{screen==="home"&&<><div className="hero"><div className="overline">🍂 오늘도 우리 말들과 함께 성장해요</div><h1>가을 목장</h1><div className="caption">마주의 새로운 하루</div><button className="primary" onClick={()=>go("ranch")}>목장 둘러보기 ›</button></div><div className="area">{section("오늘의 관리","horses")}<div className="card row"><div><div className="large gold">내 보유마</div><div className="muted">내 말 관리에서 소유마와 전적 확인</div></div><div><button className="outline" onClick={()=>go("horses")}>내 말 관리 ›</button></div><button className="outline" onClick={()=>window.location.assign("/test-race")}>경주 테스트 · 10두 ›</button></div>{section("오늘의 공식 경주 시간표","races")}
{raceSchedule?<><div className="muted" style={{marginBottom:12}}>오늘 총 {raceSchedule.raceCount}경주 · 19시/20시/21시 시간대별 공식 진행 현황</div>
 <div className="official-slot-grid">
  {todaySlotSummaries.map(slot=><a key={slot.hour}
    className={"official-slot-card official-slot-"+slot.state.toLowerCase()}
    href={"/schedule?slot="+slot.hour}
    aria-label={slot.hour+"시 경주 "+slot.total+"개, "+slot.label+", 전체 목록 보기"}>
   <div className="official-slot-top">
    <div><div className="official-slot-kicker">OFFICIAL RACE</div>
     <div className="official-slot-hour">{slot.hour}<span>시 경주</span></div></div>
    <span className={"official-slot-badge official-slot-badge-"+slot.state.toLowerCase()}>{slot.label}</span>
   </div>
   <div className="official-slot-detail">{slot.total
     ?slot.total+"경주 · "+slot.firstStart+" ~ "+slot.lastStart
     :"편성된 경주 없음"}</div>
   <div className="official-slot-bottom">
    <span>{slot.total?"완료 "+slot.completed+" / "+slot.total+"경주":"일정 없음"}</span>
    <span className="official-slot-view">경주 목록 보기 ›</span>
   </div>
   {slot.total>0&&<div className="official-slot-progress" aria-hidden="true">
    <span style={{width:slot.completed/slot.total*100+"%"}}/></div>}
  </a>)}
 </div>
 <a href="/schedule" className="outline wide" style={{display:"block",textAlign:"center",textDecoration:"none",marginTop:10}}>오늘 전체 {raceSchedule.raceCount}경주 보기 ›</a></>:
 <div className="notice">{scheduleError||"오늘 경주시간표를 불러오는 중…"}</div>}
{<a href="/breeding" className="card action row" style={{textDecoration:"none",color:"inherit",display:"flex",marginTop:14}}><div><b className="gold">✧ 교배 신청 · 임신 관리</b><div className="muted">시스템 씨수말 · 궁합 검사 · 임신 · 출산</div></div><span className="tag">교배 ›</span></a>}{<a href="/training" className="card action row" style={{textDecoration:"none",color:"inherit",display:"flex",marginTop:14}}><div><b className="gold">🐎 실제 훈련계획 · 리포트</b><div className="muted">거리·전개 스타일 선택 · 능력 성장 · 피로/컨디션 관리</div></div><span className="tag">훈련 ›</span></a>}{<a href="/entries" className="card action row" style={{textDecoration:"none",color:"inherit",display:"flex",marginTop:14}}><div><b className="gold">🏇 공식 출전 · 기수 신청</b><div className="muted">내 경주마 신청 및 NPC 기수 계약 · 실제 DB 저장</div></div><span className="tag">신청 ›</span></a>}<a href="/test-race" className="card action row" style={{textDecoration:"none",color:"inherit",display:"flex",marginTop:14}}><div><b className="gold">🧪 19시 1경주 테스트</b><div className="muted">1등급 5두 vs 5등급 5두 · 10두 출전표 · 비공식 경주 시뮬레이션</div></div><span className="tag">실행 ›</span></a>{box("⚡ 공식 시간표 강제 테스트","공식 출전마를 복사해 비공식 경주 계산 · 기존 기능 유지",()=>go("testRaces"),testRuns.length+"/"+liveSlots.length)}<a href="/schedule" className="card action row" style={{textDecoration:"none",color:"inherit",display:"flex",marginTop:14}}><div><b className="gold">📅 52주 공식 경주시간표</b><div className="muted">19시·20시·21시 경주 시간표 · 결과 3분 후</div></div><span className="tag">시간표 ›</span></a><a href="/world" className="card action row" style={{textDecoration:"none",color:"inherit",display:"flex",marginTop:14}}><div><b className="gold">🐎 내 말 관리</b><div className="muted">내 보유마 · 건강 · 훈련 · 출전 · 번식</div></div><span className="tag">열기 ›</span></a></div></>}
{screen==="testRaces"&&<>{title("공식 시간표 경주 강제 테스트","19시 부산·영천 / 20시 서울·영천 / 21시 서울·부산")}
<div className="area">
<div className="card row" style={{borderColor:"#b8924e",marginBottom:12}}>
 <div><b className="gold">🧪 19시 서울 1경주 · 등급 비교 테스트</b>
 <div className="muted">1등급 5두 vs 5등급 5두 · 10두 비공식 시연</div></div>
 <a className="outline" href="/test-race" style={{textDecoration:"none"}}>테스트 출전표 ›</a>
</div>
<button className="primary wide" disabled={testBusy} onClick={runGradeFixture}>
 {testBusy?"경주 계산 중…":"▶ 19시 서울 1경주 · 1등급 5두 / 5등급 5두 테스트 실행"}
</button>
{gradeFixtureResult&&<div className="card" style={{marginTop:12}}>
 <b className="gold">19시 1경주 비공식 결과 · 10두</b>
 {gradeFixtureResult.results.map(x=><div className="line row small" key={x.horseId}>
 <b>{x.rank}위</b><span>{x.number}번 <HorseLink horseId={x.horseId}>{x.name}</HorseLink></span>
 <span>{x.timeSec.toFixed(2)}초</span></div>)}
 <a className="outline wide" href="/test-race" style={{display:"block",textAlign:"center",textDecoration:"none",marginTop:12}}>
 전체 출전표 및 구간 중계 보기 ›</a>
</div>}
<div className="notice"><b>아래 버튼은 공식 시간표의 비공식 미리보기이며, 위 19시 1경주 등급 비교 테스트와 별개입니다.</b><br/>
오늘 편성된 경주를 출발 시각순으로 하나씩 테스트합니다.
각 경주는 3분 간격으로 시작하며 공식 결과는 시작 3분 후 공개됩니다.
테스트에서는 시계를 기다리지 않고 같은 엔진을 강제로 계산하지만
경주 상태, 공식 기록, 상금에는 영향을 주지 않습니다.</div>
<div className="card row"><b className="gold">오늘 {liveSlots.length}경주</b>
<span className="tag">{testRuns.length}/{liveSlots.length} 테스트 완료</span></div>
{scheduleError&&<div className="notice">{scheduleError}</div>}
<div className="controls">
<button className="primary" disabled={testBusy||!liveSlots.length||testRuns.length>=liveSlots.length} onClick={runNextTestRace}>
{testBusy?"경주 계산 중…":testRuns.length<liveSlots.length?
  liveSlots[testRuns.length].time+" 공식 편성 테스트":"전체 테스트 완료"}</button>
<button className="outline" disabled={testBusy||!liveSlots.length||testRuns.length>=liveSlots.length} onClick={runAllTestRaces}>전체 일정 연속 테스트</button>
</div>
<div style={{height:10}}/><button className="outline wide" disabled={testBusy} onClick={resetTestRaces}>비공식 테스트 초기화</button>
<div style={{height:14}}/>
{liveSlots.map((race,i)=><div className="card row" key={race.id} onClick={()=>{if(testResults[i])SetActiveTestIndex(i)}} style={{cursor:testResults[i]?"pointer":"default",padding:"11px 13px"}}>
 <div><b className="gold">{race.time} · {race.track} {race.displayNo}경주</b>
 <div className="muted">{race.grade} · {race.distance}m · 출전 {race.actual}/{race.dusu}두 · 결과 {race.resultTime}</div></div>
 <span className="tag">{testRuns.includes(i)?"✓ 테스트 완료":race.entryStatus==="INSUFFICIENT_ELIGIBLE_HORSES"?"출전마 부족":i===testRuns.length?"다음":"대기"}</span>
</div>)}
{activeTestIndex>=0&&testResults[activeTestIndex]&&(()=>{
 const result=testResults[activeTestIndex],winner=result.results[0],r=liveSlots[activeTestIndex];
 return <><div style={{height:14}}/>{section("선택한 비공식 경주 결과")}
 <div className="card"><b>{r.time} · {r.track} {r.displayNo}경주 · {r.grade}</b>
 <div className="large gold">{winner.number}번 {winner.name} 우승</div>
 <div className="muted">경주기록 {winner.timeSec.toFixed(2)}초 · 결과 발표 예정 {r.resultTime} · 시드 {result.seed}</div></div>
 <div className="card">{result.results.map(x=><div className="row line small" key={x.horseId}>
 <b className="gold">{x.rank}위</b><span>{x.number}번 <HorseLink horseId={x.horseId}>{x.name}</HorseLink></span><span>{x.timeSec.toFixed(2)}초</span></div>)}</div>
 {section("200m 구간 순위")}
 <div className="card">{result.sections.map(x=><div className="line" key={x.distanceM}>
 <b className="gold">{x.distanceM}m</b>
 <div className="muted">{x.ranks.slice(0,5).map(h=>h.rank+"위 "+h.number+"번 "+h.name).join(" · ")}</div></div>)}</div>
 {section("경주 중계 · 출발부터 결승선까지")}
 {selectRaceCommentary(result.events).map(x=><div className="card" key={x.seq}>
 <div className="muted">{x.timeSec.toFixed(1)}초 · {x.distanceM.toFixed(0)}m</div>
 <div className="small">{x.text}</div></div>)}
 </>;
})()}
</div></>}
{screen==="database"&&<>{title("Supabase 경주 DB 연동","my_derby · 비공식 시뮬레이션")}<div className="area">
<div className="notice">DB의 19시 서울 1경주 테스트는 1등급 5두·5등급 5두 10두로 구성되며,
20시·21시 시연 데이터는 각 12두입니다. 별도 공식 시간표 강제 테스트는 실제 공식 출전마의 복사본을 사용합니다. 정규 경주 데이터가 등록되면 본인 소유 출전마에 한해 미리보기를 실행할 수 있습니다. 공식 순위·상금·시즌 데이터는 변경하지 않습니다.</div>
<button className="outline wide" disabled={dbBusy} onClick={fetchDbStatus}>DB 연결 상태 확인</button>
{dbStatus&&<div className="card"><b className="green">● {dbStatus.schema} 연결 성공</b><div className="line row"><span>정규 등록 경주</span><b>{dbStatus.registeredRaces}건</b></div>
<div className="line row"><span>DB 테스트 경주</span><b>{dbStatus.storedTestFixtures}건</b></div><div className="muted">공식 결과 저장·상금 정산: 미연결</div></div>}
<h2>내 출전 경주 계산</h2>
<div className="muted">로그인이 필요합니다. 출전이 마감된 경주의 UUID를 입력하세요. 다른 마주의 비공개 능력치가 필요한 경주는 계산을 중단합니다.</div>
<input className="field" placeholder="경주 ID (UUID)" value={dbRaceId} onChange={e=>SetDbRaceId(e.target.value)}/>
<button className="primary wide" disabled={dbBusy||dbRaceId.trim().length<30} onClick={runDbPreview}>DB 출전마로 계산 · 비공식 기록 저장</button>
<div style={{height:10}}/><button className="outline wide" disabled={dbBusy} onClick={loadDbHistory}>내 미리보기 기록 조회</button>
{dbHistory.length>0&&<div className="card">{dbHistory.map(x=><div className="line" key={x.id}><b>{x.result_snapshot?.results?.[0]?.name||"출전 경주"}</b><div className="muted">{x.created_at} · {x.race_id}</div></div>)}</div>}
{dbPreview&&<div className="card"><b>최근 비공식 경주 순위</b>{dbPreview.results.map(x=><div className="line row small" key={x.horseId}><b>{x.rank}위</b><span>{x.number}번 <HorseLink horseId={x.horseId}>{x.name}</HorseLink></span><span>{x.timeSec}초</span></div>)}</div>}
</div></>}
{screen==="horses"&&<>{title("보유마","생애 단계와 상태를 한눈에")}<div className="area"><div className="card"><b>전체 5두</b><div className="muted">현역 2 · 목장 1 · 교배 1 · 재활 1</div></div><div className="tabs">{["전체","현역","목장","교배","재활"].map(x=><button className={filter===x?"active":""} onClick={()=>F(x)} key={x}>{x}</button>)}</div>{horses.filter(x=>filter==="전체"||x.stage===filter).map(x=><div key={x.id}>{box("♞ "+x.name,x.age+"세 · "+x.sex+"말 · 컨디션 "+x.condition,()=>{H(x);go("horse")},x.stage)}</div>)}</div></>}
{screen==="horse"&&<>{title(selected.name,selected.age+"세 · "+selected.sex+"말 · "+selected.stage)}<div className="area"><div className="card"><div className="large gold">♞ {selected.name}</div><div className="muted">컨디션 {selected.condition} · 피로 {selected.fatigue}</div><div className="bar"><div className="fill" style={{width:selected.condition+"%"}}/></div></div>{section("능력치 · 추정")}<div className="grid">{["스피드","가속력","지구력","막판탄력","파워","근성"].map((x,i)=><div className="card" key={x}><div className="row small"><span>{x}</span><b>{selected.stats[i]}</b></div><div className="bar"><div className="fill" style={{width:selected.stats[i]+"%"}}/></div></div>)}</div><div className="notice">현재 능력치 수치는 샘플입니다. 잠재력·유전값·훈련의 실제 결과는 서버 엔진 미연결 상태입니다.</div><div className="twoCol">{[["조교사 찾기","trainers"],["훈련 리포트","training"],["경주 일정","races"],["개인목장","ranch"]].map(([t,p])=><button key={p} className="outline" onClick={()=>go(p)}>{t}</button>)}</div></div></>}
{screen==="trainers"&&<>{title("조교사 찾기","등급 대신 전문성·수용량 비교")}<div className="area"><div className="notice">NPC 조교사는 최대 40두 담당합니다. 실제 신청·수락 판정은 서버 자동 판단 모듈 구현 후 연결됩니다.</div>{trainers.map(([n,s,count],i)=><div key={n}>{box(n,s+" · "+count+"/20두",()=>T(i),trainer===i?"선택":"비교")}</div>)}<button className="primary wide" onClick={()=>notReady(trainers[trainer][0]+" 위탁 신청")}>위탁 신청 (체험)</button></div></>}
{screen==="training"&&<>{title("훈련 리포트","성장 방향과 일일 관리")}<div className="area"><div className="card"><b>오늘의 훈련 · 가상 예시</b><div className="line">스피드 +0.3 · 지구력 +0.1</div><div className="muted">피로 +4 · 컨디션 -2 · 이해도 +1</div></div>{section("성장 방향")}<select className="field">{["단거리","마일","중거리","장거리"].map(x=><option key={x}>{x}</option>)}</select><select className="field">{["도주","선행","선입","중반무빙","추입","자유형"].map(x=><option key={x}>{x}</option>)}</select><button className="primary wide" onClick={()=>notReady("성장 방향 변경")}>성장 방향 선택</button></div></>}
{screen==="ranch"&&<>{title("개인목장","휴양 · 재활 · 기초육성")}<div className="area"><div className="card"><b>가을빛 개인목장</b><div className="muted">관리사 4명 · 수의사 1명</div></div>{section("목장 시설")}{[["방목지","휴양·기질 안정"],["회복 마방","컨디션 회복"],["재활 트랙","부상 재활"],["수의 진료소","치료·진료"],["어린말 육성장","0~1세 기초육성"]].map(([a,b])=><div key={a}>{box(a,b,()=>go("course"),"시설")}</div>)}<button className="primary wide" onClick={()=>go("course")}>휴양 · 재활 코스 ›</button></div></>}
{screen==="course"&&<>{title("휴양·재활 코스","입소 기간과 코스 선택")}<div className="area">{["3일 휴양","7일 회복","재활 코스","어린말 기초육성"].map(x=><div key={x}>{box(x,"NPC 강훈련과 동일 날짜 중복 불가",()=>notReady(x+" 신청"))}</div>)}</div></>}
{screen==="races"&&<>{title("경주 일정","출전 조건 및 전략 신청")}<div className="area"><div className="tabs">{["서울","부경","영천"].map(x=><button key={x} className={filter===x?"active":""} onClick={()=>F(x)}>{x}</button>)}</div>{raceData.map(([track,dist,grade],i)=><div key={i}>{box(String(i+1).padStart(2,"0")+"R · "+(filter==="부경"||filter==="영천"?filter:track)+" · "+dist+"m",grade+" · 시연 편성",()=>{R(i);go("entry")},"출전 준비")}</div>)}<div className="notice">경주 일정은 개발안 설명용 예시입니다. 실제 서버 일정과 확정 시각은 아직 연동되지 않았습니다.</div></div></>}
{screen==="entry"&&<>{title("출전 준비","경주·말·기수·전략")}<div className="area"><div className="card"><b>서울 {race+1}경주 · {raceData[race][1]}m</b><div className="muted">{raceData[race][2]} · 체험용 편성</div></div>{box(selected.name,selected.age+"세 · 컨디션 "+selected.condition,()=>go("horses"),"말 변경")}{box("기수 신청","기수 전문성 및 수락 확인",()=>go("jockey"))}{box("전략 1~3안","기수 전개 방향 설정",()=>go("strategy"))}<button className="primary wide" disabled={selected.stage!=="현역"||selected.breedingRetired===true} onClick={()=>notReady("경주 출전 신청")}>{selected.stage==="현역"&&selected.breedingRetired!==true?"출전 신청":"은퇴·번식마 출전 불가"}</button>{(selected.stage!=="현역"||selected.breedingRetired===true)&&<div className="notice">은퇴·번식 상태로 전환된 말은 다시 현역 경주마로 복귀할 수 없으며, 경주 출전이 영구적으로 제한됩니다.</div>}<div style={{height:10}}/><button className="outline wide" onClick={()=>{E(0);Play(false);go("spectate")}}>경주 로그 화면 시연 ›</button></div></>}
{screen==="jockey"&&<>{title("기수 신청","한 경주 1두 · 일일 최대 8회")}<div className="area">{jockeys.map(([n,s,count],i)=><div key={n}>{box(n,s+" · "+count+"/8경주",()=>J(i),jockey===i?"선택":"신청 가능")}</div>)}<button className="primary wide" onClick={()=>notReady(jockeys[jockey][0]+" 기승 신청")}>기승 신청</button></div></>}
{screen==="strategy"&&<>{title("경주 전략","1안·2안·3안 · 기수 자율 판단")}<div className="area"><div className="notice">기수는 전개 상황에 따라 전략을 바꿀 수 있지만, 경주 중계에는 전략 번호 대신 추월·진로 변경·선두 경쟁 등 실제 움직임만 표시됩니다.</div>{plans.map((x,i)=><div className="card" key={i}><b className="gold">{i+1}안 {i===0?"· 기본":"· 대안"}</b><select className="field" value={x} onChange={e=>P(y=>y.map((v,j)=>j===i?e.target.value:v))}>{["선입 대기","외곽 선입","후방 추입","선행 압박","중반 무빙","자유 판단"].map(p=><option key={p}>{p}</option>)}</select></div>)}<button className="primary wide" onClick={()=>notReady("전략 저장")}>전략 저장</button></div></>}
{screen==="spectate"&&<>{title("경주 로그 관전","샘플 이벤트 · 실제 엔진 산출 아님")}<div className="area"><div className="card"><b>서울 3경주 · 1,200m</b><div className="large gold">{pos?events[pos-1][1]:0}m / 1200m</div><div className="bar"><div className="fill" style={{width:(pos?events[pos-1][1]/12:0)+"%"}}/></div><div className="raceTrack">{["출발","초반","중반","승부처","종반"].map(x=><span key={x}>{x}</span>)}</div></div>{section("구간별 순위 · 시연")}<div className="card">{["7 블루라이트","3 실버윈드","5 레드스타","2 가을바람","1 골든스텝"].map((h,i)=><div className="line row" key={h}><b className="gold">{i+1}위</b><span>{h}</span><span className="muted">{i===0?"선두":"+"+(i*.8).toFixed(1)+"m"}</span></div>)}</div>{section("경주 중계 (시연)")}
{events.slice(0,pos).map(([type,m,txt])=><div className="card" key={m}><div className="muted">{m}m</div><div className="small">{txt}</div></div>)}<div className="controls"><button className="outline" onClick={()=>Play(!playing)}>{playing?"⏸ 정지":"▶ 재생"}</button><button className="outline" onClick={()=>{E(events.length);Play(false)}}>끝으로</button><button className="primary" onClick={()=>{Play(false);go("results")}}>결과</button></div></div></>}
{screen==="results"&&<>{title("경주 결과","가상 시연 자료")}<div className="area"><div className="notice">이 결과는 실제 경주 엔진 산출물이 아닙니다. 공식 기록·보상·피로도는 변경되지 않습니다.</div><div className="card">{["7 블루라이트","3 실버윈드","5 레드스타"].map((x,i)=><div className="line row" key={x}><b className="gold">{i+1}위</b><span>{x}</span><span className="muted">1:1{5+i}.8</span></div>)}</div><button className="outline wide" onClick={()=>go("spectate")}>로그 다시 보기</button></div></>}
{screen==="breeding"&&<>{title("교배 · 영구 은퇴","번식마 전환은 되돌릴 수 없습니다")}<div className="area">
<div className="notice"><b>⚠ 번식마로 은퇴하면 현역 경주마로 복귀할 수 없습니다.</b><br/>씨수말·번식암말 은퇴는 영구 처리됩니다. 시즌이 변경되어도 유지되며 기존 전적과 혈통은 남습니다. 출전 신청 중인 말은 은퇴 처리할 수 없습니다.</div>
{section("내 경주마 · 번식마")}
<button className="outline wide" onClick={loadBreedingHorses} disabled={breedingLoading}>{breedingLoading?"조회 중":"보유마 새로고침"}</button>
{breedingMessage&&<div className="notice">{breedingMessage}</div>}
{breedingHorses.map(h=><div className="card" key={h.id}>
<div className="row"><b className="gold">♞ <HorseLink horseId={h.id}>{h.name}</HorseLink></b><span className="tag">{h.breeding_retired_at||h.racing_retired_permanently?"은퇴 · 복귀 불가":h.life_stage==="RACING"?"현역":h.life_stage}</span></div>
<div className="muted">{h.age_years}세 · {h.sex==="FEMALE"?"암말":h.sex==="MALE"?"수말":"거세마"} · {h.life_stage==="BROODMARE"?"번식암말":h.life_stage==="STALLION"?"씨수말":"상태: "+h.life_stage}</div>
{canBreedRetire(h)?<button style={{marginTop:10}} className="outline wide" disabled={breedingLoading} onClick={()=>retireBreeder(h)}>교배용 영구 은퇴</button>:
<div className="muted">{h.breeding_retired_at||h.racing_retired_permanently?"영구 은퇴 상태: 경주 출전 불가":"현재 교배용 은퇴 조건 미충족"}</div>}
</div>)}
{section("교배 신청")}
<div className="card"><b>번식 자격</b><div className="muted">번식암말은 4~18세이며, 씨수말과 번식암말 모두 은퇴 상태여야 합니다. 교배 후 현역 복귀는 불가능합니다.</div></div>
{box("씨수말 후보","시스템 씨수말 선택 및 궁합 계산 준비 중",()=>notReady("씨수말 선택"),"개발 예정")}
<div className="notice">교배 승인·임신·출산·유전 계산은 아직 구현되지 않았습니다. 위 ‘교배용 영구 은퇴’ 버튼은 로그인한 본인 소유마의 실제 DB 상태를 변경합니다.</div>
<button className="outline wide" onClick={()=>notReady("교배 신청")}>교배 신청 (개발 예정)</button>
</div></>}
{screen==="menu"&&<>{title("전체 메뉴","MY DERBY")}<div className="area"><a href="/my-record" className="card action row" style={{textDecoration:"none",color:"inherit",display:"flex",borderColor:"#9a743b"}}><div><b className="gold">🏅 나의 정보</b><div className="muted">통산·시즌별 전적 · OPEN 성적 · 대상경주 트로피</div></div><span>›</span></a><a href="/world" className="card action row" style={{textDecoration:"none",color:"inherit",display:"flex"}}><div><b className="gold">🐎 내 말 관리</b><div className="muted">내 보유마 · 훈련 · 출전 · 번식</div></div><span>›</span></a>{[["경주 관리","공식 출전표 · 경주 진행 · 결과","races"],["공식 편성 강제 테스트","19시·20시·21시 공식 출전마 복사 · 정식 기록 미반영","testRaces"],["내 말 관리","보유마 · 훈련 · 출전 · 번식","horses"],["전체 경주마","통산·최근 1년 전적, 등급, 나이, 성별","allHorses"],["전체 기수","소속·기승 성적·능력치 8종","allJockeys"],["조교사 계약","NPC 위탁 신청 및 수락","trainers"],["경주마 시장","말 구매·판매 · 게임머니 거래","market"],["경주마 경매","입찰·낙찰 및 거래","auction"],["레이팅·등급","KRA 안내 기반 게임 레이팅","ratings"],["재무 내역","잔액·상금·운영비","finance"],["훈련계획 · 리포트","실제 성장 방향과 7일 정산","training"],["개인목장","회복 · 재활 · 어린말","ranch"],["교배","씨수말 · 혈통 · 자마","breeding"],["공식 결과","실제 경주 기록","races"],].map(([a,b,c])=><div key={a}>{box(a,b,()=>go(c))}</div>)}<div className="footer">MY DERBY · WEB MVP</div></div></>}
{screen==="account"&&<>{title("계정 및 연결","Supabase 이메일 로그인")}<div className="area"><div className="notice">Supabase 로그인·회원가입만 연결합니다. 플레이어 월드 생성과 데이터 저장, NPC 엔진은 아직 연결되지 않았습니다.</div><input className="field" placeholder="이메일" value={email} onChange={e=>Mail(e.target.value)}/><input className="field" placeholder="비밀번호" type="password" value={password} onChange={e=>Pass(e.target.value)}/><div className="stack"><button className="primary wide" onClick={()=>auth(false)}>로그인</button><button className="outline wide" onClick={()=>auth(true)}>회원가입</button></div></div></>}
<nav className="bottom">{[["home","⌂","홈"],["horses","♞","말 관리"],["races","♜","경주"],["menu","☰","메뉴"]].map(([x,icon,label])=><button className={screen===x?"active":""} onClick={()=>go(x)} key={x}><span>{icon}</span>{label}</button>)}</nav>{toast&&<div className="toast">{toast}</div>}</main>}
