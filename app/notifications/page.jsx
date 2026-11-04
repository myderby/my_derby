"use client";
import {useCallback,useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";

const filters=[["ALL","모두"],["RANCH_MESSAGE","목장 소식"],["TRAINING_MESSAGE","훈련 보고"],["OPERATOR_GIFT","선물"],["OTHER","기타"]];
const labels={RANCH_MESSAGE:"목장 관리사",TRAINING_MESSAGE:"훈련 소식",OPERATOR_GIFT:"운영자 선물"};
const dateOf=v=>{try{return new Date(v).toLocaleString("ko-KR",{timeZone:"Asia/Seoul"})}catch{return "-"}};

export default function Notifications(){
 const [token,T]=useState(""),[loading,L]=useState(true),[data,D]=useState(null),[error,E]=useState("");
 const [filter,F]=useState("ALL"),[busy,B]=useState(0),[isOperator,O]=useState(false);
 useEffect(()=>{let on=true;const c=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  c.auth.getSession().then(({data})=>{if(on){const session=data.session;T(session?.access_token||"");
   const role=session?.user?.app_metadata?.role;O(role==="operator"||role==="admin");L(false)}}).catch(e=>{if(on){E(e.message);L(false)}});
  const {data:{subscription}}=c.auth.onAuthStateChange((_e,s)=>{if(on){T(s?.access_token||"");
   const role=s?.user?.app_metadata?.role;O(role==="operator"||role==="admin")} });
  return()=>{on=false;subscription.unsubscribe()};},[]);
 const refresh=useCallback(async(tokenValue=token)=>{if(!tokenValue)return;
  try{const res=await fetch("/api/player/notifications",{cache:"no-store",headers:{Authorization:"Bearer "+tokenValue}});
   const body=await res.json();if(!res.ok)throw new Error(body.error);D(body);E("");
  }catch(e){E(e.message)}
 },[token]);
 useEffect(()=>{if(token)void refresh(token)},[token,refresh]);
 const action=async(body)=>{B(body.id||body.giftId);E("");try{
   const res=await fetch("/api/player/notifications",{method:"POST",headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify(body)});
   const result=await res.json();if(!res.ok)throw new Error(result.error||"처리하지 못했습니다.");
   await refresh(token);
  }catch(e){E(e.message)}finally{B(0)}};
 const items=useMemo(()=>{const all=data?.items||[];if(filter==="ALL")return all;
  if(filter==="OTHER")return all.filter(x=>!labels[x.category]);
  return all.filter(x=>x.category===filter);
 },[data,filter]);
 return <main className="shell"><header className="header">
  <a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">📬 우편함</span></header>
  <div className="area">
   <div className="controls" style={{marginBottom:12}}><a href="/" className="outline" style={{textDecoration:"none",textAlign:"center"}}>‹ 홈</a>
    {isOperator&&<a href="/operator/mail" className="outline" style={{textDecoration:"none",textAlign:"center"}}>운영자 선물 보내기 ›</a>}
   </div>
   <div className="section"><h2>내 우편함</h2><button disabled={!token||busy>0} onClick={()=>refresh()}>새로고침 ↻</button></div>
   <div className="muted" style={{marginBottom:10}}>목장 관리사의 소식, 조교사·기수의 훈련 보고, 운영자 선물을 확인합니다.</div>
   {loading&&<div className="notice">로그인 확인 중…</div>}
   {!loading&&!token&&<div className="notice">월드에서 로그인하면 우편함을 이용할 수 있습니다.</div>}
   {error&&<div className="notice" role="alert">{error}</div>}
   {data&&<>
    <div className="card row"><div><b className="gold">읽지 않은 편지</b><div className="muted">새 소식과 아직 수령하지 않은 선물</div></div><span className="tag">{data.unread||0}건</span></div>
    <div className="tabs" aria-label="우편함 분류">{filters.map(([key,label])=><button key={key} className={filter===key?"active":""} onClick={()=>F(key)}>{label}</button>)}</div>
    {!items.length&&<div className="notice">이 분류에 편지가 없습니다.</div>}
    {items.map(n=><article className="card" key={n.id}>
     <div className="row" style={{alignItems:"flex-start"}}><div><b className="gold">{n.title}</b>
      <div className="muted" style={{marginTop:5}}>{n.senderName||labels[n.category]||"MY DERBY 소식"} · {dateOf(n.createdAt)}</div></div>
      <span className="tag">{n.readAt?"읽음":"새 편지"}</span></div>
     <div style={{marginTop:10,lineHeight:1.7}}>{n.body}</div>
     {n.gift&&<div className="notice" style={{marginTop:11}}>
      <div className="row"><b>🎁 {n.gift.itemName}</b><span className="tag">{n.gift.quantity}개</span></div>
      {n.gift.description&&<div className="muted" style={{marginTop:5}}>{n.gift.description}</div>}
      {n.gift.claimedAt?<div className="green" style={{marginTop:7}}>보관함에 수령 완료</div>:
       <button className="primary" disabled={busy===n.gift.id} onClick={()=>action({action:"CLAIM_GIFT",giftId:n.gift.id})} style={{marginTop:9}}>
        {busy===n.gift.id?"수령 중…":"선물 수령"}</button>}
     </div>}
     {!n.readAt&&<button className="outline" disabled={busy===n.id} onClick={()=>action({id:n.id})} style={{marginTop:10}}>읽음 처리</button>}
    </article>)}
    <div className="section"><h2>아이템 보관함</h2><span className="tag">{(data.inventory||[]).length}종</span></div>
    {!data.inventory?.length&&<div className="notice">수령한 아이템이 없습니다. 운영자 선물은 편지에서 수령하면 이곳에 보관됩니다.</div>}
    {(data.inventory||[]).map(item=><div className="card row" key={item.code}>
     <div><b className="gold">{item.name}</b>{item.description&&<div className="muted">{item.description}</div>}
      <div className="muted">코드 {item.code}</div></div><span className="pill">× {item.quantity}</span>
    </div>)}
   </>}
   <div className="footer">MY DERBY · 개인 우편과 선물 보관함</div>
  </div></main>;
}
