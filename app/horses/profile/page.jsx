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
    <div className="section"><h2>최근 공식 경주</h2></div>
    {(data.game?.recentStarts||[]).length===0?<div className="notice">표시할 공식 경주 기록이 없습니다.</div>:
     <div className="race-entry-wrap" role="region" aria-label="경주마 최근 공식 경주 기록" tabIndex={0}>
      <table className="race-entry-table">
       <thead><tr><th>경주일자</th><th>경주-마번</th><th>등급</th><th>기수</th><th>거리</th><th>부담중량</th><th>순위</th><th>기록</th><th>출전 간격</th></tr></thead>
       <tbody>{data.game.recentStarts.map(r=>{
        const sec=Number(r.timeSec||0),minutes=Math.floor(sec/60),seconds=(sec%60).toFixed(1).padStart(4,"0");
        const day=["일","월","화","수","목","금","토"][Number(r.weekday)]||"";
        return <tr key={r.raceId}>
         <td><a href={"/race/result/"+encodeURIComponent(r.raceId)}>{r.date} ({day})</a></td>
         <td>{r.raceNo}R-{r.gateNo}</td><td>{r.grade||"-"}</td><td>{r.jockeyName||"-"}</td>
         <td>{fmt(r.distanceM)}m</td><td>{r.weightKg==null?"-":fmt(r.weightKg)+" kg"}</td>
         <td>{r.rank}/{r.fieldSize}</td><td>{minutes}:{seconds}</td>
         <td>{r.intervalDays==null?"-":r.intervalDays+"일"}</td>
        </tr>;
       })}</tbody>
      </table>
     </div>}
     <div className="section"><h2>🔍 능력·잠재력 발견 보고서</h2></div>
     <HorseDiscovery discovery={discovery} horseId={horseId||data?.id}/> 
     {data.genetics&&<>
      <div className="section"><h2>🧬 유전 특성 발견</h2></div>
      <div className="card">
       <div className="muted">훈련 리포트·목장 코스·공식 경주 관찰 {data.genetics.observations||0}회</div>
       {(data.genetics.knownTraits||[]).length?data.genetics.knownTraits.map(t=><div className="line" key={t.code}>
        <b className="gold">{t.name}</b><div className="muted">{t.description}</div>
        {t.inheritedFrom&&<div className="muted">유전 경로: {({DAM:"모마 계열",SIRE:"부마 계열",BOTH:"부모 양쪽",MUTATION:"자연 변이",DERIVED:"능력 기록 분석"})[t.inheritedFrom]||"혈통 분석"}</div>}
       </div>):<div className="muted" style={{marginTop:8}}>아직 확인된 유전 특성이 없습니다. 훈련·목장·경주 기록을 쌓으면 특성이 순차적으로 발견됩니다.</div>}
       {Number(data.genetics.undiscoveredCount||0)>0&&<div className="notice" style={{marginTop:9}}>
        미발견 특성 {data.genetics.undiscoveredCount}개 · 다음 발견 기준 {data.genetics.nextDiscoveryAt}회 관찰
       </div>}
       <div className="muted" style={{marginTop:8}}>발견된 유전 특성의 효과는 자마의 유전자 능력치에 반영됩니다. 숨겨진 실제 수치와 미발견 특성은 표시하지 않습니다.</div>
      </div>
     </>}
     {data.offspring&&<>
      <div className="section"><h2>🧬 자마 성적</h2>
       <a className="outline" href={`/horses/offspring?horseId=${encodeURIComponent(data.gameHorseId)}`}>자마 내역 전체 보기 ›</a>
      </div>
      <div className="card">
       <div className="horse-profile-attributes">
        <div><span>자마 수</span><strong>{fmt(data.offspring.summary?.offspring)}두</strong></div>
        <div><span>출전</span><strong>{fmt(data.offspring.summary?.starts)}회</strong></div>
        <div><span>1위</span><strong>{fmt(data.offspring.summary?.wins)}회</strong></div>
        <div><span>2위</span><strong>{fmt(data.offspring.summary?.second)}회</strong></div>
        <div><span>3위</span><strong>{fmt(data.offspring.summary?.third)}회</strong></div>
       </div>
       <div className="section"><h2>등급별 성적</h2></div>
       {(data.offspring.byGrade||[]).length?<div className="race-entry-wrap" role="region" aria-label="자마 등급별 성적" tabIndex={0}>
        <table className="race-entry-table"><thead><tr><th>등급</th><th>출전</th><th>1위</th><th>2위</th><th>3위</th></tr></thead>
         <tbody>{data.offspring.byGrade.map(r=><tr key={r.grade}><td>{r.grade}등급</td><td>{fmt(r.starts)}</td><td>{fmt(r.wins)}</td><td>{fmt(r.second)}</td><td>{fmt(r.third)}</td></tr>)}</tbody>
        </table>
       </div>:<div className="muted">자마의 경주 성적이 아직 없습니다.</div>}
       <div className="section"><h2>거리별 성적</h2></div>
       {(data.offspring.byDistance||[]).length?<div className="race-entry-wrap" role="region" aria-label="자마 거리별 성적" tabIndex={0}>
        <table className="race-entry-table"><thead><tr><th>거리</th><th>출전</th><th>1위</th><th>2위</th><th>3위</th></tr></thead>
         <tbody>{data.offspring.byDistance.map(r=><tr key={r.distanceM}><td>{fmt(r.distanceM)}m</td><td>{fmt(r.starts)}</td><td>{fmt(r.wins)}</td><td>{fmt(r.second)}</td><td>{fmt(r.third)}</td></tr>)}</tbody>
        </table>
       </div>:<div className="muted">거리별로 집계할 경주 성적이 없습니다.</div>}
       <div className="section"><h2>대상경주 성적</h2></div>
       {(data.offspring.stakes||[]).length?<div className="race-entry-wrap" role="region" aria-label="자마 대상경주 성적" tabIndex={0}>
        <table className="race-entry-table"><thead><tr><th>경주</th><th>출전</th><th>1위</th><th>2위</th><th>3위</th></tr></thead>
         <tbody>{data.offspring.stakes.map((r,i)=><tr key={`${r.name||"stakes"}-${i}`}><td>{r.name||"대상경주"}</td><td>{fmt(r.starts)}</td><td>{fmt(r.wins)}</td><td>{fmt(r.second)}</td><td>{fmt(r.third)}</td></tr>)}</tbody>
        </table>
       </div>:<div className="muted">자마의 대상경주 성적이 아직 없습니다.</div>}
      </div>
      <div className="section"><h2>최근 자마</h2></div>
      {(data.offspring.offspring||[]).slice(0,5).map(h=><div className="card row" key={h.id}>
       <div><b>{h.name}</b><div className="muted">{({RACING:"경주마",RESTING:"휴양마",STALLION:"씨수마",BROODMARE:"씨암말",RETIRED:"은퇴마"})[h.status]||h.status} · {fmt(h.starts)}전 {fmt(h.first)}승 · 2위 {fmt(h.second)}회 · 3위 {fmt(h.third)}회</div>
        <div className="muted">은퇴 직전 레이팅 {h.retirementRating==null?"-":fmt(h.retirementRating)} · 등급 {h.retirementGrade?`${h.retirementGrade}등급`:"-"}</div></div>
       <a className="outline" href={`/horses/profile?horseId=${encodeURIComponent(h.id)}`}>정보 ›</a>
      </div>)}
     </>}
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
