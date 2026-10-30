"use client";
import HorseLink from "../components/HorseLink";
import StaffLink from "../components/StaffLink";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const origin=()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
const showError=e=>String(e||"신청 오류").replace("NOT_YOUR_HORSE","내 경주마만 신청할 수 있습니다.")
.replace("TRAINER_AT_CAPACITY","조교사의 담당 정원이 가득 찼습니다.")
.replace("TRAINER_TRACK_MISMATCH","경주마의 소속 지역과 조교사 마방 지역이 다릅니다.")
.replace("HORSE_NOT_TRAINABLE","현재 경주마는 위탁할 수 없습니다.")
.replace("TRAINER_UNAVAILABLE","활동 중인 조교사가 아닙니다.")
.replace("TRAINER_OFFER_SCORE_UNAVAILABLE","조교사 선호도 점수를 계산할 수 없습니다.");
const track=meet=>meet==="부산경남"?"부산":meet==="제주"?"영천":meet;
export default function StablePage(){
 const [token,T]=useState(""),[loaded,Loaded]=useState(false),[data,D]=useState(null),
 [horse,H]=useState(""),[trainer,N]=useState(""),[error,E]=useState(""),[msg,M]=useState(""),[busy,B]=useState(false);
 useEffect(()=>{
  let active=true;let client;
  try{client=origin()}catch{E("로그인 설정을 확인해주세요.");Loaded(true);return}
  client.auth.getSession().then(({data})=>{if(active){T(data.session?.access_token||"");Loaded(true)}})
   .catch(e=>{if(active){E(e.message);Loaded(true)}});
  const {data:{subscription}}=client.auth.onAuthStateChange((_e,s)=>{if(active)T(s?.access_token||"")});
  return()=>{active=false;subscription.unsubscribe()};
 },[]);
 const reload=async(access=token)=>{
  if(!access)return;
  try{const r=await fetch("/api/player/stable",{headers:{Authorization:"Bearer "+access},cache:"no-store"});
   const body=await r.json();if(!r.ok)throw new Error(body.error);
   D(body);H(v=>body.horses.some(h=>h.id===v)?v:body.horses[0]?.id||"");E("");
  }catch(e){E(showError(e.message))}
 };
 useEffect(()=>{if(token)void reload(token)},[token]);
 const horseData=data?.horses?.find(h=>h.id===horse);
 const trainers=(data?.trainers||[]).filter(t=>horseData&&t.track===track(horseData.sourceMeet));
 const selected=trainers.find(t=>t.id===trainer)||trainers.find(t=>t.occupied<t.capacity);
 const apply=async()=>{
  if(!horse||!selected)return;B(true);E("");M("");
  try{const r=await fetch("/api/player/stable",{method:"POST",
   headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},
   body:JSON.stringify({horseId:horse,trainerId:selected.id})});
   const v=await r.json();if(!r.ok)throw new Error(v.error);
   M(v.status==="PENDING"?(v.reason==="ALREADY_PENDING"?"이미 조교사 "+v.trainerName+"에게 위탁 신청 중입니다.":"조교사 "+v.trainerName+"에게 위탁 신청을 접수했습니다. 현재 경쟁 신청 "+(v.competingOffers||1)+"건 · 정기 심사에서 선호도에 따라 선정됩니다."):
     v.status==="ALREADY_CONTRACTED"?"이미 해당 조교사와 위탁 계약 중입니다.":
     v.reason==="TRAINER_AT_CAPACITY"?"조교사 "+v.trainerName+"의 위탁 정원이 가득 찼습니다. 다른 조교사를 신청하세요.":
     v.reason==="ALREADY_REJECTED_TODAY"?"오늘 이미 심사에서 거절된 조교사입니다. 다른 조교사를 신청하세요.":
     "신청이 수락되지 않았습니다. 다른 조교사에게 재신청할 수 있습니다.");
   await reload();
  }catch(e){E(showError(e.message))}
  finally{B(false)}
 };
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🏠 조교사 위탁</span></header>
  <div className="area">
   <div className="controls" style={{marginBottom:12}}><a className="outline" href="/world" style={{textDecoration:"none"}}>‹ 마방</a>
    <a className="outline" href="/training" style={{textDecoration:"none"}}>훈련 관리 ›</a></div>
   <div className="section"><h2>조교사 위탁 제안 · 심사</h2><button onClick={()=>reload()} disabled={!token||busy}>새로고침 ↻</button></div>
   <div className="notice">마주가 조교사에게 위탁을 제안하면 즉시 확정되지 않고 신청 목록에 접수됩니다.
    조교사는 경주마 능력(40점) · 전문 분야 궁합(25점) · 과거 협업(5점) · 마주와의 친밀도·신뢰도(10점) · 등급(10점) · 조교사 역량(10점)을 비교하여
    남은 정원 안에서 선호하는 경주마를 선택합니다. 경주마 기본 능력 차이가 8점 이상이면 뛰어난 말을 우선 선택하며, 친밀도 100도 계약을 보장하지 않습니다. 매일 09:00~23:50(한국시간) 10분 간격으로 심사합니다.
    신청이 거절되면 다른 조교사를 선택할 수 있습니다. 기존 계약은 새 신청이 승인될 때까지 유지됩니다.
    조교사는 같은 경마장 소속 말만 맡으며, 1인 최대 40두까지 담당합니다.</div>
   {error&&<div className="notice" role="alert">{error}</div>}
   {msg&&<div className="notice" role="status">{msg}</div>}
   {!loaded&&<div className="notice">로그인 확인 중…</div>}
   {loaded&&!token&&<div className="notice">먼저 <a href="/world">월드</a>에서 로그인해주세요.</div>}
   {data&&<><div className="card">
    <div className="section"><h2>보유 경주마 선택</h2></div>
    <select className="field" value={horse} onChange={e=>{H(e.target.value);N("");M("")}}>
     {data.horses.map(h=><option key={h.id} value={h.id}>{h.name} · {track(h.sourceMeet)} · {h.age}세</option>)}
    </select>
    {horse&&<div className="muted" style={{marginBottom:9}}><HorseLink horseId={horse}>선택한 경주마 기본정보 ›</HorseLink></div>}
    {horseData&&<div className="muted">현재 담당 조교사: <StaffLink kind="trainer" staffId={horseData.trainerId}>{horseData.trainerName||"미계약"}</StaffLink>
     {horseData.trainerId?" · 이해도 "+horseData.familiarity+"/100":""}
    </div>}
    {horseData?.trainerOfferStatus==="PENDING"&&<div className="notice" role="status" style={{marginTop:9}}>⌛ <StaffLink kind="trainer" staffId={horseData.trainerOfferId}>{horseData.trainerOfferName}</StaffLink> 조교사에게 신청 접수 · 선호도 심사 대기 중</div>}
    {horseData?.trainerOfferStatus==="ACCEPTED"&&<div className="muted" style={{color:"#91d8ad",marginTop:9}}>✓ <StaffLink kind="trainer" staffId={horseData.trainerOfferId}>{horseData.trainerOfferName}</StaffLink> 조교사 위탁 신청 승인</div>}
    {horseData?.trainerOfferStatus==="REJECTED"&&<div className="muted" style={{color:"#f0c572",marginTop:9}}>위탁 신청 거절 · 다른 조교사에게 신청할 수 있습니다.</div>}
    <div className="section"><h2>조교사 선택</h2></div>
    <select className="field" value={selected?.id||""} onChange={e=>N(e.target.value)}>
     {trainers.map(t=><option key={t.id} value={t.id} disabled={t.occupied>=t.capacity}>
      {t.name} · 친밀도 {t.ownerFamiliarity??0} / 신뢰도 {t.ownerTrust??0} · 담당 {t.occupied}/{t.capacity}두 · 심사대기 {t.pendingOffers||0}건</option>)}
    </select>
    {selected&&<div className="muted" style={{marginTop:12}}>
      나와의 친밀도 {selected.ownerFamiliarity??0}/100 · 신뢰도 {selected.ownerTrust??0}/100 · 관계 점수 {selected.ownerAffinity??0}/100<br/>
      신청 심사 대기: {selected.pendingOffers||0}건 · 잔여 정원: {Math.max(0,selected.capacity-selected.occupied)}두<br/>
      전문 분야: {(selected.specialties||[]).join(" · ")||"종합"}<br/>
      <StaffLink kind="trainer" staffId={selected.id}>{selected.name} 상세정보 보기 ›</StaffLink><br/>
      조교사 능력치: {Object.entries(selected.skills||{}).slice(0,8).map(([k,v])=>k+" "+v).join(" · ")}
    </div>}
    <button className="primary wide" style={{marginTop:16}} disabled={!selected||busy||!horseData||horseData.trainerId===selected.id}
      onClick={apply}>{busy?"신청 접수 중…":"조교사에게 위탁 제안 보내기"}</button>
    </div>
    <div className="section"><h2>현재 내 마방</h2></div>
    {data.horses.map(h=><div className="card row" key={h.id}><b><HorseLink horseId={h.id}>{h.name}</HorseLink></b>
      <span className="tag"><StaffLink kind="trainer" staffId={h.trainerId}>{h.trainerName||"조교사 미계약"}</StaffLink></span></div>)}
    </>}
   <div className="footer">MY DERBY · 실제 조교사 정원 및 계약 DB 연동</div>
  </div>
 </main>
}