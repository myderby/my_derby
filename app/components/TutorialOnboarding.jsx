"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {usePathname,useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";

const stories=[
 {title:"명마의 시작",body:"명마는 하루아침에 만들어지지 않습니다. 2세 육성마 {horse}와 함께 최고의 경주마를 만들어보시죠.",task:"2세 육성마가 목장에 도착했습니다. 이름은 그대로 사용해도 되고, 원하는 이름으로 바꿔도 됩니다. 육성 코스를 한 번 신청하면 다음 이야기가 열립니다.",href:"/ranch?view=courses",action:"육성 코스 신청하기"},
 {title:"첫 경주 준비",body:"육성에는 시간이 걸리니 경주를 먼저 경험해보세요. 3세 6등급 신마 {horse}를 맡기겠습니다.",task:"육성 코스 신청이 확인되어 3세 6등급 신마가 합류했습니다. 이름을 정한 뒤 시간표와 출전표를 살펴보고 기수를 선택해 첫 경주를 신청해보세요. 튜토리얼로 받은 말은 첫 출전 신청 비용이 들지 않습니다.",href:"/entries",action:"경주 출전 신청하기"},
 {title:"놓친 경매마의 기회",body:"경매에서 아쉽게 놓쳤던 미국산 외산마 {horse}가 급히 새 마주를 찾고 있습니다. 이름을 정하고 직접 출전시켜 실력을 확인해보세요.",task:"첫 출전 신청이 완료되어 3세 미국산 외국 4등급 신마가 합류했습니다. 이름을 정하고 내 말 관리에서 정보를 확인해보세요.",href:"/world",action:"다음 이야기 보기"},
 {title:"목장으로 출발",body:"세 마리 모두 준비됐습니다. 목장과 직원은 직접 관리하며 마주님의 방식으로 키워보세요.",task:"C등급 관리사와 수의사, 목장 시설을 확인하고 직원 배치와 말 관리를 시작해보세요.",href:"/ranch/management",action:"목장 관리 살펴보기"}
];
const topics={
 training:{title:"훈련·육성",body:"훈련 신청 방법과 조교사 리포트에서 성장·컨디션 변화를 확인하는 법을 살펴보세요."},
 racing:{title:"경주",body:"19시·20시·21시 시간표에서 출전표를 확인하고, 경주 조건에 맞는 말과 기수를 골라 신청합니다."},
 results:{title:"경주 결과",body:"경주가 끝나면 순위와 기록을 확인하고, 내 말의 출전 기록과 경주 리포트를 살펴볼 수 있습니다."},
 ranch:{title:"목장·직원",body:"시설마다 수용 두수가 정해져 있습니다. 관리 두수와 직원 배치에 따라 회복·육성 관리 효과가 달라집니다."},
 betting:{title:"배팅",body:"배당과 예상 환급액을 확인할 수 있습니다. 배팅은 선택 사항이며 참여하지 않아도 경주와 육성을 계속할 수 있습니다."},
 breeding:{title:"교배",body:"번식마와 교배 조건을 확인한 뒤 신청합니다. 기능을 이용할 때 필요한 조건과 예상 정보를 이 화면에서 살펴보세요."},
 achievements:{title:"업적",body:"마주와 경주마의 성적에 따라 업적이 열립니다. 달성 조건과 현재 진행 상황을 확인할 수 있습니다."}
};
function topicFor(path){
 if(path==="/training"||path==="/horses/reports")return "training";
 if(path==="/entries"||path==="/schedule")return "racing";
 if(path.startsWith("/race/"))return ["results","betting"];
 if(path==="/ranch"||path==="/ranch/management")return "ranch";
 if(path==="/breeding")return "breeding";
 if(path==="/achievements"||path==="/my-record")return "achievements";
 return null;
}
function client(){return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)}

export default function TutorialOnboarding(){
 const pathname=usePathname();
 const router=useRouter();
 const [state,S]=useState(null),[busy,B]=useState(false),[hiddenStage,HS]=useState(null),[topicHidden,TH]=useState(false);
 const [visibleTopicKey,VTK]=useState(null),[targetBox,TB]=useState(null);
 const [manualTopicKey,MTK]=useState(null),[topicPickerOpen,TPO]=useState(false);
 const [renameValue,RV]=useState(""),[renameMessage,RM]=useState("");
 const lastScrolled=useRef("");
 const loadGeneration=useRef(0);
 const load=useCallback(async()=>{
  const requestId=++loadGeneration.current;
  try{
   const cfg=client(),{data:{session}}=await cfg.auth.getSession();if(!session)return;
   const r=await fetch("/api/player/tutorial",{headers:{Authorization:"Bearer "+session.access_token},cache:"no-store"});
   if(r.ok){
    const next=await r.json();
    if(requestId!==loadGeneration.current)return;
    S(next);
    const key="my-derby:tutorial:hidden-stage:"+session.user.id;
    const dismissed=sessionStorage.getItem(key);
    if(dismissed!==null){
     const dismissedStage=Number(dismissed);
     const intendedPath=stories[dismissedStage]?.href;
     const currentPath=window.location.pathname;
     if(dismissedStage===Number(next.storyStage)&&currentPath===intendedPath)HS(dismissedStage);
     else{sessionStorage.removeItem(key);HS(null);}
    }
   }
  }catch(_){/* Tutorial guidance must not block the game. */}
 },[]);
 useEffect(()=>{void load()},[load,pathname]);
 useEffect(()=>{
  const refresh=()=>void load();
  window.addEventListener("my-derby:progress",refresh);
  window.addEventListener("focus",refresh);
  return()=>{window.removeEventListener("my-derby:progress",refresh);window.removeEventListener("focus",refresh)};
 },[load]);
 useEffect(()=>{TH(false);MTK(null);TPO(false)},[pathname]);
 const topicCandidates=topicFor(pathname||"");
 const candidateList=Array.isArray(topicCandidates)?topicCandidates:topicCandidates?[topicCandidates]:[];
 const seenKey=(state?.seenTopics||[]).join("|");
 useEffect(()=>{
  if(!state?.joined||!candidateList.length){VTK(null);TB(null);return;}
  const refresh=()=>{
   const unseen=candidateList.filter(key=>!state.seenTopics?.includes(key));
   const requested=manualTopicKey&&candidateList.includes(manualTopicKey)?{
    key:manualTopicKey,element:document.querySelector(`[data-tutorial-target="${manualTopicKey}"]`)
   }:null;
   const available=unseen.map(key=>({key,element:document.querySelector(`[data-tutorial-target="${key}"]`)}))
    .find(item=>item.element);
   const selected=requested||available|| (unseen.length?{key:unseen[0],element:null}:null);
   const selectedKey=selected?.key||null;
   VTK(current=>current===selectedKey?current:selectedKey);
   if(!selected?.element){TB(current=>current===null?current:null);return;}
   const element=selected.element;
   const scrollKey=(pathname||"")+":"+selected.key;
   if(lastScrolled.current!==scrollKey){
    lastScrolled.current=scrollKey;
    element.scrollIntoView({block:"center",inline:"nearest",behavior:"smooth"});
   }
   const rect=element.getBoundingClientRect();
   const nextBox={key:selected.key,left:rect.left-5,top:rect.top-5,width:rect.width+10,height:rect.height+10};
   TB(current=>current&&current.key===nextBox.key&&current.left===nextBox.left&&
    current.top===nextBox.top&&current.width===nextBox.width&&current.height===nextBox.height?current:nextBox);
  };
  refresh();
  const observer=new MutationObserver(refresh);
  observer.observe(document.body,{childList:true,subtree:true});
  const onGeometryChange=()=>refresh();
  window.addEventListener("resize",onGeometryChange);
  window.addEventListener("scroll",onGeometryChange,true);
  return()=>{observer.disconnect();window.removeEventListener("resize",onGeometryChange);
   window.removeEventListener("scroll",onGeometryChange,true);};
 },[state?.joined,seenKey,pathname,candidateList.join("|"),manualTopicKey]);
 async function update(payload){
  B(true);
  try{
   const cfg=client(),{data:{session}}=await cfg.auth.getSession();if(!session)return;
   const r=await fetch("/api/player/tutorial",{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+session.access_token},body:JSON.stringify(payload)});
   const data=await r.json();if(!r.ok)throw new Error(data.error||"저장 실패");
   S(prev=>({...prev,...data,...(data.storyStage!==undefined&&data.storyStage!==prev?.storyStage?{starterHorse:null}:{})}));
   window.dispatchEvent(new Event("my-derby:progress"));
  }catch(_){/* A failed save leaves the tutorial available for retry. */}
  finally{B(false)}
 }
 const stage=Math.min(3,Math.max(0,Number(state?.storyStage)||0));
 const story=stories[stage];
 useEffect(()=>{
  if(state?.joined&&stage===0&&hiddenStage===0&&pathname==="/ranch"){
   MTK("ranch");TH(false);
  }
 },[state?.joined,stage,hiddenStage,pathname]);
 useEffect(()=>{RV("");RM("")},[stage,state?.starterHorse?.name]);
 async function renameStarter(){
  const horse=state?.starterHorse;
  if(!horse||renameValue.trim().length<2||renameValue.trim().length>20){
   RM("말 이름은 2~20자로 입력해주세요.");return;
  }
  B(true);RM("");
  try{
   const cfg=client(),{data:{session}}=await cfg.auth.getSession();if(!session)return;
   const r=await fetch("/api/player/tutorial",{method:"POST",
    headers:{"Content-Type":"application/json",Authorization:"Bearer "+session.access_token},
    body:JSON.stringify({renameHorse:{horseId:horse.id,name:renameValue.trim()}})});
   const data=await r.json();if(!r.ok)throw new Error(data.error||"말 이름을 저장하지 못했습니다.");
   S(prev=>({...prev,starterHorse:{...prev.starterHorse,...data.renamedHorse}}));
   RV("");RM("말 이름을 변경했습니다.");
   window.dispatchEvent(new Event("my-derby:progress"));
  }catch(e){
   const message=String(e?.message||"");
   RM(message.includes("TUTORIAL_HORSE_NAME_TAKEN")?"이미 사용 중인 이름입니다. 다른 이름을 입력해주세요.":message);
  }finally{B(false)}
 }
 const storyContinuation=stage===0&&hiddenStage===stage&&pathname==="/ranch";
 const topicKey=manualTopicKey||(storyContinuation?"ranch":visibleTopicKey);
 const topic=storyContinuation?{title:"첫 육성 코스 신청",body:"첫 시작 이야기는 끝나지 않았습니다. 2세 육성마를 선택하고 ‘2세 이하 기초육성’ 코스를 신청하면 다음 이야기와 3세 6등급 신마가 열립니다."}:
  topicKey&&(manualTopicKey||!state?.seenTopics?.includes(topicKey))?topics[topicKey]:null;
 const storyOpen=!!state?.joined&&hiddenStage!==stage&&!(stage>=3&&state.completed);
 const topicOpen=!storyOpen&&!!topic&&(!!manualTopicKey||storyContinuation||!topicHidden);
 const canReplay=!!state?.joined&&!storyOpen&&candidateList.length>0;
 const openReplay=()=>{
  const available=candidateList.filter(key=>document.querySelector(`[data-tutorial-target="${key}"]`));
  const choices=available.length?available:candidateList;
  if(available.length>1){TPO(true);return;}
  MTK(choices[0]||candidateList[0]||null);TH(false);
 };
 useEffect(()=>{
  if(!topicOpen||!targetBox||targetBox.key!==topicKey)return;
  const element=document.querySelector(`[data-tutorial-target="${topicKey}"]`);
  if(!element)return;
  const onClick=event=>{
   if(!element.contains(event.target))return;
   void update({topic:topicKey});TH(true);MTK(null);
  };
  document.addEventListener("click",onClick,true);
  return()=>document.removeEventListener("click",onClick,true);
 },[topicOpen,topicKey,targetBox?.key,targetBox?.left,targetBox?.top]);
 if(!state?.joined||(!storyOpen&&!topicOpen&&!topicPickerOpen&&!canReplay))return null;
 if(storyOpen)return <div style={{position:"fixed",inset:0,zIndex:9999,background:"rgba(10,15,24,.76)",display:"grid",placeItems:"center",padding:18}}>
  <section role="dialog" aria-modal="true" aria-labelledby="tutorial-title" style={{width:"min(540px,100%)",maxHeight:"90dvh",overflowY:"auto",background:"#111b2b",color:"#f5f1e7",border:"1px solid #b99a56",borderRadius:20,padding:24,boxShadow:"0 24px 80px #0008"}}>
   <div style={{color:"#c7a65c",fontSize:12,letterSpacing:2}}>MY DERBY · 첫 시작 이야기 {stage+1}/4</div>
   <h2 id="tutorial-title" style={{fontSize:24,margin:"12px 0"}}>{story.title}</h2>
   <p style={{lineHeight:1.7,color:"#d7dbe2"}}>“{story.body.replace("{horse}",state?.starterHorse?.name||"신마")}”</p>
   <div style={{background:"#1a283a",padding:12,borderRadius:10,color:"#e4c778",fontSize:14}}>안내 · {story.task}</div>
   {stage<3&&state?.starterHorse&&<div style={{background:"#172437",padding:12,borderRadius:10,marginTop:12}}>
    <div style={{fontSize:13,color:"#d7dbe2",marginBottom:8}}>이번에 받은 말 · <b style={{color:"#f0c572"}}>{state.starterHorse.name}</b></div>
    <div style={{display:"flex",gap:8,alignItems:"stretch"}}>
     <input aria-label="튜토리얼 경주마 새 이름" value={renameValue} maxLength={20}
      onChange={e=>RV(e.target.value)} placeholder="원하는 말 이름 (2~20자)"
      style={{minWidth:0,flex:1,borderRadius:8,border:"1px solid #566174",background:"#0c1522",color:"#f5f1e7",padding:"10px 11px"}}/>
     <button type="button" disabled={busy||renameValue.trim().length<2} onClick={renameStarter}
      style={{background:"#24354a",border:"1px solid #c7a65c",color:"#f0c572",fontWeight:700,borderRadius:8,padding:"8px 11px",whiteSpace:"nowrap"}}>
      {busy?"저장 중…":"이름 바꾸기"}</button>
    </div>
    <div aria-live="polite" style={{fontSize:12,color:renameMessage.includes("변경했습니다")?"#a9d7ad":"#d7dbe2",marginTop:7}}>
     {renameMessage||"새 이름을 입력하지 않으면 현재 이름으로 진행합니다."}</div>
   </div>}
   {stage===3&&<p style={{color:"#d7dbe2",fontSize:13,marginBottom:0}}>관리사 4명과 수의사 1명은 모두 C등급입니다. 시설별 수용 두수와 직원을 배치하는 방법을 익혀보세요.</p>}
   <div style={{display:"flex",justifyContent:"space-between",gap:8,marginTop:20}}>
    <button onClick={()=>HS(stage)} style={{background:"transparent",border:"1px solid #566174",color:"#d7dbe2",borderRadius:9,padding:"10px 14px"}}>나중에</button>
    <button disabled={busy} onClick={async()=>{
     if(stage===2){await update({storyStage:3});return;}
     if(stage===3)await update({completeStory:true});
     HS(stage);
     try{
      const cfg=client(),{data:{session}}=await cfg.auth.getSession();
      if(session?.user?.id)sessionStorage.setItem("my-derby:tutorial:hidden-stage:"+session.user.id,String(stage));
     }catch(_){/* Keep navigation available if the browser storage is unavailable. */}
     router.push(story.href);
    }} style={{background:"#c7a65c",border:0,color:"#17202b",fontWeight:700,borderRadius:9,padding:"10px 16px"}}>{busy?"저장 중…":story.action}</button>
   </div>
  </section>
 </div>;
 const targetInLowerHalf=targetBox&&targetBox.top+targetBox.height>window.innerHeight/2;
 const targetInRightHalf=targetBox&&targetBox.left+targetBox.width/2>window.innerWidth/2;
 return <>
  {topicOpen&&targetBox&&targetBox.key===topicKey&&<div aria-hidden="true" style={{position:"fixed",left:targetBox.left,top:targetBox.top,width:targetBox.width,height:targetBox.height,zIndex:10000,pointerEvents:"none",border:"3px solid #f0c572",borderRadius:11,boxShadow:"0 0 0 9999px rgba(5,10,18,.50),0 0 0 7px rgba(240,197,114,.28)",transition:"all .18s ease"}}>
   <div style={{position:"absolute",left:"50%",top:targetBox.top>48?-38:targetBox.height+4,transform:"translateX(-50%)",whiteSpace:"nowrap",borderRadius:999,background:"#f0c572",color:"#17202b",fontWeight:800,fontSize:13,padding:"5px 11px",boxShadow:"0 3px 12px #0008"}}>
    {targetBox.top>48?"⬇ 여기를 눌러보세요":"⬆ 여기를 눌러보세요"}
   </div>
  </div>}
  {topicOpen&&<div style={{position:"fixed",...(targetBox&&targetInLowerHalf?{top:16}:{bottom:16}),...(targetBox&&targetInRightHalf?{left:16}:{right:16}),zIndex:10001,width:"min(410px,calc(100% - 32px))",background:"#111b2b",color:"#f5f1e7",border:"1px solid #b99a56",borderRadius:16,padding:18,boxShadow:"0 14px 44px #0009"}}>
  <div style={{color:"#c7a65c",fontSize:11,letterSpacing:1.5}}>{storyContinuation?"첫 시작 이야기 · 1단계 계속":"처음 이용하는 기능"}</div>
  <h2 style={{fontSize:20,margin:"8px 0"}}>{topic.title}</h2>
  <p style={{fontSize:14,lineHeight:1.6,color:"#d7dbe2",margin:"0 0 12px"}}>{topic.body}</p>
  <p style={{fontSize:12,lineHeight:1.5,color:"#aeb8c6",margin:"0 0 12px"}}>이후에도 이 화면의 튜토리얼 보기 버튼에서 다시 열 수 있습니다.</p>
  <div style={{display:"flex",justifyContent:"flex-end",gap:8}}>
   <button disabled={busy} onClick={async()=>{await update({topic:topicKey});TH(true);MTK(null)}} style={{background:"#c7a65c",border:0,color:"#17202b",fontWeight:700,borderRadius:8,padding:"8px 12px"}}>{busy?"저장 중…":storyContinuation?"안내 닫기 · 계속 진행":"안내 완료 · 닫기"}</button>
  </div>
  </div>}
  {topicPickerOpen&&<div style={{position:"fixed",right:16,bottom:16,zIndex:10001,width:"min(360px,calc(100% - 32px))",background:"#111b2b",color:"#f5f1e7",border:"1px solid #b99a56",borderRadius:16,padding:16,boxShadow:"0 14px 44px #0009"}}>
   <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:10,marginBottom:10}}>
    <b style={{color:"#f0c572"}}>다시 볼 튜토리얼 선택</b>
    <button onClick={()=>TPO(false)} aria-label="튜토리얼 선택 닫기" style={{background:"transparent",border:"1px solid #566174",color:"#d7dbe2",borderRadius:8,padding:"5px 9px"}}>닫기</button>
   </div>
   <div style={{display:"grid",gap:8}}>{(candidateList.filter(key=>document.querySelector(`[data-tutorial-target="${key}"]`)).length?
    candidateList.filter(key=>document.querySelector(`[data-tutorial-target="${key}"]`)):candidateList).map(key=>
    <button key={key} onClick={()=>{MTK(key);TH(false);TPO(false)}} style={{textAlign:"left",background:"#1a283a",border:"1px solid #566174",color:"#f5f1e7",borderRadius:9,padding:"10px 12px"}}>{topics[key].title} 튜토리얼 보기</button>
   )}</div>
  </div>}
  {canReplay&&!topicOpen&&!topicPickerOpen&&<div className="tutorial-replay-dock">
   <button onClick={openReplay} className="tutorial-replay-button">？ 화면 설명</button>
  </div>}
 </>;
}
