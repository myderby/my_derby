"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const steps=[
 {title:"새 마주의 첫날",href:"/world",body:"오랜 경마 경험을 가진 베테랑 관리인이 당신의 첫 목장에 찾아왔습니다. 서울·영천·부산 중 선택한 지역에서 첫 시즌을 시작합니다.",task:"목장과 시작 지역을 확인해 보세요."},
 {title:"첫 목장을 꾸려요",href:"/ranch/management",body:"C등급 관리사와 수의사가 합류했습니다. 어느 시설에 배치할지는 마주인 당신이 결정합니다.",task:"방목지와 수의진료소의 인력 배치를 살펴보세요."},
 {title:"첫 데뷔를 기다리는 신마",href:"/horses",body:"6등급 신마의 기록과 컨디션을 확인하고, 출전표에서 데뷔 준비를 배워보세요.",task:"보유마 목록에서 신마의 기본 정보를 확인하세요."},
 {title:"미래와 가능성",href:"/training",body:"2살 육성마는 아직 경주에 나설 때가 아닙니다. 훈련 계획을 세우고 성장 기록을 살펴보세요.",task:"육성 화면에서 훈련 메뉴를 확인하세요."},
 {title:"먼 길을 온 외국 신마",href:"/market",body:"미국에서 온 4등급 외국 신마가 새 목장에 합류했습니다. 이제 경주 조건을 읽고 첫 출전을 준비할 차례입니다.",task:"대회와 경주 조건을 확인하고 첫 목표를 정하세요."}
];
export default function TutorialOnboarding({force=false}){
 const [state,S]=useState(null),[busy,B]=useState(false),[dismissed,D]=useState(false),[replayStep,RS]=useState(0);
 useEffect(()=>{
  let active=true;
  const load=async()=>{
   try{
    const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    if(!url||!key)return;
    const client=createClient(url,key),{data:{session}}=await client.auth.getSession();
    if(!session)return;
    const r=await fetch("/api/player/tutorial",{headers:{Authorization:"Bearer "+session.access_token},cache:"no-store"});
    if(!r.ok)return;
    const data=await r.json();if(active)setState(data);
   }catch(_){}
  };
  void load();return()=>{active=false};
 },[]);
 async function save(step,skip=false){
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if(!url||!key)return;
  B(true);
  try{
   const client=createClient(url,key),{data:{session}}=await client.auth.getSession();
   if(!session)return;
   const r=await fetch("/api/player/tutorial",{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+session.access_token},body:JSON.stringify({step,skip})});
   if(!r.ok)throw new Error("저장 실패");
   const data=await r.json();S(prev=>({...prev,...data}));RS(Math.min(5,step));
   if(data.completed)D(true);
  }catch(_){/* Keep the story open so the player can retry. */}
  finally{B(false)}
 }
 if(!state?.joined||dismissed||(!force&&state.completed))return null;
 const index=Math.min(force?replayStep:(state.currentStep||0),steps.length-1),item=steps[index];
 return <div style={{position:"fixed",inset:0,zIndex:9999,background:"rgba(10,15,24,.76)",display:"grid",placeItems:"center",padding:18}}>
  <section role="dialog" aria-modal="true" aria-labelledby="tutorial-title" style={{width:"min(520px,100%)",background:"#111b2b",color:"#f5f1e7",border:"1px solid #b99a56",borderRadius:20,padding:24,boxShadow:"0 24px 80px #0008"}}>
   <div style={{color:"#c7a65c",fontSize:12,letterSpacing:2}}>MY DERBY · 첫 시즌 이야기 {index+1}/{steps.length}</div>
   <h2 id="tutorial-title" style={{fontSize:24,margin:"12px 0"}}>{item.title}</h2>
   <p style={{lineHeight:1.7,color:"#d7dbe2"}}>{item.body}</p>
   <div style={{background:"#1a283a",padding:12,borderRadius:10,color:"#e4c778",fontSize:14}}>안내 · {item.task}</div>
   <div style={{display:"flex",justifyContent:"space-between",gap:8,marginTop:20}}>
    <button onClick={()=>{D(true);void save(5,true)}} disabled={busy} style={{background:"transparent",border:"1px solid #566174",color:"#d7dbe2",borderRadius:9,padding:"10px 14px"}}>건너뛰기</button>
    <button onClick={()=>{D(true);void save(index+1);window.location.assign(item.href)}} disabled={busy} style={{background:"transparent",border:"1px solid #c7a65c",color:"#e4c778",fontWeight:700,borderRadius:9,padding:"10px 14px"}}>화면 열기</button>
    <button onClick={()=>void save(index+1)} disabled={busy} style={{background:"#c7a65c",border:0,color:"#17202b",fontWeight:700,borderRadius:9,padding:"10px 18px"}}>{busy?"저장 중…":index===steps.length-1?"이야기 마치기":"다음"}</button>
   </div>
  </section>
 </div>;
}
