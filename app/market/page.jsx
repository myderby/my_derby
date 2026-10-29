"use client";
import {useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const create=()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
const format=v=>new Intl.NumberFormat("ko-KR").format(v||0);
const human=s=>({"NOT_YOUR_HORSE":"본인 소유 경주마만 거래할 수 있습니다.","HORSE_CANNOT_BE_LISTED":"출전 신청 중이거나 판매할 수 없는 상태입니다.","INSUFFICIENT_FUNDS":"게임머니 잔액이 부족합니다.","LISTING_NOT_AVAILABLE":"이미 판매되었거나 종료된 상품입니다.","HORSE_ALREADY_RACING":"출전 중인 말은 구매할 수 없습니다."})[String(s)]||String(s||"거래 실패");
export default function Market(){
 const [token,T]=useState(""),[checking,C]=useState(true),[board,B]=useState(null),
 [error,E]=useState(""),[message,M]=useState(""),[busy,X]=useState(false),
 [horse,H]=useState(""),[price,P]=useState(200000),[track,Track]=useState("전체");
 useEffect(()=>{let ok=true;const api=create();
 api.auth.getSession().then(({data})=>{if(ok){T(data.session?.access_token||"");C(false)}});
 const {data:{subscription}}=api.auth.onAuthStateChange((_e,s)=>{if(ok)T(s?.access_token||"")});
 return()=>{ok=false;subscription.unsubscribe()};},[]);
 const load=async(t=token)=>{
  if(!t)return;
  try{const r=await fetch("/api/player/market",{headers:{"Authorization":"Bearer "+t},cache:"no-store"});
   const d=await r.json();if(!r.ok)throw new Error(d.error);B(d);E("");
   H(x=>d.horses.some(h=>h.id===x)?x:d.horses.find(h=>h.saleState==="NOT_LISTED")?.id||"");
  }catch(e){E(human(e.message));}
 };
 useEffect(()=>{if(token)void load(token)},[token]);
 const transact=async(data)=>{
  if(data.action==="BUY"&&!window.confirm("이 경주마를 게임머니로 구매하시겠습니까?"))return;
  if(data.action==="LIST"&&!window.confirm("경주마를 즉시판매 매물로 등록하시겠습니까?"))return;
  X(true);M("");E("");
  try{const r=await fetch("/api/player/market",{method:"POST",
   headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify(data)});
   const out=await r.json();if(!r.ok)throw new Error(out.error);
   M(data.action==="BUY"?"구매가 완료되어 내 보유마에 추가되었습니다.":
     data.action==="LIST"?"매물 등록 완료":"매물 취소 완료");
   await load();
  }catch(e){E(human(e.message))}finally{X(false)}
 };
 const listings=useMemo(()=>board?.listings?.filter(l=>track==="전체"||l.track===track)||[],[board,track]);
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">💰 경주마 시장</span></header>
 <div className="area">
  <div className="controls" style={{marginBottom:12}}><a className="outline" style={{textDecoration:"none"}} href="/world">‹ 월드</a><a className="outline" style={{textDecoration:"none"}} href="/finance">재무 내역 ›</a></div>
  <div className="section"><h2>실제 경주마 거래</h2><button onClick={()=>load()} disabled={!token||busy}>새로고침 ↻</button></div>
  {error&&<div className="notice" role="alert">⚠ {error}</div>}
  {message&&<div className="notice" role="status">✓ {message}</div>}
  {checking&&<div className="notice">로그인 확인 중…</div>}
  {!checking&&!token&&<div className="notice"><a href="/world">월드에서 로그인</a>해야 이용할 수 있습니다.</div>}
  {board&&<>
   <div className="card row"><div><div className="muted">내 게임머니 잔액</div><b className="large gold">{format(board.balance)} G</b></div><a href="/finance" className="outline" style={{textDecoration:"none"}}>지갑 ›</a></div>
   <div className="notice">현재는 즉시판매 거래를 지원합니다. 기존 경주 성적·잠재 능력치는 거래 후에도 보존됩니다.
    판매 수수료는 현재 임시 설정값 {format(board.feeBasisPoints/100)}%이며, 일반 입찰 경매는 별도 연동이 필요합니다.</div>
   <div className="section"><h2>즉시 구매 매물</h2><span className="tag">{listings.length}두</span></div>
   <div className="tabs">{["전체","서울","부산","영천"].map(t=><button className={track===t?"active":""} key={t} onClick={()=>Track(t)}>{t}</button>)}</div>
   {!listings.length&&<div className="notice">현재 구매 가능한 매물이 없습니다.</div>}
   {listings.map(l=><div className="card" key={l.id}>
    <div className="row"><div><b className="gold">{l.name}</b><div className="muted">{l.track} · {l.grade??"-"}등급 · {l.age}세 · {l.sex}</div>
     <div className="muted">{l.sellerType==="SYSTEM"?"시스템 매물":l.sellerType==="MY_LISTING"?"내 판매 매물":"다른 마주 매물"}</div></div>
    <div style={{textAlign:"right"}}><b>{format(l.price)} G</b>
     {l.sellerType==="MY_LISTING"?<button className="outline" disabled={busy} onClick={()=>transact({action:"CANCEL",listingId:l.id})}>판매 취소</button>:
     <button className="primary" disabled={busy||board.balance<l.price} onClick={()=>transact({action:"BUY",listingId:l.id})}>구매하기</button>}</div></div>
   </div>)}
   <div className="section"><h2>내 경주마 판매 등록</h2></div>
   <div className="card">
    <label className="muted" htmlFor="horse">판매할 경주마</label>
    <select className="field" id="horse" value={horse} onChange={e=>H(e.target.value)}>
     {(board.horses||[]).filter(h=>h.saleState==="NOT_LISTED").map(h=><option value={h.id} key={h.id}>{h.name} · {h.grade??"-"}등급 · {h.age}세</option>)}
    </select>
    <label className="muted" htmlFor="price">즉시판매 가격 (게임머니)</label>
    <input className="field" id="price" type="number" min="50000" max="20000000" step="10000" value={price} onChange={e=>P(Number(e.target.value))}/>
    <div className="muted">판매 성사 시 게임머니가 지급됩니다. 출전 신청 중이거나 임신 중인 말은 등록할 수 없습니다.</div>
    <button className="primary wide" disabled={!horse||busy||!Number.isSafeInteger(price)||price<50000||price>20000000}
      onClick={()=>transact({action:"LIST",horseId:horse,price})}>내 말 시장에 등록</button>
   </div>
  </>}
  <div className="footer">MY DERBY · DB 소유권 이전 및 원장 이체 · 온라인 입찰 경매는 준비 중</div>
 </div></main>
}