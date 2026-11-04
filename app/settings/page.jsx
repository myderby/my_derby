"use client";
import {useCallback,useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";

const providers=[
 {id:"google",label:"Google",icon:"G"},
 {id:"apple",label:"Apple",icon:""},
 {id:"custom:naver",label:"네이버",icon:"N"},
 {id:"kakao",label:"카카오톡",icon:"K"}
];

export default function SettingsPage(){
 const supabase=useMemo(()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY),[]);
 const [user,U]=useState(null),[identities,I]=useState([]),[email,E]=useState(""),[password,P]=useState("");
 const [loading,L]=useState(true),[busy,B]=useState(false),[message,M]=useState("");
 const refresh=useCallback(async()=>{
  const [{data:{user:current},error:userError},{data:identityData,error:identityError}]=await Promise.all([
   supabase.auth.getUser(),supabase.auth.getUserIdentities()
  ]);
  if(userError)throw userError;
  if(identityError)throw identityError;
  U(current);I(identityData?.identities||[]);E(current?.email||"");
 },[supabase]);
 useEffect(()=>{
  let active=true;
  refresh().catch(error=>{if(active)M(error.message||"계정 정보를 불러오지 못했습니다.")}).finally(()=>{if(active)L(false)});
  const {data:{subscription}}=supabase.auth.onAuthStateChange(()=>setTimeout(()=>{
   if(active)refresh().catch(error=>M(error.message||"계정 정보를 새로고침하지 못했습니다."));
  },0));
  return()=>{active=false;subscription.unsubscribe()};
 },[refresh,supabase]);
 const linked=provider=>identities.some(item=>item.provider===provider||
  (provider==="custom:naver"&&(item.provider==="naver"||item.identity_data?.provider==="naver")));
 const linkProvider=async provider=>{
  if(busy)return;B(true);M("");
  try{
   const {error}=await supabase.auth.linkIdentity({provider,options:{redirectTo:window.location.origin+"/settings"}});
   if(error)throw error;
  }catch(error){M(error.message||"계정을 연결하지 못했습니다.")}
  finally{B(false)}
 };
 const requestEmailLink=async event=>{
  event.preventDefault();if(busy)return;B(true);M("");
  try{
   const {error}=await supabase.auth.updateUser({email:email.trim()},{emailRedirectTo:window.location.origin+"/settings"});
   if(error)throw error;
   M("인증 메일을 보냈습니다. 메일의 인증 링크를 완료하면 현재 게임 계정에 이메일이 연결됩니다.");
  }catch(error){M(error.message||"인증 메일을 보내지 못했습니다.")}
  finally{B(false)}
 };
 const savePassword=async event=>{
  event.preventDefault();if(busy)return;
  if(password.length<6){M("비밀번호는 6자 이상 입력해주세요.");return}
  B(true);M("");
  try{
   const {error}=await supabase.auth.updateUser({password});
   if(error)throw error;
   P("");M("비밀번호를 등록했습니다. 현재 게임 데이터는 그대로 유지됩니다.");
  }catch(error){M(error.message||"비밀번호를 등록하지 못했습니다.")}
  finally{B(false)}
 };
 const guest=!!user?.is_anonymous;
 return <main className="shell" style={{maxWidth:760}}>
  <header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">⚙ 설정</span></header>
  <div className="pageTitle"><a className="back" href="/">‹</a><div><h1>설정</h1><div className="sub">계정 연동 및 로그인 방법</div></div></div>
  {loading?<div className="notice">계정 정보를 확인하고 있습니다…</div>:<>
   <section className="card">
    <h2 style={{marginTop:0}}>계정 상태</h2>
    <div className="line row"><span>계정 유형</span><b className="gold">{guest?"게스트":"연동 계정"}</b></div>
    <div className="line row"><span>이메일</span><b>{user?.email||"미연결"}</b></div>
    <div className="muted" style={{lineHeight:1.6,marginTop:8}}>{guest?
     "게스트는 현재 브라우저에서만 복구할 수 있습니다. 로그아웃하거나 브라우저 데이터를 지우기 전에 로그인 수단을 연결해주세요.":
     "연결된 로그인 수단은 같은 게임 계정으로 이용됩니다."}</div>
   </section>
   <section className="card">
    <h2 style={{marginTop:0}}>소셜 계정 연결</h2>
    <div className="muted" style={{marginBottom:12}}>연결하면 현재 마주와 게임 기록을 유지하면서 해당 계정으로 로그인할 수 있습니다.</div>
    <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(135px,1fr))",gap:8}}>
     {providers.map(provider=><button key={provider.id} type="button" className="outline" disabled={busy||linked(provider.id)}
      onClick={()=>linkProvider(provider.id)} style={{minHeight:44}}>{linked(provider.id)?"연결됨 · "+provider.label:provider.label+" 연결"}</button>)}
    </div>
   </section>
   <section className="card">
    <h2 style={{marginTop:0}}>이메일·비밀번호 등록</h2>
    <p className="muted" style={{lineHeight:1.6}}>이메일 인증과 비밀번호를 설정하면 게스트 계정을 별도 회원 계정으로 전환할 수 있습니다. 게임 데이터는 현재 계정에 남습니다.</p>
    <form onSubmit={requestEmailLink}>
     <label className="muted" htmlFor="accountEmail">이메일</label>
     <input id="accountEmail" className="field" type="email" required value={email} onChange={event=>E(event.target.value)} placeholder="name@example.com"/>
     <button className="primary wide" disabled={busy||!email.trim()}>{busy?"처리 중…":"이메일 인증 메일 보내기"}</button>
    </form>
    {!guest&&<form onSubmit={savePassword} style={{marginTop:16}}>
     <label className="muted" htmlFor="accountPassword">새 비밀번호</label>
     <input id="accountPassword" className="field" type="password" minLength={6} required value={password} onChange={event=>P(event.target.value)} placeholder="6자 이상"/>
     <button className="outline wide" disabled={busy||password.length<6}>비밀번호 등록·변경</button>
    </form>}
   </section>
   {message&&<div className="notice" role="status">{message}</div>}
   <div className="footer">네이버 로그인은 Supabase에서 `custom:naver` 제공자 설정이 필요합니다.</div>
  </>}
 </main>;
}
