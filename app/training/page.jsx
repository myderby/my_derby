"use client";
import HorseLink from "../components/HorseLink";
import StaffLink from "../components/StaffLink";
import HorseDiscovery from "../components/HorseDiscovery";
import {useCallback,useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";

const statNames={start:"스타트",speed:"스피드",acceleration:"가속력",stamina:"지구력",finishing:"막판탄력",power:"파워",grit:"근성",stability:"안정성",recovery:"회복력"};
const distances=[["SPRINT","단거리"],["MILE","마일"],["MIDDLE","중거리"],["LONG","장거리"]];
const styles=[["FRONT_ESCAPE","도주"],["LEAD","선행"],["PRESS","선입"],["MID_MOVE","중반 무빙"],["CLOSER","추입"],["FREE","자유형"]];
const intensities=[["REST","완전 휴식"],["LIGHT","가벼운 훈련"],["NORMAL","일반 훈련"],["HARD","강훈련"]];
const modeLabel={TRAINED:"훈련 완료",RACE_DAY_REST:"경주일 휴식",RECOVERY:"회복",INELIGIBLE_REST:"훈련 불가"};
const errors={
 LOGIN_REQUIRED:"로그인이 필요합니다.",JOIN_WORLD_FIRST:"월드에 먼저 참가하세요.",
 NOT_YOUR_HORSE:"본인 소유마만 관리할 수 있습니다.",HORSE_NOT_TRAINABLE:"현재 상태에서는 훈련할 수 없는 말입니다.",
 TRAINING_PLAN_REQUIRED:"먼저 훈련계획을 저장하세요.",TRAINING_PLAN_INVALID:"훈련계획을 다시 선택해주세요.",
 TRAINING_SETTLEMENT_OPENS_2205:"훈련 리포트는 한국시간 22:05 이후에 생성할 수 있습니다."
};
const explain=text=>{
 const msg=String(text||"오류가 발생했습니다.");
 return Object.keys(errors).find(k=>msg.includes(k))?
   errors[Object.keys(errors).find(k=>msg.includes(k))]:msg;
};
const nameOf=(pairs,key)=>pairs.find(([k])=>k===key)?.[1]||key;
const sign=n=>Number(n)>0?"+":"";
const signed=n=>sign(n)+Number(n||0).toFixed(2);
const initial={distance:"SPRINT",style:"LEAD",intensity:"NORMAL"};
const currentKst=()=>new Intl.DateTimeFormat("en-GB",{timeZone:"Asia/Seoul",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date());

export default function TrainingPage(){
 const [token,SetToken]=useState("");
 const [authLoading,AuthLoading]=useState(true);
 const [board,SetBoard]=useState(null);
 const [selected,SetSelected]=useState(null);
 const [plan,SetPlan]=useState(initial);
 const [error,SetError]=useState("");
 const [message,SetMessage]=useState("");
 const [busy,SetBusy]=useState("");
 const [loading,SetLoading]=useState(false);
 const [showAll,SetShowAll]=useState(false);
 const [clock,SetClock]=useState(currentKst());

 useEffect(()=>{
  let active=true;
  let client;
  try{
   client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  }catch(e){SetError("Supabase 설정이 없습니다.");AuthLoading(false);return}
  client.auth.getSession().then(({data,error})=>{
   if(active){SetToken(data.session?.access_token||"");if(error)SetError(error.message);AuthLoading(false)}
  }).catch(e=>{if(active){SetError(explain(e.message));AuthLoading(false)}});
  const {data:{subscription}}=client.auth.onAuthStateChange((_event,session)=>{
   if(active)SetToken(session?.access_token||"");
  });
  return()=>{active=false;subscription.unsubscribe()};
 },[]);
 useEffect(()=>{const id=setInterval(()=>SetClock(currentKst()),30000);return()=>clearInterval(id)},[]);

 const refresh=useCallback(async(access=token)=>{
  if(!access)return;
  SetLoading(true);
  try{
   const res=await fetch("/api/player/training",{cache:"no-store",headers:{Authorization:"Bearer "+access}});
   const data=await res.json();if(!res.ok)throw new Error(data.error||"훈련정보 조회 실패");
   SetBoard(data);SetSelected(previous=>(data.horses||[]).some(h=>h.id===previous)?previous:data.horses?.[0]?.id||null);
   SetError("");
  }catch(e){SetError(explain(e.message))}
  finally{SetLoading(false)}
 },[token]);
 useEffect(()=>{if(token)void refresh(token);else{SetBoard(null);SetSelected(null)}},[token,refresh]);

 const horse=(board?.horses||[]).find(h=>h.id===selected);
 useEffect(()=>{
  if(horse?.plan)SetPlan({distance:horse.plan.distance,style:horse.plan.style,intensity:horse.plan.intensity});
  else SetPlan(initial);
 },[horse?.id,horse?.plan?.updatedAt]);

 const reports=useMemo(()=>(board?.reports||[]).filter(r=>!selected||r.horseId===selected),[board,selected]);
 const first=Number(board?.world?.gameDayStart||0);
 const thisWeek=reports.filter(r=>Number(r.gameDay)>=first&&Number(r.gameDay)<first+7);
 const processedDays=new Set(thisWeek.map(r=>r.gameDay));
 const canTrain=horse?.lifeStage==="RACING"&&!horse?.retired&&horse?.health!=="INJURED"
  &&Number(horse?.age)>=2&&Number(horse?.age)<=10;
 const isLate=clock>="22:05";
 const isDone=processedDays.size===7;

 const send=async body=>{
  SetBusy(body.action);SetMessage("");SetError("");
  try{
   const res=await fetch("/api/player/training",{method:"POST",cache:"no-store",
    headers:{"Content-Type":"application/json",Authorization:"Bearer "+token},body:JSON.stringify(body)});
   const data=await res.json();if(!res.ok)throw new Error(data.error||"처리 실패");
   SetMessage(body.action==="SAVE"?"훈련계획을 저장했습니다. 아직 처리되지 않은 게임 날짜부터 적용됩니다.":
    data.processedDays>0?"이번 주 "+data.processedDays+"일의 훈련·휴식 리포트를 생성하고 능력치를 반영했습니다.":
     "이번 주 훈련 기록은 이미 정산되어 중복 처리하지 않았습니다.");
   await refresh(token);
  }catch(e){SetError(explain(e.message))}
  finally{SetBusy("")}
 };

 return <main className="shell">
 <header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🐎 훈련 관리</span></header>
 <div className="area">
  <div className="controls" style={{marginBottom:14}}>
   <a href="/world" className="outline" style={{textDecoration:"none",textAlign:"center"}}>‹ 내 경주마</a>
   <a href="/entries" className="outline" style={{textDecoration:"none",textAlign:"center"}}>경주 출전 ›</a>
  </div>
  <div className="section"><h2>훈련계획 · 일일 리포트</h2>
   <button disabled={!token||loading} onClick={()=>refresh()}>새로고침 ↻</button></div>
  <div className="notice">현실 하루는 게임 7일입니다. 각 말은 게임 날짜마다 최대 1회 훈련하고,
   공식 경주일에는 자동으로 훈련을 쉬게 됩니다. 매일 <b>22:20(한국시간)</b>에 이번 주 훈련을 자동 정산하며,
   22:05 이후 직접 리포트 생성을 실행할 수도 있습니다.</div>
  {error&&<div className="notice" role="alert">⚠ {error}</div>}
  {message&&<div className="notice" role="status">✓ {message}</div>}
  {authLoading&&<div className="notice">로그인 상태 확인 중…</div>}
  {!authLoading&&!token&&<div className="card">
   <b>마주 로그인이 필요합니다.</b><div className="muted">내 경주마의 훈련계획 및 리포트를 보려면 월드에서 로그인하세요.</div>
   <a href="/world" className="primary" style={{display:"inline-block",marginTop:12,textDecoration:"none"}}>월드 로그인 ›</a>
  </div>}
  {loading&&!board&&<div className="notice">보유마와 훈련 데이터를 불러오는 중…</div>}
  {board&&<>
   <div className="card"><div className="row">
    <div><b className="large gold">{board.world?.week}주차 훈련</b>
     <div className="muted">{board.world?.season}시즌 · 게임 {first}~{first+6}일 · 오늘 {clock} KST</div></div>
    <span className="tag">실제 DB 연동</span></div>
    <div className="muted" style={{marginTop:9}}>현재 상태를 기준으로 훈련 가능 여부와 성장 한도를 판단합니다.
     잠재력·히든 특성 값은 공개하지 않습니다.</div>
   </div>
   <div className="section"><h2>내 경주마</h2><span className="tag">{board.horses?.length||0}두</span></div>
   <div className="tabs">{(board.horses||[]).map(h=>
    <button key={h.id} className={selected===h.id?"active":""} onClick={()=>SetSelected(h.id)}>{h.name}</button>)}</div>
   {!board.horses?.length&&<div className="notice">보유 중인 말이 없습니다. 월드에서 마주 등록을 완료하세요.</div>}
   {horse&&<>
    <div className="card">
     <div className="row"><div><b className="gold"><HorseLink horseId={horse.id}>{horse.name}</HorseLink></b>
      <div className="muted">{horse.age}세 · {horse.lifeStage==="RACING"?"현역":horse.lifeStage} · {horse.health}</div></div>
      <span className="tag">{canTrain?"훈련 가능":"훈련 불가"}</span></div>
     <div className="row small line"><span>컨디션</span><b>{Number(horse.condition).toFixed(1)}</b></div>
     <div className="bar"><div className="fill" style={{width:Math.max(0,Math.min(100,Number(horse.condition)))+"%"}}/></div>
     <div className="row small line"><span>피로도</span><b>{Number(horse.fatigue).toFixed(1)}</b></div>
     <div className="bar"><div className="fill" style={{width:Math.max(0,Math.min(100,Number(horse.fatigue)))+"%"}}/></div>
     <div className="muted" style={{marginTop:11}}>{horse.trainer?<>담당 조교사: <StaffLink kind="trainer" staffId={horse.trainer.id}>{horse.trainer.name}</StaffLink> · {(horse.trainer.specialties||[]).join(", ")}</>:"NPC 조교사 미계약 · 기본 자율 훈련(성장 효율 감소)"}</div>
    </div>
    <div className="section"><h2>성장 방향 · 훈련 강도</h2></div>
    <div className="card">
     <label className="muted" htmlFor="distanceFocus">거리 적성</label>
     <select className="field" id="distanceFocus" value={plan.distance}
      onChange={e=>SetPlan(p=>({...p,distance:e.target.value}))}>
      {distances.map(([id,name])=><option key={id} value={id}>{name}</option>)}</select>
     <label className="muted" htmlFor="runStyle">주행 스타일</label>
     <select className="field" id="runStyle" value={plan.style}
      onChange={e=>SetPlan(p=>({...p,style:e.target.value}))}>
      {styles.map(([id,name])=><option key={id} value={id}>{name}</option>)}</select>
     <label className="muted" htmlFor="trainingIntensity">훈련 강도</label>
     <select className="field" id="trainingIntensity" value={plan.intensity}
      onChange={e=>SetPlan(p=>({...p,intensity:e.target.value}))}>
      {intensities.map(([id,name])=><option key={id} value={id}>{name}</option>)}</select>
     <div className="muted">강훈련은 능력치가 더 잘 성장하지만 피로가 많이 쌓이고 컨디션이 떨어집니다.
      가벼운 훈련은 회복을 돕습니다. 피로 75 이상이면 자동 휴식합니다.</div>
     {horse.plan&&<div className="muted" style={{marginTop:9}}>현재 저장: {nameOf(distances,horse.plan.distance)} /
       {nameOf(styles,horse.plan.style)} / {nameOf(intensities,horse.plan.intensity)}</div>}
     <button className="primary wide" style={{marginTop:12}} disabled={!canTrain||!!busy}
       onClick={()=>send({action:"SAVE",horseId:horse.id,distance:plan.distance,style:plan.style,intensity:plan.intensity})}>
       {busy==="SAVE"?"저장 중…":"훈련계획 저장"}</button>
    </div>
    <div className="card">
     <div className="row"><b className="gold">이번 주 훈련 리포트</b>
      <span className="tag">{processedDays.size}/7일 처리</span></div>
     <div className="muted" style={{marginTop:9}}>훈련이 한 번 처리된 게임 날짜는 계획을 변경해도 다시 정산되지 않습니다.</div>
     <button className="outline wide" style={{marginTop:12}}
      disabled={!canTrain||!horse.plan||!!busy||!isLate||isDone}
      onClick={()=>send({action:"PROCESS",horseId:horse.id})}>
      {busy==="PROCESS"?"훈련 리포트 생성 중…":isDone?"이번 주 정산 완료":!isLate?"22:05 이후 실행 가능":"이번 주 훈련 리포트 생성"}</button>
     {!horse.plan&&<div className="muted" style={{marginTop:9}}>훈련계획을 저장하면 자동 정산이 시작됩니다.</div>}
    </div>
    <div className="section"><h2>🔍 조교사 능력 평가</h2></div>
    <HorseDiscovery discovery={horse.discovery} horseId={horse.id} compact/>
    <div className="section"><h2>일일 훈련 리포트</h2><span className="tag">{reports.length}건</span></div>
    {!reports.length&&<div className="notice">아직 생성된 리포트가 없습니다. 훈련계획을 저장한 뒤 자동 정산을 확인하세요.</div>}
    {(showAll?reports:reports.slice(0,12)).map(r=>{
     const m=r.changeStats?._meta||{};
     const changes=Object.entries(r.changeStats||{}).filter(([key,val])=>key in statNames&&Number(val)!==0);
     return <div className="card" key={r.id}>
      <div className="row"><b className="gold">게임 {r.gameDay}일</b>
       <span className="tag">{modeLabel[m.mode]||m.mode||"훈련 리포트"}</span></div>
      <div className="muted" style={{marginTop:8}}>{r.text}</div>
      {changes.length>0?<div className="line small" style={{lineHeight:1.9}}>
       {changes.map(([key,val])=><span key={key} style={{display:"inline-block",marginRight:14,color:"#b3d38b"}}>{statNames[key]} {signed(val)}</span>)}
      </div>:<div className="muted" style={{marginTop:8}}>능력치 변화 없음</div>}
      <div className="row small" style={{marginTop:9}}>
       <span>피로 {signed(r.fatigueChange)}</span><span>컨디션 {signed(r.conditionChange)}</span></div>
      {r.trainerName&&<div className="muted" style={{marginTop:7}}>조교사 <StaffLink kind="trainer" staffId={r.trainerId}>{r.trainerName}</StaffLink></div>}
     </div>;
    })}
    {reports.length>12&&<button className="outline wide" onClick={()=>SetShowAll(v=>!v)}>
      {showAll?"최근 12개만 보기":"전체 "+reports.length+"개 보기"}</button>}
   </>}
  </>}
  <div className="footer">MY DERBY · 실제 보유마 능력치 · 기록 기반 훈련 정산</div>
 </div>
 </main>;
}
