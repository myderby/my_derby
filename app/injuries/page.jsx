"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const health={HEALTHY:"건강",INJURED:"부상",RECOVERING:"회복 중"};
export default function Injuries(){
 const [token,T]=useState(""),[data,D]=useState(null),[error,E]=useState("");
 useEffect(()=>{
  let active=true;const c=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  c.auth.getSession().then(({data})=>{if(active)T(data.session?.access_token||"")}).catch(e=>E(e.message));
  const {data:{subscription}}=c.auth.onAuthStateChange((_e,s)=>{if(active)T(s?.access_token||"")});
  return()=>{active=false;subscription.unsubscribe()};
 },[]);
 const load=async(t=token)=>{
  if(!t)return;try{const r=await fetch("/api/player/injuries",{cache:"no-store",headers:{Authorization:"Bearer "+t}});
  const body=await r.json();if(!r.ok)throw new Error(body.error);D(body);E("");
  }catch(e){E(e.message)}
 };
 useEffect(()=>{if(token)void load(token)},[token]);
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🩺 경주마 부상</span></header>
 <div className="area"><div className="controls"><a href="/world" className="outline" style={{textDecoration:"none"}}>‹ 내 보유마</a><a href="/ranch" className="outline" style={{textDecoration:"none"}}>목장 재활 ›</a></div>
 <div className="section"><h2>경주마 부상·회복</h2><button disabled={!token} onClick={()=>load()}>새로고침 ↻</button></div>
 <div className="notice">실제 질병 기록이 아닌 게임 경주 시뮬레이션의 부상 판정입니다.
 회복 가능한 부상은 일정 게임일 경과 후 자동 회복되며, 경주 복귀 불가능 판정은 일반 회복만으로 해제되지 않습니다.</div>
 {error&&<div className="notice" role="alert">{error}</div>}
 {!token&&<div className="notice"><a href="/world">월드 로그인</a> 후 확인하세요.</div>}
 {data&&(data.horses||[]).map(h=><div className="card" key={h.id}>
 <div className="row"><b className="gold">{h.name}</b><span className="tag">{health[h.health]||h.health}</span></div>
 {h.injuryPrognosis==="RACING_UNFIT"&&<div className="notice">경주 복귀 불가 판정 · 번식마 전환 가능 여부를 검토하세요.</div>}
 {h.injuryPrognosis==="RECOVERABLE"&&<div className="muted">게임 {h.recoveryGameDay}일 이후 자동 회복 예정</div>}
 {!h.recentInjuries?.length&&<div className="muted">이 경주마의 부상 이력이 없습니다.</div>}
 {(h.recentInjuries||[]).map((item,i)=><div className="line row small" key={i}>
 <span>게임 {item.gameDay}일 · {item.severity==="RECOVERABLE"?"회복 가능":"경주 복귀 불가"}</span>
 <b>{item.status==="RECOVERED"?"회복 완료":item.recoverDay?"예정 "+item.recoverDay+"일":"장기 관리"}</b></div>)}
 </div>)}
 <div className="footer">MY DERBY · 경주 부상·자연 회복·장기 관리 기록</div>
 </div></main>;
}