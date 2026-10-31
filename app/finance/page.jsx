"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const fmt=n=>new Intl.NumberFormat("ko-KR").format(Number(n||0));
const names={INITIAL_CAPITAL:"초기 자본",RACE_PRIZE:"경주 상금",DAILY_OPERATION:"일일 운영비",
 HORSE_PURCHASE:"경주마 구매",HORSE_SALE:"경주마 판매"};
export default function Finance(){
 const [token,T]=useState(""),[checking,C]=useState(true),[data,D]=useState(null),[error,E]=useState(""),[busy,B]=useState(false),[message,M]=useState("");
 useEffect(()=>{let live=true;const api=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
 api.auth.getSession().then(({data})=>{if(live){T(data.session?.access_token||"");C(false)}});
 const {data:{subscription}}=api.auth.onAuthStateChange((_e,s)=>{if(live)T(s?.access_token||"")});
 return()=>{live=false;subscription.unsubscribe()};},[]);
 const load=async(t=token)=>{
  if(!t)return;try{const r=await fetch("/api/player/finance",{headers:{Authorization:"Bearer "+t},cache:"no-store"});
  const body=await r.json();if(!r.ok)throw new Error(body.error);D(body);E("");
  }catch(e){E(e.message)}};
 useEffect(()=>{if(token)void load(token)},[token]);
 const requestRecovery=async()=>{
  if(!window.confirm("이번 시즌 1회 한정 재정 회복 지원금을 신청하시겠습니까? 미납 운영비가 우선 상환됩니다."))return;
  B(true);E("");M("");
  try{
   const r=await fetch("/api/player/finance",{method:"POST",headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify({action:"RECOVER"})});
   const body=await r.json();if(!r.ok)throw new Error(body.error);
   M("재정 회생 지원금 "+fmt(body.grant)+" G 지급, 미납금 "+fmt(body.debtsPaid)+" G 상환 완료");
   await load();
  }catch(e){E(e.message)}finally{B(false)}
 };

 return <main className="shell"><header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">💳 재무 관리</span></header>
 <div className="area"><div className="controls" style={{marginBottom:12}}><a className="outline" href="/world" style={{textDecoration:"none"}}>‹ 월드</a><a className="outline" href="/market" style={{textDecoration:"none"}}>경주마 시장 ›</a><a className="outline" href="/bets" style={{textDecoration:"none"}}>📒 베팅 이력 ›</a></div>
 <div className="section"><h2>내 재무 내역</h2><button disabled={!token} onClick={()=>load()}>새로고침 ↻</button></div>
 {error&&<div className="notice" role="alert">{error}</div>}
 {message&&<div className="notice" role="status">{message}</div>}
 {checking&&<div className="notice">로그인 확인 중…</div>}
 {!checking&&!token&&<div className="notice">월드에서 로그인해야 재무 내역을 확인할 수 있습니다.</div>}
 {data&&<><div className="card">
 <div className="muted">게임머니 잔액</div><b className="large gold">{fmt(data.balance)} G</b>
 <div className="row small line"><span>미납 운영비</span><b>{fmt(data.unpaidExpenses)} G</b></div>
 <div className="row small"><span>재정 보호 필요</span><span className="tag">{data.protected?"미납 발생":"정상"}</span></div>
 <div className="muted" style={{marginTop:9}}>시즌 {data.world?.season}, {data.world?.week}주차 · 실제 DB 원장</div>
 {data.protected&&data.balance<20000&&
  <button className="primary wide" disabled={busy} onClick={requestRecovery} style={{marginTop:12}}>
   {busy?"회생 신청 중…":"시즌 1회 재정 회생 지원 신청"}</button>}
 </div>
 <div className="notice">경제_v2의 등급별 운영비·기본 목장 유지비·인건비를 반영합니다.
   현실 하루는 게임 7일이며 매일 22:45(한국시간) 정산합니다.
   초기 자본 200만 G는 경제 원문에 수치가 없어 설정한 <b>임시 운영값</b>입니다.</div>
 <div className="section"><h2>거래 내역</h2><span className="tag">{data.recentTransactions?.length||0}건</span></div>
 {!data.recentTransactions?.length&&<div className="notice">거래 내역이 없습니다.</div>}
 {(data.recentTransactions||[]).map((t,i)=><div className="card row" key={i}>
 <div><b>{names[t.type]||t.type}</b><div className="muted">게임 {t.gameDay}일 · 잔액 {fmt(t.balanceAfter)} G</div></div>
 <b style={{color:t.amount>=0?"#a6cb7d":"#efb4a9"}}>{t.amount>=0?"+":""}{fmt(t.amount)}</b></div>)}
 </>}
 <div className="footer">MY DERBY · 원본 경제_v2 우선 · 미확정 요율은 임시 설정값으로 분리</div>
 </div></main>;
}