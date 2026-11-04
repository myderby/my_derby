"use client";
import {Suspense,useEffect,useState} from "react";
import {useSearchParams} from "next/navigation";
import {createClient} from "@supabase/supabase-js";

const fmt=n=>Number(n||0).toLocaleString("ko-KR");
const sex={MALE:"수말",FEMALE:"암말",GELDING:"거세마"};
function ResultTable({title,rows,columns,empty}){
 return <section className="section" style={{display:"block"}}>
  <h2>{title}</h2>
  {!rows?.length?<div className="notice">{empty}</div>:<div className="race-entry-wrap" role="region" tabIndex={0} aria-label={title}>
   <table className="race-entry-table"><thead><tr>{columns.map(c=><th key={c.label}>{c.label}</th>)}</tr></thead>
    <tbody>{rows.map((row,i)=><tr key={row.id||row.name||row.grade||row.distanceM||i}>
     {columns.map(c=><td key={c.label}>{c.value(row)}</td>)}
    </tr>)}</tbody>
   </table>
  </div>}
 </section>;
}
function Offspring(){
 const q=useSearchParams(),horseId=q.get("horseId");
 const [data,D]=useState(null),[page,P]=useState(Number(q.get("page")||1)),[error,E]=useState(""),[loading,L]=useState(false);
 useEffect(()=>{
  const abort=new AbortController();
  async function load(){
   L(true);E("");
   try{
    const headers={};
    try{const c=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
     const {data:s}=await c.auth.getSession();if(s?.session?.access_token)headers.Authorization="Bearer "+s.session.access_token;
    }catch{}
    const r=await fetch(`/api/world/horse-offspring?horseId=${encodeURIComponent(horseId||"")}&page=${page}`,
     {headers,cache:"no-store",signal:abort.signal});
    const result=await r.json();if(!r.ok)throw new Error(result.error||"자마 정보를 불러오지 못했습니다.");
    if(!abort.signal.aborted)D(result);
   }catch(e){if(!abort.signal.aborted)E(e.message)}finally{if(!abort.signal.aborted)L(false)}
  }
  if(horseId)void load();else{E("경주마 정보가 없습니다.");L(false)}
  return()=>abort.abort();
 },[horseId,page]);
 const parent=data?.parent,summary=data?.summary;
 return <main className="shell directory-shell"><header className="header">
  <a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🧬 자마 내역</span>
 </header><div className="area">
  <div className="controls"><a className="outline" href={horseId?`/horses/profile?horseId=${encodeURIComponent(horseId)}`:"/horses"}>‹ 말 정보</a></div>
  {loading&&!data&&<div className="notice">자마 성적을 불러오는 중…</div>}{error&&<div className="notice" role="alert">{error}</div>}
  {parent&&<>
   <div className="card"><div className="dir-horse-name" style={{fontSize:24}}>{parent.name}</div>
    <div className="muted">{sex[parent.sex]||parent.sex} · {parent.status} · {parent.rating==null?"레이팅 미등록":`레이팅 ${fmt(parent.rating)}`} · {parent.grade?`${parent.grade}등급`:"등급 미등록"}</div>
    <div className="horse-profile-attributes" style={{marginTop:12}}>
     <div><span>자마</span><strong>{fmt(summary?.offspring)}두</strong></div>
     <div><span>출전</span><strong>{fmt(summary?.starts)}회</strong></div>
     <div><span>1위</span><strong>{fmt(summary?.wins)}회</strong></div>
     <div><span>2위</span><strong>{fmt(summary?.second)}회</strong></div>
     <div><span>3위</span><strong>{fmt(summary?.third)}회</strong></div>
    </div>
   </div>
   <ResultTable title="등급별 성적" rows={data.byGrade} empty="자마의 경주 기록이 아직 없습니다."
    columns={[{label:"등급",value:r=>`${r.grade}등급`},{label:"출전",value:r=>fmt(r.starts)},{label:"1위",value:r=>fmt(r.wins)},{label:"2위",value:r=>fmt(r.second)},{label:"3위",value:r=>fmt(r.third)}]}/>
   <ResultTable title="거리별 성적" rows={data.byDistance} empty="거리별로 집계할 경주 기록이 없습니다."
    columns={[{label:"거리",value:r=>`${fmt(r.distanceM)}m`},{label:"출전",value:r=>fmt(r.starts)},{label:"1위",value:r=>fmt(r.wins)},{label:"2위",value:r=>fmt(r.second)},{label:"3위",value:r=>fmt(r.third)}]}/>
   <ResultTable title="대상경주 성적" rows={data.stakes} empty="자마의 대상경주 기록이 아직 없습니다."
    columns={[{label:"대상경주",value:r=>r.name||"대상경주"},{label:"출전",value:r=>fmt(r.starts)},{label:"1위",value:r=>fmt(r.wins)},{label:"2위",value:r=>fmt(r.second)},{label:"3위",value:r=>fmt(r.third)}]}/>
   <div className="section"><h2>자마 목록</h2><span className="tag">총 {fmt(data.total)}두</span></div>
   {!data.offspring?.length?<div className="notice">등록된 자마가 없습니다.</div>:data.offspring.map(h=><div className="card row" key={h.id}>
    <div><a href={`/horses/profile?horseId=${encodeURIComponent(h.id)}`} style={{fontWeight:700}}>{h.name}</a>
     <div className="muted">{sex[h.sex]||h.sex} · {h.status} · {fmt(h.starts)}전 {fmt(h.first)}승 · 2위 {fmt(h.second)}회 · 3위 {fmt(h.third)}회</div>
     <div className="muted">은퇴 직전 레이팅 {h.retirementRating==null?"-":fmt(h.retirementRating)} · 등급 {h.retirementGrade?`${h.retirementGrade}등급`:"-"}</div>
    </div><a className="outline" href={`/horses/profile?horseId=${encodeURIComponent(h.id)}`}>말 정보 ›</a>
   </div>)}
   {data.totalPages>1&&<div className="controls" style={{justifyContent:"center"}}>
    <button className="outline" disabled={page<=1||loading} onClick={()=>P(page-1)}>이전</button>
    <span className="tag">{data.page} / {data.totalPages}</span>
    <button className="outline" disabled={page>=data.totalPages||loading} onClick={()=>P(page+1)}>다음</button>
   </div>}
  </>}
 </div></main>;
}
export default function OffspringPage(){return <Suspense fallback={<div>자마 정보를 불러오는 중…</div>}><Offspring/></Suspense>}
