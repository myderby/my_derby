"use client";
import {useEffect,useRef,useState} from "react";
import {officialSlotSummaries} from "../../lib/racing/slot-status";
export default function SchedulePage(){
 const [program,SetProgram]=useState(null),[error,SetError]=useState(""),
  [track,SetTrack]=useState("전체"),[week,SetWeek]=useState(null),[slot,SetSlot]=useState("전체");
 const selectedWeekRef=useRef(null),loadSeq=useRef(0);
 const load=async targetWeek=>{
  const seq=++loadSeq.current;
  try{
   const url="/api/world/program"+(targetWeek?"?week="+targetWeek:"");
   const res=await fetch(url,{cache:"no-store"});
   const data=await res.json();if(!res.ok)throw new Error(data.error||"일정 조회 실패");
   if(seq!==loadSeq.current)return;
   selectedWeekRef.current=data.requestedWeek;
   SetProgram(data);SetWeek(data.requestedWeek);SetError("");
  }catch(e){if(seq===loadSeq.current)SetError(e.message)}
 };
 useEffect(()=>{
  const initialSlot=new URLSearchParams(window.location.search).get("slot");
  if(["19","20","21"].includes(initialSlot))SetSlot(initialSlot);
  void load(null);
  const timer=setInterval(()=>{
   if(document.visibilityState==="visible")void load(selectedWeekRef.current);
  },15000);
  return ()=>{clearInterval(timer);loadSeq.current++};
 },[]);
 const chooseSlot=value=>{
  SetSlot(value);
  const url=new URL(window.location.href);
  if(value==="전체")url.searchParams.delete("slot");else url.searchParams.set("slot",value);
  window.history.replaceState(null,"",url.pathname+url.search);
 };
 const slotSummaries=officialSlotSummaries(program?.races||[]);
 const selectedSlot=slotSummaries.find(x=>x.hour===slot);
 const events=(program?.races||[]).filter(x=>
   (slot==="전체"||x.time?.slice(0,2)===slot)&&(track==="전체"||x.track===track));
 const grouped=events.reduce((a,r)=>{
  const k=r.time.slice(0,2)+":00";(a[k]||=[]).push(r);return a;
 },{});
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🏇 공식 경주</span></header>
 <div className="area"><a href="/" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:16}}>‹ 홈으로</a>
 <a href="/entries" className="primary" style={{display:"inline-block",textDecoration:"none",marginBottom:16,marginLeft:8}}>🏇 출전·기수 신청 ›</a>
 <div className="section"><h2>52주 경주 시간표</h2><button onClick={()=>load(week)}>새로고침 ↻</button></div>
 {program?.world&&<div className="card"><div className="large gold">{program.world.season}시즌 · {week}주차</div>
 <div className="muted">현실 1일 = 게임 1주 · 출발 3분 간격 · 결과 출발 3분 후 · Asia/Seoul</div>
 <div className="row" style={{marginTop:11}}>
 <button className="outline" disabled={week<=1} onClick={()=>load(week-1)}>‹ 이전 주</button>
 <span className="tag">{program.raceCount}경주</span>
 <button className="outline" disabled={week>=52} onClick={()=>load(week+1)}>다음 주 ›</button></div>
 <div className="muted" style={{marginTop:9}}>{program.world.status==="ACTIVE"?"● 월드 운영 중":"월드 대기"} · {program.world.schedulerConfigured?"자동 경주 스케줄러 설정됨":"자동 스케줄러 미설정"}</div></div>}
 {error&&<div className="notice">{error}</div>}
 <div className="notice">19시 부산·영천 / 20시 서울·영천 / 21시 서울·부산 경주가 진행됩니다.
    각 경주는 3분 간격으로 출발하며, 결과는 출발 3분 후 확정됩니다.</div>
 <div className="section"><h2>{slot==="전체"?"경주 시간대 선택":slot+"시 전체 경주 목록"}</h2>
  {slot!=="전체"&&<button onClick={()=>chooseSlot("전체")}>모든 시간대 ›</button>}</div>
 <div className="official-slot-tabs" aria-label="경주 시간대">
  <button className={slot==="전체"?"active":""} onClick={()=>chooseSlot("전체")}>전체</button>
  {slotSummaries.map(x=><button key={x.hour} className={slot===x.hour?"active":""}
    onClick={()=>chooseSlot(x.hour)}>
   <strong>{x.hour}시</strong><small>{x.label} · {x.total}경주</small>
  </button>)}
 </div>
 {selectedSlot&&<div className="notice">
  <b>{selectedSlot.hour}시 경주 · {selectedSlot.label}</b><br/>
  {selectedSlot.total}경주 중 {selectedSlot.completed}경주 종료
  {selectedSlot.ongoing>0?" · "+selectedSlot.ongoing+"경주 진행 처리 중":""}
  {" · "}실제 공식 경주 상태 기준 · 15초마다 갱신
 </div>}
  <div className="tabs">{["전체","서울","부산","영천"].map(x=><button key={x} className={track===x?"active":""} onClick={()=>SetTrack(x)}>{x}</button>)}</div>
 {!error&&program&&events.length===0&&<div className="notice">선택한 시간대와 지역에 편성된 경주가 없습니다.</div>}
 {Object.entries(grouped).map(([slot,list])=><div key={slot}><div className="section"><h2>{slot} 시작 · {list.length}경주</h2></div>
 {list.map(r=><a key={r.id} href={"/race/"+r.id} className="card row" style={{display:"flex",textDecoration:"none",color:"inherit",cursor:"pointer"}}>
 <div><b className="gold">{r.time} · {r.track} {r.raceNo}경주</b>
 <div className="muted">{r.grade} · {r.distance}m · 출전 {r.actualStarters}/{r.dusu}두 · 결과 {r.resultTime}</div>
 <div className="muted">경주일 {r.date}</div></div>
 <div style={{textAlign:"right"}}><span className="tag">{r.status==="FINISHED"?"공식 결과":r.status==="RUNNING"?"진행 중":r.status==="CANCELLED"?"취소":"예정"}</span>
 <div className="gold" style={{fontSize:12,marginTop:13}}>{r.status==="FINISHED"?"기록 보기 ›":"경주 상세 ›"}</div></div>
 </a>)}</div>)}
 {!program&&!error&&<div className="notice">경주 시간표를 불러오는 중…</div>}
 <div className="footer">MY DERBY · 공식 경주 일정</div></div></main>;
}
