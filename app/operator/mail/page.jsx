"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
export default function OperatorMail(){
 const [token,T]=useState(""),[role,R]=useState(""),[loading,L]=useState(true),[search,S]=useState(""),[recipients,U]=useState([]),[selected,V]=useState("");
 const [itemCode,C]=useState("CARE_PACK"),[itemName,N]=useState("말 돌봄 꾸러미"),[description,D]=useState(""),[quantity,Q]=useState(1),[message,M]=useState(""),[busy,B]=useState(false),[notice,H]=useState(""),[error,E]=useState("");
 useEffect(()=>{let active=true;const client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  client.auth.getSession().then(({data})=>{if(!active)return;const session=data.session;T(session?.access_token||"");R(session?.user?.app_metadata?.role||"");L(false)}).catch(e=>{if(active){E(e.message);L(false)}});
  const {data:{subscription}}=client.auth.onAuthStateChange((_event,session)=>{if(active){T(session?.access_token||"");R(session?.user?.app_metadata?.role||"")}});
  return()=>{active=false;subscription.unsubscribe()};},[]);
 const searchUsers=async()=>{if(!token)return;E("");try{const res=await fetch("/api/operator/mail?search="+encodeURIComponent(search),{cache:"no-store",headers:{Authorization:"Bearer "+token}});
  const data=await res.json();if(!res.ok)throw new Error(data.error);U(data.recipients||[]);V(current=>(data.recipients||[]).some(x=>x.userId===current)?current:data.recipients?.[0]?.userId||"");
 }catch(e){E(e.message)}};
 useEffect(()=>{if(token&&["operator","admin"].includes(role))void searchUsers()},[token,role]);
 const send=async()=>{if(!selected)return E("받는 마주를 선택해주세요.");B(true);E("");H("");try{
  const res=await fetch("/api/operator/mail",{method:"POST",headers:{Authorization:"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify({userId:selected,itemCode,itemName,itemDescription:description,quantity,message})});
  const data=await res.json();if(!res.ok)throw new Error(data.error);H(`${data.recipientNickname} 마주에게 ${itemName} ${quantity}개를 보냈습니다.`);
 }catch(e){E(e.message)}finally{B(false)}};
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🎁 운영자 우편</span></header>
  <div className="area"><div className="controls" style={{marginBottom:12}}><a href="/notifications" className="outline" style={{textDecoration:"none",textAlign:"center"}}>‹ 우편함</a><a href="/" className="outline" style={{textDecoration:"none",textAlign:"center"}}>홈</a></div>
   <div className="section"><h2>아이템 선물 보내기</h2></div>
   {loading&&<div className="notice">운영자 권한 확인 중…</div>}
   {!loading&&!token&&<div className="notice">로그인해야 이용할 수 있습니다.</div>}
   {!loading&&token&&!(["operator","admin"].includes(role))&&<div className="notice">이 화면은 운영자 계정만 사용할 수 있습니다.</div>}
   {error&&<div className="notice" role="alert">{error}</div>}{notice&&<div className="notice" role="status">✓ {notice}</div>}
   {token&&["operator","admin"].includes(role)&&<>
    <div className="card"><label className="muted" htmlFor="recipient-search">받는 마주 검색</label>
     <div className="controls"><input id="recipient-search" className="field" value={search} maxLength={40} onChange={e=>S(e.target.value)} placeholder="닉네임 검색" style={{marginBottom:0}}/>
      <button className="outline" onClick={searchUsers}>검색</button></div>
     <label className="muted" htmlFor="recipient" style={{display:"block",marginTop:12}}>수신자</label>
     <select id="recipient" className="field" value={selected} onChange={e=>V(e.target.value)}>
      {!recipients.length&&<option value="">마주를 찾지 못했습니다</option>}{recipients.map(p=><option key={p.userId} value={p.userId}>{p.nickname}</option>)}
     </select>
    </div>
    <div className="card"><label className="muted" htmlFor="item-code">아이템 코드 (영문 대문자·숫자·밑줄)</label>
     <input id="item-code" className="field" value={itemCode} maxLength={40} onChange={e=>C(e.target.value.toUpperCase())}/>
     <label className="muted" htmlFor="item-name">아이템 이름</label><input id="item-name" className="field" value={itemName} maxLength={60} onChange={e=>N(e.target.value)}/>
     <label className="muted" htmlFor="item-description">설명</label><input id="item-description" className="field" value={description} maxLength={160} onChange={e=>D(e.target.value)}/>
     <label className="muted" htmlFor="quantity">수량</label><input id="quantity" className="field" type="number" min={1} max={99} value={quantity} onChange={e=>Q(Number(e.target.value))}/>
     <label className="muted" htmlFor="message">편지 내용</label><textarea id="message" className="field" rows={4} maxLength={300} value={message} onChange={e=>M(e.target.value)} placeholder="선물과 함께 전할 내용을 적어주세요."/>
     <button className="primary wide" disabled={busy||!selected} onClick={send}>{busy?"보내는 중…":"선물 우편 보내기"}</button>
    </div>
    <div className="muted">선물은 마주가 우편함에서 직접 수령해야 아이템 보관함에 들어갑니다.</div>
   </>}
   <div className="footer">MY DERBY · 운영 우편 관리</div>
  </div></main>;
}
