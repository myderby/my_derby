"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const fmt=n=>new Intl.NumberFormat("ko-KR").format(n||0);
const facilities={PASTURE:"방목지",RECOVERY_STABLE:"회복 마방",REHAB_TRACK:"재활 트랙",
 VET_CLINIC:"수의 진료소",YOUNG_HORSE_AREA:"어린말 육성장"};
const specialists=[
 {code:"PASTURE_CARETAKER",label:"방목지 관리사",facility:"PASTURE"},
 {code:"RECOVERY_CARETAKER",label:"회복 관리사",facility:"RECOVERY_STABLE"},
 {code:"REHAB_CARETAKER",label:"재활 관리사",facility:"REHAB_TRACK"},
 {code:"VET",label:"수의사",facility:"VET_CLINIC"},
 {code:"YOUNG_HORSE_CARETAKER",label:"육성 관리사",facility:"YOUNG_HORSE_AREA"}
];
export default function RanchManagement(){
 const [token,T]=useState(""),[data,D]=useState(null),[error,E]=useState(""),
 [notice,M]=useState(""),[busy,B]=useState(false),
 [candidateMap,CM]=useState({}),[candidateLoading,CL]=useState(false);
 useEffect(()=>{let live=true;const c=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  c.auth.getSession().then(({data})=>{if(live)T(data.session?.access_token||"")}).catch(e=>E(e.message));
  const {data:{subscription}}=c.auth.onAuthStateChange((_e,s)=>{if(live)T(s?.access_token||"")});
  return()=>{live=false;subscription.unsubscribe()};
 },[]);
 const load=async(t=token)=>{if(!t)return;try{
  const r=await fetch("/api/player/ranch/management",{cache:"no-store",headers:{Authorization:"Bearer "+t}});
  const x=await r.json();if(!r.ok)throw new Error(x.error);D(x);E("");
 }catch(e){E(e.message)}};
 const loadCandidates=async(spec=specialists[0].code,t=token)=>{if(!t)return;CL(true);try{
  const r=await fetch("/api/player/ranch/management?specialty="+encodeURIComponent(spec),{cache:"no-store",headers:{Authorization:"Bearer "+t}});
  const x=await r.json();if(!r.ok)throw new Error(x.error);CM(old=>({...old,[spec]:x.candidates||[]}));
 }catch(e){E(e.message)}finally{CL(false)}};
 const loadAllCandidates=async(t=token)=>{if(!t)return;CL(true);try{
  const entries=await Promise.all(specialists.map(async spec=>{
   const r=await fetch("/api/player/ranch/management?specialty="+encodeURIComponent(spec.code),{cache:"no-store",headers:{Authorization:"Bearer "+t}});
   const x=await r.json();if(!r.ok)throw new Error(x.error);return [spec.code,x.candidates||[]];
  }));CM(Object.fromEntries(entries));
 }catch(e){E(e.message)}finally{CL(false)}};
 useEffect(()=>{if(token){void load(token);void loadAllCandidates(token)}},[token]);
 const apply=async(operation,fields={},confirmText="")=>{
  if(confirmText&&!window.confirm(confirmText))return;
  B(true);M("");E("");
  try{
   const r=await fetch("/api/player/ranch/management",{method:"POST",
    headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},
    body:JSON.stringify({operation,...fields,requestId:crypto.randomUUID()})});
   const x=await r.json();if(!r.ok)throw new Error(x.error||"목장 관리 처리에 실패했습니다.");
   if(operation==="ASSIGN_WORKER")M(fields.facilityId?"관리사를 시설에 배치했습니다.":"관리사 배치를 해제했습니다.");
   else if(operation==="FIRE_WORKER")M("선택한 직원을 감원했습니다.");
   else if(operation==="HIRE_WORKER")M("선택한 직원을 고용했습니다. · "+fmt(x.paid)+" G");
   else M("처리 완료 · 비용 "+fmt(x.paid)+" G");
   await load();
   if(operation==="HIRE_WORKER")await loadCandidates(fields.specialty);
  }catch(e){E(e.message)}finally{B(false)}
 };
 const activeWorkers=data?.workers||[];
 const staffLimit=spec=>spec.code==="VET"?data.vetMax:data.staffMax;
 const staffCount=spec=>spec.code==="VET"?data.vets:data.staff;
 return <main className="shell ranch-management-shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🏗️ 목장 경영</span></header>
 <div className="area ranch-management-area"><div className="controls"><a href="/ranch" className="outline" style={{textDecoration:"none"}}>‹ 목장 둘러보기</a><a href="/finance" className="outline" style={{textDecoration:"none"}}>재무 ›</a></div>
 <div className="section"><h2>개인목장 확장 · 시설 · 인력</h2><button disabled={!token||busy} onClick={()=>load()}>새로고침 ↻</button></div>
 <div className="notice">시설 투자·고용 비용은 게임머니 지갑에서 차감됩니다. 직원 급여는 게임일마다 청구됩니다.</div>
 {error&&<div className="notice" role="alert">{error}</div>}{notice&&<div className="notice" role="status">{notice}</div>}
 {!token&&<div className="notice"><a href="/world">로그인</a> 후 이용할 수 있습니다.</div>}
 {data&&<>
  <div className="card">
  <div className="row"><div><b className="gold">{data.name}</b><div className="muted">목장 Lv.{data.level}/10 · 정원 {data.horseCapacity}두 · 현재 {data.horses}두</div></div>
   <button className="primary" disabled={busy||data.level>=10} onClick={()=>apply("EXPAND",{},"목장을 확장하시겠습니까? 비용이 차감됩니다.")}>확장 {fmt(data.prices.expand)} G</button></div>
 </div>
 <div className="notice">시설 레벨이 높을수록 코스 종료 시 경주마의 능력·기질을 관찰하는 정보가 늘어납니다. 관리사와 수의사는 시설에 배치해야 효과가 적용됩니다. 목장 경주마가 배치 직원 1명당 2두를 넘으면 초과 1두마다 해당 코스의 실효 능력치가 5점 낮아집니다(최저 0).</div>
 {data.facilities.map(f=>{
  const spec=specialists.find(s=>s.facility===f.type)||specialists[0];
  const workers=activeWorkers.filter(w=>w.specialty===spec.code);
  const candidates=candidateMap[spec.code]||[];
  const hirePrice=spec.code==="VET"?data.prices.hireVet:data.prices.hireStaff;
  const options=data.facilities.filter(item=>item.type===spec.facility);
  return <section className="card" key={f.id} style={{marginTop:12}}>
   <div className="row"><div><b>{facilities[f.type]||f.type}</b><div className="muted">Lv.{f.level}/10 · 수용 {f.capacity}두 · {spec.label} {workers.length}명</div></div>
    <button className="primary" disabled={busy||f.level>=10} onClick={()=>apply("UPGRADE_FACILITY",{facilityId:f.id},facilities[f.type]+"을 강화하시겠습니까? 비용이 차감됩니다.")}>시설 강화 · {fmt(f.upgradePrice)} G</button>
   </div>
   <div className="section"><h3>직원 현황</h3></div>
   {!workers.length&&<div className="muted">고용한 {spec.label}이 없습니다.</div>}
   <div className="ranch-worker-list">{workers.map(w=><div className="ranch-worker" key={w.id}>
    <div className="row"><div><b>{w.name}</b><div className="muted">{spec.label} · 등급 {w.grade} · {w.assignedFacilityId===f.id?"배치 완료":"미배치"}</div></div>
     <button className="outline" disabled={busy} onClick={()=>apply("FIRE_WORKER",{workerId:w.id},w.name+" 직원을 감원하시겠습니까?")}>감원</button>
    </div>
    <div className="muted" style={{marginTop:7}}>관리 {w.skills?.care} · 의료 {w.skills?.medical} · 육성 {w.skills?.growth} · 안정 {w.skills?.stability}<br/>게임 1일 급여 {fmt(w.salary)} G</div>
    <div style={{display:"flex",gap:8,alignItems:"center",marginTop:9,flexWrap:"wrap"}}>
     <label className="muted" htmlFor={"worker-"+w.id}>배치 시설</label>
     <select data-tutorial-target={w.id===activeWorkers[0]?.id?"ranch":undefined} id={"worker-"+w.id} className="field" disabled={busy} value={w.assignedFacilityId||""}
      onChange={e=>apply("ASSIGN_WORKER",{workerId:w.id,facilityId:e.target.value||null})}>
      <option value="">미배치</option>
      {options.map(item=><option key={item.id} value={item.id}>{facilities[item.type]} · Lv.{item.level}</option>)}
     </select>
    </div>
   </div>)}</div>
   <div className="section"><h3>{spec.label} 고용 · 후보 선택</h3></div>
   <div className="muted">직원을 고용하면 자동 배치되지 않습니다. 배치 시설을 선택해야 시설 관리 효과가 적용됩니다.</div>
   {candidateLoading&&!candidateMap[spec.code]&&<div className="notice">고용 후보를 불러오는 중…</div>}
   {!candidateLoading&&!candidates.length&&<div className="notice">현재 고용 후보가 없습니다.</div>}
   <div className="ranch-worker-list">{candidates.map(candidate=><div className="ranch-worker" key={candidate.id}>
    <div className="row"><div><b>{candidate.name}</b><div className="muted">등급 {candidate.grade}</div></div>
     <button className="primary" disabled={busy||staffCount(spec)>=staffLimit(spec)}
      onClick={()=>apply("HIRE_WORKER",{candidateId:candidate.id,specialty:spec.code},candidate.name+" 후보를 "+fmt(hirePrice)+" G에 고용하시겠습니까?")}>고용 {fmt(hirePrice)} G</button>
    </div>
    <div className="muted" style={{marginTop:7}}>관리 {candidate.skills?.care} · 의료 {candidate.skills?.medical} · 육성 {candidate.skills?.growth} · 안정 {candidate.skills?.stability}<br/>게임 1일 급여 {fmt(candidate.salary)} G</div>
   </div>)}</div>
  </section>;
 })}
 </>}
 <div className="footer">MY DERBY · 직원 선택 고용 · 직접 배치 · 목장 정원 연동</div>
 </div></main>;
}
