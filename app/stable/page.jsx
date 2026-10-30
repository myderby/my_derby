"use client";
import HorseLink from "../components/HorseLink";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const origin=()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
const showError=e=>String(e||"신청 오류").replace("NOT_YOUR_HORSE","내 경주마만 신청할 수 있습니다.")
.replace("TRAINER_AT_CAPACITY","조교사의 담당 정원이 가득 찼습니다.")
.replace("TRAINER_TRACK_MISMATCH","경주마의 소속 지역과 조교사 마방 지역이 다릅니다.")
.replace("HORSE_NOT_TRAINABLE","현재 경주마는 위탁할 수 없습니다.");
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
   M(v.status==="ACCEPTED"?"조교사 "+v.trainerName+" 위탁 계약이 승인됐습니다.":
     v.status==="ALREADY_CONTRACTED"?"이미 계약된 조교사입니다.":
     "조교사가 이번 신청을 거절했습니다. 다른 조교사를 신청할 수 있습니다.");
   await reload();
  }catch(e){E(showError(e.message))}
  finally{B(false)}
 };
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🏠 조교사 위탁</span></header>
  <div className="area">
   <div className="controls" style={{marginBottom:12}}><a className="outline" href="/world" style={{textDecoration:"none"}}>‹ 마방</a>
    <a className="outline" href="/training" style={{textDecoration:"none"}}>훈련 관리 ›</a></div>
   <div className="section"><h2>실제 조교사 계약</h2><button onClick={()=>reload()} disabled={!token||busy}>새로고침 ↻</button></div>
   <div className="notice">NPC 조교사 1명당 최대 40두를 담당합니다. 경주마 소속 지역과 마방 지역이 같아야 하며,
    정원 및 조교사 판단에 따라 수락·거절됩니다. 승인 시 이전 계약은 종료되고 새 계약이 시작됩니다.</div>
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
    {horseData&&<div className="muted">현재 담당 조교사: {horseData.trainerName||"미계약"}
     {horseData.trainerId?" · 이해도 "+horseData.familiarity+"/100":""}
    </div>}
    <div className="section"><h2>조교사 선택</h2></div>
    <select className="field" value={selected?.id||""} onChange={e=>N(e.target.value)}>
     {trainers.map(t=><option key={t.id} value={t.id} disabled={t.occupied>=t.capacity}>
      {t.name} · 담당 {t.occupied}/{t.capacity}두</option>)}
    </select>
    {selected&&<div className="muted" style={{marginTop:12}}>
      전문 분야: {(selected.specialties||[]).join(" · ")||"종합"}<br/>
      조교사 능력치: {Object.entries(selected.skills||{}).slice(0,8).map(([k,v])=>k+" "+v).join(" · ")}
    </div>}
    <button className="primary wide" style={{marginTop:16}} disabled={!selected||busy||!horseData||horseData.trainerId===selected.id}
      onClick={apply}>{busy?"신청 처리 중…":"NPC 조교사 위탁 신청"}</button>
    </div>
    <div className="section"><h2>현재 내 마방</h2></div>
    {data.horses.map(h=><div className="card row" key={h.id}><b><HorseLink horseId={h.id}>{h.name}</HorseLink></b>
      <span className="tag">{h.trainerName||"조교사 미계약"}</span></div>)}
    </>}
   <div className="footer">MY DERBY · 실제 조교사 정원 및 계약 DB 연동</div>
  </div>
 </main>
}