"use client";
import {useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import StaffLink from "../components/StaffLink";
import HorseLink from "../components/HorseLink";

const won=n=>Number(n||0).toLocaleString("ko-KR")+" G";
const num=n=>Number(n||0).toLocaleString("ko-KR");
const seoulDate=()=>new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",
 year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());
const changeDay=(day,offset)=>new Date(Date.parse(day+"T00:00:00Z")+offset*86400000).toISOString().slice(0,10);
const recentDay=()=>changeDay(seoulDate(),-1);
const pad=n=>String(n||0).padStart(2,"0");
const rankText=n=>n===1?"우승":n===2?"준우승":n===3?"3위":num(n)+"위";
const rate=p=>p?.starts?(Number(p.wins)/Number(p.starts)*100).toFixed(1)+"%":"0.0%";

function NewsRanking({icon,label,subject,people}) {
 const lead=people?.[0];
 const staffKind=subject==="기수"?"jockey":subject==="조교사"?"trainer":null;
 return <section className="news-section">
  <div className="section"><h2>{icon} {label}</h2><span className="tag">TOP {Math.min(5,people?.length||0)}</span></div>
  {!lead?<div className="news-empty">{subject} 기록이 없습니다.</div>:<>
   <div className="news-feature">
    <div className="news-flag">{subject} 주요 소식</div>
    <div className="news-feature-title"><StaffLink kind={staffKind} staffId={staffKind?lead.person_key:null}>{lead.person_name}</StaffLink>, {num(lead.wins)}승으로 눈길</div>
    <p>{num(lead.starts)}전에서 {num(lead.wins)}승, 2위 {num(lead.seconds)}회, 3위 {num(lead.thirds)}회. 승률 {rate(lead)}를 기록했습니다.</p>
   </div>
   <div className="news-leaderboard">{people.map((item,i)=><div className="news-rank" key={item.person_key||item.person_name}>
     <div className="news-position">{i+1}</div><div className="news-rank-main"><b><StaffLink kind={staffKind} staffId={staffKind?item.person_key:null}>{item.person_name}</StaffLink></b>
      <small>{num(item.starts)}전 · {num(item.wins)}승 · 2위 {num(item.seconds)}회 · 3위 {num(item.thirds)}회</small></div>
     <div className="news-rank-right"><b>{rate(item)}</b><span>{won(item.prize)}</span></div>
    </div>)}</div>
  </>}
 </section>
}
function OpenNews({items}) {
 return <section className="news-section"><div className="section"><h2>🏆 OPEN · 대상경주 우승 소식</h2></div>
  {!items?.length?<div className="news-empty">이 날짜에 공식 결과가 확정된 OPEN·대상경주 우승 기록이 없습니다.</div>:
   items.map((x,i)=><article className="news-open-card" key={x.race_id+"-"+i}>
    <div className="news-flag">대상경주 우승 · {x.track} {pad(x.start_time?.slice(0,2))}:00</div>
    <h3>{x.official_race_name&&x.official_race_name!=="일반"?x.official_race_name:x.class_name}</h3>
    <div className="news-feature-title">🥇 <HorseLink horseId={x.horse_id}>{x.horse_name}</HorseLink> 우승!</div>
    <p>마주 {x.owner_name} · 기수 <StaffLink kind="jockey" staffId={x.jockey_id}>{x.jockey_name}</StaffLink> · 조교사 <StaffLink kind="trainer" staffId={x.trainer_id}>{x.trainer_name}</StaffLink></p>
    <div className="news-meta">{x.track} {x.race_no}경주 · {num(x.distance_m)}m · 우승 상금 {won(x.prize)} <a href={"/race/"+x.race_id}>경주 결과 ›</a></div>
   </article>)}
 </section>;
}
function MyNews({data}) {
 const mine=data?.mine||[],summary=data?.mySummary||{};
 return <section className="news-section" id="my-news">
  <div className="section"><h2>🐎 나의 경주 소식</h2><span className="tag">내 말 전용</span></div>
  <div className="news-my-overview"><span><strong>{num(summary.starts)}</strong><small>출전</small></span>
   <span><strong>{num(summary.wins)}</strong><small>우승</small></span>
   <span><strong>{num(summary.seconds)}</strong><small>준우승</small></span>
   <span><strong>{num(summary.thirds)}</strong><small>3위</small></span></div>
  <div className="news-total-prize">해당 날짜 내 경주마 획득 상금 <strong>{won(summary.prize)}</strong></div>
  {!mine.length?<div className="news-empty">이 날짜에는 내 소유 경주마의 확정된 경주 결과가 없습니다.<br/>
    경주에 출전하지 않았거나 공식 결과가 아직 확정되지 않았을 수 있습니다.</div>:
   mine.map(x=><article className="news-personal-card" key={x.race_id+"-"+x.horse_id}>
    <div className="news-personal-head"><span className={"news-placing"+(x.finish_rank===1?" first":"")}>{rankText(x.finish_rank)}</span>
     <span className="news-meta">{x.track} {x.start_time?.slice(0,5)} · {x.race_no}경주 · {x.class_name}</span></div>
    <h3><HorseLink horseId={x.horse_id}>{x.horse_name}</HorseLink>{x.finish_rank<=3?" · 입상 소식":""}</h3>
    <p>{x.horse_name}이(가) {x.track} {x.race_no}경주에서 {rankText(x.finish_rank)}을(를) 기록했습니다.
      {Number(x.prize)>0?" 획득 상금은 "+won(x.prize)+"입니다.":""}</p>
    <div className="news-meta">기수 <StaffLink kind="jockey" staffId={x.jockey_id}>{x.jockey_name}</StaffLink> · 조교사 <StaffLink kind="trainer" staffId={x.trainer_id}>{x.trainer_name}</StaffLink> <a href={"/race/"+x.race_id} style={{float:"right"}}>경주 상세 ›</a></div>
   </article>)}
 </section>;
}

export default function DailyNewsPage() {
 const [selectedDate,SetSelectedDate]=useState(recentDay);
 const [tab,SetTab]=useState("all");
 const [auth,SetAuth]=useState({status:"loading",token:""});
 const [state,SetState]=useState({loading:true,data:null,error:""});
 const yesterday=useMemo(recentDay,[]);
 const earliest=useMemo(()=>changeDay(yesterday,-89),[yesterday]);
 useEffect(()=>{
  const next=new URLSearchParams(window.location.search).get("view");
  if(next==="mine")SetTab("mine");
  let active=true,client;
  try{client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,
   process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)}catch{
    SetAuth({status:"error",token:""});return;
  }
  client.auth.getSession().then(({data,error})=>{
   if(!active)return;
   if(error){SetAuth({status:"error",token:""});return;}
   SetAuth({status:data.session?"ready":"signed-out",token:data.session?.access_token||""});
  }).catch(()=>{if(active)SetAuth({status:"error",token:""})});
  const {data:{subscription}}=client.auth.onAuthStateChange((_event,session)=>{
   if(active)SetAuth({status:session?"ready":"signed-out",token:session?.access_token||""});
  });
  return()=>{active=false;subscription.unsubscribe()};
 },[]);
 useEffect(()=>{
  if(auth.status!=="ready"||!auth.token){SetState(s=>({...s,loading:auth.status==="loading"}));return;}
  let active=true;
  const controller=new AbortController();
  SetState(s=>({...s,loading:true,error:""}));
  fetch("/api/news/daily?date="+encodeURIComponent(selectedDate),{
   headers:{Authorization:"Bearer "+auth.token},cache:"no-store",signal:controller.signal
  }).then(async response=>{
   const result=await response.json();
   if(!response.ok)throw Error(result.error||"소식지를 가져올 수 없습니다.");
   if(active)SetState({loading:false,data:result,error:""});
  }).catch(error=>{
   if(active&&error.name!=="AbortError")SetState({loading:false,data:null,error:error.message});
  });
  return()=>{active=false;controller.abort()};
 },[selectedDate,auth.status,auth.token]);
 const data=state.data;
 const previous=()=>SetSelectedDate(x=>changeDay(x,-1));
 const next=()=>SetSelectedDate(x=>changeDay(x,1));
 return <main className="shell">
  <header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a>
   <span className="coin">📰 더비 소식지</span></header>
  <div className="area">
   <a className="outline" href="/" style={{display:"inline-block",textDecoration:"none",marginBottom:14}}>‹ 홈으로</a>
   <div className="news-masthead">
    <div className="news-edition">MY DERBY · DAILY RACING NEWS</div>
    <h1>더비 데일리</h1>
    <p>어제 경주를 오늘의 이야기로 · 공식 결과만 전합니다.</p>
    <div className="news-date">{selectedDate} 경주 소식</div>
   </div>
   <div className="news-nav">
    <button className="outline" disabled={selectedDate<=earliest||state.loading} onClick={previous}>‹ 이전 날짜</button>
    <label>경주일 <input className="field" aria-label="소식지 경주일" type="date" min={earliest} max={yesterday}
     value={selectedDate} onChange={e=>e.target.value&&SetSelectedDate(e.target.value)}/></label>
    <button className="outline" disabled={selectedDate>=yesterday||state.loading} onClick={next}>다음 날짜 ›</button>
   </div>
   <div className="tabs" aria-label="소식지 종류">
    <button className={tab==="all"?"active":""} onClick={()=>SetTab("all")}>🌍 전체 경마 소식</button>
    <button className={tab==="mine"?"active":""} onClick={()=>SetTab("mine")}>🐎 나의 소식</button>
   </div>
   {auth.status==="loading"&&<div className="notice">로그인 상태를 확인하고 있습니다.</div>}
   {auth.status==="signed-out"&&<div className="notice">소식지를 보려면 게임에 로그인해 주세요.</div>}
   {auth.status==="error"&&<div className="notice" role="alert">로그인 정보를 불러오지 못했습니다. 새로고침해 주세요.</div>}
   {state.loading&&auth.status==="ready"&&<div className="notice">전날 공식 결과를 모아 소식지를 편집하는 중입니다.</div>}
   {!state.loading&&state.error&&<div className="notice" role="alert">{state.error}</div>}
   {data&&!state.loading&&<>
    <div className="news-digest"><div><b>{num(data.raceCount)}경주</b><span>공식 결과</span></div>
      <div><b>{num(data.runnerCount)}두</b><span>출전 기록</span></div>
      <div><b>{num(data.openWinners?.length)}</b><span>OPEN 우승</span></div></div>
    {!Number(data.raceCount)?<div className="news-empty">이 날짜에 공식 결과가 확정된 경주가 없습니다. 가상의 소식은 작성하지 않습니다.</div>:
      tab==="all"?<>
       <div className="news-intro">📰 {selectedDate} 경주 결과를 바탕으로 마주·기수·조교사의 활약을 정리했습니다.
        순위는 해당 날짜의 우승 횟수, 2위·3위 횟수, 획득 상금 순으로 집계합니다.</div>
       <OpenNews items={data.openWinners}/>
       <NewsRanking icon="👑" label="마주 활약 소식" subject="마주" people={data.owners}/>
       <NewsRanking icon="🏇" label="기수 활약 소식" subject="기수" people={data.jockeys}/>
       <NewsRanking icon="🏠" label="조교사 활약 소식" subject="조교사" people={data.trainers}/>
      </>:<MyNews data={data}/>}
    {Number(data.raceCount)>0&&<p className="news-footnote">자료: My Derby 공식 확정 경주 기록. 개인 소식은 출전 당시 마주 계정을 기준으로 조회하며, 소식지 내용은 예측이나 가상 기사가 아닙니다.</p>}
   </>}
  </div>
 </main>;
}
