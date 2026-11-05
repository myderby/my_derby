"use client";
import HorseLink from "../components/HorseLink";
import {useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const c=()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
const fmt=n=>new Intl.NumberFormat("ko-KR").format(n||0);
const courses=[["REST_3D","기본 휴양 3게임일"],["RECOVERY_7D","회복 7게임일"],["REHAB","재활 7게임일"],["YOUNG_BASIC","2세 이하 기초육성 7게임일"]];
const explain=e=>{
 const errors={RANCH_COURSE_ALREADY_ACTIVE:"이미 진행 중인 목장 코스가 있습니다.",RANCH_RACE_CONFLICT:"공식 경주 출전 예정 기간과 목장 입소 기간이 겹칩니다.",RANCH_FACILITY_FULL:"해당 시설의 수용 인원이 가득 찼습니다.",INSUFFICIENT_FUNDS:"게임머니가 부족합니다.",HORSE_NOT_RANCH_ELIGIBLE:"경주마의 상태상 목장에 입소할 수 없습니다.",REHAB_REQUIRES_INJURY:"재활은 건강 문제가 있는 경주마에게만 가능합니다.",RANCH_COURSE_AGE_MISMATCH:"경주마 나이와 코스가 맞지 않습니다.",STARTER_GRADE6_UNAVAILABLE:"튜토리얼 3세 6등급 신마를 지금 배정할 수 없습니다. 목장 코스 신청은 반영되지 않았습니다. 잠시 후 다시 시도해주세요."};
 const key=Object.keys(errors).find(k=>String(e).includes(k));return key?errors[key]:String(e);
};
export default function Ranch(){
 const [token,T]=useState(""),[loadState,Loaded]=useState(false),[board,B]=useState(null),
 [error,E]=useState(""),[notice,N]=useState(""),[busy,X]=useState(false),
 [horse,H]=useState(""),[course,C]=useState("REST_3D"),[view,V]=useState("stable");
 useEffect(()=>{
  if(new URLSearchParams(window.location.search).get("view")==="courses")V("courses");
  else{window.location.replace("/ranch/management");return;}
  let on=true;const api=c();
  api.auth.getSession().then(({data})=>{if(on){T(data.session?.access_token||"");Loaded(true)}})
   .catch(e=>{if(on){E(e.message);Loaded(true)}});
  const {data:{subscription}}=api.auth.onAuthStateChange((_e,s)=>{if(on)T(s?.access_token||"")});
  return()=>{on=false;subscription.unsubscribe()};
 },[]);
 const refresh=async(t=token)=>{
  if(!t)return;try{
   const r=await fetch("/api/player/ranch",{headers:{Authorization:"Bearer "+t},cache:"no-store"});
   const result=await r.json();if(!r.ok)throw new Error(result.error);
   const first=result.horses.find(h=>Number(h.age)<=2)||result.horses[0];
   B(result);H(old=>result.horses.some(h=>h.id===old)?old:first?.id||"");
   if(first&&Number(first.age)<=2)C(old=>old==="REST_3D"?"YOUNG_BASIC":old);
   E("");
  }catch(e){E(explain(e.message))}
 };
 useEffect(()=>{if(token)void refresh(token)},[token]);
 const h=board?.horses?.find(x=>x.id===horse);
 const active=useMemo(()=>(board?.courses||[]).filter(x=>x.status==="ACTIVE"),[board]);
 const capacity=(board?.ranch?.facilities||[]).reduce((sum,f)=>sum+(Number(f.capacity)||0),0);
 const apply=async()=>{
  if(!horse)return;
  if(!window.confirm("선택한 목장 코스를 신청하시겠습니까? 비용은 즉시 차감됩니다."))return;
  X(true);E("");N("");
  try{
   const r=await fetch("/api/player/ranch",{method:"POST",headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify({horseId:horse,course})});
   const result=await r.json();if(!r.ok)throw new Error(result.error);
   N("목장 입소 확정 · 비용 "+fmt(result.fee)+" G · 게임 "+result.startGameDay+"~"+result.endGameDay+"일");
   window.dispatchEvent(new Event("my-derby:progress"));await refresh();
  }catch(e){E(explain(e.message))}finally{X(false)}
 };
 return <main className="shell ranch-shell">
  <header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🌲 내 목장</span></header>
  <div className="area ranch-area">
   <div className="ranch-page-heading"><div><div className="ranch-eyebrow">MY DERBY · OWNER'S STABLE</div><h1>{board?.ranch?.name||"내 개인목장"}</h1></div><button className="outline" disabled={!token||busy} onClick={()=>refresh()}>새로고침 ↻</button></div>
   <div className="ranch-page-actions">
    <button className={view==="stable"?"ranch-view-tab active":"ranch-view-tab"} onClick={()=>V("stable")}>마방</button>
    <button className={view==="courses"?"ranch-view-tab active":"ranch-view-tab"} data-tutorial-target="ranch" onClick={()=>V("courses")}>목장 코스</button>
    <a className="ranch-view-tab" href="/ranch/management">시설·직원 관리 ›</a>
   </div>
   {error&&<div className="notice" role="alert">⚠ {error}</div>}
   {notice&&<div className="notice" role="status">✓ {notice}</div>}
   {!loadState&&<div className="notice">목장 정보를 불러오는 중…</div>}
   {loadState&&!token&&<div className="notice"><a href="/world">로그인</a> 후 이용할 수 있습니다.</div>}
   {board&&view==="stable"&&<div className="ranch-layout">
    <aside className="ranch-horse-sidebar">
     <div className="ranch-sidebar-head"><span>마방 현황</span><b>{board.horses.length} <small>/ {capacity||"—"}두</small></b></div>
     <div className="ranch-sidebar-note">말을 선택해 마방 정보를 확인하세요.</div>
     <div className="ranch-horse-list">{board.horses.map((item,index)=><button type="button" key={item.id}
      className={item.id===horse?"ranch-horse-option selected":"ranch-horse-option"} onClick={()=>H(item.id)}>
      <span className="ranch-horse-star">{String(index+1).padStart(2,"0")}</span><span className="ranch-horse-option-copy"><b>{item.name}</b><small>{item.age}세 · {item.stage||"경주마"}</small></span><span className="ranch-horse-chevron">›</span>
     </button>)}
     {!board.horses.length&&<div className="ranch-empty">마방에 등록된 말이 없습니다.</div>}</div>
     <a className="ranch-side-link" href="/world">내 경주마 전체 보기 ›</a>
    </aside>
    <section className="ranch-stable-content">
     <div className="ranch-stable-scene">
      <div className="ranch-stable-scene-head"><div><span>STABLE</span><h2>{h?.name||"비어 있는 마방"}</h2></div><span className="ranch-scene-badge">{h?`${h.age}세 · ${h.stage||"마방"}`:"말을 선택하세요"}</span></div>
      {h?<div className="ranch-feature-stall">
       <div className="ranch-horse-art" aria-hidden="true">♞</div>
       <div className="ranch-stall-wood"><span>MY DERBY STABLE · {String(board.horses.findIndex(x=>x.id===h.id)+1).padStart(2,"0")}</span></div>
       <div className="ranch-stall-details"><div><b><HorseLink horseId={h.id}>{h.name}</HorseLink></b><span>{h.sex||"경주마"} · {h.age}세 · {h.stage||"육성 중"}</span></div><div className="ranch-condition"><small>컨디션</small><b>{h.condition??"—"}</b></div></div>
       <div className="ranch-condition-bar"><i style={{width:Math.max(0,Math.min(100,Number(h.condition)||0))+"%"}}/></div>
      </div>:<div className="ranch-vacant-stall"><span>♞</span><b>마방을 준비하고 있습니다</b><small>내 경주마가 등록되면 이곳에서 확인할 수 있습니다.</small></div>}
      <div className="ranch-scene-floor"><span>개인목장 · {board.ranch?.region||"마주님의 목장"}</span><span>보유마 {board.horses.length}두</span></div>
     </div>
     <div className="ranch-stall-strip"><div className="ranch-stall-strip-title"><b>내 마방</b><span>{board.horses.length}두</span></div>
      <div className="ranch-mini-stalls">{board.horses.slice(0,5).map((item,index)=><button key={item.id} type="button" className={item.id===horse?"ranch-mini-stall selected":"ranch-mini-stall"} onClick={()=>H(item.id)}>
       <span aria-hidden="true">♞</span><b>{item.name}</b><small>{item.age}세 · {item.condition??"—"}%</small>
      </button>)}</div>
     </div>
     <div className="ranch-facility-summary"><div><b>목장 시설</b><span>{(board.ranch?.facilities||[]).length}곳 · 수용 {capacity||0}두</span></div><a href="/ranch/management">직원 현황·시설 강화 ›</a></div>
     <button className="primary wide ranch-course-cta" data-tutorial-target="ranch" onClick={()=>V("courses")}>휴양·재활·어린말 코스 신청 ›</button>
    </section>
   </div>}
   {board&&view==="courses"&&<>
    <div className="ranch-course-intro"><a className="outline" href="/ranch/management" style={{textDecoration:"none"}}>‹ 목장 관리로</a><div><b>목장 코스 신청</b><p>말을 선택하고 휴양·회복·재활·어린말 육성을 신청하세요.</p></div></div>
    <div className="ranch-course-grid">
     <section className="card"><div className="section"><h2>입소할 경주마</h2><span className="tag">{board.horses.length}두</span></div>
      <label className="muted" htmlFor="ranchHorse">마방에서 말 선택</label>
      <select className="field" id="ranchHorse" value={horse} onChange={e=>H(e.target.value)}>{board.horses.map(item=><option key={item.id} value={item.id}>{item.name} · {item.age}세 · 컨디션 {item.condition} · 피로 {item.fatigue}</option>)}</select>
      {h&&<div className="ranch-selected-horse"><span aria-hidden="true">♞</span><div><b><HorseLink horseId={h.id}>{h.name}</HorseLink></b><small>{h.age}세 · {h.health} · {h.stage}</small></div></div>}
     </section>
     <section className="card"><div className="section"><h2>코스 선택</h2></div>
      <label className="muted" htmlFor="course">이용할 목장 코스</label>
      <select className="field" id="course" value={course} onChange={e=>C(e.target.value)}>{courses.map(([key,title])=><option key={key} value={key}>{title}</option>)}</select>
      <div className="ranch-course-help">휴양은 피로·컨디션 회복, 재활은 부상 회복, 어린말 육성은 0~2세 기초 능력 향상을 지원합니다. 시설 레벨이 높을수록 코스 후 관찰 정보가 늘어납니다.</div>
      <button className="primary wide" data-tutorial-target="ranch" style={{marginTop:13}} disabled={!h||busy} onClick={apply}>{busy?"신청 중…":"게임머니 결제 후 입소 신청"}</button>
     </section>
    </div>
    <div className="ranch-active-courses-head"><b>진행 중인 목장 코스</b><span>{active.length}건</span></div>
    {!active.length&&<div className="notice">진행 중인 코스가 없습니다.</div>}
    {active.map(item=><div className="card row" key={item.id}><div><b>{item.horseName}</b><div className="muted">{courses.find(x=>x[0]===item.courseType)?.[1]||item.courseType}</div></div><span className="tag">게임 {item.endDay}일 종료</span></div>)}
    <div className="ranch-course-footnote">실제 게임 DB에 코스 신청·비용·회복을 기록합니다. 매일 22:50(한국시간)에 종료 대상 코스를 정산하며, 코스 기간과 출전 예정 경주가 겹치지 않도록 제한됩니다.</div>
   </>}
   <div className="footer">MY DERBY · 개인목장과 마방 관리</div>
  </div>
 </main>;
}
