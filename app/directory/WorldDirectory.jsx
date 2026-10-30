"use client";
import {useEffect,useState} from "react";
import HorseLink from "../components/HorseLink";

const sexText={MALE:"수",FEMALE:"암",GELDING:"거"};
const stageText={RACING:"현역",RETIRED:"은퇴",FOAL:"망아지",YEARLING:"1세마",
 STALLION:"씨수말",BROODMARE:"번식암말",DECEASED:"폐사",SOURCE_ONLY:"CSV 원본 등록"};
const skillText={start:"출발",pace:"페이스",urging:"추진",control:"제어",
 judgment:"판단",stability:"안정",aggression:"적극성",positioning:"위치 선정"};
const fmt=n=>Number(n||0).toLocaleString("ko-KR");
const statText=s=>(s?.starts||0)+"전 "+(s?.wins||0)+"승 · "+
 (s?.second||0)+"회 2착 · "+(s?.third||0)+"회 3착";

function RecordCard({title,record}){
 return <div className="dir-record"><div className="dir-record-title">{title}</div>
  <div className="dir-record-main"><strong>{fmt(record?.starts)}전</strong>
   <span>{fmt(record?.wins)}승</span></div>
  <div className="dir-record-sub">2착 {fmt(record?.second)}회 · 3착 {fmt(record?.third)}회</div>
 </div>;
}

function HorseCard({horse,recordMode}){
 const [expanded,show]=useState(false);
 const grade=horse.grade==null?(horse.sourceRank||"등급 미정"):horse.grade+"등급";
 return <article className="card dir-entry">
  <div className="dir-entry-head">
   <div><div className="dir-horse-name"><HorseLink
     horseId={horse.gameHorseId||(/^[0-9a-f]{8}-/i.test(horse.id)?horse.id:null)}
     sourceMeet={horse.sourceMeet} hrNo={horse.horseNo}>{horse.name}</HorseLink>
     <span className="dir-region">{horse.track||"소속 미정"}</span></div>
    <div className="muted">#{horse.horseNo||horse.id.slice(0,8)} · {grade} · {horse.age==null?"나이 미등록":horse.age+"세"} · {sexText[horse.sex]||horse.sex||"-"} · {stageText[horse.stage]||horse.stage}</div></div>
   <div className="dir-rating">{horse.rating==null?"미부여":horse.rating+"점"}<small>레이팅</small></div>
  </div>
  <div className="dir-records"><RecordCard title={recordMode==="world"?"게임 통산 전적":"원본 통산 전적"} record={horse.career}/>
    <RecordCard title={recordMode==="world"?"게임 최근 364일":"원본 최근 1년"} record={horse.recentYear}/></div>
  {horse.ratingPending&&<div className="dir-alert">레이팅 기준 {horse.ratingProposedGrade}등급 전환 대기 · 기존 확정 출전표 유지</div>}
  <div className="dir-footer">
   <span className="muted">{recordMode==="world"?"게임 경주 기준":horse.gameLinked?"게임 경주마 연결 완료":"CSV 원본 등록 · 게임 미연결"}</span>
   <HorseLink horseId={horse.gameHorseId||(/^[0-9a-f]{8}-/i.test(horse.id)?horse.id:null)} sourceMeet={horse.sourceMeet} hrNo={horse.horseNo}>상세정보 ›</HorseLink>
   <button className="dir-expand" type="button" onClick={()=>show(v=>!v)}>
    {expanded?"간략히":"기록 기준 보기"} {expanded?"⌃":"⌄"}</button>
  </div>
  {expanded&&<div className="dir-explain">CSV 등록모드는 업로드된 원본의 통산·최근 1년 입상 집계를 표시합니다.
    게임 전체모드는 My Derby에서 실제 종료된 공식 경주만 집계하며 최근 1년은 게임 내 364일입니다.
    두 전적은 합산하지 않습니다.
    6등급은 레이팅이 부여되지 않을 수 있습니다.</div>}
 </article>;
}
function JockeyCard({jockey}){
 const [expanded,show]=useState(false);
 const skills=Object.entries(jockey.skills||{});
 const specialty=(jockey.specialties||[]).filter(s=>s!=="2025_SOURCE_RECORD_ESTIMATE");
 const estimated=(jockey.specialties||[]).includes("2025_SOURCE_RECORD_ESTIMATE");
 return <article className="card dir-entry">
  <div className="dir-entry-head"><div>
   <div className="dir-horse-name">{jockey.name}
    <span className="dir-region">{jockey.track}</span></div>
   <div className="muted">{jockey.active?"활동 중":"비활동"} · 게임 하루 최대 {jockey.maxDailyRides}회 기승</div>
  </div><span className="tag">{jockey.career?.wins||0}승</span></div>
  <div className="dir-records"><RecordCard title="통산 게임 기승" record={jockey.career}/>
   <RecordCard title="최근 1년 기승" record={jockey.recentYear}/></div>
  <div className="dir-footer">
   <div className="muted">{specialty.length?specialty.join(" · "):"능력치 8종 보유"}</div>
   <button className="dir-expand" type="button" onClick={()=>show(v=>!v)}>
    {expanded?"능력치 닫기":"능력치 보기"} {expanded?"⌃":"⌄"}</button>
  </div>
  {expanded&&<div className="dir-skill-grid">
   {skills.map(([key,val])=><div className="dir-skill" key={key}>
    <span>{skillText[key]||key}</span><strong>{val}</strong></div>)}
   {estimated&&<div className="muted dir-skill-note">※ 능력치는 2025년 자료 기반 게임용 추정치입니다.</div>}
  </div>}
 </article>;
}

export default function WorldDirectory({kind}){
 const horses=kind==="horses";
 const [mode,Mode]=useState("uploaded"),
 [search,S]=useState(""),[track,T]=useState(""),[grade,G]=useState(""),
 [sex,X]=useState(""),[stage,F]=useState(""),
 [sort,O]=useState("name"),[page,P]=useState(1),[jump,J]=useState("1"),
 [data,D]=useState(null),[loading,L]=useState(true),[error,E]=useState(""),[retry,Retry]=useState(0);
 const update=(fn,v)=>{fn(v);P(1);J("1")};
 useEffect(()=>{
  const controller=new AbortController();
  const timer=setTimeout(async()=>{
   L(true);
   const q=new URLSearchParams({page:String(page),size:"24",sort,q:search.trim()});
   if(horses)q.set("mode",mode);
   if(track)q.set("track",track);
   if(horses&&grade)q.set("grade",grade);
   if(horses&&sex)q.set("sex",sex);
   if(horses&&stage&&mode==="world")q.set("stage",stage);
   try{
    const r=await fetch((horses?"/api/world/horses":"/api/world/jockeys")+"?"+q.toString(),{
     signal:controller.signal,cache:"no-store"});
    const body=await r.json();
    if(!r.ok)throw new Error(body.error||"목록을 불러오지 못했습니다.");
    if(!controller.signal.aborted){D(body);E("");}
   }catch(e){
    if(!controller.signal.aborted){E(e.message||"조회 오류");D(null);}
   }finally{if(!controller.signal.aborted)L(false);}
  },240);
  return()=>{clearTimeout(timer);controller.abort()};
 },[horses,mode,search,track,grade,sex,stage,page,sort,retry]);
 const last=Math.max(1,data?.pages||1);
 const goPage=v=>{const next=Math.min(last,Math.max(1,Number(v)||1));P(next);J(String(next));};
 const tracks=horses?["서울","부산","영천","제주"]:["서울","부산","영천"];
 return <main className="shell directory-shell">
  <header className="header"><a href="/" className="brand" style={{textDecoration:"none"}}>MY DERBY</a>
   <span className="coin">{horses?"🐎 전체 경주마":"🏇 전체 기수"}</span></header>
  <div className="area">
   <nav className="dir-main-nav" aria-label="도감 목록">
    <a href="/world">월드</a>
    <a className={horses?"selected":""} href="/horses">전체 경주마</a>
    <a className={!horses?"selected":""} href="/jockeys">전체 기수</a>
   </nav>
   <div className="section"><h2>{horses?"경주마 전체 목록":"기수 전체 목록"}</h2>
    <span className="tag">{data?fmt(data.total)+(horses?"두":"명"):"조회 중"}</span></div>
   {horses&&<div className="dir-main-nav" style={{marginBottom:12}}>
    <button type="button" className={mode==="uploaded"?"selected":""}
      onClick={()=>{Mode("uploaded");P(1);J("1");O("name")}}>
     CSV 등록마 4,060두
    </button>
    <button type="button" className={mode==="world"?"selected":""}
      onClick={()=>{Mode("world");P(1);J("1");O("name")}}>
     게임 전체 경주마
    </button>
   </div>}
   <p className="muted">{horses?(mode==="uploaded"?
    "업로드한 CSV의 통산·최근 1년 전적을 표시합니다. 기존 게임 전적과 합산하지 않습니다. 이름을 누르면 경주마 기본정보가 열립니다.":
    "My Derby의 게임 공식 경주 결과를 표시합니다. 최근 1년은 게임 364일 기준입니다."):
    "기수 통산·최근 1년은 게임 공식 경주 결과 기준이며, 최근 1년은 게임 364일입니다."}</p>
   <div className="card dir-filter">
    <label htmlFor="directory-search" className="muted">이름{horses?" 또는 마번":""} 검색</label>
    <input id="directory-search" className="field" value={search}
     maxLength={50} placeholder={horses?"경주마 이름 또는 마번":"기수 이름"}
     onChange={e=>update(S,e.target.value)}/>
    <div className="dir-selects">
     <label>소속 지역
      <select className="field" value={track} onChange={e=>update(T,e.target.value)}>
       <option value="">전체 지역</option>
       {tracks.map(v=><option key={v} value={v}>{v}</option>)}
      </select></label>
     {horses&&<label>등급
      <select className="field" value={grade} onChange={e=>update(G,e.target.value)}>
       <option value="">전체 등급</option>
       {[1,2,3,4,5,6].map(v=><option value={v} key={v}>{v}등급</option>)}
      </select></label>}
     {horses&&<label>성별
      <select className="field" value={sex} onChange={e=>update(X,e.target.value)}>
       <option value="">전체 성별</option>
       <option value="MALE">수말</option><option value="FEMALE">암말</option>
       <option value="GELDING">거세마</option>
      </select></label>}
     {horses&&mode==="world"&&<label>활동 상태
      <select className="field" value={stage} onChange={e=>update(F,e.target.value)}>
       <option value="">모든 경주마</option>
       {Object.entries(stageText).map(([key,v])=><option key={key} value={key}>{v}</option>)}
      </select></label>}
     <label>정렬
      <select className="field" value={sort} onChange={e=>update(O,e.target.value)}>
       <option value="name">이름순</option>
       {horses?<><option value="rating">레이팅 높은 순</option>
         <option value="grade">등급순</option><option value="age">나이 많은 순</option>{mode==="uploaded"&&<><option value="wins">원본 통산 승수순</option><option value="starts">원본 통산 출전순</option></>}</>:
         <><option value="wins">게임 승수순</option><option value="rides">게임 기승 횟수순</option></>}
      </select></label>
    </div>
    <div className="dir-filter-bottom"><span>한 페이지 24{horses?"두":"명"}</span>
     <button className="outline" type="button" onClick={()=>{
       S("");T("");G("");X("");F("");O("name");P(1);J("1");
     }}>필터 초기화</button></div>
   </div>
   <div className="section"><h2>{horses?"경주마 명단":"기수 명단"}</h2>
    <span className="muted">{data?fmt(data.total)+"건 · "+data.page+"/"+last+"페이지":""}</span></div>
   {error&&<div className="notice" role="alert">{error}
     <button className="outline" onClick={()=>Retry(v=>v+1)}>재시도</button></div>}
   {loading&&<div className="notice" aria-live="polite">실제 경주 기록을 조회하고 있습니다…</div>}
   {!loading&&data?.items?.length===0&&<div className="notice">조건에 맞는 {horses?"경주마":"기수"}가 없습니다. 필터를 변경해주세요.</div>}
   {!loading&&(data?.items||[]).map(item=>horses?
    <HorseCard key={item.id} horse={item} recordMode={mode}/>:
    <JockeyCard key={item.id} jockey={item}/>)}
   {data&&data.total>24&&<nav className="dir-pagination" aria-label="페이지 선택">
    <button type="button" className="outline" disabled={page<=1||loading} onClick={()=>goPage(1)}>처음</button>
    <button type="button" className="outline" disabled={page<=1||loading} onClick={()=>goPage(page-1)}>이전</button>
    <span className="dir-page-counter">{page} / {last}</span>
    <button type="button" className="outline" disabled={page>=last||loading} onClick={()=>goPage(page+1)}>다음</button>
    <button type="button" className="outline" disabled={page>=last||loading} onClick={()=>goPage(last)}>끝</button>
    <div className="dir-go-page"><label htmlFor="jump-page">페이지 이동</label>
      <input type="number" id="jump-page" min={1} max={last} value={jump}
       onChange={e=>J(e.target.value)}/>
      <button type="button" className="primary" onClick={()=>goPage(jump)}>이동</button>
    </div>
   </nav>}
   <div className="footer">MY DERBY · {horses?(mode==="uploaded"?"CSV 4,060두 원본 자료":"게임 경주마"):"기수"} 전체 도감</div>
  </div>
 </main>;
}