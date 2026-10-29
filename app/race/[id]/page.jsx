"use client";
import {useEffect,useMemo,useState} from "react";
import {useParams} from "next/navigation";
import {selectRaceCommentary} from "../../../lib/racing/commentary";

const statusName={OPEN:"경주 예정",CLOSED:"출전 마감",RUNNING:"공식 경주 진행 중",
 FINISHED:"공식 결과 확정",CANCELLED:"취소",RESULT_NOT_AVAILABLE:"공식 결과 처리 중"};
const sexLabel={MALE:"수",FEMALE:"암",GELDING:"거"};
const sec=n=>Number(n||0).toFixed(2);
const stamp=n=>Number(n||0).toFixed(1);
const emptyLabel="기록이 아직 없습니다.";

export default function RaceDetailPage(){
 const params=useParams();
 const id=typeof params?.id==="string"?params.id:"";
 const [race,SetRace]=useState(null);
 const [error,SetError]=useState("");
 const [loading,SetLoading]=useState(true);
 const [tab,SetTab]=useState("result");
 const [replay,SetReplay]=useState(false);
 const [playing,SetPlaying]=useState(false);
 const [replayTime,SetReplayTime]=useState(0);
 const [speed,SetSpeed]=useState(1);

 useEffect(()=>{
  if(!id)return;
  let active=true;
  let finished=false;
  async function load(){
   try{
    const res=await fetch("/api/race/official/"+encodeURIComponent(id),{cache:"no-store"});
    const data=await res.json();
    if(!res.ok)throw new Error(data.error||"공식 경주를 조회할 수 없습니다.");
    if(!active)return;
    SetRace(data);SetError("");finished=data.status==="FINISHED"||data.status==="CANCELLED";
   }catch(e){if(active)SetError(e.message||"공식 경주 조회 실패");}
   finally{if(active)SetLoading(false);}
  }
  void load();
  const poll=setInterval(()=>{if(finished){clearInterval(poll);return;}void load();},15000);
  return()=>{active=false;clearInterval(poll)};
 },[id]);

 const events=useMemo(()=>selectRaceCommentary(race?.events||[]),[race]);
 const finish=events.length?Math.max(...events.map(e=>Number(e.timeSec)||0)):0;
 const visibleEvents=useMemo(
  ()=>replay?events.filter(e=>Number(e.timeSec)<=replayTime+0.001):events,
  [events,replay,replayTime]
 );
 const entrants=useMemo(()=>new Map((race?.entries||[]).map(e=>[e.horseId,e])),[race]);
 useEffect(()=>{
  if(!playing||!replay||!finish)return;
  const timer=setInterval(()=>SetReplayTime(current=>{
   const next=Math.min(finish,current+speed*0.25);
   if(next>=finish)SetPlaying(false);
   return next;
  }),250);
  return()=>clearInterval(timer);
 },[playing,replay,speed,finish]);

 const goReplay=()=>{
  SetTab("log");SetReplay(true);SetReplayTime(0);SetPlaying(true);
 };
 const resetReplay=()=>{
  SetPlaying(false);SetReplay(false);SetReplayTime(0);
 };
 const completed=race?.status==="FINISHED"&&race?.results?.length>0;
 const status=statusName[race?.status]||race?.status||"확인 중";
 const today=race?.kstDate||"일정 확인 중";

 return <main className="shell">
  <header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a>
   <span className="coin">🏇 공식 경주</span></header>
  <div className="area">
   <div className="controls" style={{marginBottom:14}}>
    <a className="outline" href="/schedule" style={{textAlign:"center",textDecoration:"none"}}>‹ 공식 경주시간표</a>
    <a className="outline" href="/" style={{textAlign:"center",textDecoration:"none"}}>홈으로</a>
   </div>
   {loading&&!race&&<div className="notice">실제 공식 경주 기록을 불러오는 중입니다…</div>}
   {error&&<div className="notice" role="alert">경주 조회 오류: {error}
    <div className="muted">공식 기록을 임의로 재계산하거나 테스트 기록으로 대체하지 않습니다.</div>
   </div>}
   {race&&<>
    <div className="card">
     <div className="row"><div>
      <div className="muted">{today} · {race.startTime} 출발</div>
      <h1 style={{fontSize:24,margin:"9px 0 5px"}}>{race.track} {race.raceNo||race.gameRaceNo}경주</h1>
      <div className="muted">{race.className} · {race.distanceM}m · {race.entries?.length||0}두 출전</div>
     </div><span className="tag">{status}</span></div>
     <div className="muted" style={{marginTop:10}}>공식 경주 ID: {String(race.raceId||id).slice(0,8)} · 결과 공개 {race.resultTime||"미정"} (한국시간)</div>
     {race.status==="RUNNING"&&<div className="notice">🏇 공식 경주가 진행되고 있습니다. 결과가 확정되면 자동으로 표시됩니다. (약 15초 간격 조회)</div>}
     {race.status==="OPEN"&&<div className="notice">출전표가 확정된 실제 공식 경주입니다. 출발 후 결과가 공개되면 이 화면에 공식 순위와 중계 로그가 표시됩니다.</div>}
     {race.status==="CANCELLED"&&<div className="notice">이 경주는 취소되었습니다. 비공식 결과는 생성하지 않습니다.</div>}
    </div>
    {completed&&<div className="card" style={{borderColor:"#94662c"}}>
     <div className="muted">🏆 공식 우승마</div>
     <div className="large gold" style={{marginTop:7}}>{race.results[0].number}번 {race.results[0].name}</div>
     <div className="muted">우승 기록 {sec(race.results[0].timeSec)}초 · 공식 완료 {race.completedAt?new Date(race.completedAt).toLocaleString("ko-KR",{timeZone:"Asia/Seoul"}):"확정"}</div>
     <div className="controls" style={{marginTop:12}}>
      <button className="primary" onClick={goReplay}>▶ 실제 중계 다시보기</button>
      <button className="outline" onClick={()=>{SetTab("sections");resetReplay()}}>구간별 순위</button>
     </div>
    </div>}
    {completed&&<div className="tabs" aria-label="공식 경주 기록 화면">
      {[["result","최종 순위"],["sections","구간 순위"],["log","전체 중계"]].map(([key,label])=>
       <button key={key} className={tab===key?"active":""} onClick={()=>SetTab(key)}>{label}</button>)}
    </div>}
    {!completed&&<><div className="section"><h2>공식 출전표</h2></div>
      {race.entries?.length?<div className="card">
       {race.entries.map(e=><div className="line" key={e.horseId}>
        <div className="row"><b className="gold">{e.number??"-"}번 {e.name}</b><span className="tag">{e.entryStatus==="CONFIRMED"?"출전 확정":e.entryStatus}</span></div>
        <div className="muted">{e.age}세 · {sexLabel[e.sex]||e.sex} · 기수 {e.jockeyName||"미배정"} · 부담중량 {e.weightKg??"-"}kg</div>
       </div>)}
      </div>:<div className="notice">출전마 정보가 없습니다.</div>}
      {race.status==="RESULT_NOT_AVAILABLE"&&<div className="notice">공식 결과를 저장하는 중입니다. 이 화면을 새로고침해 주세요.</div>}
    </>}
    {completed&&tab==="result"&&<>
     <div className="section"><h2>🏁 공식 최종 순위</h2></div>
     <div className="card">{race.results.map(x=>{
      const e=entrants.get(x.horseId);
      return <div className="line row" key={x.horseId}>
       <div style={{flex:1}}><b className="gold">{x.rank}위</b>
        <b style={{marginLeft:12}}>{x.number}번 {x.name}</b>
        <div className="muted">기수 {e?.jockeyName||"정보 없음"} · {e?.weightKg??"-"}kg</div></div>
       <div style={{whiteSpace:"nowrap",fontSize:13}}>{sec(x.timeSec)}초</div>
      </div>;
     })}</div>
     <div className="notice">이 내용은 실제 월드에서 실행된 경주 엔진의 공식 저장 결과입니다. 상금 및 경제 정산은 별도 기능입니다.</div>
    </>}
    {completed&&tab==="sections"&&<>
     <div className="section"><h2>200m 구간별 전 마필 순위</h2></div>
     {!race.sections?.length&&<div className="notice">{emptyLabel}</div>}
     {(race.sections||[]).map(segment=><div className="card" key={segment.distanceM}>
      <div className="row"><b className="gold">{segment.distanceM}m</b><span className="tag">{segment.ranks?.length||0}두</span></div>
      {(segment.ranks||[]).map(h=><div className="line row small" key={segment.distanceM+"-"+h.number}>
       <b style={{minWidth:38}}>{h.rank}위</b><span style={{flex:1}}>{h.number}번 {h.name}</span>
       <span className="muted">{Number(h.gapM)<0.01?"선두":"+"+sec(h.gapM)+"m"}</span>
      </div>)}
     </div>)}
    </>}
    {completed&&tab==="log"&&<>
     <div className="section"><h2>실제 경주 중계 · 전체 {events.length}개</h2></div>
     <div className="notice">공식 DB에 저장된 중계 이벤트를 시간순으로 표시합니다. 영상이 아닌 실제 경주 엔진 로그입니다. 이벤트 개수 제한은 없습니다.</div>
     <div className="card">
      <div className="row"><b className="gold">{replay?"중계 다시보기":"전체 중계 기록"}</b>
       <span className="tag">{replay?stamp(replayTime)+"/"+stamp(finish)+"초":"전체 공개"}</span></div>
      <div className="controls" style={{marginTop:12,flexWrap:"wrap"}}>
       {replay?<><button className="primary" onClick={()=>{if(replayTime>=finish)SetReplayTime(0);SetPlaying(!playing)}}>{playing?"⏸ 일시정지":"▶ 재생"}</button>
        <button className="outline" onClick={resetReplay}>전체 보기</button></>:
        <button className="primary wide" onClick={goReplay}>▶ 출발부터 다시보기</button>}
      </div>
      {replay&&<>
       <input style={{width:"100%",marginTop:12}} aria-label="공식 중계 시간 이동" type="range" min="0" max={finish} step="0.2"
        value={replayTime} onChange={e=>{SetReplayTime(Number(e.target.value));SetPlaying(false)}}/>
       <div className="controls">{[1,2,4].map(n=><button className={speed===n?"primary":"outline"} key={n} onClick={()=>SetSpeed(n)}>{n}×</button>)}</div>
      </>}
     </div>
     {visibleEvents.length?visibleEvents.map((e,i)=><div className="card" key={e.seq+"-"+i} style={{marginBottom:8}}>
      <div className="muted">{stamp(e.timeSec)}초 · {Math.min(Number(e.distanceM)||0,race.distanceM).toFixed(0)}m · {e.eventType==="FINISH"?"🏁 결승":e.eventType==="START"?"출발":"경주 진행"}</div>
      <div className="small" style={{marginTop:4,lineHeight:1.65}}>{e.text}</div>
     </div>):<div className="notice">중계 이벤트가 아직 표시되지 않았습니다.</div>}
    </>}
   </>}
   <div className="footer">MY DERBY · 공식 경주 DB 기록 · 테스트 경주와 구분</div>
  </div>
 </main>;
}
