"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const labels={CAREER_WINS:"통산 승리",GRADE_WINS:"등급별 승리",HORSE_WINS:"말 승리",HORSE_STREAK:"말 연승",WIN_ODDS:"단승 배당",PLACE_ODDS:"연승 배당",STAKES_WINS:"대상경주",COMPETITION_TITLE:"대회 호칭"};
export default function AchievementsPage(){
 const [data,S]=useState(null),[error,E]=useState("");
 useEffect(()=>{
  let active=true;
  (async()=>{
   try{
    const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    if(!url||!key)throw new Error("인증 설정을 확인해 주세요.");
    const client=createClient(url,key),{data:{session}}=await client.auth.getSession();
    if(!session)throw new Error("로그인 후 업적을 확인할 수 있습니다.");
    const r=await fetch("/api/player/achievements",{headers:{Authorization:"Bearer "+session.access_token},cache:"no-store"});
    const json=await r.json();if(!r.ok)throw new Error(json.error||"업적 조회 실패");
    if(active)S(json);
   }catch(e){if(active)E(e.message)}
  })();return()=>{active=false};
 },[]);
 const progress=new Map((data?.progress||[]).map(p=>[p.achievement_key+"|"+p.subject_id,p]));
 const categories=[...new Set((data?.definitions||[]).map(d=>d.category))];
 return <main style={{maxWidth:900,margin:"0 auto",padding:"24px 16px 90px",color:"#f4f1e8"}}>
  <a href="/" style={{color:"#d5b65f"}}>‹ MY DERBY</a><h1>업적과 호칭</h1><p style={{color:"#aab3c1"}}>{data?.nickname||"마주"}님의 경주 기록과 획득한 호칭입니다.</p>
  {error&&<div role="alert" style={{padding:12,background:"#492d31",borderRadius:10}}>{error}</div>}
  {!data&&!error&&<p>업적을 불러오는 중입니다.</p>}
  {categories.map(category=><section key={category} style={{marginTop:26}}>
   <h2 style={{fontSize:18,borderBottom:"1px solid #354151",paddingBottom:8}}>{labels[category]||category}</h2>
   <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(220px,1fr))",gap:10}}>
    {(data?.definitions||[]).filter(d=>d.category===category).flatMap(d=>{
     const related=(data?.progress||[]).filter(p=>p.achievement_key===d.achievement_key);
     if(d.subject_kind==="HORSE"){
      return (data?.horses||[]).map(h=>{
       const p=related.find(x=>x.subject_id===h.id),value=Number(p?.progress||0),done=!!p?.unlocked_at;
       return <article key={d.achievement_key+":"+h.id} style={{background:"#162131",border:"1px solid "+(done?"#c7a65c":"#2d3a4b"),borderRadius:12,padding:14}}>
        <div style={{display:"flex",justifyContent:"space-between",gap:8}}><b>{d.title}</b><span>{done?"🏆":"🔒"}</span></div>
        <div style={{fontSize:13,color:"#e4c778",marginTop:6}}>{h.name}</div>
        <div style={{height:6,background:"#2d3a4b",borderRadius:99,marginTop:12}}><div style={{height:6,width:Math.min(100,value/Number(d.threshold)*100)+"%",background:"#c7a65c",borderRadius:99}}/></div>
        <small style={{color:"#aab3c1"}}>{value.toLocaleString()} / {Number(d.threshold).toLocaleString()}</small>
       </article>
      });
     }
     const p=related.find(x=>x.subject_id==="00000000-0000-0000-0000-000000000000"),value=Number(p?.progress||0),done=!!p?.unlocked_at;
     return [<article key={d.achievement_key} style={{background:"#162131",border:"1px solid "+(done?"#c7a65c":"#2d3a4b"),borderRadius:12,padding:14}}>
      <div style={{display:"flex",justifyContent:"space-between",gap:8}}><b>{d.title}</b><span>{done?"🏆":"🔒"}</span></div>
      <div style={{fontSize:13,color:"#aab3c1",marginTop:6}}>{d.description}</div>
      <div style={{height:6,background:"#2d3a4b",borderRadius:99,marginTop:12}}><div style={{height:6,width:Math.min(100,value/Number(d.threshold)*100)+"%",background:"#c7a65c",borderRadius:99}}/></div>
      <small style={{color:"#aab3c1"}}>{value.toLocaleString()} / {Number(d.threshold).toLocaleString()}</small>
     </article>];
    })}
   </div>
  </section>)}
</main>
}
