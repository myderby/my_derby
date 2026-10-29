"use client";
import {useEffect,useState} from "react";
export default function SchedulePage(){
 const [program,SetProgram]=useState(null),[error,SetError]=useState(""),[track,SetTrack]=useState("전체"),[week,SetWeek]=useState(null);
 const load=async targetWeek=>{
  try{
   const url="/api/world/program"+(targetWeek?"?week="+targetWeek:"");
   const res=await fetch(url,{cache:"no-store"});
   const data=await res.json();if(!res.ok)throw new Error(data.error||"일정 조회 실패");
   SetProgram(data);SetWeek(data.requestedWeek);SetError("");
  }catch(e){SetError(e.message)}
 };
 useEffect(()=>{void load(null)},[]);
 const events=(program?.races||[]).filter(x=>track==="전체"||x.track===track);
 const grouped=events.reduce((a,r)=>{const k=r.time.slice(0,2)+":00";(a[k]||=[]).push(r);return a},{});
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🏇 공식 경주</span></header>
 <div className="area"><a href="/" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:16}}>‹ 홈으로</a>
 <div className="section"><h2>52주 경주 시간표</h2><button onClick={()=>load(week)}>새로고침 ↻</button></div>
 {program?.world&&<div className="card"><div className="large gold">{program.world.season}시즌 · {week}주차</div>
 <div className="muted">현실 1일 = 게임 1주 · 출발 3분 간격 · 결과 출발 3분 후 · Asia/Seoul</div>
 <div className="row" style={{marginTop:11}}>
 <button className="outline" disabled={week<=1} onClick={()=>load(week-1)}>‹ 이전 주</button>
 <span className="tag">{program.raceCount}경주</span>
 <button className="outline" disabled={week>=52} onClick={()=>load(week+1)}>다음 주 ›</button></div>
 <div className="muted" style={{marginTop:9}}>{program.world.status==="ACTIVE"?"● 월드 운영 중":"월드 대기"} · {program.world.schedulerConfigured?"자동 경주 스케줄러 설정됨":"자동 스케줄러 미설정"}</div></div>}
 {error&&<div className="notice">{error}</div>}
 <div className="notice">19시 부산·영천 (원본 금요일) / 20시 서울·영천 (원본 토요일) / 21시 서울·부산 (원본 일요일).
 원본 CSV의 rank, rcNo, stTime 순서를 보존했으며 게임 시작 시각으로 재배치했습니다. 영천은 부산의 거리 비율에 맞춘 1000~2000m 게임 거리를 사용하며 제주 원본 거리는 별도 보존합니다. 실제 결과는 출발 후 3분에 확정됩니다.</div>
 <div className="tabs">{["전체","서울","부산","영천"].map(x=><button key={x} className={track===x?"active":""} onClick={()=>SetTrack(x)}>{x}</button>)}</div>
 {Object.entries(grouped).map(([slot,list])=><div key={slot}><div className="section"><h2>{slot} 시작 · {list.length}경주</h2></div>
 {list.map(r=><div key={r.id} className="card row">
 <div><b className="gold">{r.time} {r.track} {r.sourceRaceNo}경주</b><div className="muted">{r.grade} · {r.distance}m · 출전 {r.actualStarters}/{r.dusu}두 · 결과 {r.resultTime}</div>
 <div className="muted">원본 {r.sourceMeet} {r.sourceDate} / stTime {r.sourceStTime}{r.sourceWeekReused?" · 원본 주간 재사용":""}</div>
 {r.track==="영천"&&r.sourceDistance!=null&&<div className="muted">원본 제주 {r.sourceDistance}m → 게임 영천 {r.distance}m</div>}</div>
 <div><span className="tag">{r.status==="FINISHED"?"결과 확정":r.status==="RUNNING"?"경주 진행 중":"예정"}</span>
 {r.status==="FINISHED"&&<a className="outline" style={{display:"block",fontSize:11,marginTop:8,textDecoration:"none"}} href={"/race/result/"+r.id}>결과 ›</a>}</div>
 </div>)}</div>)}
 {!program&&!error&&<div className="notice">경주 시간표를 불러오는 중…</div>}
 <div className="footer">MY DERBY · 원본 rank·stTime 기반 시즌 편성</div></div></main>;
}
