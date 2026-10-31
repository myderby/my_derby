"use client";
import {useCallback,useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const typeNames={WIN:"단승",PLACE:"연승",QUINELLA:"복승",QUINELLA_PLACE:"복연승",EXACTA:"쌍승",TRIO:"삼복승",TRIFECTA:"삼쌍승"};
const labels={PLACED:"정산 대기",WON:"적중",LOST:"미적중",REFUNDED:"환급"};
const fmt=n=>new Intl.NumberFormat("ko-KR").format(Number(n||0));
const pageSize=30;
export default function MyBetHistory(){
 const [token,setToken]=useState(""),[data,setData]=useState(null),[error,setError]=useState(""),
  [loading,setLoading]=useState(true),[page,setPage]=useState(0),[kind,setKind]=useState("ALL");
 useEffect(()=>{
  let live=true;
  const c=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  c.auth.getSession().then(({data})=>{if(live)setToken(data.session?.access_token||"");if(live&&!data.session)setLoading(false)}).catch(()=>{if(live)setLoading(false)});
  const {data:{subscription}}=c.auth.onAuthStateChange((_e,s)=>{if(live)setToken(s?.access_token||"")});
  return()=>{live=false;subscription.unsubscribe()};
 },[]);
 const load=useCallback(async()=>{
  if(!token){setLoading(false);return;}
  setLoading(true);
  try{
   const res=await fetch(`/api/player/betting-history?limit=${pageSize}&offset=${page*pageSize}`,{
     headers:{Authorization:"Bearer "+token},cache:"no-store"});
   const body=await res.json();
   if(!res.ok)throw Error(body.error||"베팅 이력 조회 실패");
   setData(body);setError("");
  }catch(e){setError(e.message||"베팅 이력을 불러올 수 없습니다.")}finally{setLoading(false)}
 },[token,page]);
 useEffect(()=>{void load()},[load]);
 const summary=data?.summary||{};
 const tickets=data?.tickets||[];
 const shown=kind==="ALL"?tickets:tickets.filter(t=>t.betType===kind);
 const win=Boolean(summary.count);
 return <main className="shell">
  <header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a>
   <span className="coin">📒 내 베팅 기록</span></header>
  <div className="area">
   <div className="controls" style={{marginBottom:14}}>
    <a className="outline" href="/schedule" style={{textDecoration:"none"}}>‹ 경주시간표</a>
    <a className="outline" href="/finance" style={{textDecoration:"none"}}>재무 관리 ›</a>
   </div>
   <div className="section"><h1>나의 베팅 이력</h1><button className="outline" onClick={load}>↻ 새로고침</button></div>
   <div className="notice">가상 게임머니(G) 전용 기록입니다. 내가 직접 신청한 베팅만 표시됩니다.
    승식별로 별도의 공동 풀에서 90%를 적중 베팅 금액 비율대로 분배합니다.
    적중자가 없는 승식은 전액 환급합니다.</div>
   {!token&&<div className="notice"><a href="/world">로그인</a> 후 내 베팅 기록을 볼 수 있습니다.</div>}
   {error&&<div className="notice" role="alert">{error}</div>}
   {data&&<>
    <div className="bet-history-summary">
      <div className="card"><small>전체 베팅</small><b>{fmt(summary.count)}건</b></div>
      <div className="card"><small>누적 베팅액</small><b>{fmt(summary.totalStake)}G</b></div>
      <div className="card"><small>총 지급액</small><b>{fmt(summary.totalPayout)}G</b></div>
      <div className="card"><small>확정 손익</small><b className={Number(summary.net)>=0?"gold":"bet-negative"}>
       {Number(summary.net)>0?"+":""}{fmt(summary.net)}G</b></div>
      <div className="card"><small>적중 / 미적중</small><b>{fmt(summary.won)} / {fmt(summary.lost)}</b></div>
      <div className="card"><small>정산 대기 / 환급</small><b>{fmt(summary.pending)} / {fmt(summary.refunded)}</b></div>
    </div>
    <div className="section"><h2>베팅 상세 기록</h2><span className="tag">{fmt(summary.count)}건</span></div>
    <div className="controls" style={{marginBottom:12,flexWrap:"wrap"}}>
     <label>승식 필터 <select className="field" value={kind} onChange={e=>setKind(e.target.value)}>
       <option value="ALL">전체</option>
       {Object.entries(typeNames).map(([k,v])=><option key={k} value={k}>{v}</option>)}
      </select></label>
    </div>
    {!win&&!loading&&<div className="notice">아직 베팅 기록이 없습니다. 경주정보 화면에서 승식을 선택해 신청할 수 있습니다.</div>}
    <div className="bet-history-list">{shown.map(t=>{
     const unordered=["QUINELLA","QUINELLA_PLACE","TRIO"].includes(t.betType);
     const ticketProfit=t.status==="PLACED"?null:Number(t.payout)-Number(t.amount);
     return <article className="card bet-history-item" key={t.id}>
      <div className="row"><div><b className="gold">{typeNames[t.betType]||t.betType}</b>
        <span className="muted"> · {t.track} {t.raceNo}경주</span></div>
       <span className="tag">{labels[t.status]||t.status}</span></div>
      <div className="muted" style={{marginTop:7}}>{t.raceDate||"날짜 미정"}
       {t.startTime?" · "+String(t.startTime).slice(0,5):""}</div>
      <div className="bet-history-picks">{(t.horses||[]).map((h,i)=><span key={h.horseId}>
       {i>0&&<em>{unordered?" + ":" → "}</em>}
       <strong>{h.number??"?"}번 {h.name}</strong></span>)}</div>
      <div className="bet-history-numbers">
       <div><small>베팅액</small><b>{fmt(t.amount)}G</b></div>
       <div><small>지급액</small><b>{fmt(t.payout)}G</b></div>
       <div><small>확정 손익</small>
        <b className={ticketProfit!=null&&ticketProfit<0?"bet-negative":"gold"}>
         {ticketProfit==null?"정산 대기":(ticketProfit>0?"+":"")+fmt(ticketProfit)+"G"}</b></div>
      </div>
      <div className="row" style={{marginTop:11}}>
       <small className="muted">신청: {new Date(t.placedAt).toLocaleString("ko-KR",{timeZone:"Asia/Seoul"})}</small>
       <a className="outline" style={{textDecoration:"none"}} href={"/race/"+t.raceId}>경주정보 ›</a>
      </div>
     </article>})}</div>
    <div className="controls" style={{justifyContent:"space-between",marginTop:16}}>
     <button className="outline" disabled={loading||page===0} onClick={()=>setPage(p=>Math.max(0,p-1))}>‹ 이전</button>
     <span className="muted">{page+1}페이지 · {fmt(summary.count)}건 중 {fmt(page*pageSize+1)}~{fmt(Math.min((page+1)*pageSize,summary.count))}건</span>
     <button className="outline" disabled={loading||(page+1)*pageSize>=Number(summary.count||0)}
      onClick={()=>setPage(p=>p+1)}>다음 ›</button>
    </div>
   </>}
   {loading&&<div className="notice">베팅 기록을 불러오는 중입니다…</div>}
  </div>
 </main>;
}
