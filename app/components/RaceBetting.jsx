"use client";
import {useCallback,useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const fmt=n=>new Intl.NumberFormat("ko-KR").format(Number(n||0));
const errors={
 BETTING_CLOSED:"베팅 가능 시간이 아닙니다. 출전표 발표 이후부터 출발 1분 전까지만 신청할 수 있습니다.",
 ONE_WIN_BET_PER_RACE:"이 경주에는 이미 단승식 베팅을 신청했습니다.",
 STAKE_EXCEEDS_5_PERCENT_BALANCE:"베팅은 잔액의 5%와 10,000G 중 작은 금액까지만 가능합니다.",
 INSUFFICIENT_FUNDS:"게임머니가 부족합니다.",HORSE_NOT_IN_RACE:"해당 경주마는 출전표에 없습니다."
};
export default function RaceBetting({raceId}){
 const [data,setData]=useState(null),[token,setToken]=useState(""),[horse,setHorse]=useState(""),
  [amount,setAmount]=useState(100),[busy,setBusy]=useState(false),
  [err,setErr]=useState(""),[notice,setNotice]=useState("");
 useEffect(()=>{
  if(!process.env.NEXT_PUBLIC_SUPABASE_URL||!process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)return;
  let alive=true;
  const c=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  c.auth.getSession().then(({data})=>{if(alive)setToken(data.session?.access_token||"")}).catch(()=>{});
  const {data:{subscription}}=c.auth.onAuthStateChange((_e,s)=>{if(alive)setToken(s?.access_token||"")});
  return()=>{alive=false;subscription.unsubscribe()};
 },[]);
 const load=useCallback(async()=>{
   if(!raceId)return;
   try{
    const res=await fetch("/api/player/race-bet?raceId="+encodeURIComponent(raceId),{
      headers:token?{"Authorization":"Bearer "+token}:{},cache:"no-store"});
    const payload=await res.json();
    if(!res.ok)throw Error(payload.error||"배당 조회 실패");
    setData(payload);setErr("");
    setHorse(prev=>prev||payload.horses?.[0]?.horseId||"");
   }catch(e){setErr(e.message||"배당 정보를 불러올 수 없습니다.")}
 },[raceId,token]);
 useEffect(()=>{void load();const timer=setInterval(()=>void load(),30000);return()=>clearInterval(timer)},[load]);
 const place=async()=>{
  if(!token||!horse||!data?.bettingOpen||data?.mine?.length)return;
  if(!Number.isInteger(Number(amount))||Number(amount)<100||Number(amount)>Math.min(10000,Number(data.maxStake||0))){
   setErr("100G 이상, 보유 게임머니의 5% 및 최대 10,000G 이내로 신청해주세요.");return;
  }
  const pick=data.horses?.find(x=>x.horseId===horse);
  if(!window.confirm(`${pick?.number||""}번 ${pick?.name||"경주마"}에 단승식 ${fmt(amount)}G를 사용하시겠습니까? 배당은 확정 전까지 변동하며 취소할 수 없습니다.`))return;
  setBusy(true);setErr("");setNotice("");
  try{
   const res=await fetch("/api/player/race-bet",{method:"POST",
    headers:{"Content-Type":"application/json",Authorization:"Bearer "+token},
    body:JSON.stringify({raceId,horseId:horse,amount:Number(amount),requestId:crypto.randomUUID()})});
   const payload=await res.json();
   if(!res.ok)throw Error(errors[payload.error]||payload.error||"베팅 실패");
   setNotice("단승식 베팅이 접수됐습니다. 배당과 경주 결과는 서버에서 정산됩니다.");
   await load();
  }catch(e){setErr(e.message||"베팅 실패")}finally{setBusy(false)}
 };
 if(!data&&!err)return <div className="notice">경주 AI 예상가와 배당을 불러오고 있습니다…</div>;
 return <section className="race-betting">
  <div className="section"><h2>📈 AI 예상가 · 가상 단승 배당</h2>
    <button className="outline" type="button" onClick={load}>새로고침 ↻</button></div>
  <div className="notice">게임머니(G) 전용 가상 단승식입니다. 현금 베팅·환전은 지원하지 않습니다.
   AI 추천과 예상 배당은 결과 보장이 아니며, 참가 마주와 NPC 마주의 베팅으로 배당이 변동합니다.
   최대 운영 공제 10%이며 적중하면 최소 원금을 돌려받습니다. 경주 확정 후 정산됩니다.</div>
  {data?.entryAnnouncementPending&&<div className="notice">경주 당일 낮 12시(한국시간) 출전표 발표 후 예상가·배당이 공개됩니다.</div>}
  {err&&<div className="notice" role="alert">{err}</div>}
  {notice&&<div className="notice">{notice}</div>}
  {data&&<>
   <div className="card"><div className="row"><b className="gold">AI 경주 예상가</b>
     <span className="tag">가상 분석 · 승부 예측</span></div>
     <div className="bet-analysts">{(data.analysts||[]).map(t=>
      <div className="bet-analyst" key={t.analyst}><small>{t.analyst}</small>
       <b>{t.name}</b></div>)}</div>
   </div>
   <div className="card"><div className="row"><b className="gold">단승 예상 배당</b>
     <span className="muted">현재 베팅 풀 {fmt(data.marketPool)}G · {fmt(data.betCount)}건</span></div>
    <div className="race-entry-wrap" style={{marginTop:12}}>
     <table className="race-entry-table"><thead><tr>
      <th>번호</th><th>경주마</th><th>모델 예상 승률</th><th>현재 배당</th><th>접수 금액</th>
     </tr></thead><tbody>{(data.horses||[]).map(h=><tr key={h.horseId}
      onClick={()=>setHorse(h.horseId)} style={{cursor:"pointer",background:horse===h.horseId?"rgba(211,162,74,.13)":undefined}}>
      <td>{h.number}</td><td>{h.name}</td><td>{h.estimatedChance}%</td>
      <td><strong className="gold">{Number(h.winOdds).toFixed(2)}배{h.oddsSource==="MODEL"?" *":""}</strong></td>
      <td>{fmt(h.betAmount)}G</td></tr>)}</tbody></table></div>
    <div className="muted" style={{marginTop:9}}>* 참가 금액이 없는 말은 AI 모델 기반 예상 배당입니다.
     실제 지급률은 최종 공동 베팅 풀과 당첨마 베팅 총액으로 계산됩니다.</div>
   </div>
   <div className="card">
    <div className="row"><b className="gold">🎟️ 단승식 베팅</b>
     <span className="tag">{data.bettingOpen?"접수 중":"접수 마감 / 준비 중"}</span></div>
    {typeof data.walletBalance==="number"&&<div className="muted" style={{marginTop:9}}>
       현재 보유 {fmt(data.walletBalance)}G · 최대 신청 {fmt(data.maxStake)}G</div>}
    {data.mine?.length?<div className="notice">{data.mine.map(b=><div key={b.betId}>
       내 베팅: {data.horses?.find(h=>h.horseId===b.horseId)?.name||"경주마"} · {fmt(b.amount)}G
       · {b.status==="PLACED"?"정산 대기":b.status==="WON"?"적중":b.status==="REFUNDED"?"환급":"미적중"}
       {b.status!=="PLACED"&&<> · 지급 {fmt(b.payout)}G</>}
      </div>)}</div>:<>
      <div className="controls" style={{marginTop:13,alignItems:"end"}}>
       <label>선택마 <select className="field" value={horse} onChange={e=>setHorse(e.target.value)}>
       {(data.horses||[]).map(h=><option key={h.horseId} value={h.horseId}>
       {h.number}번 {h.name} · {h.winOdds}배</option>)}</select></label>
       <label>신청 게임머니 <input className="field" type="number" min="100" max="10000" step="100"
       value={amount} onChange={e=>setAmount(Number(e.target.value))}/></label>
      </div>
      <button className="primary" style={{marginTop:12,width:"100%"}} disabled={busy||!token||
       !data.bettingOpen||!(data.horses||[]).length||Number(data.maxStake)<100}
       onClick={place}>{busy?"접수 처리 중…":"단승식 가상 베팅 신청"}</button>
      {!token&&<div className="muted" style={{marginTop:8}}>베팅하려면 로그인해 주세요. 배당은 로그인 없이 조회할 수 있습니다.</div>}
      </>}
    </div>
  </>}
 </section>;
}