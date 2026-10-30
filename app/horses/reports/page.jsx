"use client";
import {useCallback,useEffect,useState} from "react";
import {useSearchParams} from "next/navigation";
import {Suspense} from "react";
import {createClient} from "@supabase/supabase-js";
import HorseDiscovery from "../../components/HorseDiscovery";
import HorseLink from "../../components/HorseLink";
import StaffLink from "../../components/StaffLink";

const SID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const stamp=x=>x?new Date(x).toLocaleString("ko-KR",{timeZone:"Asia/Seoul",
 year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit"}):"—";
const evidenceTypes={TRAINING:"🏇 조교 훈련",RANCH:"🌿 목장 관찰",RACE:"🏆 공식 경주"};
const focusLabels={speed:"스피드",start:"출발",acceleration:"가속력",stamina:"지구력",
 finishing:"막판 탄력",power:"파워",grit:"근성",stability:"안정성",recovery:"회복력"};

function ReportPage(){
 const query=useSearchParams();
 const horseId=query.get("horseId");
 const [auth,SetAuth]=useState({loading:true,token:""});
 const [list,SetList]=useState({loading:false,reports:[],horseName:"",error:""});
 const [selected,SetSelected]=useState("");
 const [busy,SetBusy]=useState(false);
 const [message,SetMessage]=useState("");
 useEffect(()=>{
  let active=true;
  const client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  client.auth.getSession().then(({data})=>{
   if(active)SetAuth({loading:false,token:data?.session?.access_token||""});
  }).catch(()=>{if(active)SetAuth({loading:false,token:""})});
  const {data:{subscription}}=client.auth.onAuthStateChange((_event,session)=>{
   if(active)SetAuth({loading:false,token:session?.access_token||""});
  });
  return()=>{active=false;subscription.unsubscribe()};
 },[]);
 const load=useCallback(async(token,signal)=>{
  if(!SID.test(horseId||"")||!token)return;
  SetList(s=>({...s,loading:true,error:""}));
  try{
   const response=await fetch("/api/player/horse-reports?horseId="+encodeURIComponent(horseId),{
    headers:{Authorization:"Bearer "+token},cache:"no-store",signal
   });
   const data=await response.json();
   if(!response.ok)throw Error(data.error||"리포트를 불러오지 못했습니다.");
   if(signal?.aborted)return;
   SetList({loading:false,reports:data.reports||[],horseName:data.horseName||"",error:""});
   SetSelected(old=>data.reports?.some(r=>r.id===old)?old:data.reports?.[0]?.id||"");
  }catch(e){
   if(signal?.aborted)return;
   SetList(s=>({...s,loading:false,error:e.message||"리포트를 불러오지 못했습니다."}));
  }
 },[horseId]);
 useEffect(()=>{
  if(!auth.token||!SID.test(horseId||""))return;
  const controller=new AbortController();
  void load(auth.token,controller.signal);
  return()=>controller.abort();
 },[auth.token,horseId,load]);
 const issue=async()=>{
  if(!auth.token||!SID.test(horseId||"")||busy)return;
  SetBusy(true);SetMessage("");
  try{
   const response=await fetch("/api/player/horse-reports",{
    method:"POST",headers:{Authorization:"Bearer "+auth.token,"Content-Type":"application/json"},
    body:JSON.stringify({horseId}),cache:"no-store"
   });
   const data=await response.json();
   if(!response.ok)throw Error(data.error||"리포트를 발급하지 못했습니다.");
   await load(auth.token);
   SetSelected(data.reportId);
   SetMessage(data.status==="ALREADY_ISSUED"
    ?"현재 게임일·관찰 상태로 이미 발급된 리포트를 열었습니다. 새 관찰 결과가 추가되면 다시 발급할 수 있습니다."
    :"새 능력·기질 분석 리포트를 발급했습니다. 이전 리포트도 보관됩니다.");
  }catch(e){SetMessage("⚠ "+(e.message||"발급에 실패했습니다."))}
  finally{SetBusy(false)}
 };
 const report=list.reports.find(x=>x.id===selected)||list.reports[0];
 const data=report?.data||{},horse=data.horse||{};
 return <main className="shell horse-report-shell">
  <header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a>
   <span className="coin">📋 경주마 분석 리포트</span></header>
  <div className="area">
   <div className="controls no-print" style={{marginBottom:16}}>
    <a href="/world" className="outline" style={{textDecoration:"none"}}>‹ 내 경주마</a>
    <a href="/training" className="outline" style={{textDecoration:"none"}}>훈련 관리 ›</a>
   </div>
   <div className="horse-report-masthead">
    <div className="horse-report-series">MY DERBY · OWNER'S OBSERVATION REPORT</div>
    <h1>경주마 능력·기질 분석 리포트</h1>
    <p>조교사와 개인목장, 공식 경주 관찰을 종합한 마주 전용 분석 기록</p>
   </div>
   {!SID.test(horseId||"")&&<div className="notice">내 경주마 상세정보 또는 훈련 관리에서 리포트를 발급할 경주마를 선택해 주세요.</div>}
   {auth.loading&&<div className="notice">로그인 정보를 확인하고 있습니다.</div>}
   {!auth.loading&&!auth.token&&<div className="notice">본인 소유 경주마의 리포트는 게임 로그인 후 이용할 수 있습니다.</div>}
   {auth.token&&SID.test(horseId||"")&&<>
    <div className="horse-report-tools no-print">
     <div><b className="gold">{list.horseName||"내 경주마"}</b>
      <div className="muted">리포트 {list.reports.length}건 · 발급 당시의 추정 평가를 보관합니다.</div></div>
     <button className="primary" disabled={busy||list.loading} onClick={issue}>
      {busy?"발급 중…":"📑 새 분석 리포트 발급"}</button>
    </div>
    {message&&<div role="status" className="notice no-print">{message}</div>}
    {list.error&&<div role="alert" className="notice">{list.error}</div>}
    {list.loading&&<div className="notice">발급된 리포트를 조회하고 있습니다.</div>}
    {!list.loading&&!report&&!list.error&&<div className="news-empty">
     발급된 리포트가 없습니다. <b>새 분석 리포트 발급</b>을 누르면 현재까지의 관찰 결과를 기록합니다.
     아직 관찰 기록이 없다면 능력치는 ‘미확인’ 상태로 발급됩니다.</div>}
    {!!list.reports.length&&<div className="horse-report-history no-print">
      <label htmlFor="reportHistory">과거 분석 리포트 보기</label>
      <select className="field" id="reportHistory" value={report?.id||""}
        onChange={e=>SetSelected(e.target.value)}>
       {list.reports.map(x=><option key={x.id} value={x.id}>
        게임 {x.gameDay}일 · 관찰 {x.observationCount}회 · {stamp(x.issuedAt)}
       </option>)}
      </select>
      <span className="muted">최대 최근 30건을 조회하며 발급된 기록은 이후에도 수정되지 않습니다.</span>
    </div>}
    {report&&<article className="horse-report-paper" aria-label="발급된 경주마 분석 리포트">
     <div className="horse-report-paper-head">
      <div><span className="horse-report-label">CONFIDENTIAL · OWNER ASSESSMENT</span>
       <h2>{horse.name||list.horseName} 분석 보고서</h2>
       <div className="muted">게임 {report.gameDay}일 · 발급 {stamp(report.issuedAt)}</div></div>
      <div className="horse-report-seal">MY<br/>DERBY</div>
     </div>
     <div className="horse-report-meta">
      <span>말 이름 <b><HorseLink horseId={horse.id}>{horse.name}</HorseLink></b></span>
      <span>등급 <b>{horse.grade?horse.grade+"등급":"미정"}</b></span>
      <span>레이팅 <b>{horse.rating??"—"}</b></span>
      <span>작성 조교사 <b>{data.trainer?
       <StaffLink kind="trainer" staffId={data.trainer.id}>{data.trainer.name}</StaffLink>:"미계약 · 자동 관찰"}</b></span>
     </div>
     <div className="horse-report-overview">
      <div><span>평가 단계</span><strong>{data.evaluation?.level||"미확인"}</strong></div>
      <div><span>평균 평가 신뢰도</span><strong>{data.evaluation?.averageConfidence??0}%</strong></div>
      <div><span>누적 관찰 건수</span><strong>{report.observationCount}건</strong></div>
     </div>
     <div className="section"><h3>종합 소견</h3></div>
     <p className="horse-report-summary">{data.evaluation?.summary||"관찰 근거가 부족합니다."}</p>
     <div className="section"><h3>능력·성장·기질 평가</h3></div>
     <HorseDiscovery discovery={data.assessment} compact/>
     <div className="section"><h3>분석 근거 · 최근 관찰</h3></div>
     {data.evidence?.length?<div className="horse-report-evidence">
       {data.evidence.map(e=><div key={e.id}>
        <b>{evidenceTypes[e.source_type]||e.source_type}</b>
        <span>게임 {e.game_day}일 · {(e.observed_focus||[]).map(k=>focusLabels[k]||k).join(" · ")||"종합 관찰"}</span>
        {e.context?.distance&&<small>{e.context.distance}m · {e.context.rank?e.context.rank+"위":"경주 관찰"}</small>}
        {e.context?.course&&<small>목장 코스: {e.context.course} · 시설 Lv.{e.context.facilityLevel||1}</small>}
       </div>)}
      </div>:<p className="muted">아직 축적된 훈련·목장·경주 관찰 근거가 없습니다.</p>}
     <div className="horse-report-disclaimer">이 문서는 게임 내 발견한 정보만 포함합니다. 실제 능력 수치, 정확한 최대 성장 능력치,
       미발견 히든 특성 및 유전자 수치는 제공하지 않습니다. 결과는 관찰과 조교사 판단에 따른 추정치입니다.</div>
    </article>}
    {report&&<div className="controls no-print" style={{marginTop:15}}>
      <button className="outline" onClick={()=>window.print()}>🖨 리포트 인쇄 · PDF 저장</button>
      <a className="outline" href={"/horses/profile?horseId="+horseId} style={{textDecoration:"none"}}>경주마 상세정보 ›</a>
    </div>}
   </>}
  </div>
 </main>;
}
export default function HorseReportPage(){
 return <Suspense fallback={<div className="notice">리포트를 준비하고 있습니다.</div>}>
  <ReportPage/>
 </Suspense>;
}
