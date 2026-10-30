"use client";
import HorseLink from "../components/HorseLink";
import {useEffect,useState} from "react";
import {selectRaceCommentary} from "../../lib/racing/commentary";

export default function FixtureRace(){
 const [race,R]=useState(null),[label,L]=useState(""),
  [result,Q]=useState(null),[error,E]=useState(""),[busy,B]=useState(false);
 const load=async()=>{
  try{
   const r=await fetch("/api/race/test-19",{cache:"no-store"});
   const x=await r.json();if(!r.ok)throw new Error(x.error||"테스트 경주 조회 실패");
   R(x.race);L(x.label);E("");
  }catch(e){E(e.message)}
 };
 useEffect(()=>{void load()},[]);
 const run=async()=>{
  B(true);E("");Q(null);
  try{
   const r=await fetch("/api/race/test-19",{method:"POST",
    headers:{"Content-Type":"application/json"},
    body:JSON.stringify({})});
   const x=await r.json();if(!r.ok)throw new Error(x.error||"테스트 실패");
   Q(x.result);
  }catch(e){E(e.message)}finally{B(false)}
 };
 const sorted=[...(race?.runners||[])].sort((a,b)=>a.gate-b.gate);
 return <main className="shell"><header className="header">
  <a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a>
  <span className="coin">🧪 19시 테스트</span></header>
  <div className="area">
   <div className="controls"><a href="/" className="outline" style={{textDecoration:"none"}}>‹ 홈</a>
    <a href="/schedule?slot=19" className="outline" style={{textDecoration:"none"}}>공식 19시 시간표 ›</a></div>
   <div className="section"><h2>19:00 · 서울 1경주 (시연)</h2></div>
   <div className="notice">
    <b>비공식 테스트 전용 경주</b><br/>
    1등급 5두 + 5등급 5두를 한 경주에 배정해 능력 차이를 시험합니다.
    실제 경주마 이름과 현재 능력치의 복사본을 사용하며, 정식 출전 규정과 별개의 시뮬레이션입니다.
    공식 결과·레이팅·피로도·상금·지갑은 변경되지 않습니다.
   </div>
   {error&&<div className="notice" role="alert">{error}</div>}
   {race&&<>
    <div className="card"><b className="gold">{label}</b>
     <div className="muted">{race.track} · {race.distanceM}m · 10두 · 1등급 5두 / 5등급 5두</div></div>
    {[1,5].map(grade=><div key={grade}>
     <div className="section"><h2>{grade}등급 경주마 · 5두</h2></div>
     {sorted.filter(x=>x.gradeNo===grade).map(x=><div className="card row" key={x.id}>
      <div><b className="gold">{x.number}번 <HorseLink horseId={x.sourceHorseId||x.id}>{x.name}</HorseLink></b>
       <div className="muted">마번 {x.horseNo} · 현재 능력치 속도 {x.horse.speed} /
        지구력 {x.horse.stamina} / 가속 {x.horse.acceleration}</div></div>
      <span className="tag">{grade}등급</span></div>)}
    </div>)}
    <button className="primary wide" disabled={busy} onClick={run}>
     {busy?"경주 계산 중…":"▶ 19시 1경주 비공식 테스트 실행"}</button>
   </>}
   {result&&<>
    <div className="section"><h2>테스트 경주 결과</h2></div>
    <div className="notice">비공식 결과 · 시드 {result.seed} · 정식 기록 미반영</div>
    <div className="card">{result.results.map(x=><div className="line row small" key={x.horseId}>
      <b className="gold">{x.rank}위</b><span>{x.number}번 <HorseLink horseId={x.horseId}>{x.name}</HorseLink> · {sorted.find(h=>h.id===x.horseId)?.gradeNo}등급</span>
      <span>{x.timeSec.toFixed(2)}초</span></div>)}</div>
    <div className="section"><h2>구간 순위</h2></div>
    <div className="card">{result.sections.map(x=><div className="line" key={x.distanceM}>
      <b className="gold">{x.distanceM}m</b>
      <div className="muted">{x.ranks.map(h=>h.rank+"위 "+h.number+"번 "+h.name).join(" · ")}</div>
    </div>)}</div>
    <div className="section"><h2>경주 중계 로그</h2></div>
    {selectRaceCommentary(result.events).map(x=><div className="card" key={x.seq}>
      <div className="muted">{x.timeSec.toFixed(1)}초 · {x.distanceM.toFixed(0)}m</div>
      <div className="small">{x.text}</div></div>)}
   </>}
   <div className="footer">MY DERBY · test-only fixture · 공식 레이팅·경제 정산 미반영</div>
  </div>
 </main>;
}