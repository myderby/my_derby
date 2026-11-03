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
const regionName={SEOUL:"서울",YEONGCHEON:"영천",BUSAN:"부산"};
const regionOptions=[["SEOUL","서울"],["YEONGCHEON","영천"],["BUSAN","부산"]];
const patternOptions=[["solid","민무늬"],["stripe","줄무늬"],["check","체크"],
 ["diamond","다이아"],["dot","점무늬"],["star","별무늬"]];
const defaultSilks={bodyColor:"#D6A84F",sleeveColor:"#23180F",pattern:"solid",patternColor:"#FFFFFF"};
const tutorialTopics=[
 {key:"training",title:"훈련과 성장",text:"훈련계획을 세우고 목장에서 휴양·육성·재활을 관리하세요.",href:"/ranch"},
 {key:"racing",title:"경주 출전",text:"출전표에서 경주와 기수를 확인한 뒤 출전을 신청하세요.",href:"/entries"},
 {key:"results",title:"결과와 기록",text:"출전이 끝나면 결과와 말의 전적을 확인하세요.",href:"/my-record"},
 {key:"ranch",title:"목장과 직원",text:"시설과 관리사를 직접 배치해 말의 회복과 육성을 도와주세요.",href:"/ranch"},
 {key:"betting",title:"경주 베팅",text:"베팅은 선택 기능입니다. 원할 때 경주 정보를 살펴 참여하세요.",href:"/bets"},
 {key:"breeding",title:"교배와 번식",text:"번식 자격을 얻은 말은 번식 메뉴에서 교배를 신청할 수 있어요.",href:"/breeding"},
 {key:"achievements",title:"업적",text:"첫 승리 뒤 나의 정보에서 통산·말별 기록과 우승 호칭을 확인하세요.",href:"/my-record"}
];
const silksColorOptions=["#111111","#3D1E0B","#7A1F1F","#C62828","#EF6C00","#F9A825",
 "#D6A84F","#F5E6C8","#FFFFFF","#9E9E9E","#4CAF50","#1B5E20","#00897B",
 "#00ACC1","#1565C0","#283593","#6A1B9A","#AD1457"];
const setupSteps=["마주명 정하기","마주복 꾸미기","시작 지역 고르기","첫 육성마와 직원 받기"];
const setupGuide=[
 "안녕하세요, 새 마주님! 먼저 경주장에서 사용할 마주명을 정해볼까요?",
 "좋아요. 이제 상의와 소매 색, 무늬를 골라 나만의 마주복을 만들어보세요.",
 "첫 목장을 시작할 지역을 선택해주세요. 선택한 지역은 마주 정보에 저장됩니다.",
 "준비가 거의 끝났어요. 등록을 마치면 2세 육성마 한 마리와 C등급 관리사·수의사가 먼저 합류합니다."
];
function SilksPreview({design,small=false}){
 const patternId="silks-pattern-"+design.pattern;
 return <svg viewBox="0 0 120 96" role="img" aria-label="마주복 상의 미리보기"
  style={{width:small?74:126,height:small?60:96,flex:"0 0 auto"}}>
  <defs><pattern id={patternId} width="16" height="16" patternUnits="userSpaceOnUse">
   <rect width="16" height="16" fill={design.bodyColor}/>
   {design.pattern==="stripe"&&<path d="M-4 16 12 0M4 20 20 4" stroke={design.patternColor} strokeWidth="4"/>}
   {design.pattern==="check"&&<path d="M0 0h8v8H0zM8 8h8v8H8z" fill={design.patternColor}/>}
   {design.pattern==="diamond"&&<path d="M8 1 15 8 8 15 1 8Z" fill={design.patternColor}/>}
   {design.pattern==="dot"&&<circle cx="8" cy="8" r="3" fill={design.patternColor}/>}
   {design.pattern==="star"&&<text x="2" y="13" fontSize="12" fill={design.patternColor}>★</text>}
  </pattern></defs>
  <path d="M40 14 27 17 7 39l16 14 14-15 3 43h40l3-43 14 15 16-14-20-22-13-3-8 7-12-5-12 5-8-7Z"
   fill={`url(#${patternId})`} stroke="#17110d" strokeWidth="3" strokeLinejoin="round"/>
  <path d="m40 14-13 3L7 39l16 14 14-15 5-17Zm40 0 13 3 20 22-16 14-14-15-5-17Z"
   fill={design.sleeveColor} stroke="#17110d" strokeWidth="3" strokeLinejoin="round"/>
  <path d="M40 81h40" stroke="#17110d" strokeWidth="3"/>
 </svg>;
}
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
 const [tutorialStep,TutorialStep]=useState(0);
 const [startingRegion,StartingRegion]=useState("SEOUL");
 const [silksDesign,SilksDesign]=useState(defaultSilks);
 const [colorTarget,ColorTarget]=useState(null),[colorDraft,ColorDraft]=useState("");
 const [busy,Busy]=useState(false),[notice,Notice]=useState("");
 const [refresh,Refresh]=useState(0);
 const [tutorial,Tutorial]=useState(null);
 const [tutorialTopic,TutorialTopic]=useState(null);

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
    await c.auth.signUp({email:email.trim(),password,options:{emailRedirectTo:window.location.origin+"/world"}}):
    await c.auth.signInWithPassword({email:email.trim(),password});
   if(result.error)throw result.error;
   Notice(signup&&!result.data.session?"My Derby 가입 인증 메일을 보냈습니다. 이메일 인증을 마치면 마주명 입력 화면으로 이동합니다.":"로그인했습니다.");
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
    body:JSON.stringify({nickname:nickname.trim(),startingRegion,silksDesign})
   });
   const data=await response.json();
   if(!response.ok)throw new Error(data.error||"마주 등록 실패");
   Notice(data.alreadyJoined?"이미 등록된 마주입니다.":"마주 등록을 완료했습니다.");
   window.dispatchEvent(new Event("my-derby:progress"));
   Refresh(x=>x+1);
  }catch(e){Notice("마주 등록 오류: "+e.message)}
  finally{Busy(false)}
 };
 const saveTutorial=async payload=>{
  if(!token)return;
  try{
   const response=await fetch("/api/player/tutorial",{method:"POST",cache:"no-store",
    headers:{"Content-Type":"application/json",Authorization:"Bearer "+token},
    body:JSON.stringify(payload)});
   const data=await response.json();
   if(!response.ok)throw new Error(data.error||"튜토리얼 저장 실패");
   Tutorial(v=>({...v,...data}));
  }catch(e){Notice("튜토리얼 안내 저장 실패: "+e.message)}
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
 useEffect(()=>{
  let mounted=true;
  if(!token||!mine?.joined){Tutorial(null);return;}
  fetch("/api/player/tutorial",{cache:"no-store",headers:{Authorization:"Bearer "+token}})
   .then(async res=>{const data=await res.json();if(!res.ok)throw new Error(data.error||"상태 조회 실패");return data;})
   .then(data=>{if(mounted)Tutorial(data);})
   .catch(e=>{if(mounted)Notice("튜토리얼 상태 조회 실패: "+e.message);});
  return()=>{mounted=false};
 },[token,mine?.joined,refresh]);
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
 const openColorPicker=(field,label)=>{ColorTarget({field,label});ColorDraft(silksDesign[field])};
 const confirmSilksColor=()=>{
  if(!/^#[0-9A-Fa-f]{6}$/.test(colorDraft)){Notice("색상 코드는 #RRGGBB 형식으로 입력해주세요.");return}
  SilksDesign(v=>({...v,[colorTarget.field]:colorDraft.toUpperCase()}));
  ColorTarget(null);
 };
 const raceDate=r=>r?.date|| (r?.gameDay?`게임 ${r.gameDay}일`:"");
 const raceLabel=r=>r?`${raceDate(r)}${r.time?` ${String(r.time).slice(0,5)}`:""} · ${trackName(r.track)} ${r.raceNo}경주 · ${r.distanceM}m${r.className?` · ${r.className}`:""}`:"";
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
     <h2 style={{fontSize:18}}>첫 시작 튜토리얼</h2>
     <div className="muted">단계 {tutorialStep+1} / {setupSteps.length} · {setupSteps[tutorialStep]}</div>
     <div style={{display:"flex",gap:5,margin:"10px 0 14px"}} aria-label="튜토리얼 진행 상황">
      {setupSteps.map((_,i)=><span key={i} style={{height:5,flex:1,borderRadius:8,
       background:i<=tutorialStep?"#e8b64d":"#493725"}}/>)} 
     </div>
     <div className="notice" role="status">🧑‍🏫 안내자 · {setupGuide[tutorialStep]}</div>
     {tutorialStep===0&&<>
      <label className="muted" htmlFor="ownerNickname">마주명</label>
      <input id="ownerNickname" className="field" value={nickname} maxLength={32}
       placeholder="마주 닉네임 (2~32자)" autoFocus onChange={e=>Nickname(e.target.value)}/>
      <div className="muted">게임에서 다른 마주에게 표시될 이름입니다.</div>
     </>}
     {tutorialStep===1&&<>
      <div className="card" style={{display:"flex",alignItems:"center",gap:12,marginTop:8}}>
       <SilksPreview design={silksDesign}/>
       <div><b>마주복 미리보기</b><div className="muted">상의와 소매 색상, 무늬를 자유롭게 골라보세요. 모자는 설정하지 않습니다.</div></div>
      </div>
      <div className="twoCol">
       {[["bodyColor","상의 색상"],["sleeveColor","소매 색상"],["patternColor","무늬 색상"]].map(([field,label])=><button
        key={field} type="button" className="field" disabled={busy}
        aria-label={label+" 선택"} onClick={()=>openColorPicker(field,label)}
        style={{display:"flex",alignItems:"center",justifyContent:"space-between",gap:8,textAlign:"left"}}>
        <span>{label}</span><span style={{display:"flex",alignItems:"center",gap:8}}>
         <span aria-hidden="true" style={{width:24,height:24,borderRadius:6,border:"1px solid #b4a28e",background:silksDesign[field]}}/>
         <code style={{color:"inherit"}}>{silksDesign[field]}</code>
        </span>
       </button>)}
       <label className="field">상의 무늬<select className="field" value={silksDesign.pattern}
        disabled={busy} onChange={e=>SilksDesign(v=>({...v,pattern:e.target.value}))}>
        {patternOptions.map(([value,label])=><option key={value} value={value}>{label}</option>)}
       </select></label>
      </div>
     </>}
     {tutorialStep===2&&<>
      <b style={{display:"block",margin:"10px 0 7px"}}>처음 활동할 지역</b>
      <div className="controls" aria-label="시작 지역 선택">
       {regionOptions.map(([value,label])=><button key={value}
        className={startingRegion===value?"primary":"outline"}
        aria-pressed={startingRegion===value} disabled={busy}
        onClick={()=>StartingRegion(value)}>{label}</button>)}
      </div>
      <div className="muted" style={{marginTop:10}}>선택한 지역은 마주 정보에 저장됩니다.</div>
     </>}
     {tutorialStep===3&&<>
      <div className="line"><b>시작 지역</b><span> · {regionName[startingRegion]}</span></div>
      <div className="line"><b>먼저 받는 말</b><div className="muted">2세 육성마 1마리 · 육성 코스를 신청하면 3세 6등급 신마를 받습니다.</div>
       <div className="muted">첫 출전을 신청하면 3세 미국산 외국 4등급 신마가 합류합니다.</div></div>
      <div className="line"><b>초기 목장 직원</b><div className="muted">관리사 4명과 수의사 1명 · 모두 C등급</div>
       <div className="muted">시설 배치는 목장에 들어간 뒤 직접 할 수 있습니다.</div></div>
      <div className="muted" style={{marginTop:10}}>마주명과 마주복을 다시 확인하고 등록을 완료하세요.</div>
     </>}
     <div className="controls" style={{marginTop:14}}>
      {tutorialStep>0&&<button className="outline" disabled={busy}
       onClick={()=>TutorialStep(x=>Math.max(0,x-1))}>이전</button>}
      {tutorialStep<setupSteps.length-1?
       <button className="primary" disabled={busy||(tutorialStep===0&&nickname.trim().length<2)}
        onClick={()=>TutorialStep(x=>Math.min(setupSteps.length-1,x+1))}>다음 단계</button>:
       <button className="primary" disabled={busy||nickname.trim().length<2}
        onClick={join}>{busy?"등록 중…":"등록 완료하고 시작하기"}</button>}
     </div>
    </div>:
    mine&&mine.joined?<section>
     <div className="card">
      <div className="row">
       <div><b className="gold">{mine.profile?.nickname||"내 마방"}</b>
        <div className="muted">시작 지역 · {regionName[mine.profile?.starting_region]||"미설정"}</div>
        <div className="muted">내가 소유한 경주마의 상태와 관찰 리포트를 관리합니다.</div></div>
       <SilksPreview design={mine.profile?.silks_design||defaultSilks} small/>
      </div>
      <div className="my-horse-summary">
       <div><b>{horses.length}</b><span>보유마</span></div>
       <div><b>{activeCount}</b><span>현역</span></div>
       <div><b>{horses.filter(breeding).length}</b><span>번식·은퇴</span></div>
      </div>
     </div>
     {tutorial&&tutorial.storyStage===0&&<div className="card" aria-live="polite">
      <div className="row"><b className="gold">🧑‍🏫 첫 시작 이야기</b><span className="tag">이야기 1 / 3</span></div>
      <div className="notice">“명마는 하루아침에 만들어지지 않습니다. ${tutorial.starterHorse?.name||"새로 맡은 2세마"}와 함께 최고의 경주마를 키워보시죠.”
       <div className="muted" style={{marginTop:6}}>먼저 목장에서 2세 육성마의 육성 과정을 신청해주세요. 과정이 시작되면 경주를 경험할 말이 합류합니다. 튜토리얼 말 세 마리는 각각 첫 출전 신청비가 면제됩니다.</div>
       <a className="primary" href="/ranch" style={{display:"inline-block",textDecoration:"none",marginTop:10}}>육성하러 가기 ›</a>
      </div>
     </div>}
     {tutorial&&tutorial.storyStage===1&&<div className="card" aria-live="polite">
      <div className="row"><b className="gold">🧑‍🏫 첫 시작 이야기</b><span className="tag">이야기 2 / 3</span></div>
      <div className="notice">“육성에는 시간이 필요하니, 경주도 먼저 경험해보세요. 3세 6등급 신마를 맡기겠습니다.”
       <div className="muted" style={{marginTop:6}}>출전표에서 경주와 기수를 확인해 첫 출전을 신청하세요. 이 말의 첫 출전 신청비는 면제됩니다.</div>
       <a className="primary" href="/entries" style={{display:"inline-block",textDecoration:"none",marginTop:10}}>출전표 보기 ›</a>
      </div>
     </div>}
     {tutorial&&tutorial.storyStage===2&&<div className="card" aria-live="polite">
      <div className="row"><b className="gold">🧑‍🏫 첫 시작 이야기</b><span className="tag">이야기 3 / 3</span></div>
      <div className="notice">“경매에서 아쉽게 놓쳤던 미국산 외산마가 급히 새 마주를 찾고 있습니다. 이번에는 직접 출전시켜 실력을 확인해보세요.”
       <div className="muted" style={{marginTop:6}}>3세 미국산 4등급 신마를 목장에 추가했습니다. 이 말도 첫 출전 신청비가 면제됩니다.</div>
       <a className="primary" href="/entries" style={{display:"inline-block",textDecoration:"none",marginTop:10}}>외산마 출전 신청 ›</a>
       <button className="outline" style={{marginLeft:8}} disabled={busy} onClick={()=>saveTutorial({storyStage:3})}>이야기 마무리</button>
      </div>
     </div>}
     {tutorial&&tutorial.storyStage===3&&!tutorial.completed&&<div className="notice">
      첫 시작 이야기를 모두 진행했습니다.
      <button className="outline" style={{marginLeft:10}} disabled={busy} onClick={()=>saveTutorial({completeStory:true})}>튜토리얼 완료</button>
     </div>}
     {tutorial&&tutorial.completed&&<div className="notice">첫 시작 튜토리얼을 완료했습니다. 아래 기능 안내는 언제든 다시 볼 수 있습니다.</div>}
     <div className="card">
      <b>게임 기능 안내</b>
      <div className="muted" style={{margin:"5px 0 10px"}}>항목을 눌러 간단한 설명을 보고 해당 기능으로 이동하세요.</div>
      <div className="my-horse-action-grid">
       {tutorialTopics.map(topic=><div key={topic.key} className="card my-horse-action">
        <button className="outline" style={{textAlign:"left",width:"100%"}}
         aria-expanded={tutorialTopic===topic.key}
         onClick={()=>{TutorialTopic(tutorialTopic===topic.key?null:topic.key);
          if(!tutorial?.seenTopics?.includes(topic.key))saveTutorial({topic:topic.key});}}>
         {tutorial?.seenTopics?.includes(topic.key)?"✓ ":""}{topic.title}
        </button>
        {tutorialTopic===topic.key&&<><span className="muted">{topic.text}</span>
         <a href={topic.href} className="my-horse-race-link">기능 열기 ›</a></>}
       </div>)}
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
       <div className="my-horse-race-info" aria-label={h.name+" 출전 정보"}>
        <div className="my-horse-race-row">
         <span>마지막 출전</span>
         <b>{mine.raceSchedule?.[h.id]?.lastStart?
          <a className="my-horse-race-link" href={"/race/"+encodeURIComponent(mine.raceSchedule[h.id].lastStart.raceId)}>
           {raceLabel(mine.raceSchedule[h.id].lastStart)} · {mine.raceSchedule[h.id].lastStart.rank}위 · 경주 결과 보기 ›
          </a>:"출전 기록 없음"}</b>
        </div>
        <div className="my-horse-race-row">
         <span>출전 예정</span>
         <b>{mine.raceSchedule?.[h.id]?.nextStart?
          <a className="my-horse-race-link" href={"/race/"+encodeURIComponent(mine.raceSchedule[h.id].nextStart.raceId)}>
           {raceLabel(mine.raceSchedule[h.id].nextStart)} · {mine.raceSchedule[h.id].nextStart.entryStatus==="CONFIRMED"?"출전 확정":"신청 접수"} · 출전 정보 보기 ›
          </a>:"예정된 출전 없음"}</b>
        </div>
       </div>
       <div className="controls" style={{marginTop:11}}>
        <HorseLink horseId={h.id} className="outline" style={{textDecoration:"none",fontSize:12}}>
         기본정보·전적 보기 ›
        </HorseLink>
        <a className="outline" href={"/horses/reports?horseId="+encodeURIComponent(h.id)}
         style={{textDecoration:"none",fontSize:12}}>📑 능력·기질 분석 리포트 ›</a>
       </div>
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
  {colorTarget&&<div role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget)ColorTarget(null)}}
   style={{position:"fixed",inset:0,zIndex:10000,background:"#000b",display:"grid",placeItems:"center",padding:16}}>
   <section role="dialog" aria-modal="true" aria-labelledby="silks-color-title"
    style={{width:"min(420px,100%)",maxHeight:"90dvh",overflowY:"auto",background:"#211810",color:"#f7edde",border:"1px solid #84633b",borderRadius:16,padding:18,boxShadow:"0 20px 60px #0009"}}>
    <div style={{display:"flex",alignItems:"center",justifyContent:"space-between",gap:12}}>
     <h2 id="silks-color-title" style={{fontSize:18,margin:"0 0 12px"}}>{colorTarget.label} 선택</h2>
     <button type="button" aria-label="색상 선택 취소" className="outline" onClick={()=>ColorTarget(null)}>×</button>
    </div>
    <div className="card" style={{display:"flex",alignItems:"center",gap:12}}>
     <SilksPreview design={{...silksDesign,[colorTarget.field]:colorDraft}}/>
     <div><b>마주복 미리보기</b><div className="muted">색상을 고른 뒤 확인을 누르면 적용됩니다.</div></div>
    </div>
    <div className="muted" style={{margin:"12px 0 5px"}}>색상 팔레트</div>
    <div style={{display:"grid",gridTemplateColumns:"repeat(6,minmax(0,1fr))",gap:8}}>
     {silksColorOptions.map(color=><button key={color} type="button" aria-label={color}
      aria-pressed={colorDraft.toUpperCase()===color} onClick={()=>ColorDraft(color)}
      style={{height:38,borderRadius:8,border:colorDraft.toUpperCase()===color?"3px solid #edb94d":"1px solid #8c765e",background:color}}/>)}
    </div>
    <label className="muted" style={{display:"block",marginTop:14}}>직접 입력 (#RRGGBB)
     <input className="field" aria-label="색상 코드" inputMode="text" maxLength={7}
      value={colorDraft} onChange={e=>ColorDraft(e.target.value)} placeholder="#D6A84F"/>
    </label>
    <div className="controls" style={{marginTop:12}}>
     <button type="button" className="outline" onClick={()=>ColorTarget(null)}>취소</button>
     <button type="button" className="primary" disabled={!/^#[0-9A-Fa-f]{6}$/.test(colorDraft)}
      onClick={confirmSilksColor}>확인</button>
    </div>
   </section>
  </div>}
 </main>;
}
