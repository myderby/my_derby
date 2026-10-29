"use client";
import {useEffect,useState} from "react";
export default function SchedulePage(){
 const [program,SetProgram]=useState(null),[error,SetError]=useState(""),[track,SetTrack]=useState("전체");
 const load=async()=>{
  try{const res=await fetch("/api/world/program",{cache:"no-store"});const data=await res.json();
   if(!res.ok)throw new Error(data.error||"일정 로딩 실패");
   SetProgram(data);SetError("");
  }catch(e){SetError(e.message)}
 };
 useEffect(()=>{load()},[]);
 const events=(program?.races||[]).filter(r=>track==="전체"||r.track===track);
 const groups=Object.groupBy?Object.groupBy(events,r=>r.date):events.reduce((out,r)=>{
  (out[r.date]||=[]).push(r);return out;
 },{});
 return <main className="shell">
  <header className="header"><a className="brand" style={{textDecoration:"none"}} href="/">MY DERBY</a>
   <span className="coin">🏇 경주일정</span></header>
  <div className="area">
  <a href="/" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:15}}>‹ 홈</a>
  <div className="section"><h2>공식 경주 일정</h2><button onClick={load}>갱신 ↻</button></div>
  {program?.world&&<div className="card"><div className="large gold">{program.world.season}시즌 · {program.world.week}주차</div>
   <div className="muted">한국시간(KST) · 실제 하루=게임 1주 · 52주 시즌</div>
   <div className="row"><span className="pill">{program.world.status==="ACTIVE"?"● 월드 운영 중":"운영 대기"}</span>
    <span className="tag">{program.world.schedulerConfigured&&program.world.automaticProcessingEnabled?"정시 자동 실행 등록":"스케줄러 미설정"}</span></div></div>}
  {error&&<div className="notice">{error}</div>}
  <div className="tabs">{["전체","서울","부산","영천"].map(x=><button className={track===x?"active":""} onClick={()=>SetTrack(x)} key={x}>{x}</button>)}</div>
  <div className="notice">서울 19:00 · 부산 20:00 · 영천 21:00. 경주는 실제 출전마를 사용하는 게임 시뮬레이션입니다. 경주 결과는 정시 종료 후 기록되며 상금 정산은 아직 연결되지 않았습니다. 2025년 과거 편성을 게임 프로그램의 템플릿으로 활용했습니다.</div>
  {Object.entries(groups).map(([date,races])=><div key={date}>
   <div className="section"><h2>{date} · {races[0].season}시즌 {races[0].week}주차</h2></div>
   {races.map(r=><div key={r.id} className="card row">
    <div><b className="gold">{r.time} · {r.track}</b>
    <div className="muted">{r.grade} · {r.distance}m · 원본 meet: {r.sourceMeet}</div></div>
    <span className="tag">{r.status==="FINISHED"?"경주 종료":r.status==="RUNNING"?"진행 중":"예정"}</span>
   </div>)}
  </div>)}
  {!program&&!error&&<div className="notice">경주 시간표를 불러오는 중…</div>}
  <div className="footer">MY DERBY · 자동 시즌 편성</div></div>
 </main>
}
