"use client";
import {useCallback,useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import betPayout from "../../lib/racing/bet-payout.cjs";
const {estimatePayout}=betPayout;
const fmt=n=>new Intl.NumberFormat("ko-KR").format(Number(n||0));
const types=[
 {id:"WIN",label:"단승",count:1,rule:"1착 1두"},
 {id:"PLACE",label:"연승",count:1,rule:"7두 이하 2착 이내 · 8두 이상 3착 이내"},
 {id:"QUINELLA",label:"복승",count:2,rule:"1·2착 순서 무관"},
 {id:"QUINELLA_PLACE",label:"복연승",count:2,rule:"3착 이내 2두 · 순서 무관"},
 {id:"EXACTA",label:"쌍승",count:2,rule:"1·2착 순서까지 일치"},
 {id:"TRIO",label:"삼복승",count:3,rule:"1·2·3착 순서 무관"},
 {id:"TRIFECTA",label:"삼쌍승",count:3,rule:"1·2·3착 순서까지 일치"}
];
const names=Object.fromEntries(types.map(t=>[t.id,t.label]));
const errors={
 BETTING_CLOSED:"출전표 발표 후부터 출발 1분 전까지만 베팅할 수 있습니다.",
 STAKE_EXCEEDS_RACE_LIMIT:"한 경주 전체 베팅 합계는 시작 잔액의 5% 또는 10,000G 중 작은 금액까지 가능합니다.",
 INSUFFICIENT_FUNDS:"게임머니가 부족합니다.",
 SELECTION_NOT_CONFIRMED:"확정 출전표에 없는 경주마입니다.",
 INVALID_SELECTION:"선택한 말이 중복되었거나 승식에 맞지 않습니다.",
 INSUFFICIENT_STARTERS_FOR_BET_TYPE:"이 승식에 필요한 출전두수가 부족합니다."
};
export default function RaceBetting({raceId}){
 const [data,setData]=useState(null),[token,setToken]=useState(""),[type,setType]=useState("WIN"),
  [picks,setPicks]=useState([]),[amount,setAmount]=useState(100),
  [quote,setQuote]=useState(null),[busy,setBusy]=useState(false),
  [error,setError]=useState(""),[notice,setNotice]=useState("");
 useEffect(()=>{
  if(!process.env.NEXT_PUBLIC_SUPABASE_URL||!process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)return;
  let active=true;
  const client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  client.auth.getSession().then(({data})=>{if(active)setToken(data.session?.access_token||"")}).catch(()=>{});
  const {data:{subscription}}=client.auth.onAuthStateChange((_event,session)=>{if(active)setToken(session?.access_token||"")});
  return()=>{active=false;subscription.unsubscribe()};
 },[]);
 const load=useCallback(async()=>{
  if(!raceId)return;
  try{
   const res=await fetch("/api/player/race-bet?raceId="+encodeURIComponent(raceId),{
    headers:token?{Authorization:"Bearer "+token}:{},cache:"no-store"});
   const body=await res.json();
   if(!res.ok)throw Error(body.error||"배당 조회 실패");
   setData(body);setError("");
  }catch(e){setError(e.message||"배당 조회 실패")}
 },[raceId,token]);
 useEffect(()=>{void load();const timer=setInterval(()=>void load(),30000);return()=>clearInterval(timer)},[load]);
 const current=types.find(t=>t.id===type)||types[0];
 const horses=data?.horses||[];
 useEffect(()=>{
  if(!horses.length)return;
  setPicks(previous=>{
   const chosen=[];
   for(let i=0;i<current.count;i++){
    const previousId=previous[i];
    const id=previousId&&horses.some(h=>h.horseId===previousId)&&!chosen.includes(previousId)
      ?previousId:(horses.find(h=>!chosen.includes(h.horseId))?.horseId||"");
    chosen.push(id);
   }
   return chosen;
  });
 },[data?.raceId, data?.horses?.length,current.count]);
 const valid=picks.length===current.count&&picks.every(Boolean)&&new Set(picks).size===picks.length;
 useEffect(()=>{
  if(!valid||!raceId||!horses.length){setQuote(null);return}
  let live=true;const timer=setTimeout(async()=>{
   try{
    const url="/api/player/race-bet?raceId="+encodeURIComponent(raceId)+"&betType="+
     encodeURIComponent(type)+"&selection="+picks.map(encodeURIComponent).join(",");
    const res=await fetch(url,{cache:"no-store"});
    const body=await res.json();
    if(live)setQuote(res.ok?body.quote:null);
   }catch{if(live)setQuote(null)}
  },350);
  return()=>{live=false;clearTimeout(timer)};
 },[raceId,type,picks.join(","),horses.length,valid,data?.betCount,(data?.betTypePools||[]).find(p=>p.type===type)?.pool]);
 const refundPreview=useMemo(()=>{
  const activePool=(data?.betTypePools||[]).find(p=>p.type===type);
  if(!valid||!data?.bettingOpen||!quote||quote.betType!==type||
    !Array.isArray(quote.selection)||quote.selection.join(",")!==picks.join(",")||
    Number(quote.pool)!==Number(activePool?.pool))return null;
  return estimatePayout({
    pool:quote.pool,combinationPool:quote.combinationPool,stake:Number(amount)
  });
 },[valid,data?.bettingOpen,data?.betTypePools,quote,type,picks.join(","),amount]);
 const isMultiWinner=type==="PLACE"||type==="QUINELLA_PLACE";
 const choose=(i,id)=>{if(picks.some((v,index)=>v===id&&index!==i)){
   setError("같은 경주마를 두 번 선택할 수 없습니다.");return;}
  setError("");setPicks(x=>x.map((v,j)=>j===i?id:v));
 };
 const place=async()=>{
  if(!token||!data?.bettingOpen||busy||!valid)return;
  const stake=Number(amount);
  if(!Number.isInteger(stake)||stake<100||stake>Math.min(10000,Number(data.maxStake||0))){
   setError("한 경주 내 총 베팅 한도와 보유 잔액을 확인해주세요.");return;
  }
  const label=picks.map(id=>{const h=horses.find(x=>x.horseId===id);return (h?.number||"")+"번 "+(h?.name||"")}).join(" → ");
  if(!window.confirm(`[${current.label}] ${label} / ${fmt(stake)}G를 신청할까요? 배당은 출발 전까지 변동할 수 있고 베팅은 취소할 수 없습니다.`))return;
  setBusy(true);setError("");setNotice("");
  try{
   const res=await fetch("/api/player/race-bet",{method:"POST",headers:{
    "Content-Type":"application/json",Authorization:"Bearer "+token},
    body:JSON.stringify({raceId,betType:type,selections:picks,amount:stake,requestId:crypto.randomUUID()})});
   const body=await res.json();
   if(!res.ok)throw Error(errors[body.error]||body.error||"베팅 실패");
   setNotice(current.label+" 베팅이 접수됐습니다. '나의 베팅 이력'에서 모든 신청을 확인할 수 있습니다.");
   await load();
  }catch(e){setError(e.message||"베팅 실패")}finally{setBusy(false)}
 };
 if(!data&&!error)return <div className="notice">7가지 승식 배당과 AI 분석을 불러오는 중입니다…</div>;
 return <section className="race-betting">
  <div className="section"><h2>📈 AI 예상가 · 7개 승식 배당</h2>
   <a className="outline" href="/bets" style={{textDecoration:"none"}}>📒 나의 베팅 이력 ›</a></div>
  {data?.entryAnnouncementPending&&<div className="notice">경주 당일 12시(한국시간) 출전표 발표 후 공개됩니다.</div>}
  {error&&<div className="notice" role="alert">{error}</div>}
  {notice&&<div className="notice">{notice}</div>}
  {data&&<>
   <div className="card"><div className="row"><b className="gold">AI 예상가 3명 · 경주 참고 정보</b>
    <button className="outline" onClick={load}>↻ 새로고침</button></div>
    <div className="bet-analysts">{(data.analysts||[]).map(t=>
     <div className="bet-analyst" key={t.analyst}><small>{t.analyst}</small><b>{t.name}</b></div>)}</div>
   </div>
   <div className="section"><h2>승식별 배당 풀</h2></div>
   <div className="bet-type-grid">{types.map(t=>
    <button type="button" key={t.id} className={"bet-type-card "+(type===t.id?"selected":"")}
     onClick={()=>{setType(t.id);setPicks([]);setQuote(null)}}>
     <b>{t.label}</b>
    </button>
   )}</div>
   <div className="card"><div className="row"><b className="gold">{current.label} · {current.rule}</b>
     <span className="tag">{data.bettingOpen?"베팅 접수 중":"접수 마감/준비 중"}</span></div>
    <div className="muted" style={{marginTop:9}}>아래 경주마를 순서대로 선택하세요.
    복승·복연승·삼복승은 선택한 말의 순서를 따지지 않습니다.</div>
    <div className="race-entry-wrap" style={{marginTop:12}}>
     <table className="race-entry-table"><thead><tr><th>번호</th><th>경주마</th><th>AI 예상 승률</th><th>단승 실배당</th><th>단승 접수액</th></tr></thead>
     <tbody>{horses.map(h=><tr key={h.horseId}><td>{h.number}</td><td>{h.name}</td>
      <td>{h.estimatedChance??"—"}%</td><td><b className="gold">{h.winOdds==null?"—":Number(h.winOdds).toFixed(2)+"배"}</b></td>
      <td>{fmt(h.betAmount)}G</td></tr>)}</tbody></table>
    </div>
    <div className="bet-pick-grid">{Array.from({length:current.count},(_,i)=><label key={i}>
     {current.count===1?"선택마":(i+1)+"번째 선택"}
     <select className="field" value={picks[i]||""} onChange={e=>choose(i,e.target.value)}>
      <option value="">선택하세요</option>{horses.map(h=><option key={h.horseId} value={h.horseId}>
       {h.number}번 {h.name}</option>)}</select>
    </label>)}</div>
    <div className="notice" style={{marginTop:12}}>
     {quote?.quoteAvailable&&<div style={{marginTop:6}}>
      현재 선택 조합 접수액 {fmt(quote.combinationPool)}G ·
      <b> 참고 배당 상한 {quote.upperBoundOdds}배</b>
     </div>}
     {!quote?.quoteAvailable&&<div className="muted" style={{marginTop:6}}>
      이 조합에 접수된 금액이 없어 현재 실배당을 계산할 수 없습니다.</div>}
     <div className="muted" style={{marginTop:6}}>
      {quote?.note||"경주 종료 시 적중 조합의 실제 베팅 금액 전체를 합산해 최종 배당을 결정합니다."}
     </div>
    </div>
    {typeof data.walletBalance==="number"&&<div className="muted" style={{marginTop:12}}>
      내 게임머니 {fmt(data.walletBalance)}G · 이 경주에 사용 {fmt(data.raceStakeUsed)}G ·
      추가 가능 {fmt(data.maxStake)}G</div>}
    <label className="bet-stake-label">신청 금액 (G)
     <input className="field" type="number" min={100} max={10000} step={100}
      value={amount} onChange={e=>setAmount(Number(e.target.value))}/></label>
    <div className="bet-refund-preview" aria-live="polite" aria-atomic="true">
     <div className="row" style={{alignItems:"center",gap:10}}>
      <strong>예상 환급액{isMultiWinner?" (상한)":""}</strong>
      <strong className="gold bet-refund-amount">
       {refundPreview?"약 "+fmt(refundPreview.estimatedRefund)+"G":"—"}
      </strong>
     </div>
     {refundPreview?<div className="muted" style={{marginTop:7}}>
      현재 조합에 {fmt(amount)}G를 추가했을 때 예상 배당 {refundPreview.estimatedOdds.toFixed(2)}배
      {isMultiWinner?
       " · 다른 적중 조합의 베팅액은 제외한 최대 예상치입니다.":
       " · 선택 조합 적중 시 지급 예상액입니다."}
     </div>:<div className="muted" style={{marginTop:7}}>
      유효한 신청 금액과 선택 조합을 확인하면 예상 환급액이 표시됩니다.
     </div>}
     <small className="muted" style={{display:"block",marginTop:5}}>
      실제 환급액은 추가 베팅과 경주 결과에 따라 달라집니다.
     </small>
    </div>
    <button className="primary" style={{width:"100%",marginTop:12}}
     disabled={busy||!token||!data.bettingOpen||!valid||Number(data.maxStake||0)<100}
     onClick={place}>{busy?"신청 처리 중…":current.label+" 가상 베팅 신청"}</button>
    {!token&&<div className="muted" style={{marginTop:8}}>로그인 후 신청할 수 있습니다. 배당 조회는 로그인 없이 가능합니다.</div>}
   </div>
   {token&&data.mine?.length>0&&<div className="card"><div className="row"><b className="gold">🎟️ 이 경주의 내 베팅</b>
     <a href="/bets" className="outline" style={{textDecoration:"none"}}>전체 이력 ›</a></div>
    {data.mine.map(b=><div className="bet-ticket-row" key={b.betId}><div><b>{names[b.betType]||"단승"}</b>
     <span className="muted"> {b.selections?.map(id=>horses.find(h=>h.horseId===id)?.name||"경주마").join(" → ")}</span>
     <small>{fmt(b.amount)}G</small></div>
     <div><b>{b.status==="PLACED"?"정산 대기":b.status==="WON"?"적중":b.status==="REFUNDED"?"환급":"미적중"}</b>
      <small>지급 {fmt(b.payout)}G</small></div>
     </div>)}
    </div>}
  </>}
 </section>;
}
