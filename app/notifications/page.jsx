"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
export default function Notifications(){
 const [token,T]=useState(""),[loading,L]=useState(true),[data,D]=useState(null),[error,E]=useState("");
 useEffect(()=>{let on=true;const c=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
 c.auth.getSession().then(({data})=>{if(on){T(data.session?.access_token||"");L(false)}}).catch(e=>{if(on){E(e.message);L(false)}});
 const {data:{subscription}}=c.auth.onAuthStateChange((_e,s)=>{if(on)T(s?.access_token||"")});return()=>{on=false;subscription.unsubscribe()};},[]);
 const refresh=async(tokenValue=token)=>{if(!tokenValue)return;
  try{const res=await fetch("/api/player/notifications",{cache:"no-store",headers:{"Authorization":"Bearer "+tokenValue}});
   const body=await res.json();if(!res.ok)throw new Error(body.error);D(body);E("");
  }catch(e){E(e.message)}
 };
 useEffect(()=>{if(token)void refresh(token)},[token]);
 const read=async id=>{try{const res=await fetch("/api/player/notifications",{method:"POST",
   headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},
   body:JSON.stringify({id})});if(!res.ok)throw new Error("알림 확인 실패");await refresh();
  }catch(e){E(e.message)}};
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🔔 알림</span></header>
 <div className="area">
 <div className="controls" style={{marginBottom:12}}><a href="/world" className="outline" style={{textDecoration:"none"}}>‹ 월드</a><a href="/finance" className="outline" style={{textDecoration:"none"}}>재무 현황 ›</a></div>
 <div className="section"><h2>내 알림</h2><button disabled={!token} onClick={()=>refresh()}>새로고침 ↻</button></div>
 {loading&&<div className="notice">로그인 확인 중…</div>}
 {!loading&&!token&&<div className="notice">월드에서 로그인해야 알림을 확인할 수 있습니다.</div>}
 {error&&<div className="notice" role="alert">{error}</div>}
 {data&&<><div className="card row"><b className="gold">읽지 않은 알림</b><span className="tag">{data.unread||0}건</span></div>
 {!data.items?.length&&<div className="notice">아직 알림이 없습니다.</div>}
 {(data.items||[]).map(n=><div className="card" key={n.id}>
  <div className="row"><b className="gold">{n.title}</b><span className="tag">{n.readAt?"읽음":"새 알림"}</span></div>
  <div className="muted" style={{marginTop:8}}>{new Date(n.createdAt).toLocaleString("ko-KR",{timeZone:"Asia/Seoul"})} · {n.category}</div>
  <div style={{marginTop:8}}>{n.body}</div>
  {!n.readAt&&<button className="outline" onClick={()=>read(n.id)} style={{marginTop:11}}>확인 완료</button>}
 </div>)}</>}
 <div className="footer">MY DERBY · 마주 본인 전용 알림 보관함</div>
 </div></main>;
}
