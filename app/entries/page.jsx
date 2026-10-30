"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";

const readable={
 LOGIN_REQUIRED:"로그인이 필요합니다.",JOIN_WORLD_FIRST:"월드에 먼저 참가해주세요.",
 WEEK_OUT_OF_RANGE:"신청 가능한 주차가 아닙니다.",
 RACE_NOT_OPEN:"신청할 수 없는 경주입니다.",ENTRY_DEADLINE_PASSED:"출전 신청 마감 시각이 지났습니다.",
 NOT_YOUR_HORSE:"본인 소유 경주마만 신청할 수 있습니다.",
 HORSE_NOT_RACE_ELIGIBLE:"연령·건강·컨디션·피로도 또는 은퇴 상태상 출전이 불가능합니다.",
 REGION_OR_GRADE_MISMATCH:"출전마의 지역이나 등급이 경주 조건과 다릅니다.",
 REGION_MISMATCH:"출전마의 소속 지역과 경주 지역이 다릅니다.",
 GRADE_ENTRY_NOT_ALLOWED:"경주마와 동일한 등급의 경주에만 출전 신청할 수 있습니다. 상위·하위 등급 경주는 모두 제한됩니다.",
 ENTRY_NOT_OPEN_YET:"아직 출전 신청 시작일이 아닙니다. OPEN·대상경주는 4일 전, 일반 경주는 2일 전부터 신청할 수 있습니다.",
 ENTRY_RACE_DAY_BLOCKED:"경주 당일에는 출전 신청할 수 없습니다. 전날까지 신청해주세요.",
 AGE_COND_UNAVAILABLE:"이 OPEN·대상경주는 원본 ageCond(연령 조건)가 등록되지 않아 출전 신청이 제한됩니다.",
 AGE_COND_NOT_ELIGIBLE:"경주마 나이가 해당 OPEN·대상경주의 ageCond 조건과 맞지 않습니다.",
 HORSE_BIRTH_HEMISPHERE_REQUIRED:"이 경주는 남·북반구 출생 조건이 있습니다. 경주마의 출생 반구 정보가 확인되어야 출전할 수 있습니다.",
 HORSE_ALREADY_ENTERED_THIS_DAY:"이 경주마는 같은 게임 날짜의 다른 경주에 이미 출전합니다.",
 RACE_FULL_NO_NPC_SLOT:"현재 경주에는 교체 가능한 NPC 출전 슬롯이 없습니다.",
 JOCKEY_ALREADY_BOOKED_FOR_RACE:"선택한 기수는 이 경주에 이미 출전합니다.",
 JOCKEY_DAILY_LIMIT:"기수의 하루 최대 기승 횟수(8회)에 도달했습니다.",
 JOCKEY_NOT_ELIGIBLE:"선택한 기수가 해당 지역에서 활동하지 않거나 비활성 상태입니다.",
 OWN_CONFIRMED_ENTRY_REQUIRED:"먼저 내 경주마를 공식 경주에 출전 신청하세요.",
 NO_JOCKEY_AVAILABLE:"배정 가능한 기수가 없습니다.",
 NPC_REPLACEMENT_UNAVAILABLE:"출전 정원을 유지할 대체 NPC 말이 없어 현재는 취소할 수 없습니다."
};
function explain(message){
 const m=String(message||"").trim();
 const key=Object.keys(readable).find(k=>m.includes(k));
 return key?readable[key]:m||"작업에 실패했습니다.";
}
const apiClient=()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
const currentKst=()=>new Intl.DateTimeFormat("sv-SE",{timeZone:"Asia/Seoul",
 year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date()).replace(",","");
const eligible=(h,r)=>h.sourceMeet===r.sourceMeet
 && Array.isArray(r.eligibleHorseIds)&&r.eligibleHorseIds.includes(h.id)
 && h.lifeStage==="RACING"&&!h.retired&&!h.breedingRetired
 && h.health==="HEALTHY"&&h.age>=2&&h.age<=10
 && h.saleState==="NOT_LISTED"&&Number(h.condition)>=50&&Number(h.fatigue)<80;
const entryWindowState=r=>{
 if(r.status!=="OPEN"||!r.kstDate)return "CLOSED";
 const now=currentKst();
 if(r.entryOpenDate&&now<r.entryOpenDate+" 00:00")return "NOT_OPEN";
 if(now.slice(0,10)>=r.kstDate)return "CLOSED";
 return "OPEN";
};
const beforeDeadline=r=>entryWindowState(r)==="OPEN";
export default function EntriesPage(){
 const [token,SetToken]=useState("");
 const [checking,SetChecking]=useState(true);
 const [,SetWindowClock]=useState(0);
 const [board,SetBoard]=useState(null);
 const [week,SetWeek]=useState(null);
 const [track,SetTrack]=useState("전체");
 const [view,SetView]=useState("신청 가능");
 const [choice,SetChoice]=useState({});
 const [busy,SetBusy]=useState(false);
 const [loading,SetLoading]=useState(false);
 const [message,SetMessage]=useState("");
 const [error,SetError]=useState("");
 const [active,SetActive]=useState(null);
 const [jockeys,SetJockeys]=useState([]);
 const [jockeyChoice,SetJockeyChoice]=useState("");
 const [jockeyBusy,SetJockeyBusy]=useState(false);
 const [strategyFocus,SetStrategyFocus]=useState(null);
 const [strategyChoices,SetStrategyChoices]=useState({});
 const [strategyBusy,SetStrategyBusy]=useState(false);
 const strategyOptions=[["FRONT","도주"],["PRESS","선입"],["SAVE","절약"],["MOVE","중반 무빙"],["CLOSER","추입"],["FREE","자유형"]];
 const defaultPlans=["SAVE","MOVE","CLOSER"];
 const submitStrategies=async(raceId,horseId)=>{
  const selected=strategyChoices[horseId]||defaultPlans;
  SetStrategyBusy(true);SetMessage("");
  try{
   const res=await fetch("/api/player/strategies",{method:"POST",cache:"no-store",
    headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},
    body:JSON.stringify({raceId,horseId,strategies:selected})});
   const body=await res.json();if(!res.ok)throw new Error(body.error||"전략 저장 실패");
   SetMessage("공식 경주 전략 1·2·3안을 저장했습니다. 이 전략이 실제 경주 엔진에 입력됩니다.");
   SetStrategyFocus(null);await load(week);
  }catch(e){SetMessage(explain(e.message));}
  finally{SetStrategyBusy(false)}
 };


 useEffect(()=>{
  let live=true;
  let client;
  try{
   client=apiClient();
   client.auth.getSession().then(({data})=>{
    if(live){SetToken(data.session?.access_token||"");SetChecking(false)}
   }).catch(e=>{if(live){SetError(explain(e.message));SetChecking(false)}});
  }catch(e){SetError("Supabase 설정이 없습니다.");SetChecking(false);return}
  const {data:{subscription}}=client.auth.onAuthStateChange((_event,session)=>{
   if(live)SetToken(session?.access_token||"");
  });
  return()=>{live=false;subscription.unsubscribe()};
 },[]);
 useEffect(()=>{
  const timer=setInterval(()=>SetWindowClock(v=>v+1),30000);
  return()=>clearInterval(timer);
 },[]);

 const load=async(w,accessToken=token)=>{
  if(!accessToken)return;
  SetLoading(true);
  try{
   const url="/api/player/entries"+(w===null?"":"?week="+w);
   const r=await fetch(url,{headers:{Authorization:"Bearer "+accessToken},cache:"no-store"});
   const data=await r.json();
   if(!r.ok)throw new Error(data.error||"경주 조회 실패");
   SetBoard(data);SetWeek(data.week);SetError("");
  }catch(e){SetError(explain(e.message))}
  finally{SetLoading(false)}
 };
 useEffect(()=>{if(token)void load(week,token)},[token,week]);

 const submitEntry=async(race,horseId)=>{
  if(!horseId)return SetMessage("경주마를 선택해주세요.");
  if(!beforeDeadline(race))return SetMessage("출전 신청 기간이 아닙니다. 경주 당일에는 신청할 수 없으며 OPEN·대상경주는 4일 전, 일반 경주는 2일 전부터 접수합니다.");
  if(!window.confirm("선택한 경주에 공식 출전 신청하시겠습니까? 만석이면 NPC 출전 슬롯을 교체합니다."))return;
  SetBusy(true);SetMessage("");
  try{
   const r=await fetch("/api/player/entries",{method:"POST",cache:"no-store",
    headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},
    body:JSON.stringify({raceId:race.id,horseId})});
   const data=await r.json();if(!r.ok)throw new Error(data.error||"신청 실패");
   SetMessage(data.status==="ALREADY_CONFIRMED"?"이미 출전 확정된 경주입니다.":
     "출전 확정! "+race.track+" "+race.raceNo+"경주 · "+data.gateNo+"번 게이트 · 기수는 기본 배정되었습니다.");
   await load(week);
  }catch(e){SetMessage(explain(e.message))}finally{SetBusy(false)}
 };
 const withdrawEntry=async(raceId,horseId)=>{
  if(!window.confirm("공식 출전을 취소하시겠습니까? 신청금이 납부된 경우 전액 환불되고 NPC 출전마로 대체됩니다."))return;
  SetBusy(true);SetMessage("");
  try{
   const r=await fetch("/api/player/entries",{method:"DELETE",cache:"no-store",
    headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},
    body:JSON.stringify({raceId,horseId})});
   const data=await r.json();if(!r.ok)throw new Error(data.error||"출전 취소 실패");
   SetMessage("출전 취소 완료 · 신청금 "+new Intl.NumberFormat("ko-KR").format(data.refund||0)+
    " G 환급 · NPC 출전마가 기존 게이트로 복구됐습니다.");
   SetActive(null);SetStrategyFocus(null);await load(week);
  }catch(e){SetMessage(explain(e.message))}finally{SetBusy(false)}
 };
 const showJockeys=async(raceId,horseId)=>{
  SetJockeyBusy(true);SetMessage("");SetActive({raceId,horseId});
  try{
   const url="/api/player/jockeys?raceId="+encodeURIComponent(raceId)+"&horseId="+encodeURIComponent(horseId);
   const r=await fetch(url,{headers:{Authorization:"Bearer "+token},cache:"no-store"});
   const data=await r.json();if(!r.ok)throw new Error(data.error||"기수 조회 실패");
   SetJockeys(data.jockeys||[]);
   const first=(data.jockeys||[]).find(j=>j.selected)||
      (data.jockeys||[]).find(j=>!j.busyInRace&&j.dailyRides<j.maxDailyRides);
   SetJockeyChoice(first?.id||"");
  }catch(e){SetJockeys([]);SetMessage(explain(e.message))}
  finally{SetJockeyBusy(false)}
 };
 const submitJockey=async()=>{
  if(!active||!jockeyChoice)return;
  SetJockeyBusy(true);SetMessage("");
  try{
   const r=await fetch("/api/player/jockeys",{method:"POST",cache:"no-store",
    headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},
    body:JSON.stringify({raceId:active.raceId,horseId:active.horseId,jockeyId:jockeyChoice})});
   const data=await r.json();if(!r.ok)throw new Error(data.error||"기수 신청 실패");
   if(data.status==="REJECTED"){
    SetMessage("기수 신청 거절: "+data.jockeyName+" · "+(data.reason==="ALREADY_DECLINED_THIS_RACE"?"이미 거절한 기수입니다.":"기수 성향에 따른 수락 가능성 "+data.acceptanceChance+"%")+
     " · 다른 기수에게 신청할 수 있습니다.");
    return;
   }
   SetMessage("기수 신청 승인: "+data.jockeyName+" · 이번 게임 날짜 "+data.dailyRidesAfter+"/"+data.maxDailyRides+"회");
   SetActive(null);SetJockeys([]);await load(week);
  }catch(e){SetMessage(explain(e.message))}finally{SetJockeyBusy(false)}
 };
 const horses=board?.horses||[];
 const races=(board?.races||[]).filter(r=>{
  if(track!=="전체"&&r.track!==track)return false;
  const hasMine=(r.myEntries||[]).length>0;
  const can=beforeDeadline(r)&&(r.npcReplaceableCount>0||r.confirmedCount<r.capacity)
    &&horses.some(h=>eligible(h,r));
  if(view==="내 출전")return hasMine;
  if(view==="연령 조건 확인")return r.isSpecialRace;
  if(view==="신청 예정")return entryWindowState(r)==="NOT_OPEN"&&horses.some(h=>eligible(h,r));
  if(view==="신청 가능")return can||hasMine;
  return true;
 });

 return <main className="shell"><header className="header">
  <a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a>
  <span className="coin">🏇 출전 · 기수 신청</span></header>
  <div className="area">
   <a href="/world" className="outline" style={{display:"inline-block",marginBottom:12,textDecoration:"none"}}>‹ 월드 화면</a>
   <a href="/schedule" className="outline" style={{display:"inline-block",marginBottom:12,marginLeft:8,textDecoration:"none"}}>공식 시간표 ›</a>
   <div className="section"><h2>출전 및 기수 신청</h2><button onClick={()=>load(week)} disabled={!token||loading}>새로고침 ↻</button></div>
   <div className="notice">실제 공식 경주 편성에 저장됩니다. 신청과 기수 선택은 조건 충족 시 즉시 승인되며,
   기존 NPC 출전으로 만석이면 NPC 슬롯을 1개 교체합니다.
   일반 경주는 경주마와 소속 지역·등급이 같아야 신청할 수 있습니다.
   OPEN·대상경주는 소속 지역 및 해당 경주의 ageCond(연령 조건)를 충족하면 등급과 관계없이 신청할 수 있습니다.
   OPEN·대상경주는 4일 전, 일반 경주는 2일 전 00:00(한국시간)부터 신청 가능하며, 경주 당일에는 신청할 수 없습니다.
   ageCond가 확인되지 않은 OPEN·대상경주는 조건 등록 전까지 출전 신청을 제한합니다.
   건강·피로도 및 중복 출전 제한은 유지합니다.
   기수는 경주당 한 마리, 게임 날짜당 최대 8회까지 기승할 수 있습니다.</div>
   {message&&<div className="notice" role="status">{message}</div>}
   {error&&<div className="notice" role="alert">{error}</div>}
   {checking&&<div className="notice">로그인 상태 확인 중…</div>}
   {!checking&&!token&&<div className="card">
    <b>마주 계정 로그인이 필요합니다.</b>
    <div className="muted">월드에서 로그인·마주 등록을 완료한 후 출전 신청할 수 있습니다.</div>
    <a href="/world" className="primary" style={{display:"inline-block",marginTop:12,textDecoration:"none"}}>월드에서 로그인하기 ›</a>
   </div>}
   {board&&<><div className="card">
    <div className="row"><div><b className="large gold">{week}주차 공식 경주</b>
    <div className="muted">현재 {board.currentWeek}주차 · 내 경주마 {horses.length}두 · 선택한 주의 편성</div></div>
    <span className="tag">{board.races.length}경주</span></div>
    <div className="controls" style={{marginTop:12}}>
     <button className="outline" disabled={busy||week<=board.currentWeek} onClick={()=>{SetWeek(w=>w-1);SetActive(null)}}>‹ 이전 주</button>
     <button className="outline" disabled={busy||week>=52} onClick={()=>{SetWeek(w=>w+1);SetActive(null)}}>다음 주 ›</button>
    </div>
    <div className="muted" style={{marginTop:10}}>신청 가능한 경주가 없다면 다음 주차 또는 ‘연령 조건 확인’ 탭을 확인하세요.</div>
   </div>
   <div className="tabs">{["전체","서울","부산","영천"].map(x=><button key={x} className={track===x?"active":""} onClick={()=>SetTrack(x)}>{x}</button>)}</div>
   <div className="tabs">{["신청 가능","신청 예정","연령 조건 확인","내 출전","전체 경주"].map(x=><button key={x} className={view===x?"active":""} onClick={()=>SetView(x)}>{x}</button>)}</div>
   {loading&&<div className="notice">공식 경주 정보를 확인하는 중…</div>}
   {!races.length&&!loading&&<div className="notice">이 조건에 해당하는 경주가 없습니다. 주차 또는 필터를 변경하세요.</div>}
   {races.map(r=>{
    const mine=r.myEntries||[];
    const candidate=horses.filter(h=>eligible(h,r)&&!board.races.some(other=>
     other.id!==r.id&&(other.myEntries||[]).some(e=>e.horseId===h.id)))
     .sort((a,b)=>a.name.localeCompare(b.name,"ko"));
    const windowState=entryWindowState(r);
    const close=windowState!=="OPEN";
    const room=r.npcReplaceableCount>0||r.confirmedCount<r.capacity;
    const selected=candidate.some(h=>h.id===choice[r.id])?choice[r.id]:candidate[0]?.id||"";
    return <div className="card" key={r.id}>
     <div className="row"><div><b className="gold">{r.kstDate} {r.startTime} · {r.track} {r.raceNo}경주</b>
       <div className="muted">{r.grade} · {r.distance}m · {r.confirmedCount}/{r.capacity}두</div></div>
       <span className="tag">{r.status==="FINISHED"?"종료":r.isSpecialRace&&!r.ageCondValid?"연령 조건 미등록":windowState==="NOT_OPEN"?"접수 예정":close?"신청 마감":"신청 가능"}</span></div>
     <div className="muted" style={{marginTop:8}}>접수 시작 {r.entryOpenDate} 00:00 ({r.isSpecialRace?"OPEN·대상 4일 전":"일반 2일 전"}) · 마감 {r.kstDate} 00:00 (경주 당일 신청 금지, 한국시간)</div>
     {r.isSpecialRace&&<div className="notice" style={{marginTop:8,fontSize:12}}>
      대상경주 출전 연령 조건(ageCond): <b>{r.ageCondValid?r.ageCond:"확인되지 않음"}</b>
      {!r.ageCondValid&&" · 정확한 원본 경주 연령 조건이 등록될 때까지 신청할 수 없습니다."}
      {r.ageCondValid&&" · 소속 지역 및 연령 조건을 충족하면 등급 제한 없이 신청할 수 있습니다."}
      {r.ageCondRequiresBirthHemisphere&&<span style={{display:"block",marginTop:4}}>
       ※ 남·북반구 출생마에 따라 나이 자격이 달라집니다. 출생 반구가 확인되지 않은 말은 출전할 수 없습니다.
       </span>}
     </div>}
     <div className="muted" style={{marginTop:4}}>지역 {r.track} · 등급 {r.gradeNo} · NPC 교체 가능 {r.npcReplaceableCount}두</div>
     {mine.map(e=><div key={e.horseId} className="card" style={{padding:12,marginTop:12}}>
      <div className="row"><div><b>✓ {horses.find(h=>h.id===e.horseId)?.name||"내 경주마"} 출전 확정</b>
        <div className="muted">{e.gateNo}번 게이트 · 현재 기수 {e.jockeyName||"미배정"}</div></div>
       <div className="controls">
        <button className="outline" disabled={close||busy||jockeyBusy}
         onClick={()=>showJockeys(r.id,e.horseId)}>기수 선택 ›</button>
        <button className="outline" disabled={close||busy||strategyBusy}
         onClick={()=>SetStrategyFocus(strategyFocus===e.horseId?null:e.horseId)}>
         전략 1·2·3안 ›</button>
        <button className="outline" disabled={close||busy||strategyBusy||jockeyBusy}
         onClick={()=>withdrawEntry(r.id,e.horseId)}>출전 취소</button>
       </div></div>
      {strategyFocus===e.horseId&&
       <div style={{marginTop:12}}>
        <div className="muted">선택한 세 가지 전개 전략은 실제 공식 경주 엔진에 저장됩니다.</div>
        {(strategyChoices[e.horseId]||defaultPlans).map((v,index)=>
          <div className="row" key={index}>
           <label className="muted" style={{minWidth:60}}>{index+1}안</label>
           <select className="field" value={v} onChange={event=>{
             const next=[...(strategyChoices[e.horseId]||defaultPlans)];
             next[index]=event.target.value;SetStrategyChoices(old=>({...old,[e.horseId]:next}));
           }}>{strategyOptions.map(([code,name])=><option key={code} value={code}>{name}</option>)}</select>
          </div>)}
        <button className="primary wide" disabled={strategyBusy}
          onClick={()=>submitStrategies(r.id,e.horseId)}>{strategyBusy?"저장 중…":"공식 경주 전략 저장"}</button>
       </div>}
      {active?.raceId===r.id&&active?.horseId===e.horseId&&
       <div style={{marginTop:14}}>
        <div className="muted">NPC 기수에게 신청하면 기수의 성향·기승일정에 따라 수락 또는 거절됩니다.</div>
        <select className="field" aria-label="기수 선택" value={jockeyChoice} onChange={e=>SetJockeyChoice(e.target.value)}>
         {jockeys.map(j=><option key={j.id} value={j.id} disabled={!j.selected&&(j.busyInRace||j.dailyRides>=j.maxDailyRides)}>
          {j.name} · {j.dailyRides}/{j.maxDailyRides}회 {j.busyInRace?"(해당 경주 기승 중)":""}
         </option>)}
        </select>
        <div className="controls">
         <button className="primary" disabled={jockeyBusy||!jockeyChoice} onClick={submitJockey}>{jockeyBusy?"처리 중…":"기수 신청 확정"}</button>
         <button className="outline" onClick={()=>SetActive(null)}>닫기</button>
        </div>
       </div>}
     </div>)}
     {!close&&room&&candidate.length>0&&
      <div style={{marginTop:14}}>
       <label className="muted">출전 경주마 선택</label>
       <select className="field" aria-label="출전마 선택"
        value={selected} onChange={e=>SetChoice(prev=>({...prev,[r.id]:e.target.value}))}>
        {candidate.map(h=><option key={h.id} value={h.id}>
         {h.name} · {h.age}세 · {h.sourceMeet==="제주"?"영천":h.sourceMeet} {h.gradeNo}등급
         {r.ageCondRequiresBirthHemisphere&&(" · "+(h.birthHemisphere==="NORTH"?"북반구 출생":h.birthHemisphere==="SOUTH"?"남반구 출생":"출생 반구 미확인"))}
        </option>)}
       </select>
       <button className="primary wide" disabled={busy||loading} onClick={()=>submitEntry(r,selected)}>
        {busy?"처리 중…":"공식 출전 신청"}
       </button>
      </div>}
     {!mine.length&&(!room||close||!candidate.length)&&<div className="muted" style={{marginTop:12}}>
      {r.isSpecialRace&&!r.ageCondValid?"원본 ageCond 연령 조건이 등록되지 않아 출전 신청할 수 없습니다.":windowState==="NOT_OPEN"?"접수 대기: "+r.entryOpenDate+" 00:00부터 출전 신청할 수 있습니다.":close?"신청 기간 종료: 경주 당일에는 출전 신청할 수 없습니다.":!room?"출전 정원이 가득 찼습니다.":r.isSpecialRace?(r.ageCondRequiresBirthHemisphere?
 "경주마의 출생 반구(남/북)를 확인해야 합니다. 반구 정보가 없거나 연령 조건을 충족하지 않는 말은 신청할 수 없습니다.":
 "소속 지역·ageCond·건강 조건을 충족하는 말이 없습니다."):"같은 지역·등급이며 건강 조건을 충족하는 경주마만 신청 가능합니다."}</div>}
    </div>;
   })}
   </>}
   <div className="footer">MY DERBY · 공식 출전 및 NPC 기수 신청 · 기록은 DB에 저장</div>
  </div>
 </main>
}
