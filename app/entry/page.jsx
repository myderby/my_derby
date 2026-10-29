"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const client=()=>createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
const region=s=>s==="부산경남"?"부산":s==="제주"?"영천":s;
export default function EntryPage(){
 const [data,D]=useState(null),[race,R]=useState(""),[horse,H]=useState(""),[jockey,J]=useState(""),[error,E]=useState(""),[info,I]=useState(""),[busy,B]=useState(false);
 const token=async()=>{const {data:{session}}=await client().auth.getSession();if(!session)throw new Error("월드 화면에서 먼저 로그인하세요.");return session.access_token};
 const load=async()=>{try{const t=await token();const res=await fetch("/api/world/entry",{headers:{Authorization:"Bearer "+t},cache:"no-store"});const v=await res.json();if(!res.ok)throw new Error(v.error);D(v);E("");}catch(e){E(e.message)}};
 useEffect(()=>{void load()},[]);
 const send=async action=>{B(true);E("");I("");try{const t=await token();const res=await fetch("/api/world/entry",{method:"POST",headers:{Authorization:"Bearer "+t,"Content-Type":"application/json"},body:JSON.stringify({action,raceId:race,horseId:horse,jockeyId:jockey})});const v=await res.json();if(!res.ok)throw new Error(v.error);I(action==="race"?"출전 확정되었습니다. 기수를 선택할 수 있습니다.":"기수 신청이 수락되었습니다.");await load()}catch(e){E(e.message)}finally{B(false)}};
 const selectedRace=data?.races?.find(x=>x.id===race);
 const grade=selectedRace?.class_name.match(/([1-6])등급/)?.[1];
 const eligible=(data?.horses||[]).filter(h=>h.life_stage==="RACING"&&h.health_state==="HEALTHY"&&!h.racing_retired_permanently&&h.age_years>=2&&Number(h.fatigue)<90&&region(h.source_meet)===selectedRace?.track&&String(h.source_grade_no)===grade);
 const myEntry=(data?.entries||[]).find(x=>x.id===race&&x.horseId===horse);
 const availableJockeys=(data?.jockeys||[]).filter(j=>!j.home_track||j.home_track===selectedRace?.track);
 return <main className="shell"><header className="header"><a href="/" className="brand">MY DERBY</a><span className="coin">출전·기수 신청</span></header><div className="area">
 <a href="/world" className="outline" style={{textDecoration:"none",display:"inline-block",marginBottom:18}}>‹ 내 경주마 보기</a>
 <div className="section"><h2>공식 경주 출전 신청</h2><button onClick={load}>새로고침 ↻</button></div>
 <div className="notice">실제 월드 DB에 반영됩니다. 출전 신청은 미래 경주만 가능하며 NPC로 채워진 슬롯을 대체합니다. 출전 확정 후 기수를 지정하세요.</div>
 {error&&<div className="notice" role="alert">{error}</div>}{info&&<div className="card" style={{color:"#7cdb9f"}}>{info}</div>}
 {data&&!data.joined&&<div className="notice">먼저 /world에서 마주로 등록하세요.</div>}
 {data?.joined&&<div className="card">
 <label>경주 선택</label><select className="field" value={race} onChange={e=>{R(e.target.value);H("");J("")}}>
 <option value="">경주를 선택하세요</option>{data.races.map(r=><option key={r.id} value={r.id}>{r.race_day}일차 · {r.track} {r.race_no}경주 · {r.class_name} · {r.distance_m}m · {r.start_time} · 교체가능 {r.replaceableNpcCount}두</option>)}</select>
 <label>내 경주마</label><select className="field" value={horse} onChange={e=>{H(e.target.value);J("")}}><option value="">경주마 선택</option>{eligible.map(h=><option key={h.id} value={h.id}>{h.name} · {h.age_years}세 · {h.source_grade_no}등급</option>)}</select>
 {selectedRace&&<div className="muted">출전 등록 {selectedRace.confirmedCount}/{selectedRace.target_runner_count||"—"}두 · 등록 대체 슬롯 {selectedRace.replaceableNpcCount}두</div>}
 {selectedRace&&eligible.length===0&&<div className="muted">이 경주에 출전 가능한 보유마가 없습니다. 등급·지역·건강 조건을 확인하세요.</div>}
 {myEntry?<div className="notice">✅ 출전 확정 · 기수를 신청할 수 있습니다.</div>:<button className="primary wide" disabled={busy||!race||!horse||!selectedRace?.replaceableNpcCount} onClick={()=>send("race")}>출전 신청 및 확정</button>}
 </div>}
 {myEntry&&<div className="card"><div className="section"><h2>기수 기승 신청</h2></div>
 <div className="muted">현재 기수: {data.jockeys.find(j=>j.id===myEntry.jockeyId)?.name||"미지정"} · NPC의 기승 가능 여부를 확인하여 즉시 처리합니다.</div>
 <select className="field" value={jockey} onChange={e=>J(e.target.value)}><option value="">기수 선택</option>{availableJockeys.map(j=><option key={j.id} value={j.id}>{j.name} · {j.home_track||"전 지역"} · 하루 최대 {j.max_daily_rides}회</option>)}</select>
 <button className="primary wide" disabled={busy||!jockey} onClick={()=>send("jockey")}>선택한 기수에게 신청</button></div>}
 {data?.joined&&<><div className="section"><h2>내 출전 현황</h2></div>{data.entries.length===0?<div className="notice">아직 신청한 출전이 없습니다.</div>:data.entries.map(e=>{const r=data.races.find(x=>x.id===e.id),h=data.horses.find(x=>x.id===e.horseId),j=data.jockeys.find(x=>x.id===e.jockeyId);return <div className="card row" key={e.id+e.horseId}><div><b>{h?.name||"경주마"} · {r?.track} {r?.race_no}경주</b><div className="muted">게임 {r?.race_day}일차 · 기수 {j?.name||"미정"} · {e.status}</div></div><button className="outline" onClick={()=>{R(e.id);H(e.horseId);J(e.jockeyId||"")}}>기수 선택</button></div>})}</>}
 </div></main>;
}
