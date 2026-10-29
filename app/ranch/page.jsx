"use client";
import {useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const c=()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
const fmt=n=>new Intl.NumberFormat("ko-KR").format(n||0);
const facility={PASTURE:"방목지",RECOVERY_STABLE:"회복 마방",REHAB_TRACK:"재활 트랙",VET_CLINIC:"수의 진료소",YOUNG_HORSE_AREA:"어린말 육성장"};
const courses=[["REST_3D","기본 휴양 3게임일"],["RECOVERY_7D","회복 7게임일"],["REHAB","재활 7게임일"],["YOUNG_BASIC","어린말 기초육성 7게임일"]];
const errors={RANCH_COURSE_ALREADY_ACTIVE:"이미 진행 중인 목장 코스가 있습니다.",
 RANCH_RACE_CONFLICT:"공식 경주 출전 예정 기간과 목장 입소 기간이 겹칩니다.",
 RANCH_FACILITY_FULL:"해당 시설의 수용 인원이 가득 찼습니다.",
 INSUFFICIENT_FUNDS:"게임머니가 부족합니다.",
 HORSE_NOT_RANCH_ELIGIBLE:"경주마의 상태상 목장에 입소할 수 없습니다.",
 REHAB_REQUIRES_INJURY:"재활은 건강 문제가 있는 경주마에게만 가능합니다.",
 RANCH_COURSE_AGE_MISMATCH:"경주마 나이와 코스가 맞지 않습니다."};
const explain=e=>{const k=Object.keys(errors).find(k=>String(e).includes(k));return k?errors[k]:String(e)};
export default function Ranch(){
 const [token,T]=useState(""),[loadState,Loaded]=useState(false),[board,B]=useState(null),
 [error,E]=useState(""),[notice,N]=useState(""),[busy,X]=useState(false),
 [horse,H]=useState(""),[course,C]=useState("REST_3D");
 useEffect(()=>{let on=true;const api=c();
 api.auth.getSession().then(({data})=>{if(on){T(data.session?.access_token||"");Loaded(true)}})
 .catch(e=>{if(on){E(e.message);Loaded(true)}});
 const {data:{subscription}}=api.auth.onAuthStateChange((_e,s)=>{if(on)T(s?.access_token||"")});
 return()=>{on=false;subscription.unsubscribe()};},[]);
 const refresh=async(t=token)=>{
  if(!t)return;try{
   const r=await fetch("/api/player/ranch",{headers:{Authorization:"Bearer "+t},cache:"no-store"});
   const result=await r.json();if(!r.ok)throw new Error(result.error);
   B(result);H(old=>result.horses.some(h=>h.id===old)?old:result.horses?.[0]?.id||"");E("");
  }catch(e){E(explain(e.message))}
 };
 useEffect(()=>{if(token)void refresh(token)},[token]);
 const h=board?.horses?.find(x=>x.id===horse);
 const active=useMemo(()=>(board?.courses||[]).filter(x=>x.status==="ACTIVE"),[board]);
 const apply=async()=>{
  if(!horse)return;
  if(!window.confirm("선택한 목장 코스를 신청하시겠습니까? 비용은 즉시 차감됩니다."))return;
  X(true);E("");N("");
  try{const r=await fetch("/api/player/ranch",{method:"POST",
   headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},
   body:JSON.stringify({horseId:horse,course})});const result=await r.json();
   if(!r.ok)throw new Error(result.error);
   N("목장 입소 확정 · 비용 "+fmt(result.fee)+" G · 게임 "+result.startGameDay+"~"+result.endGameDay+"일");
   await refresh();
  }catch(e){E(explain(e.message))}
  finally{X(false)}
 };
 return <main className="shell"><header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🌲 개인목장</span></header>
 <div className="area">
  <div className="controls" style={{marginBottom:14}}><a className="outline" href="/world" style={{textDecoration:"none"}}>‹ 내 경주마</a><a href="/finance" className="outline" style={{textDecoration:"none"}}>재무 현황 ›</a></div>
  <div className="section"><h2>목장 휴양 · 재활 · 어린말 육성</h2><button disabled={!token||busy} onClick={()=>refresh()}>새로고침 ↻</button></div>
  <div className="notice">실제 게임 DB에 코스 신청·비용·회복을 기록합니다. 매일 22:50(한국시간) 종료 대상 코스를 정산합니다.
   코스 기간 중에는 출전 예정 경주와 겹치지 않도록 제한합니다.</div>
  {error&&<div className="notice" role="alert">⚠ {error}</div>}
  {notice&&<div className="notice" role="status">✓ {notice}</div>}
  {!loadState&&<div className="notice">로그인 확인 중…</div>}
  {loadState&&!token&&<div className="notice"><a href="/world">월드 로그인</a> 후 이용할 수 있습니다.</div>}
  {board&&<><div className="card">
   <div className="row"><div><b className="gold">{board.ranch?.name||"내 개인목장"}</b>
    <div className="muted">관리사 {board.ranch?.staff||0}명 · 수의사 {board.ranch?.veterinarians||0}명</div></div>
    <b>{fmt(board.balance)} G</b></div>
   <div className="section"><h2>목장 시설</h2></div>
   {(board.ranch?.facilities||[]).map(f=><div className="line row small" key={f.id}>
    <span>{facility[f.type]||f.type}</span><span>Lv.{f.level} · 수용 {f.capacity}두</span></div>)}
  </div>
  <div className="card">
   <div className="section"><h2>코스 입소 신청</h2></div>
   <label className="muted" htmlFor="ranchHorse">경주마 선택</label>
   <select className="field" id="ranchHorse" value={horse} onChange={e=>H(e.target.value)}>
   {board.horses.map(h=><option key={h.id} value={h.id}>{h.name} · {h.age}세 · 컨디션 {h.condition} · 피로 {h.fatigue}</option>)}
   </select>
   <label className="muted" htmlFor="course">코스 선택</label>
   <select className="field" id="course" value={course} onChange={e=>C(e.target.value)}>
    {courses.map(([key,title])=><option key={key} value={key}>{title}</option>)}
   </select>
   <div className="muted">휴양: 피로·컨디션 회복 / 회복: 장기 피로 관리 / 재활: 부상마의 회복 상태 개선 /
   어린말 육성: 0~1세 기초 능력치 향상. 적용 효과는 실제 DB에 기록됩니다.</div>
   {h&&<div className="muted" style={{marginTop:9}}>선택: {h.name} · 상태 {h.health} · {h.stage}</div>}
   <button className="primary wide" style={{marginTop:14}} disabled={!h||busy} onClick={apply}>
    {busy?"신청 중…":"게임머니 결제 후 목장 입소"}</button>
  </div>
  <div className="section"><h2>진행 중인 목장 코스</h2><span className="tag">{active.length}건</span></div>
  {!active.length&&<div className="notice">진행 중인 코스가 없습니다.</div>}
  {active.map(x=><div className="card row" key={x.id}>
   <div><b>{x.horseName}</b><div className="muted">{courses.find(c=>c[0]===x.courseType)?.[1]||x.courseType}</div></div>
   <span className="tag">게임 {x.endDay}일 종료</span>
  </div>)}
  </>}
  <div className="footer">MY DERBY · 경제_v2 목장 코스 · 실제 소유 경주마 회복</div>
 </div></main>;
}