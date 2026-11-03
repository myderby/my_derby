"use client";
import {useCallback,useEffect,useMemo,useRef,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import omr from "../../lib/racing/omr.cjs";
const {expandOmr}=omr;
const fmt=n=>new Intl.NumberFormat("ko-KR").format(Number(n||0));
const BET_TYPES=[
 {id:"WIN",label:"단승",legs:1,rule:"1착 말 하나"},
 {id:"PLACE",label:"연승",legs:1,rule:"7두 이하 2착 이내 · 8두 이상 3착 이내"},
 {id:"QUINELLA",label:"복승",legs:2,rule:"1·2착 순서 무관"},
 {id:"QUINELLA_PLACE",label:"복연승",legs:2,rule:"3착 내 두 말, 순서 무관"},
 {id:"EXACTA",label:"쌍승",legs:2,rule:"1·2착 순서까지 일치"},
 {id:"TRIO",label:"삼복승",legs:3,rule:"1·2·3착 순서 무관"},
 {id:"TRIFECTA",label:"삼쌍승",legs:3,rule:"1·2·3착 순서 일치"}
];
const names=Object.fromEntries(BET_TYPES.map(x=>[x.id,x.label]));
const errMap={
 BETTING_CLOSED:"출전표 발표 후부터 출발 1분 전까지만 구매할 수 있습니다.",
 STAKE_EXCEEDS_RACE_LIMIT:"경주당 총 베팅은 시작 잔액의 5% 및 최대 10,000G까지만 가능합니다.",
 TOO_MANY_COMBINATIONS:"최대 100조합까지만 구매할 수 있습니다.",
 DUPLICATE_COMBINATION:"동일한 조합을 중복 선택했습니다.",
 SELECTION_NOT_CONFIRMED:"확정 출전표에 없는 경주마가 포함되어 있습니다.",
 INVALID_SELECTION:"선택마를 다시 확인해 주세요.",
 INSUFFICIENT_STARTERS_FOR_BET_TYPE:"현재 출전두수로 구매할 수 없는 승식입니다."
};
export default function RaceBetting({raceId,readOnly=false}){
 const [data,setData]=useState(null),[token,setToken]=useState(""),[betType,setBetType]=useState("WIN");
 const [rows,setRows]=useState([[],[],[]]),[stakeEach,setStakeEach]=useState(100);
 const [runnerOddsSort,setRunnerOddsSort]=useState(null);
 const [quote,setQuote]=useState(null),[busy,setBusy]=useState(false);
 const [error,setError]=useState(""),[notice,setNotice]=useState("");
 const requestRef=useRef({signature:"",id:""});
 useEffect(()=>{
  if(!process.env.NEXT_PUBLIC_SUPABASE_URL||!process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)return;
  let mounted=true;
  const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  supabase.auth.getSession().then(({data:d})=>{if(mounted)setToken(d.session?.access_token||"")}).catch(()=>{});
  const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,s)=>{if(mounted)setToken(s?.access_token||"")});
  return()=>{mounted=false;subscription.unsubscribe()};
 },[]);
 const load=useCallback(async()=>{
  if(!raceId)return;
  try{
   const res=await fetch("/api/player/race-bet?raceId="+encodeURIComponent(raceId)+
    (readOnly?"":"&popularType="+encodeURIComponent(betType)),
    {cache:"no-store",headers:token?{Authorization:"Bearer "+token}:{}});
   const body=await res.json();
   if(!res.ok)throw Error(body.error||"베팅 정보를 조회할 수 없습니다.");
   setData(body);setError("");
  }catch(e){setError(e.message||"배당 조회 실패")}
 },[raceId,token,betType,readOnly]);
 useEffect(()=>{void load();const timer=setInterval(()=>void load(),30000);return()=>clearInterval(timer)},[load]);
 useEffect(()=>{setRunnerOddsSort(null)},[raceId]);
 const current=BET_TYPES.find(t=>t.id===betType)||BET_TYPES[0];
 const horses=(data?.horses||[]).slice().sort((a,b)=>Number(a.number)-Number(b.number));
 const runnerOddsRows=horses.map(h=>({
  horse:h,
  odds:(data?.popularOdds?.popular||[]).find(p=>String(p.numbers?.[0])===String(h.number))?.odds
 }));
 const visibleRunnerOddsRows=runnerOddsSort?[...runnerOddsRows].sort((a,b)=>{
  const aValue=a.odds==null?null:Number(a.odds),bValue=b.odds==null?null:Number(b.odds);
  const aOdds=aValue!=null&&Number.isFinite(aValue)?aValue:null;
  const bOdds=bValue!=null&&Number.isFinite(bValue)?bValue:null;
  if(aOdds===null&&bOdds===null)return Number(a.horse.number)-Number(b.horse.number);
  if(aOdds===null)return 1;
  if(bOdds===null)return -1;
  const order=aOdds-bOdds;
  return runnerOddsSort==="asc"?order||Number(a.horse.number)-Number(b.horse.number):
   -order||Number(a.horse.number)-Number(b.horse.number);
 }):runnerOddsRows;
 const rosterIds=horses.map(x=>x.horseId);
 const validRows=rows.map(row=>row.filter(id=>rosterIds.includes(id)));
 const combos=useMemo(()=>expandOmr(betType,validRows,rosterIds),
  [betType,validRows.map(x=>x.join(",")).join("|"),rosterIds.join(",")]);
 const total=combos.length*Number(stakeEach);
 const validStake=Number.isInteger(Number(stakeEach))&&Number(stakeEach)>=100&&
    Number(stakeEach)<=10000&&combos.length>=1&&combos.length<=100&&total<=10000;
 const canPurchase=validStake&&data?.bettingOpen&&!!token&&!busy&&
    Number(data?.maxStake||0)>=total;
 const comboKey=combos.map(arr=>arr.join(":")).join("|");
 useEffect(()=>{
  if(readOnly||!validStake||!data?.bettingOpen){setQuote(null);return;}
  let live=true;
  const timer=setTimeout(async()=>{
   try{
    const res=await fetch("/api/player/race-bet",{method:"POST",
     headers:{"Content-Type":"application/json"},
     body:JSON.stringify({action:"omr-quote",raceId,betType,
       combinations:combos,amountEach:Number(stakeEach)})});
    const body=await res.json();
    if(live)setQuote(res.ok&&body.status==="OK"?body:null);
   }catch{if(live)setQuote(null);}
  },350);
  return()=>{live=false;clearTimeout(timer)};
 },[raceId,betType,comboKey,stakeEach,validStake,data?.bettingOpen,data?.betCount,readOnly]);
 const switchType=id=>{setBetType(id);setRows([[],[],[]]);setQuote(null);setError("");setNotice("");setRunnerOddsSort(null)};
 const toggle=(rowIndex,id)=>{
  setRows(before=>before.map((row,i)=>i!==rowIndex?row:
   row.includes(id)?row.filter(x=>x!==id):
    [...row,id].sort((a,b)=>rosterIds.indexOf(a)-rosterIds.indexOf(b))));
  setQuote(null);setError("");setNotice("");
 };
 const nameFor=id=>{const h=horses.find(x=>x.horseId===id);return h?String(h.number):"?"};
 const selectionLabel=pick=>pick.map(nameFor).join(
   ["EXACTA","TRIFECTA"].includes(betType)?" → ":" + ");
 const buy=async()=>{
  if(!canPurchase)return;
  const stake=Number(stakeEach);
  if(!window.confirm(`[${current.label}] ${fmt(combos.length)}조합 × ${fmt(stake)}G = 총 ${fmt(total)}G를 구매하시겠습니까?\n신청 이후 베팅은 취소할 수 없습니다.`))return;
  const signature=[raceId,betType,comboKey,stake].join("|");
  if(requestRef.current.signature!==signature)
   requestRef.current={signature,id:crypto.randomUUID()};
  setBusy(true);setError("");setNotice("");
  try{
   const res=await fetch("/api/player/race-bet",{method:"POST",
    headers:{"Content-Type":"application/json",Authorization:"Bearer "+token},
    body:JSON.stringify({action:"omr-batch",raceId,betType,
      combinations:combos,amountEach:stake,requestId:requestRef.current.id})});
   const body=await res.json();
   if(!res.ok)throw Error(errMap[body.error]||body.error||"OMR 베팅 구매에 실패했습니다.");
   setNotice(`${current.label} ${fmt(body.ticketCount)}조합 · 총 ${fmt(body.totalAmount)}G가 접수됐습니다. 나의 베팅 이력에서 조합별 결과를 확인할 수 있습니다.`);
   requestRef.current={signature:"",id:""};
   await load();
  }catch(e){setError(e.message||"OMR 베팅 구매 실패")}finally{setBusy(false);}
 };
 if(!data&&!error)return <div className="notice">경주 전문가 정보와 배당을 불러오는 중입니다…</div>;
 return <section className="race-betting omr-betting" data-tutorial-target={readOnly?"betting":undefined}>
  <div className="section"><h2>{readOnly?"📈 경주 전문가 예상지":"📈 AI 예상가 · OMR 7개 승식"}</h2>
   {!readOnly&&<a className="outline" href="/bets" style={{textDecoration:"none"}}>📒 나의 베팅 이력 ›</a>}</div>
  {data?.entryAnnouncementPending&&<div className="notice">출전마 발표는 경주 당일 오전 8시(한국시간)입니다.</div>}
  {error&&<div className="notice" role="alert">{error}</div>}
  {notice&&<div className="notice" role="status">{notice}</div>}
  {data&&<>
   <div className="card"><div className="row"><b className="gold">AI 예상가 3명 · 경주 참고 정보</b>
    <button className="outline" type="button" onClick={load}>↻ 새로고침</button></div>
    <div className="bet-analysts expert-grid">{(data.analysts||[]).map(t=>
     <div className="bet-analyst expert-card" key={t.analyst}>
      <div className="expert-title"><strong>{t.analyst}</strong>
       <small>{t.headline||"경주 데이터 분석"}</small></div>
      <div className="expert-picks">
       {(t.picks||[]).map((pick,index)=><div className="expert-pick" key={pick.horseId||index}>
        <b className={"expert-mark "+(index===0?"expert-key":"")}>{pick.mark}</b>
        <span className="expert-runner-no">{pick.number}번</span>
        <span className="expert-runner-name">{pick.name}</span>
       </div>)}
      </div>
      <div className="expert-legend">◎ 축마 · ○ 대항 · ▲ 도전 · △ 복병 · ☆ 관심</div>
     </div>)}</div>
    <div className="muted" style={{marginTop:9}}>
     전문가별 예상은 서로 다른 분석 기준으로 계산한 참고 의견이며 실제 착순을 보장하지 않습니다.
    </div>
   </div>
   {!readOnly&&<>
   <div className="row" style={{margin:"4px 0 10px",gap:10}}>
    <span className="muted">🎟️ 관중 NPC {fmt(data.spectatorBetCount)}명 참여</span>
    <span className="muted">인기 경주·상위 등급일수록 관중 참여 증가</span>
   </div>
   <div className="section"><h2>승식 선택</h2></div>
   <div className="bet-type-grid">{BET_TYPES.map(t=>
    <button type="button" key={t.id} data-tutorial-target={t.id==="WIN"?"betting":undefined} className={"bet-type-card "+(betType===t.id?"selected":"")}
      aria-pressed={betType===t.id} onClick={()=>switchType(t.id)}><b>{t.label}</b></button>)}</div>
   <div className="card popular-odds-card">
    <div className="row" style={{gap:10,alignItems:"center"}}>
     <b className="gold">{current.legs===1?current.label+" 배당 현황":current.label+" 인기 조합 TOP 20"}</b>
     <button className="outline" type="button" onClick={load}>↻ 갱신</button>
    </div>
    {data.popularOdds?.betType!==betType?
     <div className="muted" style={{padding:"13px 0"}}>선택한 승식의 배당을 불러오는 중입니다…</div>:
     data.popularOdds.status==="UNANNOUNCED"?
     <div className="muted" style={{padding:"13px 0"}}>경주 당일 오전 8시 출전표 공개 후 배당이 표시됩니다.</div>:
     <>
      {current.legs===1?
       <div className="race-entry-wrap" style={{marginTop:11}}>
        <table className="race-entry-table popular-odds-table">
         <thead><tr><th>마번</th><th>경주마</th><th aria-sort={runnerOddsSort==="asc"?"ascending":runnerOddsSort==="desc"?"descending":"none"}>
          <button type="button" className="odds-sort-button" onClick={()=>setRunnerOddsSort(value=>value==="asc"?"desc":"asc")}
           aria-label={runnerOddsSort==="asc"?"현재 배당률 내림차순 정렬":"현재 배당률 오름차순 정렬"}>
           현재 배당률 <span>{runnerOddsSort==="asc"?"▲":runnerOddsSort==="desc"?"▼":"↕"}</span>
          </button></th></tr></thead>
         <tbody>{visibleRunnerOddsRows.map(({horse:h,odds})=>{
          return <tr key={h.horseId}><td>{h.number}</td><td>{h.name}</td>
           <td className="popular-odds-value">{odds!=null?Number(odds).toFixed(2)+"배":"—"}</td>
          </tr>;
         })}</tbody>
        </table>
       </div>:
       (data.popularOdds.popular||[]).length>0?
        <div className="race-entry-wrap" style={{marginTop:11}}>
         <table className="race-entry-table popular-odds-table">
          <thead><tr><th>인기</th><th>조합</th><th>현재 배당률</th></tr></thead>
          <tbody>{(data.popularOdds.popular||[]).map(p=>
           <tr key={p.rank}>
            <td>{p.rank}위</td>
            <td className="popular-odds-combination">
             {(p.numbers||[]).join(["EXACTA","TRIFECTA"].includes(betType)?" → ":" - ")}
            </td>
            <td className="popular-odds-value">{p.odds!=null?Number(p.odds).toFixed(2)+"배":"—"}</td>
           </tr>)}</tbody>
         </table>
        </div>:
        <div className="muted" style={{padding:"14px 0"}}>
         아직 베팅된 조합이 없습니다. 베팅이 접수되면 인기순위가 표시됩니다.
        </div>}
      {data.popularOdds.isUpperBound&&
       <div className="muted" style={{marginTop:7,fontSize:11}}>
        연승·복연승은 여러 조합이 적중할 수 있어 표시 배당이 예상 상한입니다.
       </div>}
      <div className="popular-odds-footer">
       <span>{current.label} 전체 베팅금액</span>
       <strong>{fmt(data.popularOdds.totalAmount)}G</strong>
      </div>
     </>}
   </div>
   <div className="card">
    <div className="row"><b className="gold">🎟️ {current.label} OMR 카드</b>
     <span className="tag">{data.bettingOpen?"접수 중":"접수 마감/준비 중"}</span></div>
    <p className="muted" style={{marginTop:9}}>{current.rule} · 번호를 여러 개 선택할 수 있습니다.
      첫 줄만 선택하면 박스 조합, 다음 줄을 선택하면 줄 간 조합으로 계산됩니다.
      {["EXACTA","TRIFECTA"].includes(betType)&&" 이 승식은 순서가 서로 다르면 다른 조합입니다."}</p>
    {Array.from({length:current.legs},(_,line)=>
     <div className="omr-card-row" key={line}>
      <div className="row"><strong>{current.legs===1?"선택 번호":line+1+"열"}</strong>
        <button type="button" className="outline" onClick={()=>setRows(prev=>prev.map((r,i)=>i===line?[]:r))}>
         선택 해제</button></div>
      <div className="omr-number-grid" role="group" aria-label={line+1+"열 경주마 번호"}>
       {horses.map(h=><button type="button" key={h.horseId}
        className={"omr-number "+(validRows[line]?.includes(h.horseId)?"marked":"")}
        aria-pressed={Boolean(validRows[line]?.includes(h.horseId))}
        title={h.number+"번 "+h.name}
        onClick={()=>toggle(line,h.horseId)}>{h.number}</button>)}
      </div>
     </div>)}
    <div className="omr-horse-legend">{horses.map(h=>
     <span key={h.horseId}><b>{h.number}</b> {h.name}</span>)}</div>
    <div className="omr-combinations">
      <div className="row"><b>자동 생성 조합</b><strong className="gold">{fmt(combos.length)}조합</strong></div>
      {combos.length?<div className="omr-combo-list">{combos.slice(0,24).map((pick,i)=>
       <span key={pick.join(":")}>{selectionLabel(pick)}</span>)}
       {combos.length>24&&<span>외 {fmt(combos.length-24)}조합</span>}
       </div>:<div className="muted" style={{marginTop:8}}>
        {current.legs===1?"1개 이상 번호를 선택하세요.":current.legs===2?
         "첫 줄에서 2개 이상 또는 각 줄에서 1개 이상 번호를 선택하세요.":
         "첫 줄에서 3개 이상, 또는 줄을 나누어 총 3두가 되도록 선택하세요."}
       </div>}
      {combos.length>100&&<p className="bet-negative">100조합을 초과했습니다. 번호 선택을 줄여 주세요.</p>}
    </div>
    {typeof data.walletBalance==="number"&&<div className="muted" style={{marginTop:11}}>
     내 게임머니 {fmt(data.walletBalance)}G · 이 경주에 사용 {fmt(data.raceStakeUsed)}G ·
     추가 가능 {fmt(data.maxStake)}G</div>}
    <label className="bet-stake-label">조합당 신청 금액 (G)
      <input className="field" type="number" min="100" max="10000" step="100"
       value={stakeEach} onChange={e=>setStakeEach(Number(e.target.value))}/>
    </label>
    <div className="omr-stake-summary"><span>총 구매 금액</span>
       <b>{fmt(combos.length)}조합 × {fmt(stakeEach)}G = <span className="gold">{fmt(total)}G</span></b>
    </div>
    <div className="bet-refund-preview" aria-live="polite">
      <div className="row"><strong>예상 환급액 (적중 조합당)</strong>
       <b className="gold bet-refund-amount">{quote?.status==="OK"?
       quote.estimatedPayoutMin===quote.estimatedPayoutMax?
        "약 "+fmt(quote.estimatedPayoutMin)+"G":
        "약 "+fmt(quote.estimatedPayoutMin)+"~"+fmt(quote.estimatedPayoutMax)+"G":"—"}</b></div>
      <small className="muted">현재 승식 풀에 선택한 전체 조합의 신청 금액을 추가한 예상치입니다.
       {quote?.multiWinnerPossible?
        " 여러 조합이 동시에 적중할 수 있으므로 실제 합산 환급액과 다를 수 있습니다.":
        " 실제 환급액은 최종 접수 금액과 적중 조합에 따라 달라집니다."}</small>
    </div>
    <button className="primary" style={{width:"100%",marginTop:13}}
     disabled={!canPurchase} onClick={buy}>{busy?"일괄 신청 처리 중…":
      `${current.label} ${fmt(combos.length)}조합 · 총 ${fmt(total)}G 구매`}</button>
    {!token&&<div className="muted" style={{marginTop:8}}>베팅하려면 로그인해 주세요.</div>}
    {validStake&&Number(data.maxStake||0)<total&&token&&
     <div className="muted" style={{marginTop:8}}>전체 구매액이 이 경주의 추가 베팅 한도를 초과합니다.</div>}
   </div>
   {token&&data.mine?.length>0&&<div className="card">
    <div className="row"><b className="gold">🎫 내 베팅 이력 · 이 경주</b>
     <a className="outline" style={{textDecoration:"none"}} href="/bets">전체 보기 ›</a></div>
    {data.mine.slice(0,12).map(b=><div className="bet-ticket-row" key={b.betId}>
     <div><b>{names[b.betType]||"단승"}</b>
       <span className="muted"> {(b.selections||[b.horseId]).map(id=>
        horses.find(h=>h.horseId===id)?.number||"?").join(
        ["EXACTA","TRIFECTA"].includes(b.betType)?" → ":" + ")}</span>
       <small>{fmt(b.amount)}G</small></div>
     <div><b>{b.status==="PLACED"?"정산 대기":b.status==="WON"?"적중":b.status==="REFUNDED"?"환급":"미적중"}</b>
       <small>지급 {fmt(b.payout)}G</small></div>
    </div>)}
    {data.mine.length>12&&<div className="muted">나머지 {fmt(data.mine.length-12)}건은 전체 이력에서 볼 수 있습니다.</div>}
   </div>}
   </>}
  </>}
 </section>;
}
