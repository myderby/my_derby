"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const fmt=n=>new Intl.NumberFormat("ko-KR").format(n||0);
const facility={PASTURE:"방목지",RECOVERY_STABLE:"회복 마방",REHAB_TRACK:"재활 트랙",
 VET_CLINIC:"수의 진료소",YOUNG_HORSE_AREA:"어린말 육성장"};
const ops={EXPAND:"목장 확장",HIRE_STAFF:"관리사 고용",FIRE_STAFF:"관리사 감원",
 HIRE_VET:"수의사 고용",FIRE_VET:"수의사 감원"};
export default function RanchManagement(){
 const [token,T]=useState(""),[data,D]=useState(null),[error,E]=useState(""),
 [notice,M]=useState(""),[busy,B]=useState(false);
 useEffect(()=>{let live=true;const c=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
 c.auth.getSession().then(({data})=>{if(live)T(data.session?.access_token||"")}).catch(e=>E(e.message));
 const {data:{subscription}}=c.auth.onAuthStateChange((_e,s)=>{if(live)T(s?.access_token||"")});
 return()=>{live=false;subscription.unsubscribe()};},[]);
 const load=async(t=token)=>{if(!t)return;try{
 const r=await fetch("/api/player/ranch/management",{cache:"no-store",headers:{Authorization:"Bearer "+t}});
 const x=await r.json();if(!r.ok)throw new Error(x.error);D(x);E("");
 }catch(e){E(e.message)}};
 useEffect(()=>{if(token)void load(token)},[token]);
 const apply=async(operation,facilityId)=>{
  if(!window.confirm((ops[operation]||"시설 업그레이드")+" 작업을 진행하시겠습니까? 비용이 발생할 수 있습니다."))return;
  B(true);M("");E("");
  try{const r=await fetch("/api/player/ranch/management",{method:"POST",headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},
    body:JSON.stringify({operation,facilityId:facilityId||null,requestId:crypto.randomUUID()})});
    const x=await r.json();if(!r.ok)throw new Error(x.error||"목장 관리 실패");
    M("처리 완료 · 비용 "+fmt(x.paid)+" G");await load();
  }catch(e){E(e.message)}finally{B(false)}
 };
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🏗️ 목장 경영</span></header>
 <div className="area"><div className="controls"><a href="/ranch" className="outline" style={{textDecoration:"none"}}>‹ 목장 코스</a><a href="/finance" className="outline" style={{textDecoration:"none"}}>재무 ›</a></div>
 <div className="section"><h2>개인목장 확장 · 시설 · 인력</h2><button disabled={!token||busy} onClick={()=>load()}>새로고침 ↻</button></div>
 <div className="notice">시설 투자·고용 비용은 현재 게임 임시값입니다. 모두 게임머니 지갑에서 실제 차감되며, 이미 처리된 신청은 중복 적용되지 않습니다.</div>
 {error&&<div className="notice" role="alert">{error}</div>}{notice&&<div className="notice">{notice}</div>}
 {!token&&<div className="notice"><a href="/world">로그인</a> 후 이용할 수 있습니다.</div>}
 {data&&<>
 <div className="card">
 <div className="row"><div><b className="gold">{data.name}</b><div className="muted">목장 Lv.{data.level}/10 · 정원 {data.horseCapacity}두 · 현재 {data.horses}두</div></div>
 <button className="primary" disabled={busy||data.level>=10} onClick={()=>apply("EXPAND")}>확장 {fmt(data.prices.expand)} G</button></div></div>
 <div className="section"><h2>시설 업그레이드</h2></div>
 {data.facilities.map(f=><div className="card row" key={f.id}>
 <div><b>{facility[f.type]||f.type}</b><div className="muted">Lv.{f.level}/10 · 코스 정원 {f.capacity}두</div></div>
 <button className="outline" disabled={busy||f.level>=10} onClick={()=>apply("UPGRADE_FACILITY",f.id)}>강화 {fmt(f.upgradePrice)} G</button></div>)}
 <div className="section"><h2>목장 직원 관리</h2></div>
 <div className="card">
 <div className="row"><span>관리사</span><b>{data.staff} / {data.staffMax}명</b></div>
 <div className="controls"><button className="primary" disabled={busy||data.staff>=data.staffMax} onClick={()=>apply("HIRE_STAFF")}>고용 {fmt(data.prices.hireStaff)} G</button>
 <button className="outline" disabled={busy||data.staff<=0} onClick={()=>apply("FIRE_STAFF")}>감원</button></div>
 <div className="line row"><span>수의사</span><b>{data.vets} / {data.vetMax}명</b></div>
 <div className="controls"><button className="primary" disabled={busy||data.vets>=data.vetMax} onClick={()=>apply("HIRE_VET")}>고용 {fmt(data.prices.hireVet)} G</button>
 <button className="outline" disabled={busy||data.vets<=0} onClick={()=>apply("FIRE_VET")}>감원</button></div>
 <div className="muted" style={{marginTop:10}}>관리사·수의사 인건비는 매일 경제 정산 시 운영비에 포함됩니다.</div>
 </div>
 </>}
 <div className="footer">MY DERBY · 실제 목장 확장/직원 수 및 지갑 데이터 연동</div>
 </div></main>;
}