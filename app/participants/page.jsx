"use client";
import {useEffect,useMemo,useState} from "react";
import StaffLink from "../components/StaffLink";
const format=n=>Number(n||0).toLocaleString("ko-KR");
const rate=(value,starts)=>starts?(Number(value||0)/Number(starts)*100).toFixed(1)+"%":"—";
export default function Participants(){
 const [people,setPeople]=useState([]),[view,setView]=useState("records"),[kind,setKind]=useState("jockey"),[meet,setMeet]=useState("전체"),[term,setTerm]=useState(""),[error,setError]=useState("");
 const [sort,setSort]=useState({key:null,direction:"desc"});
 useEffect(()=>{const v=new URLSearchParams(location.search).get("view");if(["owners","trainers","records"].includes(v))setView(v);fetch("/api/world/participants",{cache:"no-store"}).then(async r=>{const j=await r.json();if(!r.ok)throw Error(j.error);setPeople(j.people||[])}).catch(e=>setError(e.message))},[]);
 const type=view==="owners"?"owner":view==="trainers"?"trainer":kind;
 const rows=useMemo(()=>people.filter(p=>p.type===type&&(meet==="전체"||p.track===meet)&&p.name?.includes(term)).sort((a,b)=>{
  if(sort.key){
   const metric=value=>{
    const starts=Number(value.starts||0),wins=Number(value.wins||0),seconds=Number(value.seconds||0),thirds=Number(value.thirds||0);
    if(sort.key==="starts")return starts;
    if(sort.key==="wins")return wins;
    if(sort.key==="seconds")return seconds;
    if(sort.key==="thirds")return thirds;
    if(!starts)return null;
    if(sort.key==="winRate")return wins/starts;
    if(sort.key==="quinellaRate")return (wins+seconds)/starts;
    if(sort.key==="placeRate")return (wins+seconds+thirds)/starts;
    return null;
   };
   const aValue=metric(a),bValue=metric(b);
   if(aValue===null&&bValue!==null)return 1;
   if(bValue===null&&aValue!==null)return -1;
   if(aValue!==null&&bValue!==null&&aValue!==bValue){
    const difference=aValue-bValue;
    return sort.direction==="asc"?difference:-difference;
   }
  }else if(view==="records")return Number(b.wins||0)-Number(a.wins||0)||Number(b.starts||0)-Number(a.starts||0)||a.name.localeCompare(b.name,"ko");
  return a.name.localeCompare(b.name,"ko");
 }),[people,type,meet,term,view,sort]);
 const sortableColumns={출전:"starts","1위":"wins","2위":"seconds","3위":"thirds",승률:"winRate",복승률:"quinellaRate",연승률:"placeRate"};
 const toggleSort=key=>setSort(current=>({key,direction:current.key===key&&current.direction==="asc"?"desc":"asc"}));
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
 </article>)}</div>:<div className="race-entry-wrap"><table className="race-entry-table"><thead><tr>{["이름","소속","출전","1위","2위","3위","승률","복승률","연승률"].map(x=>{
  const key=sortableColumns[x];
  return <th key={x} aria-sort={key?(sort.key===key?(sort.direction==="asc"?"ascending":"descending"):"none"):undefined}>
   {key?<button type="button" className="participant-sort-button" onClick={()=>toggleSort(key)} aria-label={x+" 기준 "+(sort.key===key&&sort.direction==="asc"?"내림차순":"오름차순")}>
    {x} <span>{sort.key===key?(sort.direction==="asc"?"▲":"▼"):"↕"}</span>
   </button>:x}</th>;
 })}</tr></thead><tbody>{rows.map(p=><tr key={p.type+p.id}><td className="race-entry-name"><StaffLink kind={p.type} staffId={p.id}>{p.name}</StaffLink></td><td>{p.track}</td><td>{p.starts}</td><td>{p.wins}</td><td>{p.seconds}</td><td>{p.thirds}</td><td>{rate(p.wins,p.starts)}</td><td>{rate(Number(p.wins||0)+Number(p.seconds||0),p.starts)}</td><td>{rate(Number(p.wins||0)+Number(p.seconds||0)+Number(p.thirds||0),p.starts)}</td></tr>)}</tbody></table></div>}
 <p className="muted">{view==="owners"?"마주별 공식 경주 성적과 입상률입니다.":"조교사는 경마장별로 소속이 고정됩니다. 공식 경주 기록이 없는 경우 0전으로 표시됩니다."}</p>
 </div></main>;
}
