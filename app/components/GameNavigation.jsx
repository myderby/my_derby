"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";

const categories=[
 {id:"ranch",label:"목장",icon:"🌲",paths:["/ranch","/ranch/management"],groups:[
  {id:"ranch-space",label:"목장 관리",items:[["목장 둘러보기","/ranch/management"],["재무 관리","/finance"]]},
  {id:"ranch-care",label:"말 돌보기",items:[["휴양·재활 코스","/ranch?view=courses"],["부상·회복 관리","/injuries"],["내 경주마","/world"]]}
 ]},
 {id:"stable",label:"마사",icon:"🐎",paths:["/world","/breeding","/market","/auction","/horses"],groups:[
  {id:"horses",label:"경주마 관리",items:[["내 말 목록","/world"],["경주마 상세·전적","/horses"],["자마 내역","/horses/offspring"]]},
  {id:"breeding-market",label:"교배·시장",items:[["교배·번식 관리","/breeding"],["경주마 매매","/market"],["경주마 경매","/auction"]]}
 ]},
 {id:"race",label:"경주 & 승마",icon:"🏇",paths:["/schedule","/entries","/race","/news","/bets"],groups:[
  {id:"race-prep",label:"경주 준비",items:[["경주 시간표","/schedule"],["출전 신청·기수 선택","/entries"]]},
  {id:"race-results",label:"경주 소식·배팅",items:[["경주 결과·기록","/schedule"],["나의 경주 소식","/news?view=mine"],["배팅·베팅 이력","/bets"]]}
 ]},
 {id:"training",label:"훈련",icon:"⚒️",paths:["/training","/stable","/horses/reports"],groups:[
  {id:"training-plan",label:"훈련 관리",items:[["훈련 계획","/training"],["훈련 리포트","/horses/reports"]]},
  {id:"training-staff",label:"조교사",items:[["조교사 위탁·계약","/stable"],["조교사 성적","/participants?view=trainers"]]}
 ]},
 {id:"events",label:"이벤트 허브",icon:"✦",paths:["/news","/notifications","/achievements","/my-record"],groups:[
  {id:"event-news",label:"소식·우편",items:[["더비 데일리","/news"],["우편함·선물","/notifications"]]},
  {id:"event-records",label:"마주 기록",items:[["나의 정보","/my-record"],["업적","/achievements"]]}
 ]}
];

const client=()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
export default function GameNavigation(){
 const [ready,Ready]=useState(false),[open,Open]=useState(null),[expanded,Expanded]=useState(null);
 useEffect(()=>{
  let alive=true;
  const supabase=client();
  const check=async session=>{
   if(!session?.access_token){if(alive)Ready(false);return;}
   try{
    const r=await fetch("/api/world/me",{cache:"no-store",headers:{Authorization:"Bearer "+session.access_token}});
    const data=await r.json();
    if(alive)Ready(r.ok&&data.joined===true);
   }catch(_){if(alive)Ready(false)}
  };
  supabase.auth.getSession().then(({data})=>check(data.session));
  const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,session)=>{void check(session)});
  return()=>{alive=false;subscription.unsubscribe()};
 },[]);
 if(!ready)return null;
 const pathname=typeof window==="undefined"?"":window.location.pathname;
 const active=categories.find(item=>item.paths.some(path=>pathname===path||pathname.startsWith(path+"/")))?.id;
 const selected=categories.find(item=>item.id===open);
 return <>
  {selected&&<section className="game-nav-panel" aria-label={selected.label+" 하위 메뉴"}>
   <div className="game-nav-panel-head"><div><b>{selected.icon} {selected.label}</b><span>메뉴를 선택하세요</span></div>
    <button type="button" aria-label="하위 메뉴 닫기" onClick={()=>{Open(null);Expanded(null)}}>닫기 ×</button></div>
   <div className="game-nav-groups">{selected.groups.map(group=><div className="game-nav-group" key={group.id}>
    <button type="button" className="game-nav-depth-two" aria-expanded={expanded===group.id}
     onClick={()=>Expanded(expanded===group.id?null:group.id)}>{group.label}<span>{expanded===group.id?"−":"＋"}</span></button>
    {expanded===group.id&&<div className="game-nav-depth-three">{group.items.map(([label,href])=>
     <a key={href+label} href={href}>{label}<span>›</span></a>)}</div>}
   </div>)}</div>
  </section>}
  <nav className="game-bottom-nav" aria-label="주요 메뉴">{categories.map(item=><button key={item.id}
   type="button" className={(open===item.id||(!open&&active===item.id))?"active":""}
   aria-expanded={open===item.id} onClick={()=>{Open(open===item.id?null:item.id);Expanded(null)}}>
   <span aria-hidden="true">{item.icon}</span><b>{item.label}</b>
  </button>)}</nav>
 </>;
}
