"use client";
import {useCallback,useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";

const errors={
 LOGIN_REQUIRED:"로그인 후 신청할 수 있습니다.",
 JOIN_WORLD_FIRST:"먼저 월드에 참가해주세요.",
 MARE_NOT_OWNED:"본인 소유 암말만 교배할 수 있습니다.",
 MARE_NOT_ELIGIBLE:"암말의 나이·은퇴 상태·건강·임신 여부를 확인해주세요.",
 SIRE_NOT_AVAILABLE:"해당 씨수말은 현재 이용할 수 없습니다.",
 SIRE_NOT_ELIGIBLE:"씨수말의 상태가 번식 조건에 맞지 않습니다.",
 MARE_ALREADY_PREGNANT:"이미 임신 중인 암말입니다.",
 MARE_SEASON_LIMIT:"이번 시즌에는 이미 이 암말의 교배를 신청했습니다.",
 SIRE_SEASON_LIMIT:"이 씨수말은 이번 시즌 예약 한도에 도달했습니다.",
 CLOSE_INBREEDING_PROHIBITED:"가까운 혈연관계여서 교배할 수 없습니다.",
 BREEDING_PAIR_INVALID:"서로 다른 씨수말과 암말을 선택하세요.",
 BREEDING_AGE_OR_SEX_INELIGIBLE:"번식용 은퇴는 암말 4~18세, 수말 2세 이상만 가능합니다.",
 ACTIVE_RACE_ENTRY:"출전 신청 중인 말은 번식마로 은퇴시킬 수 없습니다.",
 ALREADY_PERMANENTLY_RETIRED:"이미 영구 은퇴한 말입니다.",
 HORSE_NOT_OWNED:"다른 마주의 말은 변경할 수 없습니다."
};
function messageOf(msg){
 const text=String(msg||"처리 실패");
 const token=Object.keys(errors).find(x=>text.includes(x));
 return token?errors[token]:text;
}
function dateOf(v){try{return new Date(v).toLocaleDateString("ko-KR",{timeZone:"Asia/Seoul"})}catch{return "-";}}
const fmt=n=>Number(n||0).toFixed(1);
const status={APPROVED:"임신 성공",REJECTED:"임신 실패",COMPLETED:"출산 완료",PENDING:"심사 중",CANCELLED:"취소"};
const babyStatus={PREGNANT:"임신 중",BORN:"출산 완료",FAILED:"임신 종료"};
function gender(sex){return {FEMALE:"암",MALE:"수",GELDING:"거"}[sex]||sex;}

export default function BreedingPage(){
 const [token,SetToken]=useState("");
 const [checking,SetChecking]=useState(true);
 const [board,SetBoard]=useState(null);
 const [mareId,SetMareId]=useState("");
 const [sireId,SetSireId]=useState("");
 const [preview,SetPreview]=useState(null);
 const [busy,SetBusy]=useState("");
 const [loading,SetLoading]=useState(false);
 const [error,SetError]=useState("");
 const [notice,SetNotice]=useState("");

 useEffect(()=>{
  let active=true;let client;
  try{client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,
   process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);}
  catch{SetError("Supabase 접속 설정이 없습니다.");SetChecking(false);return;}
  client.auth.getSession().then(({data,error})=>{
   if(!active)return;
   SetToken(data.session?.access_token||"");
   if(error)SetError(error.message);
   SetChecking(false);
  }).catch(e=>{if(active){SetError(messageOf(e.message));SetChecking(false);}});
  const {data:{subscription}}=client.auth.onAuthStateChange((_event,session)=>{
   if(active)SetToken(session?.access_token||"");
  });
  return()=>{active=false;subscription.unsubscribe();};
 },[]);

 const reload=useCallback(async(access=token)=>{
  if(!access)return;
  SetLoading(true);
  try{
   const res=await fetch("/api/player/breeding",{cache:"no-store",
    headers:{Authorization:"Bearer "+access}});
   const data=await res.json();
   if(!res.ok)throw new Error(data.error||"번식정보 조회 실패");
   SetBoard(data);
   SetMareId(value=>(data.mares||[]).some(m=>m.id===value)?value:data.mares?.find(m=>m.sex==="FEMALE")?.id||"");
   SetSireId(value=>(data.sires||[]).some(s=>s.id===value)?value:data.sires?.[0]?.id||"");
   SetError("");
  }catch(e){SetError(messageOf(e.message));}
  finally{SetLoading(false);}
 },[token]);
 useEffect(()=>{if(token)void reload(token);else{SetBoard(null);SetPreview(null);}},[token,reload]);
 const female=useMemo(()=>(board?.mares||[]).filter(m=>m.sex==="FEMALE"),[board]);
 const stallions=board?.sires||[];
 const mare=female.find(m=>m.id===mareId);
 const sire=stallions.find(s=>s.id===sireId);
 const requests=board?.requests||[];
 const pregnant=requests.filter(r=>r.pregnancy?.status==="PREGNANT");
 const past=requests.filter(r=>r.pregnancy?.status!=="PREGNANT");
 const canRetire=(h)=>
  !h.retired&&h.stage==="RACING"&&h.health==="HEALTHY"&&
  (h.sex==="FEMALE"&&h.age>=4&&h.age<=18||
   h.sex==="MALE"&&h.age>=4);
 const send=async(body)=>{
  SetBusy(body.action);SetNotice("");SetError("");
  try{
   const res=await fetch("/api/player/breeding",{method:"POST",cache:"no-store",
    headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},
    body:JSON.stringify(body)});
   const data=await res.json();
   if(!res.ok)throw new Error(data.error||"작업 실패");
   if(body.action==="PREVIEW"){
    SetPreview(data);
    return;
   }
   if(body.action==="RETIRE"){
    SetNotice("번식용 영구 은퇴가 완료되었습니다. 이 말은 다시 경주에 출전할 수 없습니다.");
   }else if(data.status==="PREGNANT"){
    SetNotice("교배 신청 결과: 임신 성공! 게임 "+data.dueGameDay+
      "일에 출산 예정입니다. 임신 기간은 게임 330일입니다.");
   }else{
    SetNotice("교배 신청 결과: 임신하지 못했습니다. 이 암말은 다음 시즌에 다시 신청할 수 있습니다.");
   }
   SetPreview(null);
   await reload(token);
  }catch(e){SetError(messageOf(e.message))}
  finally{SetBusy("");}
 };
 const retire=(h)=>{
  if(!window.confirm(h.name+"을(를) 번식마로 영구 은퇴시키겠습니까?\n은퇴하면 경주마로 다시 복귀할 수 없습니다."))return;
  if(!window.confirm("최종 확인: "+h.name+"의 현역 복귀가 영구적으로 불가능해집니다. 계속하시겠습니까?"))return;
  void send({action:"RETIRE",horseId:h.id});
 };
 const apply=()=>{
  if(!mare?.canMate||!sire)return;
  if(!preview)return SetError("신청 전 교배 궁합을 먼저 확인해주세요.");
  if(!window.confirm(
   mare.name+" × "+sire.name+" 교배를 신청하시겠습니까?\n"+
   "이번 시즌 이 암말은 1회만 신청할 수 있습니다. 임신이 실패해도 재신청은 다음 시즌부터 가능합니다.\n"+
   "추정 임신 확률: "+preview.chance+"%"))return;
  void send({action:"APPLY",mareId,sireId});
 };
 const changeMare=e=>{SetMareId(e.target.value);SetPreview(null)};
 const changeSire=e=>{SetSireId(e.target.value);SetPreview(null)};
 return <main className="shell"><header className="header">
  <a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a>
  <span className="coin">✧ 교배 · 임신</span></header>
  <div className="area">
   <div className="controls" style={{marginBottom:16}}>
    <a href="/world" className="outline" style={{textDecoration:"none",textAlign:"center"}}>‹ 내 경주마</a>
    <button className="outline" disabled={!token||loading||!!busy} onClick={()=>reload()}>정보 새로고침 ↻</button>
   </div>
   <div className="section"><h2>번식 관리</h2><span className="tag">실제 DB 연동</span></div>
   <div className="notice"><b>암말 4~18세 / 수말 4세 이상</b> · 번식마 영구 은퇴 후 교배할 수 있습니다.
    암말은 시즌당 교배 신청 최대 1회, 씨수말은 시즌당 최대 40회이며
    임신에 성공하면 <b>게임 330일</b> 후 출산합니다. 매일 09:15(한국시간)에 출산 대상이 자동 처리됩니다.
    교배 수수료는 경제 시스템 연동 전까지 부과되지 않습니다.</div>
   {checking&&<div className="notice">로그인 확인 중…</div>}
   {error&&<div className="notice" role="alert">⚠ {error}</div>}
   {notice&&<div className="notice" role="status">✓ {notice}</div>}
   {!checking&&!token&&<div className="card"><b>로그인이 필요합니다.</b>
    <div className="muted">월드에서 로그인하고 마주 등록을 완료하면 교배 신청할 수 있습니다.</div>
    <a href="/world" className="primary" style={{display:"inline-block",textDecoration:"none",marginTop:10}}>월드에서 로그인 ›</a></div>}
   {loading&&!board&&<div className="notice">실제 번식마 목록을 불러오는 중…</div>}
   {board&&<>
    <div className="card row"><div><b className="gold">시즌 {board.world?.season} · {board.world?.week}주차</b>
      <div className="muted">이번 주 게임 {board.world?.gameDayStart}~{Number(board.world?.gameDayStart||0)+6}일</div></div>
     <span className="tag">{pregnant.length}두 임신 중</span></div>

    <div className="section"><h2>교배 신청</h2></div>
    <div className="card">
     <label className="muted" htmlFor="mare">내 번식암말</label>
     <select id="mare" className="field" value={mareId} onChange={changeMare}>
      {!female.length&&<option value="">보유 암말이 없습니다</option>}
      {female.map(m=><option key={m.id} value={m.id}>{m.name} · {m.age}세 · {m.canMate?"신청 가능":m.stage==="BROODMARE"?"이번 시즌/임신 상태 확인":"은퇴·나이 조건 확인"}</option>)}
     </select>
     {mare&&<div className="muted">
      현재 {mare.age}세 · {mare.stage==="BROODMARE"?"번식암말":mare.stage==="RACING"?"현역 경주마":mare.stage}
      · {mare.canMate?"✓ 신청 가능":"교배 신청 불가"}
     </div>}
     <label className="muted" htmlFor="sire" style={{display:"block",marginTop:14}}>시스템/NPC 씨수말 선택</label>
     <select id="sire" className="field" value={sireId} onChange={changeSire}>
      {!stallions.length&&<option value="">이용 가능한 씨수말이 없습니다</option>}
      {stallions.map(s=><option key={s.id} value={s.id} disabled={s.booked>=40}>
       {s.name} · {s.age}세 · 시즌 예약 {s.booked}/40회
      </option>)}
     </select>
     {sire&&<div className="muted">추정 유전 능력 · 스피드 {sire.geneSummary?.speed??"-"} /
      지구력 {sire.geneSummary?.stamina??"-"} /
      막판탄력 {sire.geneSummary?.finishing??"-"}
     </div>}
     <div className="controls" style={{marginTop:15}}>
      <button className="outline" disabled={!mareId||!sireId||!!busy}
       onClick={()=>send({action:"PREVIEW",mareId,sireId})}>
       {busy==="PREVIEW"?"검사 중…":"혈통·궁합 확인"}</button>
      <button className="primary" disabled={!mare?.canMate||!preview||!!busy||!sire||sire.booked>=40}
       onClick={apply}>교배 신청 확정</button>
     </div>
     {preview&&<div className="notice">
      <b>혈통·궁합 검사 결과</b><br/>
      적합도 <b>{fmt(preview.compatibility)}점</b> · 추정 임신 확률 <b>{fmt(preview.chance)}%</b><br/>
      알려진 공통조상에 의한 근친 계수 추정: {fmt(Number(preview.knownInbreeding||0)*100)}%
      {preview.pedigreeIncomplete&&<div className="muted">⚠ 혈통 정보가 불완전합니다. 근친 계수 0은 무혈연을 의미하지 않으며, 이 평가는 추정값입니다.</div>}
      {!mare?.canMate&&<div className="muted">현재 암말은 교배 신청 조건을 충족하지 못했습니다.</div>}
     </div>}
     {!mare?.canMate&&female.length>0&&<div className="muted" style={{marginTop:10}}>
       암말이 4세 이상이 되고 번식암말로 영구 은퇴한 뒤 신청할 수 있습니다.</div>}
    </div>

    <div className="section"><h2>임신 현황</h2><span className="tag">{pregnant.length}건</span></div>
    {!pregnant.length&&<div className="notice">현재 임신 중인 암말이 없습니다.</div>}
    {pregnant.map(r=><div className="card" key={r.id}>
     <div className="row"><b className="gold">{r.mareName}</b><span className="tag">🤰 임신 중</span></div>
     <div className="muted">{r.sireName} 교배 · 임신 게임 {r.conceivedGameDay}일</div>
     <div className="line row small"><span>출산 예정</span><b>게임 {r.pregnancy.dueGameDay}일</b></div>
     <div className="row small"><span>남은 기간</span><b>{r.pregnancy.daysRemaining}게임일 · 약 {Math.ceil(r.pregnancy.daysRemaining/7)}현실일</b></div>
     <div className="bar"><div className="fill" style={{width:Math.max(0,Math.min(100,(1-r.pregnancy.daysRemaining/330)*100))+"%"}}/></div>
    </div>)}

    <div className="section"><h2>교배·출산 이력</h2><span className="tag">{past.length}건</span></div>
    {!past.length&&<div className="notice">아직 완료되거나 실패한 교배 이력이 없습니다.</div>}
    {past.map(r=><div className="card" key={r.id}>
     <div className="row"><b className="gold">{r.mareName} × {r.sireName}</b><span className="tag">{status[r.status]||r.status}</span></div>
     <div className="muted">{dateOf(r.createdAt)} · 시즌 {r.season} · 궁합 {fmt(r.compatibility)}점</div>
     {r.pregnancy?.status==="BORN"&&<div className="line">🐴 자마 출산 완료 · 보유마 목록에 자동 추가됨</div>}
     {r.status==="REJECTED"&&<div className="muted" style={{marginTop:8}}>임신 실패 · 다음 시즌 재신청 가능</div>}
    </div>)}

    <div className="section"><h2>번식용 영구 은퇴</h2></div>
    <div className="notice">⚠ 번식용 은퇴는 되돌릴 수 없습니다. 출전 등록된 말은 은퇴할 수 없으며,
    은퇴한 말은 경주에 다시 출전할 수 없습니다. 수말 2~3세도 은퇴 자체는 가능하지만
    씨수말 교배 이용은 4세부터이므로 이 화면에서는 4세 이상만 은퇴 신청을 제공합니다.</div>
    {(board.mares||[]).map(h=><div className="card row" key={h.id}>
     <div><b>{h.name}</b><div className="muted">{h.age}세 · {gender(h.sex)} ·
      {h.stage==="RACING"?"현역":h.stage==="BROODMARE"?"번식암말":h.stage==="STALLION"?"씨수말":h.stage}
      {h.retired?" · 경주 영구 은퇴":""}</div></div>
     {canRetire(h)?<button className="outline" disabled={!!busy} onClick={()=>retire(h)}>
      번식마 은퇴</button>:<span className="tag">{h.retired?"은퇴 완료":"조건 미달"}</span>}
    </div>)}
   </>}
   <div className="footer">MY DERBY · 번식·임신·출산 DB 시스템 · 시스템 씨수말은 실제 KRA 출전마가 아닌 게임용 NPC</div>
  </div>
 </main>;
}
