"use client";
import {useEffect,useState} from "react";
import HorseLink from "./HorseLink";
import {createClient} from "@supabase/supabase-js";

const changeReasons={
 EXPERIENCE_GROWTH:"경주·훈련 경험에 따른 점진 성장",
 GRADUAL_AGE_DECLINE:"전성기 이후 자연스러운 기량 하락",
 EXTENDED_INACTIVITY:"장기간 활동 공백",
 NO_ACTIVITY:"이번 주 활동 없음",
 GROWTH_POTENTIAL_REACHED:"해당 분야 성장 한계 도달",
 DECLINE_FLOOR_REACHED:"해당 분야 하락 하한 도달"
};
const skillNames={start:"출발",pace:"페이스",urging:"추진",control:"제어",judgment:"판단",
 stability:"안정성",aggression:"적극성",positioning:"위치 선정",speed:"속도",
 finishing:"막판 탄력",stamina:"지구력",acceleration:"가속력",
 power:"파워",grit:"근성",recovery:"회복력"};
const fmt=n=>Number(n||0).toLocaleString("ko-KR");
function RecordCard({title,record}){
 const s=record||{};
 return <section className="card staff-record">
  <div className="muted">{title}</div>
  <div className="large gold">{fmt(s.starts)}전 {fmt(s.wins)}승</div>
  <div className="muted">2위 {fmt(s.seconds)}회 · 3위 {fmt(s.thirds)}회</div>
  <div className="staff-rates"><span>승률 <b>{s.winRate??0}%</b></span>
   <span>복승률 <b>{s.quinellaRate??0}%</b></span>
   <span>연승률 <b>{s.placeRate??0}%</b></span></div>
  <div className="muted" style={{marginTop:8}}>획득 상금 {fmt(s.prize)} G</div>
 </section>;
}
export default function StaffProfile({kind,id}){
 const isJockey=kind==="jockey";
 const [state,setState]=useState({loading:true,data:null,error:""});
 const [ownerBond,setOwnerBond]=useState(null);
 useEffect(()=>{
  let alive=true,client;
  try{client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)}
  catch{return;}
  const update=async(session)=>{
   if(!session){if(alive)setOwnerBond(null);return;}
   const {data,error}=await client.schema("my_derby").rpc("player_staff_relationship",{p_kind:kind,p_staff_id:id});
   if(alive)setOwnerBond(error?null:data);
  };
  client.auth.getSession().then(({data})=>update(data?.session)).catch(()=>{});
  const {data:{subscription}}=client.auth.onAuthStateChange((_event,session)=>{void update(session);});
  return()=>{alive=false;subscription.unsubscribe()};
 },[kind,id]);
 useEffect(()=>{
  const ctrl=new AbortController();
  setState({loading:true,data:null,error:""});
  fetch("/api/world/staff-profile?kind="+encodeURIComponent(kind)+"&id="+encodeURIComponent(id),{
   cache:"no-store",signal:ctrl.signal
  }).then(async res=>{
   const result=await res.json();
   if(!res.ok)throw Error(result.error||"상세정보를 불러오지 못했습니다.");
   if(!ctrl.signal.aborted)setState({loading:false,data:result,error:""});
  }).catch(error=>{
   if(!ctrl.signal.aborted)setState({loading:false,data:null,error:error.message});
  });
  return()=>ctrl.abort();
 },[kind,id]);
 const v=state.data,who=isJockey?"기수":"조교사";
 return <main className="shell directory-shell">
  <header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a>
   <span className="coin">{isJockey?"🏇":"🏠"} {who} 상세정보</span></header>
  <div className="area">
   <div className="controls" style={{marginBottom:16}}>
    <a className="outline" href={isJockey?"/jockeys":"/participants?view=trainers"} style={{textDecoration:"none"}}>‹ {who} 목록</a>
    <a className="outline" href="/participants?view=records" style={{textDecoration:"none"}}>전체 성적 ›</a>
   </div>
   {state.loading&&<div className="notice">공식 경주 기록과 {who} 정보를 조회하고 있습니다.</div>}
   {state.error&&<div className="notice" role="alert">{state.error}</div>}
   {!state.loading&&v&&<>
    <section className="card staff-hero">
     <div className="staff-hero-head"><div>
      <div className="muted">{who} PROFILE · MY DERBY</div>
      <h1>{v.name}</h1>
      <div className="muted">{v.track||"소속 미정"} · {v.active?"활동 중":"비활동"}</div>
     </div><span className="tag">{isJockey?"기수":"조교사"}</span></div>
     <div className="staff-quick">
      <div><small>소속</small><b>{v.track||"—"}</b></div>
      <div><small>{isJockey?"하루 최대 기승":"담당 마방"}</small><b>{isJockey?fmt(v.capacity)+"회":v.stable||"—"}</b></div>
      <div><small>{isJockey?"통산 우승":"담당 정원"}</small>
       <b>{isJockey?fmt(v.career?.wins)+"승":fmt(v.occupied)+"/"+fmt(v.capacity)+"두"}</b></div>
     </div>
     <div className="muted" style={{marginTop:10}}>게임 공식 경주 기록 기준 · 원본 마사회 전적과 합산하지 않습니다.</div>
    </section>
    {ownerBond&&<><div className="section"><h2>🤝 나와의 친밀도·신뢰도</h2></div>
     <section className="card staff-bond">
      <div className="staff-bond-metrics">
       <div><small>친밀도</small><strong>{ownerBond.familiarity}/100</strong></div>
       <div><small>신뢰도</small><strong>{ownerBond.trust}/100</strong></div>
       <div><small>관계 단계</small><strong>{ownerBond.relationshipLevel}</strong></div>
      </div>
      <div className="muted" style={{marginTop:12,lineHeight:1.7}}>
       함께한 경주와 훈련으로 관계가 깊어집니다. 협업 기록 {ownerBond.interactions||0}건.
       친밀도·신뢰도는 계약 평가에서 최대 10점만 반영되며,
       더 뛰어난 경주마가 경쟁하면 관계 점수가 높아도 선택되지 않을 수 있습니다.
      </div>
     </section>
     <div className="section"><h2>🔒 히든 특성 발견</h2><span className="tag">마주별 관찰 정보</span></div>
     <section className="card staff-hidden-panel">
      {ownerBond.discoveredTraits?.length ? <>
        <div className="staff-hidden-list">{ownerBond.discoveredTraits.map(trait=><div className="staff-hidden-trait" key={trait.code}>
          <span className="staff-hidden-badge">✨ 발견</span>
          <b>{trait.name}</b>
          <p>{trait.description}</p>
          <small>게임 {trait.gameDay}일 · 협업 경험으로 발견</small>
        </div>)}</div>
       </> : <div className="staff-hidden-locked">
        <strong>🔒 아직 밝혀진 특성이 없습니다</strong>
        <p>{ownerBond.hiddenDiscovery?.status||"기승·훈련 활동을 관찰해 주세요."}</p>
       </div>}
       <div className="muted" style={{marginTop:12,lineHeight:1.8}}>
         {isJockey?"공식 경주에서 전개·거리·상황을 경험":"담당마 훈련에서 연령·거리·강도별 성과를 관찰"}하고
         친밀도와 신뢰를 쌓으면 새로운 특징을 알아낼 수 있습니다.
         히든 특성은 미발견 상태에서도 실제 경주·훈련 계산에 적용됩니다.
         모든 인물이 반드시 특성을 보유한 것은 아닙니다.
       </div>
     </section></>}
    <div className="section"><h2>📈 개인별 능력 성장·변화</h2></div>
    <section className="card staff-development">
     {v.development?<><div className="staff-growth-facts">
       <div><small>나이</small><strong>{v.development.age}세</strong></div>
       <div><small>전성기 기준</small><strong>{v.development.peakAge}세</strong></div>
       <div><small>현재 단계</small><strong>{v.development.careerStage}</strong></div>
       <div><small>성장 성향</small><strong>{v.development.developmentStyle}</strong></div>
       <div><small>남은 성장 여력</small><strong>{v.development.growthPotential}</strong></div>
       <div><small>누적 경험치</small><strong>{fmt(v.development.experience)}</strong></div>
      </div>
      <div className="muted" style={{marginTop:12,lineHeight:1.8}}>
       현실 하루(게임 7일) 단위로 실제 {isJockey?"기승":"훈련·담당마 경주"} 경험을 정산합니다.
       한 번에 하나의 능력만 성장·하락하며, 최대 상승 +0.035점 / 최대 하락 -0.020점입니다.
       실제 성장 한계는 개인마다 다르며 급격한 능력 변화를 방지합니다.
      </div>
      <div className="section"><h3>최근 능력 변동 내역</h3></div>
      {!v.development.recentChanges?.length?<div className="muted">
       아직 정산된 성장 기록이 없습니다. 첫 정산 후 경험과 능력 변화가 표시됩니다.</div>:
       <div className="staff-growth-history">
        {v.development.recentChanges.map(row=><div key={row.week_end_game_day} className="staff-growth-line">
         <div><b>게임 {row.week_start_game_day}~{row.week_end_game_day}일</b>
           <small>{changeReasons[row.reason]||row.reason} · {isJockey?row.rides+"회 기승":row.trainings+"회 훈련"} · {row.wins}승</small></div>
         <div className="staff-growth-change">
          <strong style={{color:Number(row.skill_delta)>0?"#a9e2b0":Number(row.skill_delta)<0?"#f0aa93":"#c6b29c"}}>
           {Number(row.skill_delta)>0?"+":""}{Number(row.skill_delta).toFixed(3)}
          </strong>
          <small>{skillNames[row.trained_skill]||row.trained_skill||"능력 유지"}</small>
         </div>
        </div>)}
       </div>}
     </>:<div className="muted">개인별 성장 프로필이 아직 준비되지 않았습니다.</div>}
    </section>
    <div className="section"><h2>🏆 통산·최근 1년 경주 성적</h2></div>
    <div className="staff-record-grid"><RecordCard title="게임 통산 공식 전적" record={v.career}/>
     <RecordCard title="게임 최근 364일" record={v.recentYear}/></div>
    <div className="section"><h2>⭐ 능력치 · 전문분야</h2></div>
    <section className="card">
     <div className="staff-skills">{Object.entries(v.skills||{}).map(([key,value])=><div key={key}>
      <span>{skillNames[key]||key}</span><b>{value}</b></div>)}</div>
     <div className="muted" style={{marginTop:12}}>전문 분야: {(v.specialties||[]).filter(x=>!String(x).includes("SOURCE_RECORD_ESTIMATE")).join(" · ")||"등록된 특기 없음"}</div>
     {(v.specialties||[]).some(x=>String(x).includes("ESTIMATE"))&&
      <div className="muted" style={{marginTop:8,fontSize:11}}>※ 일부 능력치는 게임용 추정치입니다.</div>}
    </section>
    {!isJockey&&<><div className="section"><h2>🐎 현재 담당 경주마</h2><span className="tag">{fmt(v.occupied)}두</span></div>
     <section className="card">
      {!v.horses?.length?<div className="muted">현재 담당하고 있는 경주마가 없습니다.</div>:
       <div className="staff-horse-grid">{v.horses.map(h=><div key={h.horse_id}>
        <HorseLink horseId={h.horse_id}>{h.horse_name}</HorseLink>
        <span className="muted">{h.grade?fmt(h.grade)+"등급":"등급 미정"} · 레이팅 {h.rating??"—"}</span>
       </div>)}</div>}
     </section>
    </>}
    <div className="section"><h2>📋 최근 공식 경주 내역</h2></div>
    {!v.races?.length?<div className="notice">아직 확정된 게임 공식 경주 기록이 없습니다.</div>:
     <div className="race-entry-wrap" role="region" aria-label={who+" 최근 공식 경주 내역"} tabIndex={0}>
      <table className="race-entry-table">
       <thead><tr><th>경주일</th><th>경주</th><th>경주마</th><th>착순</th><th>상금</th></tr></thead>
       <tbody>{v.races.map((r,index)=><tr key={r.race_id+"-"+r.horse_id+"-"+index}>
        <td>{r.race_date||"—"}</td>
        <td><a className="staff-inline-link" href={"/race/"+r.race_id}>{r.track} {r.race_no}경주<br/>
         <small>{r.class_name} · {fmt(r.distance_m)}m</small></a></td>
        <td><HorseLink horseId={r.horse_id}>{r.horse_name}</HorseLink></td>
        <td className={r.finishing_rank===1?"gold":""}>{r.finishing_rank}위</td>
        <td>{fmt(r.prize)} G</td>
       </tr>)}</tbody>
      </table>
     </div>}
    <div className="footer">MY DERBY · {who} 기록실 · 공식 종료 경주만 집계</div>
   </>}
  </div>
 </main>;
}
