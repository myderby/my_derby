"use client";
import {useEffect,useState} from "react";
import HorseLink from "./HorseLink";

const skillNames={start:"출발",pace:"페이스",urging:"추진",control:"제어",judgment:"판단",
 stability:"안정성",aggression:"적극성",positioning:"위치 선정",speed:"속도",
 finishing:"막판 탄력",stamina:"지구력",acceleration:"가속력",
 power:"파워",grit:"근성",recovery:"회복력"};
const fmt=n=>Number(n||0).toLocaleString("ko-KR");
function RecordCard({title,record}){
 const s=record||{};
 return <section className="card staff-record">
  <div className="muted">{title}</div>
  <div className="large gold">{fmt(s.starts)}전 {fmt(s.wins)}승</div>
  <div className="muted">2위 {fmt(s.seconds)}회 · 3위 {fmt(s.thirds)}회</div>
  <div className="staff-rates"><span>승률 <b>{s.winRate??0}%</b></span>
   <span>복승률 <b>{s.quinellaRate??0}%</b></span>
   <span>연승률 <b>{s.placeRate??0}%</b></span></div>
  <div className="muted" style={{marginTop:8}}>획득 상금 {fmt(s.prize)} G</div>
 </section>;
}
export default function StaffProfile({kind,id}){
 const isJockey=kind==="jockey";
 const [state,setState]=useState({loading:true,data:null,error:""});
 useEffect(()=>{
  const ctrl=new AbortController();
  setState({loading:true,data:null,error:""});
  fetch("/api/world/staff-profile?kind="+encodeURIComponent(kind)+"&id="+encodeURIComponent(id),{
   cache:"no-store",signal:ctrl.signal
  }).then(async res=>{
   const result=await res.json();
   if(!res.ok)throw Error(result.error||"상세정보를 불러오지 못했습니다.");
   if(!ctrl.signal.aborted)setState({loading:false,data:result,error:""});
  }).catch(error=>{
   if(!ctrl.signal.aborted)setState({loading:false,data:null,error:error.message});
  });
  return()=>ctrl.abort();
 },[kind,id]);
 const v=state.data,who=isJockey?"기수":"조교사";
 return <main className="shell directory-shell">
  <header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a>
   <span className="coin">{isJockey?"🏇":"🏠"} {who} 상세정보</span></header>
  <div className="area">
   <div className="controls" style={{marginBottom:16}}>
    <a className="outline" href={isJockey?"/jockeys":"/participants?view=trainers"} style={{textDecoration:"none"}}>‹ {who} 목록</a>
    <a className="outline" href="/participants?view=records" style={{textDecoration:"none"}}>전체 성적 ›</a>
   </div>
   {state.loading&&<div className="notice">공식 경주 기록과 {who} 정보를 조회하고 있습니다.</div>}
   {state.error&&<div className="notice" role="alert">{state.error}</div>}
   {!state.loading&&v&&<>
    <section className="card staff-hero">
     <div className="staff-hero-head"><div>
      <div className="muted">{who} PROFILE · MY DERBY</div>
      <h1>{v.name}</h1>
      <div className="muted">{v.track||"소속 미정"} · {v.active?"활동 중":"비활동"}</div>
     </div><span className="tag">{isJockey?"기수":"조교사"}</span></div>
     <div className="staff-quick">
      <div><small>소속</small><b>{v.track||"—"}</b></div>
      <div><small>{isJockey?"하루 최대 기승":"담당 마방"}</small><b>{isJockey?fmt(v.capacity)+"회":v.stable||"—"}</b></div>
      <div><small>{isJockey?"통산 우승":"담당 정원"}</small>
       <b>{isJockey?fmt(v.career?.wins)+"승":fmt(v.occupied)+"/"+fmt(v.capacity)+"두"}</b></div>
     </div>
     <div className="muted" style={{marginTop:10}}>게임 공식 경주 기록 기준 · 원본 마사회 전적과 합산하지 않습니다.</div>
    </section>
    <div className="section"><h2>🏆 통산·최근 1년 경주 성적</h2></div>
    <div className="staff-record-grid"><RecordCard title="게임 통산 공식 전적" record={v.career}/>
     <RecordCard title="게임 최근 364일" record={v.recentYear}/></div>
    <div className="section"><h2>⭐ 능력치 · 전문분야</h2></div>
    <section className="card">
     <div className="staff-skills">{Object.entries(v.skills||{}).map(([key,value])=><div key={key}>
      <span>{skillNames[key]||key}</span><b>{value}</b></div>)}</div>
     <div className="muted" style={{marginTop:12}}>전문 분야: {(v.specialties||[]).filter(x=>!String(x).includes("SOURCE_RECORD_ESTIMATE")).join(" · ")||"등록된 특기 없음"}</div>
     {(v.specialties||[]).some(x=>String(x).includes("ESTIMATE"))&&
      <div className="muted" style={{marginTop:8,fontSize:11}}>※ 일부 능력치는 게임용 추정치입니다.</div>}
    </section>
    {!isJockey&&<><div className="section"><h2>🐎 현재 담당 경주마</h2><span className="tag">{fmt(v.occupied)}두</span></div>
     <section className="card">
      {!v.horses?.length?<div className="muted">현재 담당하고 있는 경주마가 없습니다.</div>:
       <div className="staff-horse-grid">{v.horses.map(h=><div key={h.horse_id}>
        <HorseLink horseId={h.horse_id}>{h.horse_name}</HorseLink>
        <span className="muted">{h.grade?fmt(h.grade)+"등급":"등급 미정"} · 레이팅 {h.rating??"—"}</span>
       </div>)}</div>}
     </section>
    </>}
    <div className="section"><h2>📋 최근 공식 경주 내역</h2></div>
    {!v.races?.length?<div className="notice">아직 확정된 게임 공식 경주 기록이 없습니다.</div>:
     <div className="race-entry-wrap" role="region" aria-label={who+" 최근 공식 경주 내역"} tabIndex={0}>
      <table className="race-entry-table">
       <thead><tr><th>경주일</th><th>경주</th><th>경주마</th><th>착순</th><th>상금</th></tr></thead>
       <tbody>{v.races.map((r,index)=><tr key={r.race_id+"-"+r.horse_id+"-"+index}>
        <td>{r.race_date||"—"}</td>
        <td><a className="staff-inline-link" href={"/race/"+r.race_id}>{r.track} {r.race_no}경주<br/>
         <small>{r.class_name} · {fmt(r.distance_m)}m</small></a></td>
        <td><HorseLink horseId={r.horse_id}>{r.horse_name}</HorseLink></td>
        <td className={r.finishing_rank===1?"gold":""}>{r.finishing_rank}위</td>
        <td>{fmt(r.prize)} G</td>
       </tr>)}</tbody>
      </table>
     </div>}
    <div className="footer">MY DERBY · {who} 기록실 · 공식 종료 경주만 집계</div>
   </>}
  </div>
 </main>;
}
