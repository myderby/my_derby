"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const format=n=>Number(n||0).toLocaleString("ko-KR");
function Stats({value}){return <div className="record-grid">{[["출전",value.starts],["1위",value.wins],["2위",value.seconds],["3위",value.thirds]].map(([label,num])=><div className="record-stat" key={label}><span>{label}</span><strong>{format(num)}</strong></div>)}<div className="record-prize">획득 상금 <strong>{format(value.prize)} G</strong></div></div>}
export default function MyRecord(){
 const [state,setState]=useState({loading:true,data:null,error:""});
 useEffect(()=>{let active=true;const load=async()=>{try{
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if(!url||!key)throw Error("인증 설정이 없습니다.");
  const client=createClient(url,key);const {data:{session}}=await client.auth.getSession();
  if(!session)throw Error("로그인이 필요합니다.");
  const response=await fetch("/api/player/my-record",{headers:{Authorization:"Bearer "+session.access_token},cache:"no-store"});
  const body=await response.json();if(!response.ok)throw Error(body.error||"기록 조회 실패");
  if(active)setState({loading:false,data:body,error:""});
 }catch(error){if(active)setState({loading:false,data:null,error:error.message});}};load();return()=>{active=false};},[]);
 const data=state.data;
 return <main className="shell"><header className="header"><div><div className="brand">MY DERBY</div><div className="sub">마주 기록실</div></div><div className="controls"><a className="outline" href="/" style={{textDecoration:"none"}}>홈</a><a className="outline" href="/bets" style={{textDecoration:"none"}}>베팅 이력 ›</a></div></header>
 <div className="area"><div className="section"><h2>🏅 나의 정보</h2><a href="/" style={{color:"#efc779",fontSize:12}}>돌아가기</a></div>
 {state.loading?<div className="notice">공식 경주 기록을 조회하고 있습니다.</div>:state.error?<div className="notice" role="alert">{state.error}</div>:data&&<>
 <div className="card"><div className="muted">마주</div><h2 style={{margin:"8px 0",color:"#f0c572"}}>{data.profile.nickname}</h2><div className="muted">공식 결과가 확정된 경주만 집계합니다. 출전 당시의 마주를 기준으로 합니다.</div></div>
 <div className="section"><h2>통산 전적</h2></div><div className="card"><Stats value={data.total}/></div>
 <div className="section"><h2>시즌별 전적</h2></div>{data.seasons.length?data.seasons.map(s=><div className="card" key={s.season}><b className="gold">시즌 {s.season}</b><Stats value={s}/></div>):<div className="notice">집계된 시즌 기록이 없습니다.</div>}
 <div className="section"><h2>대상경주(OPEN) 성적</h2></div><div className="card"><Stats value={data.open}/></div>
 <div className="section"><h2>🏆 대상경주 트로피</h2></div>{data.trophies.length?data.trophies.map(t=><div className="card" key={t.raceId}><b className="gold">🏆 {t.name} 우승</b><div className="muted" style={{marginTop:7}}>시즌 {t.season} · {t.track} · {t.raceNo}경주</div></div>):<div className="notice">아직 획득한 대상경주 트로피가 없습니다. OPEN 경주 우승 시 이곳에 기록됩니다.</div>}
 </>}</div></main>;
}
