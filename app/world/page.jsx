"use client";
import HorseLink from "../components/HorseLink";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";

const sexName={MALE:"수말",FEMALE:"암말",GELDING:"거세마"};
const stageName={FOAL:"망아지",YEARLING:"1세마",RACING:"현역",
 RETIRED:"은퇴",STALLION:"씨수말",BROODMARE:"번식암말",DECEASED:"폐사"};
const skillNames={start:"출발",speed:"속도",acceleration:"가속력",stamina:"지구력",
 finishing:"막판탄력",power:"파워",grit:"근성",stability:"안정성",recovery:"회복력"};
const trackName=s=>s==="부산경남"?"부산":s==="제주"?"영천":s||"소속 미정";
const panels={
 "훈련·건강":[
  {href:"/training",icon:"🐎",title:"훈련계획·리포트",desc:"내 경주마 훈련과 성장"},
  {href:"/stable",icon:"🏠",title:"조교사 위탁·계약",desc:"내 말의 담당 조교사 관리"},
  {href:"/injuries",icon:"🩺",title:"부상·회복 관리",desc:"부상과 회복 상태 확인"},
  {href:"/ranch",icon:"🌲",title:"개인목장",desc:"휴양·재활·어린말 관리"}
 ],
 "출전·기록":[
  {href:"/entries",icon:"🏇",title:"출전·기수 신청",desc:"내 경주마 출전 신청"},
  {href:"/ratings",icon:"📊",title:"레이팅·등급 내역",desc:"성적과 등급 변동"},
  {href:"/schedule",icon:"📅",title:"경주 시간표",desc:"공식 경주 일정과 출전표"}
 ],
 "거래·번식":[
  {href:"/breeding",icon:"✧",title:"교배·번식 관리",desc:"내 말의 번식 신청"},
  {href:"/market",icon:"💰",title:"경주마 시장",desc:"내 말 구매·판매"},
  {href:"/auction",icon:"🔨",title:"경주마 경매",desc:"경매 참여와 거래"}
 ]
};
const makeClient=()=>createClient(
 process.env.NEXT_PUBLIC_SUPABASE_URL,
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
);
export default function WorldPage(){
 const [token,Token]=useState(null);
 const [mine,Mine]=useState(null);
 const [loading,Loading]=useState(true);
 const [active,Active]=useState("내 말");
 const [filter,Filter]=useState("전체");
 const [expanded,Expand]=useState(null);
 const [email,Email]=useState(""),[password,Password]=useState("");
 const [nickname,Nickname]=useState("");
 const [busy,Busy]=useState(false),[notice,Notice]=useState("");
 const [refresh,Refresh]=useState(0);

 useEffect(()=>{
  let mounted=true;
  let subscription;
  try{
   const client=makeClient();
   client.auth.getSession().then(({data,error})=>{
    if(!mounted)return;
    if(error)Notice(error.message);
    Token(data?.session?.access_token||"");
   }).catch(e=>{if(mounted){Notice(e.message);Token("")}});
   const observer=client.auth.onAuthStateChange((_event,s)=>{
    if(mounted)Token(s?.access_token||"");
   });
   subscription=observer.data.subscription;
  }catch(e){Notice("로그인 설정을 확인해주세요.");Token("")}
  return()=>{mounted=false;subscription?.unsubscribe()};
 },[]);

 useEffect(()=>{
  let mounted=true;
  if(token===null)return;
  if(!token){Mine(null);Loading(false);return;}
  Loading(true);
  fetch("/api/world/mine",{cache:"no-store",headers:{Authorization:"Bearer "+token}})
   .then(async res=>{
    const data=await res.json();
    if(!res.ok)throw new Error(data.error||"내 보유마를 조회할 수 없습니다.");
    return data;
   }).then(data=>{if(mounted){Mine(data);Notice("")}})
   .catch(e=>{if(mounted){Mine(null);Notice("내 말 조회 오류: "+e.message)}})
   .finally(()=>{if(mounted)Loading(false)});
  return()=>{mounted=false};
 },[token,refresh]);

 const authenticate=async signup=>{
  if(!email.trim()||!password){Notice("이메일과 비밀번호를 입력해주세요.");return}
  Busy(true);Notice("");
  try{
   const c=makeClient();
   const result=signup?
    await c.auth.signUp({email:email.trim(),password}):
    await c.auth.signInWithPassword({email:email.trim(),password});
   if(result.error)throw result.error;
   Notice(signup&&!result.data.session?"인증 이메일을 확인한 뒤 로그인해주세요.":"로그인했습니다.");
   if(result.data.session)Token(result.data.session.access_token);
  }catch(e){Notice(e.message||"로그인에 실패했습니다.")}
  finally{Busy(false)}
 };
 const join=async()=>{
  if(nickname.trim().length<2||nickname.trim().length>32)return;
  Busy(true);
  try{
   const response=await fetch("/api/world/join",{
    method:"POST",cache:"no-store",
    headers:{"Content-Type":"application/json",Authorization:"Bearer "+token},
    body:JSON.stringify({nickname:nickname.trim()})
   });
   const data=await response.json();
   if(!response.ok)throw new Error(data.error||"마주 등록 실패");
   Notice(data.alreadyJoined?"이미 등록된 마주입니다.":"마주 등록을 완료했습니다.");
   Refresh(x=>x+1);
  }catch(e){Notice("마주 등록 오류: "+e.message)}
  finally{Busy(false)}
 };
 const logout=async()=>{
  Busy(true);
  try{
   const {error}=await makeClient().auth.signOut();
   if(error)throw error;
   Token("");Mine(null);Notice("로그아웃했습니다.");
  }catch(e){Notice(e.message)}
  finally{Busy(false)}
 };
 const horses=mine?.horses||[];
 const breeding=h=>["STALLION","BROODMARE","RETIRED","DECEASED"].includes(h.life_stage);
 const injured=h=>h.health_state==="INJURED"||Number(h.condition_score)<50;
 const visible=horses.filter(h=>filter==="전체"||
   filter==="현역"&&h.life_stage==="RACING"||
   filter==="어린말"&&["FOAL","YEARLING"].includes(h.life_stage)||
   filter==="번식·은퇴"&&breeding(h)||
   filter==="회복 필요"&&injured(h));
 const activeCount=horses.filter(h=>h.life_stage==="RACING").length;
 const fmt=n=>typeof n==="number"?Math.round(n):"-";
 return <main className="shell">
  <header className="header">
   <a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a>
   <span className="coin">🐎 내 말 관리</span>
  </header>
  <div className="area">
   <div className="controls" style={{marginBottom:14}}>
    <a href="/" className="outline" style={{textDecoration:"none"}}>‹ 홈</a>
    {token&&<button className="outline" disabled={loading} onClick={()=>Refresh(x=>x+1)}>보유마 새로고침 ↻</button>}
    {token&&<button className="outline" disabled={busy} onClick={logout}>로그아웃</button>}
   </div>
   <div className="section"><h2>내 말 관리</h2></div>
   {notice&&<div className="notice" role="status">{notice}</div>}
   {token===null||loading?<div className="notice">내 보유 경주마를 불러오는 중입니다…</div>:!token?
    <div className="card">
     <h2 style={{fontSize:19}}>내 말 관리에 로그인하기</h2>
     <div className="muted">로그인한 마주가 소유한 경주마만 표시합니다.</div>
     <input className="field" type="email" autoComplete="email" placeholder="이메일"
      value={email} onChange={e=>Email(e.target.value)}/>
     <input className="field" type="password" autoComplete="current-password" placeholder="비밀번호"
      value={password} onChange={e=>Password(e.target.value)}/>
     <div className="controls">
      <button className="primary" disabled={busy} onClick={()=>authenticate(false)}>로그인</button>
      <button className="outline" disabled={busy} onClick={()=>authenticate(true)}>회원가입</button>
     </div>
    </div>:
    mine&&!mine.joined?
    <div className="card">
     <h2 style={{fontSize:18}}>마주 등록</h2>
     <p className="muted">처음 가입하는 마주에게 경주마 3두를 배정합니다.</p>
     <input className="field" value={nickname} maxLength={32}
      placeholder="마주 닉네임 (2~32자)" onChange={e=>Nickname(e.target.value)}/>
     <button className="primary wide" disabled={busy||nickname.trim().length<2}
      onClick={join}>마주 등록 · 경주마 3두 배정</button>
    </div>:
    mine&&mine.joined?<section>
     <div className="card">
      <div className="row">
       <div><b className="gold">{mine.profile?.nickname||"내 마방"}</b>
        <div className="muted">내가 소유한 경주마의 상태와 능력치를 관리합니다.</div></div>
       <span className="tag">마주</span>
      </div>
      <div className="my-horse-summary">
       <div><b>{horses.length}</b><span>보유마</span></div>
       <div><b>{activeCount}</b><span>현역</span></div>
       <div><b>{horses.filter(breeding).length}</b><span>번식·은퇴</span></div>
      </div>
     </div>
     <div className="tabs my-horse-nav" aria-label="내 말 관리 메뉴">
      {["내 말","훈련·건강","출전·기록","거래·번식"].map(x=>
       <button key={x} className={active===x?"active":""} onClick={()=>Active(x)}>{x}</button>)}
     </div>
     {active==="내 말"?<>
      <div className="section"><h2>내 보유마 · {visible.length}두</h2></div>
      <div className="tabs" aria-label="내 말 분류">
       {["전체","현역","어린말","번식·은퇴","회복 필요"].map(x=>
        <button key={x} className={filter===x?"active":""} onClick={()=>Filter(x)}>{x}</button>)}
      </div>
      {visible.length===0&&<div className="notice">
       {horses.length===0?"아직 보유한 경주마가 없습니다.":"해당 분류에 속한 내 경주마가 없습니다."}
      </div>}
      {visible.map(h=><div className="card my-horse-card" key={h.id}>
       <div className="row">
        <div>
         <b className="gold">🐎 <HorseLink horseId={h.id}>{h.name}</HorseLink></b>
         <div className="muted">
          {trackName(h.source_meet)} · {h.source_grade_no?h.source_grade_no+"등급 · ":""}
          {h.age_years}세 · {sexName[h.sex]||h.sex}
         </div>
        </div>
        <span className="tag">{stageName[h.life_stage]||h.life_stage}</span>
       </div>
       <div className="my-horse-vitals">
        <span>컨디션 <strong>{fmt(h.condition_score)}</strong></span>
        <span>피로도 <strong>{fmt(h.fatigue)}</strong></span>
        <span>건강 <strong>{h.health_state==="HEALTHY"?"정상":h.health_state==="INJURED"?"부상":"상태 확인"}</strong></span>
       </div>
       <div className="controls" style={{marginTop:11}}>
        <HorseLink horseId={h.id} className="outline" style={{textDecoration:"none",fontSize:12}}>
         기본정보·전적 보기 ›
        </HorseLink>
        <button className="outline" onClick={()=>Expand(expanded===h.id?null:h.id)}>
         {expanded===h.id?"능력치 접기":"현재 능력치"}
        </button>
       </div>
       {expanded===h.id&&<div className="my-horse-skills">
        {Object.entries(h.currentStats||{}).map(([k,value])=><div key={k}>
         <span>{skillNames[k]||k}</span><strong>{value}</strong>
        </div>)}
        {!h.currentStats&&<div className="muted">현재 능력치가 등록되지 않았습니다.</div>}
       </div>}
      </div>)}
     </>:<>
      <div className="section"><h2>{active}</h2></div>
      <div className="my-horse-action-grid">
       {(panels[active]||[]).map(item=><a key={item.href}
        className="card my-horse-action" href={item.href}>
        <span className="my-horse-action-icon">{item.icon}</span>
        <b>{item.title}</b><span className="muted">{item.desc}</span>
       </a>)}
      </div>
      <div className="muted" style={{marginTop:14}}>위 메뉴는 보유마 관리 기능으로 이동합니다. 실제 수정 권한은 로그인한 마주에게만 있습니다.</div>
     </>}
    </section>:null}
   <div className="footer">MY DERBY · 내 소유 경주마 관리</div>
  </div>
 </main>;
}
