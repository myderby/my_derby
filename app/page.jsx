"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const horses=[{id:1,name:"가을바람",age:4,sex:"수",stage:"현역",condition:82,fatigue:18,stats:[81,74,68,76,70,73]},{id:2,name:"골든레이스",age:3,sex:"수",stage:"현역",condition:77,fatigue:22,stats:[74,76,69,72,70,66]},{id:3,name:"작은별",age:1,sex:"암",stage:"목장",condition:93,fatigue:4,stats:[35,39,42,32,36,41]},{id:4,name:"여왕의꿈",age:6,sex:"암",stage:"교배",condition:89,fatigue:9,stats:[80,78,82,76,73,77]},{id:5,name:"블랙스톰",age:5,sex:"거",stage:"재활",condition:58,fatigue:42,stats:[83,73,77,82,69,74]}];
const trainers=[["김도윤","스피드·가속",14],["박수진","지구력·회복",8],["이민호","파워·근성",19],["최은영","컨디션·기질",6],["정우석","마일·선입",20]];
const jockeys=[["박준호","마일·선입",3],["김하늘","중거리·페이스",5],["이승민","출발·단거리",8],["정다은","추입·안정성",2]];
const raceData=[["서울",1200,"6등급"],["서울",1400,"5등급"],["서울",1400,"4등급"],["서울",1800,"3등급"],["서울",1600,"OPEN"]];
const events=[["START",200,"3번마가 빠르게 출발해 선두를 차지합니다."],["PACE",400,"초반 선행 경쟁이 치열해지고 있습니다."],["STRATEGY_SWITCH",600,"7번마 기수가 1안 선행에서 2안 외곽 선입으로 변경합니다."],["LANE_CHANGE",800,"7번마가 바깥 진로를 확보합니다."],["OVERTAKE",1000,"7번마가 선두를 추월합니다."],["FINISH",1200,"7번마 블루라이트가 가장 먼저 결승선을 통과합니다."]];
const testRaceSlots=[
  {time:"19:00",track:"서울",distance:1200,grade:"6등급"},
  {time:"20:00",track:"부경",distance:1400,grade:"5등급"},
  {time:"21:00",track:"영천",distance:1600,grade:"4등급"}
];
export default function Home(){const [screen,S]=useState("home"),[selected,H]=useState(horses[0]),[filter,F]=useState("전체"),[race,R]=useState(2),[trainer,T]=useState(0),[jockey,J]=useState(0),[plans,P]=useState(["선입 대기","외곽 선입","후방 추입"]),[pos,E]=useState(0),[playing,Play]=useState(false),[testRuns,SetTestRuns]=useState([]),[testResults,SetTestResults]=useState({}),[activeTestIndex,SetActiveTestIndex]=useState(-1),[testBusy,SetTestBusy]=useState(false),[dbStatus,SetDbStatus]=useState(null),[dbBusy,SetDbBusy]=useState(false),[dbRaceId,SetDbRaceId]=useState(""),[dbHistory,SetDbHistory]=useState([]),[dbPreview,SetDbPreview]=useState(null),[toast,Q]=useState(""),[email,Mail]=useState(""),[password,Pass]=useState("");
useEffect(()=>{if(!playing||pos>=events.length)return;const id=setTimeout(()=>E(x=>x+1),1200);return()=>clearTimeout(id)},[playing,pos]);
const go=x=>{S(x);if(typeof window!=="undefined")window.scrollTo(0,0)},msg=x=>{Q(x);setTimeout(()=>Q(""),3500)};
const title=(x,sub)=><div className="pageTitle"><button className="back" onClick={()=>go("home")}>‹</button><div><h1>{x}</h1><div className="sub">{sub}</div></div></div>;
const section=(x,next)=><div className="section"><h2>{x}</h2>{next&&<button onClick={()=>go(next)}>전체 보기 ›</button>}</div>;
const box=(a,b,d,right)=><div className="card action row" onClick={d}><div><b>{a}</b><div className="muted">{b}</div></div><span className="tag">{right||"›"}</span></div>;
const notReady=x=>msg(x+"은(는) 아직 시연 화면입니다. 실제 서버에 기록되지 않습니다.");
const runNextTestRace=async()=>{
  if(testBusy)return;
  const index=testRuns.length;
  if(index>=testRaceSlots.length)return;
  SetTestBusy(true);
  try{
    const response=await fetch("/api/race/simulate",{
      method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({slot:index}),cache:"no-store"
    });
    const payload=await response.json();
    if(!response.ok||!payload.result||payload.mode!=="TEST_ONLY")throw new Error(payload.error||"경주 계산 실패");
    SetTestResults(previous=>({...previous,[index]:payload.result}));
    SetTestRuns(previous=>[...previous,index]);
    SetActiveTestIndex(index);
    msg(testRaceSlots[index].time+" 경주 계산 완료 · Supabase DB 12두 출전 데이터");
  }catch(error){msg("경주 계산 실패: "+(error instanceof Error?error.message:"알 수 없는 오류"))}
  finally{SetTestBusy(false)}
};
const resetTestRaces=()=>{
  SetTestRuns([]);
  SetTestResults({});
  SetActiveTestIndex(-1);
  msg("테스트 결과를 초기화했습니다.");
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
const auth=async signup=>{const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;if(!url||!key)return msg("Supabase 환경 설정이 필요합니다.");const c=createClient(url,key);try{const {error}=signup?await c.auth.signUp({email,password}):await c.auth.signInWithPassword({email,password});msg(error?error.message:signup?"이메일 가입 요청 완료":"로그인 완료 (게임 데이터 저장 미연동)")}catch(e){msg(e.message)}};
return <main className="shell"><header className="header"><div onClick={()=>go("home")}><div className="brand">MY DERBY</div><div className="sub">52주 시즌 · 일정 연동 준비 중</div></div><span className="coin">◉ 3,675 G</span><button className="hamburger" onClick={()=>go("menu")}>☰</button></header><div className="disclaimer">모바일 UI 체험판 · 가상 데이터 · 실제 경주 결과 아님</div>
{screen==="home"&&<><div className="hero"><div className="overline">🍂 오늘도 우리 말들과 함께 성장해요</div><h1>가을 목장</h1><div className="caption">마주의 새로운 하루</div><button className="primary" onClick={()=>go("ranch")}>목장 둘러보기 ›</button></div><div className="area">{section("오늘의 관리","horses")}<div className="card row"><div><div className="large">5두</div><div className="muted">훈련 중 2두</div></div><div><div className="sub">평균 컨디션</div><div className="large green">80%</div></div><button className="outline" onClick={()=>go("testRaces")}>경주 테스트 ›</button></div>{section("정시 경주 테스트","testRaces")}{box("19:00 → 20:00 → 21:00","한국시간 · 12두 실제 엔진 계산",()=>go("testRaces"),testRuns.length+"/3 완료")}{section("게임 메뉴")}<div className="grid">{[["⌂","목장","휴양 · 재활 · 어린말 육성","ranch"],["♞","마방","조교사 · 훈련 리포트","horses"],["♜","경주","출전 · 전략 · 로그 결과","races"],["✧","교배","씨수말 · 교배 · 자마","breeding"]].map(([i,n,d,p])=><button className="card action" onClick={()=>go(p)} key={n}><div className="icon">{i}</div><b>{n}</b><div className="muted">{d}</div></button>)}</div></div></>}
{screen==="testRaces"&&<>{title("정시 경주 엔진 테스트","19:00 → 20:00 → 21:00 · 서버 계산")}<div className="area">
<div className="notice"><b>TypeScript 경주 엔진 · 테스트 전용</b><br/>12두 출전마의 스피드·체력·위치·기수 1~3안 전략을 0.2초 단위로 계산합니다. 출력되는 결과·로그는 엔진이 계산한 값이며, 출전 데이터는 Supabase my_derby 테스트 테이블에서 읽습니다. 공식 시즌·경주 결과·상금·전적에는 기록하지 않습니다.</div>
{testRaceSlots.map((slot,i)=><div className="card row" key={slot.time}>
  <div><b className="gold">{slot.time} · {slot.track} 경주</b><div className="muted">{slot.distance}m · {slot.grade} · 12두</div></div>
  <span className="tag">{testRuns.includes(i)?"✓ 계산 완료":i===testRuns.length?"다음 실행":"대기"}</span>
</div>)}
<button className="primary wide" disabled={testBusy||testRuns.length>=testRaceSlots.length} onClick={runNextTestRace}>
{testBusy?"경주 시뮬레이션 계산 중…":testRuns.length<testRaceSlots.length?testRaceSlots[testRuns.length].time+" 경주 계산 실행":"19시 · 20시 · 21시 계산 완료"}
</button><div style={{height:10}}/><button className="outline wide" disabled={testBusy} onClick={resetTestRaces}>테스트 초기화</button>
{activeTestIndex>=0&&testResults[activeTestIndex]&&(()=>{
 const result=testResults[activeTestIndex];
 const winner=result.results[0];
 return <><div style={{height:20}}/>{section("경주 계산 결과")}
 <div className="card"><div className="row"><b>{testRaceSlots[activeTestIndex].time} · {result.track}</b><span className="tag">엔진 결과 · 비공식</span></div>
 <div className="large gold">{winner.number}번 {winner.name} · 우승</div>
 <div className="muted">기록 {winner.timeSec.toFixed(2)}초 · 시드 {result.seed} · 엔진 {result.version} · {result.tickSeconds}초 틱</div></div>
 {section("최종 순위 · 12두")}
 <div className="card">{result.results.map(r=><div className="row line small" key={r.horseId}><b className="gold">{r.rank}위</b><span>{r.number}번 {r.name}</span><span>{r.timeSec.toFixed(2)}초</span></div>)}</div>
 {section("200m 구간별 순위")}
 <div className="card">{result.sections.map(sec=><div className="line" key={sec.distanceM}><b className="gold">{sec.distanceM}m</b><div className="muted">{sec.ranks.slice(0,5).map(r=>r.rank+"위 "+r.number+"번 "+r.name).join(" · ")}</div></div>)}</div>
 {section("실제 계산에서 생성된 사건 로그")}
 <div className="notice">전개·추월·전환·결승 사건을 표시합니다. 전략 전환은 실제 기수 AI 판단에 의해 기록됩니다.</div>
 {result.events.filter(e=>e.importance>=2).slice(0,65).map(ev=><div className="card" key={ev.seq}><div className="muted">{ev.timeSec.toFixed(1)}초 · {ev.distanceM.toFixed(0)}m · {ev.eventType}{ev.reasonCode?" · "+ev.reasonCode:""}</div><div className="small">{ev.text}</div></div>)}
 </>;
})()}
</div></>}

{screen==="database"&&<>{title("Supabase 경주 DB 연동","my_derby · 비공식 시뮬레이션")}<div className="area">
<div className="notice">19·20·21시 테스트 경주는 DB에 저장한 시연용 12두를 사용합니다. 정규 경주 데이터가 등록되면 본인 소유 출전마에 한해 미리보기를 실행할 수 있습니다. 공식 순위·상금·시즌 데이터는 변경하지 않습니다.</div>
<button className="outline wide" disabled={dbBusy} onClick={fetchDbStatus}>DB 연결 상태 확인</button>
{dbStatus&&<div className="card"><b className="green">● {dbStatus.schema} 연결 성공</b><div className="line row"><span>정규 등록 경주</span><b>{dbStatus.registeredRaces}건</b></div>
<div className="line row"><span>DB 테스트 경주</span><b>{dbStatus.storedTestFixtures}건</b></div><div className="muted">공식 결과 저장·상금 정산: 미연결</div></div>}
<h2>내 출전 경주 계산</h2>
<div className="muted">로그인이 필요합니다. 출전이 마감된 경주의 UUID를 입력하세요. 다른 마주의 비공개 능력치가 필요한 경주는 계산을 중단합니다.</div>
<input className="field" placeholder="경주 ID (UUID)" value={dbRaceId} onChange={e=>SetDbRaceId(e.target.value)}/>
<button className="primary wide" disabled={dbBusy||dbRaceId.trim().length<30} onClick={runDbPreview}>DB 출전마로 계산 · 비공식 기록 저장</button>
<div style={{height:10}}/><button className="outline wide" disabled={dbBusy} onClick={loadDbHistory}>내 미리보기 기록 조회</button>
{dbHistory.length>0&&<div className="card">{dbHistory.map(x=><div className="line" key={x.id}><b>{x.result_snapshot?.results?.[0]?.name||"출전 경주"}</b><div className="muted">{x.created_at} · {x.race_id}</div></div>)}</div>}
{dbPreview&&<div className="card"><b>최근 비공식 경주 순위</b>{dbPreview.results.map(x=><div className="line row small" key={x.horseId}><b>{x.rank}위</b><span>{x.number}번 {x.name}</span><span>{x.timeSec}초</span></div>)}</div>}
</div></>}
{screen==="horses"&&<>{title("보유마","생애 단계와 상태를 한눈에")}<div className="area"><div className="card"><b>전체 5두</b><div className="muted">현역 2 · 목장 1 · 교배 1 · 재활 1</div></div><div className="tabs">{["전체","현역","목장","교배","재활"].map(x=><button className={filter===x?"active":""} onClick={()=>F(x)} key={x}>{x}</button>)}</div>{horses.filter(x=>filter==="전체"||x.stage===filter).map(x=><div key={x.id}>{box("♞ "+x.name,x.age+"세 · "+x.sex+"말 · 컨디션 "+x.condition,()=>{H(x);go("horse")},x.stage)}</div>)}</div></>}
{screen==="horse"&&<>{title(selected.name,selected.age+"세 · "+selected.sex+"말 · "+selected.stage)}<div className="area"><div className="card"><div className="large gold">♞ {selected.name}</div><div className="muted">컨디션 {selected.condition} · 피로 {selected.fatigue}</div><div className="bar"><div className="fill" style={{width:selected.condition+"%"}}/></div></div>{section("능력치 · 추정")}<div className="grid">{["스피드","가속력","지구력","막판탄력","파워","근성"].map((x,i)=><div className="card" key={x}><div className="row small"><span>{x}</span><b>{selected.stats[i]}</b></div><div className="bar"><div className="fill" style={{width:selected.stats[i]+"%"}}/></div></div>)}</div><div className="notice">현재 능력치 수치는 샘플입니다. 잠재력·유전값·훈련의 실제 결과는 서버 엔진 미연결 상태입니다.</div><div className="twoCol">{[["조교사 찾기","trainers"],["훈련 리포트","training"],["경주 일정","races"],["개인목장","ranch"]].map(([t,p])=><button key={p} className="outline" onClick={()=>go(p)}>{t}</button>)}</div></div></>}
{screen==="trainers"&&<>{title("조교사 찾기","등급 대신 전문성·수용량 비교")}<div className="area"><div className="notice">NPC 조교사는 최대 20두 담당합니다. 실제 신청·수락 판정은 서버 자동 판단 모듈 구현 후 연결됩니다.</div>{trainers.map(([n,s,count],i)=><div key={n}>{box(n,s+" · "+count+"/20두",()=>T(i),trainer===i?"선택":"비교")}</div>)}<button className="primary wide" onClick={()=>notReady(trainers[trainer][0]+" 위탁 신청")}>위탁 신청 (체험)</button></div></>}
{screen==="training"&&<>{title("훈련 리포트","성장 방향과 일일 관리")}<div className="area"><div className="card"><b>오늘의 훈련 · 가상 예시</b><div className="line">스피드 +0.3 · 지구력 +0.1</div><div className="muted">피로 +4 · 컨디션 -2 · 이해도 +1</div></div>{section("성장 방향")}<select className="field">{["단거리","마일","중거리","장거리"].map(x=><option key={x}>{x}</option>)}</select><select className="field">{["도주","선행","선입","중반무빙","추입","자유형"].map(x=><option key={x}>{x}</option>)}</select><button className="primary wide" onClick={()=>notReady("성장 방향 변경")}>성장 방향 선택</button></div></>}
{screen==="ranch"&&<>{title("개인목장","휴양 · 재활 · 기초육성")}<div className="area"><div className="card"><b>가을빛 개인목장</b><div className="muted">관리사 4명 · 수의사 1명</div></div>{section("목장 시설")}{[["방목지","휴양·기질 안정"],["회복 마방","컨디션 회복"],["재활 트랙","부상 재활"],["수의 진료소","치료·진료"],["어린말 육성장","0~1세 기초육성"]].map(([a,b])=><div key={a}>{box(a,b,()=>go("course"),"시설")}</div>)}<button className="primary wide" onClick={()=>go("course")}>휴양 · 재활 코스 ›</button></div></>}
{screen==="course"&&<>{title("휴양·재활 코스","입소 기간과 코스 선택")}<div className="area">{["3일 휴양","7일 회복","재활 코스","어린말 기초육성"].map(x=><div key={x}>{box(x,"NPC 강훈련과 동일 날짜 중복 불가",()=>notReady(x+" 신청"))}</div>)}</div></>}
{screen==="races"&&<>{title("경주 일정","출전 조건 및 전략 신청")}<div className="area"><div className="tabs">{["서울","부경","영천"].map(x=><button key={x} className={filter===x?"active":""} onClick={()=>F(x)}>{x}</button>)}</div>{raceData.map(([track,dist,grade],i)=><div key={i}>{box(String(i+1).padStart(2,"0")+"R · "+(filter==="부경"||filter==="영천"?filter:track)+" · "+dist+"m",grade+" · 시연 편성",()=>{R(i);go("entry")},"출전 준비")}</div>)}<div className="notice">경주 일정은 개발안 설명용 예시입니다. 실제 서버 일정과 확정 시각은 아직 연동되지 않았습니다.</div></div></>}
{screen==="entry"&&<>{title("출전 준비","경주·말·기수·전략")}<div className="area"><div className="card"><b>서울 {race+1}경주 · {raceData[race][1]}m</b><div className="muted">{raceData[race][2]} · 체험용 편성</div></div>{box(selected.name,selected.age+"세 · 컨디션 "+selected.condition,()=>go("horses"),"말 변경")}{box("기수 신청","기수 전문성 및 수락 확인",()=>go("jockey"))}{box("전략 1~3안","기수 전개 방향 설정",()=>go("strategy"))}<button className="primary wide" onClick={()=>notReady("경주 출전 신청")}>출전 신청</button><div style={{height:10}}/><button className="outline wide" onClick={()=>{E(0);Play(false);go("spectate")}}>경주 로그 화면 시연 ›</button></div></>}
{screen==="jockey"&&<>{title("기수 신청","한 경주 1두 · 일일 최대 8회")}<div className="area">{jockeys.map(([n,s,count],i)=><div key={n}>{box(n,s+" · "+count+"/8경주",()=>J(i),jockey===i?"선택":"신청 가능")}</div>)}<button className="primary wide" onClick={()=>notReady(jockeys[jockey][0]+" 기승 신청")}>기승 신청</button></div></>}
{screen==="strategy"&&<>{title("경주 전략","1안·2안·3안 · 기수 자율 판단")}<div className="area"><div className="notice">기수가 경주 전개에 따라 2안이나 3안으로 전환합니다. 전환 결과는 이벤트 로그에 기록됩니다.</div>{plans.map((x,i)=><div className="card" key={i}><b className="gold">{i+1}안 {i===0?"· 기본":"· 대안"}</b><select className="field" value={x} onChange={e=>P(y=>y.map((v,j)=>j===i?e.target.value:v))}>{["선입 대기","외곽 선입","후방 추입","선행 압박","중반 무빙","자유 판단"].map(p=><option key={p}>{p}</option>)}</select></div>)}<button className="primary wide" onClick={()=>notReady("전략 저장")}>전략 저장</button></div></>}
{screen==="spectate"&&<>{title("경주 로그 관전","샘플 이벤트 · 실제 엔진 산출 아님")}<div className="area"><div className="card"><b>서울 3경주 · 1,200m</b><div className="large gold">{pos?events[pos-1][1]:0}m / 1200m</div><div className="bar"><div className="fill" style={{width:(pos?events[pos-1][1]/12:0)+"%"}}/></div><div className="raceTrack">{["출발","초반","중반","승부처","종반"].map(x=><span key={x}>{x}</span>)}</div></div>{section("구간별 순위 · 시연")}<div className="card">{["7 블루라이트","3 실버윈드","5 레드스타","2 가을바람","1 골든스텝"].map((h,i)=><div className="line row" key={h}><b className="gold">{i+1}위</b><span>{h}</span><span className="muted">{i===0?"선두":"+"+(i*.8).toFixed(1)+"m"}</span></div>)}</div>{section("경주 사건 로그")}{events.slice(0,pos).map(([type,m,txt])=><div className="card" key={type}><div className="muted">{m}m · {type}</div><div className="small">{txt}</div></div>)}<div className="controls"><button className="outline" onClick={()=>Play(!playing)}>{playing?"⏸ 정지":"▶ 재생"}</button><button className="outline" onClick={()=>{E(events.length);Play(false)}}>끝으로</button><button className="primary" onClick={()=>{Play(false);go("results")}}>결과</button></div></div></>}
{screen==="results"&&<>{title("경주 결과","가상 시연 자료")}<div className="area"><div className="notice">이 결과는 실제 경주 엔진 산출물이 아닙니다. 공식 기록·보상·피로도는 변경되지 않습니다.</div><div className="card">{["7 블루라이트","3 실버윈드","5 레드스타"].map((x,i)=><div className="line row" key={x}><b className="gold">{i+1}위</b><span>{x}</span><span className="muted">1:1{5+i}.8</span></div>)}</div><button className="outline wide" onClick={()=>go("spectate")}>로그 다시 보기</button></div></>}
{screen==="breeding"&&<>{title("교배","번식암말 · 씨수말 · 자마 관리")}<div className="area"><div className="card"><b>여왕의꿈 · 6세</b><div className="muted">시즌당 1회 · 4~18세 교배 가능</div></div>{box("씨수말 후보","시스템 씨수말 · 혈통 궁합",()=>notReady("씨수말 선택"),"보기") }<div className="notice">교배 승인 · 임신 · 출산 · 유전 계산은 아직 서버 기능 미구현 상태입니다.</div><button className="primary wide" onClick={()=>notReady("교배 신청")}>교배 신청</button></div></>}
{screen==="menu"&&<>{title("전체 메뉴","MY DERBY")}<div className="area">{[["경주 관리","출전 일정 · 전략 · 결과","races"],["정시 경주 테스트","19시 → 20시 → 21시 (임시)","testRaces"],["Supabase 연동","경주 DB 연결 및 개인 미리보기","database"],["말 관리","보유마 · 조교사 · 훈련","horses"],["개인목장","회복 · 재활 · 어린말","ranch"],["교배","씨수말 · 혈통 · 자마","breeding"],["기록","샘플 경주 결과","results"],["계정","Supabase 이메일 인증","account"]].map(([a,b,c])=><div key={a}>{box(a,b,()=>go(c))}</div>)}<div className="footer">MY DERBY · WEB MVP</div></div></>}
{screen==="account"&&<>{title("계정 및 연결","Supabase 이메일 로그인")}<div className="area"><div className="notice">Supabase 로그인·회원가입만 연결합니다. 플레이어 월드 생성과 데이터 저장, NPC 엔진은 아직 연결되지 않았습니다.</div><input className="field" placeholder="이메일" value={email} onChange={e=>Mail(e.target.value)}/><input className="field" placeholder="비밀번호" type="password" value={password} onChange={e=>Pass(e.target.value)}/><div className="stack"><button className="primary wide" onClick={()=>auth(false)}>로그인</button><button className="outline wide" onClick={()=>auth(true)}>회원가입</button></div></div></>}
<nav className="bottom">{[["home","⌂","홈"],["horses","♞","말 관리"],["races","♜","경주"],["menu","☰","메뉴"]].map(([x,icon,label])=><button className={screen===x?"active":""} onClick={()=>go(x)} key={x}><span>{icon}</span>{label}</button>)}</nav>{toast&&<div className="toast">{toast}</div>}</main>}
