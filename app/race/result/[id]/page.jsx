"use client";
import {useEffect,useState} from "react";
import {useParams} from "next/navigation";
export default function OfficialResultPage(){
 const params=useParams();const [race,SetRace]=useState(null),[error,SetError]=useState("");
 useEffect(()=>{if(!params?.id)return;let alive=true;
  fetch("/api/race/official/"+encodeURIComponent(params.id),{cache:"no-store"})
  .then(async r=>{const d=await r.json();if(!r.ok)throw new Error(d.error||"결과 조회 오류");
   if(alive){SetRace(d);SetError("")}})
  .catch(e=>{if(alive)SetError(e.message)});return()=>{alive=false};
 },[params?.id]);
 return <div className="shell"><header className="header">
 <a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a>
 <span className="coin">🏁 공식 경주 결과</span></header>
 <div className="area">
 <a href="/schedule" className="outline" style={{textDecoration:"none",display:"inline-block",marginBottom:14}}>‹ 경주시간표</a>
 <h2>{race?.track||"경주"} · 공식 기록</h2>
 {error&&<div className="notice">{error}</div>}
 {!race&&!error&&<div className="notice">공식 경주 결과를 조회 중…</div>}
 {race?.status!=="FINISHED"&&race&&<div className="notice">경주 상태: {race.status} · 아직 공식 결과가 없습니다.</div>}
 {race?.status==="FINISHED"&&<>
 <div className="card"><b className="gold">{race.kstDate} · {race.startTime} · {race.track}</b>
 <div className="muted">{race.className} · {race.distanceM}m · 엔진 {race.engineVersion}</div>
 <div className="notice">공식 순위·기록은 저장됐으나 상금·경제_v2 정산은 아직 연결되지 않았습니다.</div></div>
 <div className="section"><h2>최종 결과</h2></div>
 <div className="card">{race.results?.map(r=><div className="row line small" key={r.horseId}>
 <b className="gold">{r.rank}위</b><span>{r.number}번 {r.name}</span><span>{Number(r.timeSec).toFixed(2)}초</span>
 </div>)}</div>
 <div className="section"><h2>200m 구간 순위</h2></div>
 {race.sections?.map(sec=><div className="card" key={sec.distanceM}>
 <b>{sec.distanceM}m</b><div className="muted">{sec.ranks?.slice(0,5).map(r=>r.rank+"위 "+r.number+"번 "+r.name).join(" · ")}</div></div>)}
 <div className="section"><h2>경주 사건 로그</h2></div>
 {race.events?.filter(e=>e.text&&e.eventType!=="STRATEGY_SWITCH"&&e.importance>=2).slice(0,100).map(e=><div className="card" key={e.seq}>
 <div className="muted">{Number(e.timeSec).toFixed(1)}초 · {Number(e.distanceM).toFixed(0)}m</div>
 <div className="small">{e.text}</div></div>)}
 </>}
 </div></div>
}
