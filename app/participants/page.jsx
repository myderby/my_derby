"use client";
import {useEffect,useMemo,useState} from "react";
export default function Participants(){
 const [people,setPeople]=useState([]),[view,setView]=useState("records"),[kind,setKind]=useState("jockey"),[meet,setMeet]=useState("전체"),[term,setTerm]=useState(""),[error,setError]=useState("");
 useEffect(()=>{const v=new URLSearchParams(location.search).get("view");if(["owners","trainers","records"].includes(v))setView(v);fetch("/api/world/participants",{cache:"no-store"}).then(async r=>{const j=await r.json();if(!r.ok)throw Error(j.error);setPeople(j.people||[])}).catch(e=>setError(e.message))},[]);
 const type=view==="owners"?"owner":view==="trainers"?"trainer":kind;
 const rows=useMemo(()=>people.filter(p=>p.type===type&&(meet==="전체"||p.track===meet)&&p.name?.includes(term)).sort((a,b)=>view==="records"?b.wins-a.wins||b.starts-a.starts:a.name.localeCompare(b.name,"ko")),[people,type,meet,term,view]);
 return <main className="shell"><header className="header"><a href="/" className="brand">MY DERBY</a><span className="coin">성적·인물</span></header><div className="area">
 <div className="section"><h2>전체 인물 및 성적</h2><a href="/" className="outline">홈</a></div>
 <div className="tabs">{[["owners","전체 마주"],["trainers","전체 조교사"],["records","성적"]].map(([k,label])=><button className={view===k?"active":""} onClick={()=>{setView(k);setMeet("전체")}} key={k}>{label}</button>)}</div>
 {view==="records"&&<div className="tabs">{[["jockey","기수"],["owner","마주"],["trainer","조교사"]].map(([k,label])=><button className={kind===k?"active":""} onClick={()=>{setKind(k);setMeet("전체")}} key={k}>{label} 성적</button>)}</div>}
 {(type==="trainer"||type==="jockey")&&<div className="tabs">{["전체","서울","부산","영천"].map(m=><button className={meet===m?"active":""} key={m} onClick={()=>setMeet(m)}>{m}</button>)}</div>}
 <input className="field" placeholder="이름 검색" value={term} onChange={e=>setTerm(e.target.value)}/>
 <p className="muted">{rows.length}명 · 실제 공식 경주 결과 기준</p>
 {error&&<div className="notice">{error}</div>}
 <div className="race-entry-wrap"><table className="race-entry-table"><thead><tr>{["이름","소속","출전","1위","2위","3위","승률","복승률","연승률"].map(x=><th key={x}>{x}</th>)}</tr></thead><tbody>{rows.map(p=><tr key={p.type+p.id}><td className="race-entry-name">{p.name}</td><td>{p.track}</td><td>{p.starts}</td><td>{p.wins}</td><td>{p.seconds}</td><td>{p.thirds}</td><td>{p.starts?(p.wins/p.starts*100).toFixed(1)+"%":"—"}</td><td>{p.starts?((p.wins+p.seconds)/p.starts*100).toFixed(1)+"%":"—"}</td><td>{p.starts?((p.wins+p.seconds+p.thirds)/p.starts*100).toFixed(1)+"%":"—"}</td></tr>)}</tbody></table></div>
 <p className="muted">조교사는 경마장별로 소속이 고정됩니다. 공식 경주 기록이 없는 경우 0전으로 표시됩니다.</p>
 </div></main>;
}