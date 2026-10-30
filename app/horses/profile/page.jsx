"use client";
import {useEffect,useState} from "react";
import {useSearchParams} from "next/navigation";
import {Suspense} from "react";
import StaffLink from "../../components/StaffLink";
import HorseDiscovery from "../../components/HorseDiscovery";
import {createClient} from "@supabase/supabase-js";

const fmt=x=>x==null?"-":Number(x).toLocaleString("ko-KR");
const sex={MALE:"수말",FEMALE:"암말",GELDING:"거세마"};
const skills={start:"출발",speed:"속도",acceleration:"가속력",stamina:"지구력",
 finishing:"막판 탄력",power:"파워",grit:"근성",stability:"안정성",recovery:"회복력"};
const stages={RACING:"현역",RETIRED:"은퇴",STALLION:"씨수말",BROODMARE:"번식암말",
 FOAL:"망아지",YEARLING:"1세마",DECEASED:"폐사"};
function Record({title,stats,subtitle}){
 return <div className="card horse-profile-record">
  <div className="muted">{title}</div>
  {stats?<><div className="horse-profile-record-top">{fmt(stats.starts)}전 <b>{fmt(stats.wins)}승</b></div>
   <div className="muted">2착 {fmt(stats.second)}회 · 3착 {fmt(stats.third)}회</div></>
   :<div className="muted" style={{marginTop:12}}>제공된 전적이 없습니다.</div>}
  {subtitle&&<div className="muted" style={{marginTop:8,fontSize:11}}>{subtitle}</div>}
 </div>;
}
function Detail(){
 const q=useSearchParams();
 const [data,D]=useState(null),[loading,L]=useState(true),[error,E]=useState("");
 const horseId=q.get("horseId"),meet=q.get("meet"),hrNo=q.get("hrNo");
 useEffect(()=>{
  const controller=new AbortController();
  const params=new URLSearchParams();
  if(horseId)params.set("horseId",horseId);
  else{if(meet)params.set("meet",meet);if(hrNo)params.set("hrNo",hrNo)}
  async function load(){
   L(true);
   try{
    let headers={};
    try{
     const client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
     const {data:sessionData}=await client.auth.getSession();
     if(sessionData?.session?.access_token)headers={Authorization:"Bearer "+sessionData.session.access_token};
    }catch{}
    const r=await fetch("/api/world/horse-profile?"+params.toString(),
     {headers,cache:"no-store",signal:controller.signal});
    const x=await r.json();
    if(!r.ok)throw new Error(x.error||"경주마 정보를 불러올 수 없습니다.");
    if(!controller.signal.aborted){D(x);E("")}
   }catch(e){if(!controller.signal.aborted){E(e.message);D(null)}}
   finally{if(!controller.signal.aborted)L(false)}
  }
  void load();return()=>controller.abort();
 },[horseId,meet,hrNo]);
 const source=data?.source;
 const discovery=data?.discovery;
 return <main className="shell directory-shell">
  <header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a>
   <span className="coin">🐎 경주마 정보</span></header>
  <div className="area">
   <div className="controls"><a className="outline" href="/horses" style={{textDecoration:"none"}}>‹ 경주마 목록</a>
    <a className="outline" href="/world" style={{textDecoration:"none"}}>마이더비 월드 ›</a></div>
   {loading&&<div className="notice">경주마 기본정보를 조회하고 있습니다…</div>}
   {error&&<div className="notice" role="alert">{error}</div>}
   {!loading&&data&&<>
    <div className="card">
     <div className="dir-horse-name" style={{fontSize:24}}>{data.name}
      <span className="dir-region">{data.track}</span></div>
     <div className="muted">{data.sourceRank||((data.grade||"-")+"등급")}
      {data.stage?" · "+(stages[data.stage]||data.stage):" · CSV 기본정보 등록마"}</div>
     <div className="horse-profile-attributes">
      <div><span>나이</span><strong>{data.age!=null?data.age+"세":"게임 나이 미등록"}</strong></div>
      <div><span>성별</span><strong>{sex[data.sex]||data.sourceSex||"-"}</strong></div>
      <div><span>생년월일</span><strong>{data.birthDate||"-"}</strong></div>
      <div><span>게임 등급</span><strong>{data.grade?data.grade+"등급":"미등록"}</strong></div>
      <div><span>게임 레이팅</span><strong>{data.rating!=null?data.rating+"점":"미부여"}</strong></div>
      <div><span>원본 레이팅</span><strong>{data.sourceRating!=null?data.sourceRating+"점":"자료 없음"}</strong></div>
      <div><span>건강</span><strong>{data.health||"게임 상태 미등록"}</strong></div>
      <div><span>컨디션 / 피로도</span><strong>{data.condition!=null?fmt(data.condition)+" / "+fmt(data.fatigue):"미등록"}</strong></div>
     </div>
    </div>
    <div className="section"><h2>통산 전적 · 최근 1년 전적</h2></div>
    {source?<><div className="muted" style={{marginBottom:8}}>
     업로드한 CSV의 실제 원본 전적입니다. ‘최근 1년’은 <b>제공된 파일의 1년 집계</b>로,
     게임 내 364일 기록과 합산하지 않습니다.</div>
     <div className="dir-records"><Record title="원본 통산 전적" stats={source.career}/>
      <Record title="원본 최근 1년 전적" stats={source.recentYear}/></div></>:
     <div className="notice">이 경주마는 업로드한 CSV에 없어 과거 통산·최근 1년 전적을 표시할 수 없습니다.</div>}
    {data.gameHorseId&&<>
     <div className="section"><h2>My Derby 게임 전적</h2></div>
     <div className="dir-records">
      <Record title="게임 통산" stats={data.game?.career}/>
      <Record title="게임 최근 364일" stats={data.game?.recentYear}/></div>
     <div className="section"><h2>🔍 능력·잠재력 발견 보고서</h2></div>
     <HorseDiscovery discovery={discovery} horseId={horseId||data?.id}/> 
    </>}
    {data.gameTrainer&&<div className="card"><div className="muted">현재 게임 담당 조교사</div><strong><StaffLink kind="trainer" staffId={data.gameTrainer.id}>{data.gameTrainer.name}</StaffLink></strong></div>}
    {source&&<><div className="section"><h2>혈통 · 관계자</h2></div>
     <div className="card horse-profile-attributes">
      <div><span>부마</span><strong>{source.fatherName||"-"}</strong></div>
      <div><span>모마</span><strong>{source.motherName||"-"}</strong></div>
      <div><span>출생 국가</span><strong>{source.country||"-"}</strong></div>
      <div><span>마주(원본)</span><strong>{source.ownerName||"-"}</strong></div>
      <div><span>조교사(원본)</span><strong>{source.trainerName||"-"}</strong></div>
      <div><span>원본 경마장</span><strong>{source.meet}</strong></div>
     </div></>}
    {!data.gameHorseId&&<div className="notice">
      이 말은 제공된 CSV에는 등록되어 있지만 My Derby 게임 경주마 명단에는 없습니다.
      임의의 능력치·마주·게임 전적을 생성하지 않았습니다.
     </div>}
    <div className="footer">MY DERBY · 실제 CSV 원본 전적과 게임 전적을 구분해 표시</div>
   </>}
  </div>
 </main>;
}
export default function HorseProfilePage(){return <Suspense fallback={<div>경주마 정보 조회 중…</div>}><Detail/></Suspense>}
