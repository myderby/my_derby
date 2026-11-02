"use client";
import {useEffect,useMemo,useState} from "react";
import StaffLink from "../components/StaffLink";
const format=n=>Number(n||0).toLocaleString("ko-KR");
const rate=(value,starts)=>starts?(Number(value||0)/Number(starts)*100).toFixed(1)+"%":"—";
export default function Participants(){
 const [people,setPeople]=useState([]),[view,setView]=useState("records"),[kind,setKind]=useState("jockey"),[meet,setMeet]=useState("전체"),[term,setTerm]=useState(""),[error,setError]=useState("");
 useEffect(()=>{const v=new URLSearchParams(location.search).get("view");if(["owners","trainers","records"].includes(v))setView(v);fetch("/api/world/participants",{cache:"no-store"}).then(async r=>{const j=await r.json();if(!r.ok)throw Error(j.error);setPeople(j.people||[])}).catch(e=>setError(e.message))},[]);
 const type=view==="owners"?"owner":view==="trainers"?"trainer":kind;
 const rows=useMemo(()=>people.filter(p=>p.type===type&&(meet==="전체"||p.track===meet)&&p.name?.includes(term)).sort((a,b)=>view==="records"?b.wins-a.wins||b.starts-a.starts:a.name.localeCompare(b.name,"ko")),[people,type,meet,term,view]);
 const pageTitle=view==="owners"?"전체 마주":view==="trainers"?"전체 조교사":"경주 성적";
 return <main className="shell"><header className="header"><a href="/" className="brand">MY DERBY</a><span className="coin">성적·인물</span></header><div className="area">
 <div className="section"><h2>{pageTitle}</h2><a href="/" className="outline">홈</a></div>
 <div className="tabs">{[["owners","전체 마주"],["trainers","전체 조교사"],["records","성적"]].map(([k,label])=><button className={view===k?"active":""} onClick={()=>{setView(k);setMeet("전체")}} key={k}>{label}</button>)}</div>
 {view==="records"&&<div className="tabs">{[["jockey","기수"],["owner","마주"],["trainer","조교사"]].map(([k,label])=><button className={kind===k?"active":""} onClick={()=>{setKind(k);setMeet("전체")}} key={k}>{label} 성적</button>)}</div>}
 {(type==="trainer"||type==="jockey")&&<div className="tabs">{["전체","서울","부산","영천"].map(m=><button className={meet===m?"active":""} key={m} onClick={()=>setMeet(m)}>{m}</button>)}</div>}
 <input className="field" placeholder="이름 검색" value={term} onChange={e=>setTerm(e.target.value)}/>
 <p className="muted">{rows.length}명 · 실제 공식 경주 결과 기준</p>
 {error&&<div className="notice">{error}</div>}
 {view==="owners"?<div className="participant-cards">{rows.map(p=><article className="card participant-card" key={p.type+p.id}>
  <div className="participant-card-head"><div><strong>{p.name}</strong><span>{p.track||"소속 미정"}</span></div><span className="tag">마주</span></div>
  <div className="participant-stats">{[["출전",p.starts], ["우승",p.wins], ["2착",p.seconds], ["3착",p.thirds]].map(([label,value])=><div key={label}><small>{label}</small><b>{format(value)}</b></div>)}</div>
  <div className="participant-rates"><span>승률 <b>{rate(p.wins,p.starts)}</b></span><span>복승률 <b>{rate(Number(p.wins||0)+Number(p.seconds||0),p.starts)}</b></span><span>연승률 <b>{rate(Number(p.wins||0)+Number(p.seconds||0)+Number(p.thirds||0),p.starts)}</b></span></div>
 </article>)}</div>:<div className="race-entry-wrap"><table className="race-entry-table"><thead><tr>{["이름","소속","출전","1위","2위","3위","승률","복승률","연승률"].map(x=><th key={x}>{x}</th>)}</tr></thead><tbody>{rows.map(p=><tr key={p.type+p.id}><td className="race-entry-name"><StaffLink kind={p.type} staffId={p.id}>{p.name}</StaffLink></td><td>{p.track}</td><td>{p.starts}</td><td>{p.wins}</td><td>{p.seconds}</td><td>{p.thirds}</td><td>{rate(p.wins,p.starts)}</td><td>{rate(Number(p.wins||0)+Number(p.seconds||0),p.starts)}</td><td>{rate(Number(p.wins||0)+Number(p.seconds||0)+Number(p.thirds||0),p.starts)}</td></tr>)}</tbody></table></div>}
 <p className="muted">{view==="owners"?"마주별 공식 경주 성적과 입상률입니다.":"조교사는 경마장별로 소속이 고정됩니다. 공식 경주 기록이 없는 경우 0전으로 표시됩니다."}</p>
 </div></main>;
}
