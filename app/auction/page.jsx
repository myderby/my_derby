"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const fmt=v=>new Intl.NumberFormat("ko-KR").format(v||0);
export default function Auctions(){
 const [token,T]=useState(""),[data,D]=useState(null),[error,E]=useState(""),[msg,M]=useState(""),[busy,B]=useState(false);
 const [horse,H]=useState(""),[start,P]=useState(100000),[days,Y]=useState(7),[bidAmounts,SetBid]=useState({});
 useEffect(()=>{
  let on=true;const c=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  c.auth.getSession().then(({data})=>{if(on)T(data.session?.access_token||"")}).catch(e=>E(e.message));
  const {data:{subscription}}=c.auth.onAuthStateChange((_e,s)=>{if(on)T(s?.access_token||"")});
  return()=>{on=false;subscription.unsubscribe()};
 },[]);
 const load=async(t=token)=>{
  if(!t)return;try{
   const r=await fetch("/api/player/auction",{headers:{Authorization:"Bearer "+t},cache:"no-store"});
   const body=await r.json();if(!r.ok)throw new Error(body.error||"경매 조회 실패");
   D(body);H(old=>body.myHorses?.some(h=>h.id===old)?old:body.myHorses?.find(h=>h.saleState==="NOT_LISTED")?.id||"");E("");
  }catch(e){E(e.message)}
 };
 useEffect(()=>{if(token)void load(token)},[token]);
 const send=async(body)=>{
  if(!window.confirm(body.action==="BID"?"이 금액을 경매에 예치하고 입찰하시겠습니까?":body.action==="CANCEL"?"경매를 취소하고 현재 최고 입찰자의 예치금을 환불하시겠습니까?":"경주마를 경매에 등록하시겠습니까?"))return;
  B(true);E("");M("");
  try{
   const r=await fetch("/api/player/auction",{method:"POST",headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify(body)});
   const v=await r.json();if(!r.ok)throw new Error(v.error||"경매 요청 실패");
   M(body.action==="BID"?"입찰 성공 · 낙찰 전까지 예치금이 잠깁니다.":body.action==="CANCEL"?"경매 취소 및 최고 입찰금 환불이 완료되었습니다.":"경매 등록 완료 · 기간 종료 시 자동 정산됩니다.");
   await load();
  }catch(e){E(e.message)}finally{B(false)}
 };
 const mine=(data?.myHorses||[]).filter(h=>h.saleState==="NOT_LISTED");
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🔨 경주마 경매</span></header>
 <div className="area">
 <div className="controls"><a href="/market" className="outline" style={{textDecoration:"none"}}>‹ 즉시구매 시장</a><a href="/finance" className="outline" style={{textDecoration:"none"}}>게임머니 ›</a></div>
 <div className="section"><h2>실제 입찰 경매</h2><button onClick={()=>load()} disabled={!token||busy}>새로고침 ↻</button></div>
 <div className="notice">입찰액은 즉시 예치됩니다. 더 높은 입찰이 들어오면 예치금이 자동 환불되고, 경매 마감 시 최고 입찰자에게 경주마 소유권이 이전됩니다.</div>
 {error&&<div className="notice" role="alert">⚠ {error}</div>}
 {msg&&<div className="notice" role="status">✓ {msg}</div>}
 {!token&&<div className="notice"><a href="/world">로그인</a> 후 이용 가능합니다.</div>}
 {data&&<>
 <div className="card row"><span className="muted">보유 게임머니</span><b className="gold">{fmt(data.balance)} G</b></div>
 <div className="section"><h2>진행 중인 경매</h2><span className="tag">{data.auctions.length}건</span></div>
 {!data.auctions.length&&<div className="notice">진행 중인 경매가 없습니다. 아래에서 내 말을 경매에 올릴 수 있습니다.</div>}
 {data.auctions.map(a=>{
  const minimum=a.highestBid>0?a.highestBid+a.minIncrement:a.startPrice;
  const amount=bidAmounts[a.listingId]??minimum;
  return <div className="card" key={a.listingId}>
    <div className="row"><div><b className="gold">{a.horseName}</b><div className="muted">{a.track} · {a.horseGrade??"-"}등급 · {a.age}세</div></div><span className="tag">게임 {a.endGameDay}일 마감</span></div>
    <div className="row small line"><span>시작가</span><b>{fmt(a.startPrice)} G</b></div>
    <div className="row small"><span>현재 최고입찰가</span><b>{a.highestBid?fmt(a.highestBid)+" G":"입찰 없음"}</b></div>
    {!a.sellerIsMe&&<>
     <input className="field" type="number" min={minimum} step={a.minIncrement} value={amount}
       onChange={e=>SetBid(v=>({...v,[a.listingId]:Number(e.target.value)}))}/>
     <button className="primary wide" disabled={busy||amount<minimum||!Number.isSafeInteger(amount)}
      onClick={()=>send({action:"BID",listingId:a.listingId,amount})}>입찰하기 (최소 {fmt(minimum)} G)</button>
    </>}
    {a.sellerIsMe&&<div><div className="muted">내가 등록한 경매입니다. 본인 경매에는 입찰할 수 없습니다.</div>
     <button className="outline" disabled={busy} onClick={()=>send({action:"CANCEL",listingId:a.listingId})}>경매 취소 및 입찰금 환불</button></div>}
  </div>
 })}
 <div className="section"><h2>내 말 경매 등록</h2></div>
 <div className="card"><label className="muted">경매에 올릴 말</label>
 <select className="field" value={horse} onChange={e=>H(e.target.value)}>
 {mine.map(h=><option key={h.id} value={h.id}>{h.name} · {h.grade??"-"}등급</option>)}
 </select>
 <label className="muted">경매 시작가 (G)</label><input className="field" type="number" min={50000} max={20000000} step={10000} value={start} onChange={e=>P(Number(e.target.value))}/>
 <label className="muted">경매 기간 (게임일)</label>
 <select className="field" value={days} onChange={e=>Y(Number(e.target.value))}>
 <option value={7}>7일</option><option value={14}>14일</option><option value={21}>21일</option></select>
 <button className="primary wide" disabled={!horse||busy||start<50000||start>20000000}
  onClick={()=>send({action:"CREATE",horseId:horse,price:start,days})}>경매 등록</button></div>
 </>}
 <div className="footer">MY DERBY · 게임머니 예치형 경매 · 매일 자동 마감</div>
 </div></main>;
}