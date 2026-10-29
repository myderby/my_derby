"use client";
import {useCallback,useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";

const labelStat={start:"스타트",speed:"스피드",acceleration:"가속력",stamina:"지구력",
 finishing:"막판탄력",power:"파워",grit:"근성",stability:"안정성",recovery:"회복력"};
const sexName={MALE:"수",FEMALE:"암",GELDING:"거"};
const stageName={FOAL:"망아지",YEARLING:"1세마",RACING:"현역",RETIRED:"은퇴",
 STALLION:"씨수말",BROODMARE:"번식암말",DECEASED:"폐사"};
const apiClient=()=>{const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!url||!key)throw new Error("Supabase 설정이 없습니다.");
 return createClient(url,key);};

export default function WorldPage(){
 const [overview,O]=useState(null),[mine,M]=useState(null),[authenticated,A]=useState(false);
 const [busy,B]=useState(false),[notice,N]=useState(""),[email,E]=useState(""),[pass,P]=useState(""),[nickname,Nick]=useState("");
 const [loaded,L]=useState(false),[expanded,Expand]=useState(null),[trainers,Trainers]=useState([]),[trainerTrack,TrainerTrack]=useState("전체"),[trainerError,TrainerError]=useState(""),[npcRetirements,NpcRetirements]=useState(null),[npcRetireError,NpcRetireError]=useState("");
 const flash=x=>{N(x);setTimeout(()=>N(""),7000)};
 const loadMine=useCallback(async()=>{
  try{
   const client=apiClient();
   const {data,error}=await client.auth.getSession();
   if(error)throw error;
   const token=data.session?.access_token;
   A(!!token);
   if(!token){M(null);return;}
   const r=await fetch("/api/world/mine",{cache:"no-store",headers:{Authorization:"Bearer "+token}});
   const o=await r.json();if(!r.ok)throw new Error(o.error||"내 경주마 조회 실패");
   M(o);
  }catch(err){flash(err.message);M(null);}
 },[]);
 const loadOverview=useCallback(async()=>{
  try{const r=await fetch("/api/world/overview",{cache:"no-store"});const o=await r.json();
   if(!r.ok)throw new Error(o.error||"월드 정보를 불러올 수 없습니다.");O(o);
  }catch(e){flash(e.message)}
 },[]);
 useEffect(()=>{Promise.all([loadOverview(),loadMine()]).finally(()=>L(true))},[loadOverview,loadMine]);
 useEffect(()=>{fetch("/api/world/trainers",{cache:"no-store"}).then(async r=>{const data=await r.json();if(!r.ok)throw new Error(data.error||"조교사 목록 조회 실패");Trainers(data.trainers||[])}).catch(e=>TrainerError(e.message))},[]);
 useEffect(()=>{fetch("/api/world/npc-retirements",{cache:"no-store"}).then(async r=>{const data=await r.json();if(!r.ok)throw new Error(data.error||"NPC 은퇴 현황 조회 실패");NpcRetirements(data)}).catch(e=>NpcRetireError(e.message))},[]);
 const login=async signup=>{
  B(true);
  try{
   const client=apiClient();
   const {data,error}=signup?await client.auth.signUp({email,password:pass}):
    await client.auth.signInWithPassword({email,password:pass});
   if(error)throw error;
   if(signup&&!data.session){flash("가입 요청 완료. 인증 이메일을 확인한 뒤 로그인하세요.");}
   else{flash("로그인 완료");await loadMine();}
  }catch(e){flash(e.message)}finally{B(false)}
 };
 const join=async()=>{
  B(true);
  try{
   const c=apiClient();const {data,error}=await c.auth.getSession();
   if(error||!data.session)throw new Error("로그인부터 진행하세요.");
   const r=await fetch("/api/world/join",{method:"POST",cache:"no-store",
    headers:{"Content-Type":"application/json",Authorization:"Bearer "+data.session.access_token},
    body:JSON.stringify({nickname:nickname.trim()})});
   const o=await r.json();if(!r.ok)throw new Error(o.error||"마주 등록 실패");
   flash(o.alreadyJoined?"이미 등록된 마주입니다.":"마주 등록 완료! 무작위 경주마 "+o.ownedHorses+"두를 배정했습니다.");
   await Promise.all([loadOverview(),loadMine()]);
  }catch(e){flash(e.message)}finally{B(false)}
 };
 const logout=async()=>{
  B(true);try{await apiClient().auth.signOut();A(false);M(null);flash("로그아웃했습니다.");}
  catch(e){flash(e.message)}finally{B(false)}
 };
 return <div className="shell">
  <header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">🌍 월드 운영</span></header>
  <div className="disclaimer">경주기록 기반 월드 · 추가 편성마는 임시 능력치 · 운영 중</div>
  <div className="area">
   <a href="/" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:14}}>‹ 홈으로</a>
   <a href="/schedule" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:14,marginLeft:8}}>공식 경주시간표 ›</a>
   <a href="/entries" className="primary" style={{display:"inline-block",textDecoration:"none",marginBottom:14,marginLeft:8}}>🏇 출전·기수 신청 ›</a><a href="/stable" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:14,marginLeft:8}}>🏠 조교사 위탁·계약 ›</a><a href="/training" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:14,marginLeft:8}}>🐎 훈련계획·리포트 ›</a><a href="/breeding" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:14,marginLeft:8}}>✧ 교배·임신 관리 ›</a><a href="/market" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:14,marginLeft:8}}>💰 경주마 시장 ›</a><a href="/finance" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:14,marginLeft:8}}>💳 재무 현황 ›</a><a href="/ranch" className="outline" style={{display:"inline-block",textDecoration:"none",marginBottom:14,marginLeft:8}}>🌲 개인목장 ›</a>
   <div className="section"><h2>월드 현황</h2><button onClick={loadOverview}>새로고침 ↻</button></div>
   {!overview&&<div className="notice">{loaded?"월드 데이터를 읽지 못했습니다.":"데이터를 불러오는 중…"}</div>}
   {overview&&<><div className="card">
     <div className="row"><div><b className="gold">실경주 경주마 월드</b><div className="muted">기록 기반 능력치 모델 kra_v1</div></div>
     <span className="tag">{overview.world.status==="PAUSED"?"운영 대기":"운영 중"}</span></div>
     <div className="row" style={{marginTop:15}}><div><b className="large">{overview.world.season}시즌 · {overview.world.week}주차</b><div className="muted">현실 1일 = 게임 1주 · 52주=1시즌</div></div><span className="pill">KST</span></div>
     <div className="raceTrack">{overview.world.raceSlots?.map(t=><span key={t} style={{fontSize:14,padding:11}}>{t}</span>)}</div>
     <div className="muted">세계 시간 기준: {overview.world.kstDate} · 자동 경주 {overview.world.schedulerConfigured?"설정됨":"아직 미설정"}</div>
    </div>
    <div className="grid">
     <div className="card"><div className="muted">전체 경주마</div><div className="large gold">{overview.horseCount?.toLocaleString("ko-KR")}두</div></div>
     <div className="card"><div className="muted">NPC 마주</div><div className="large">{overview.npcOwnerCount}명</div></div>
     <div className="card"><div className="muted">NPC 보유마</div><div className="large">{overview.npcOwnedHorses?.toLocaleString("ko-KR")}두</div></div>
     <div className="card"><div className="muted">사용자 배정 대기</div><div className="large green">{overview.reservedHorses}두</div></div>
    </div>
    <div className="notice">월드 시간표는 <b>{overview.world.status==="ACTIVE"?"ACTIVE":"PAUSED"}</b> 상태이며 현실 1일=게임 1주, 52일=1시즌으로 계산됩니다. <b>공식 경주 자동 실행은 {overview.world.schedulerConfigured&&overview.world.automaticProcessingEnabled?"스케줄러가 활성화됨":"아직 비활성화"}</b> 상태입니다. 경주 결과와 구간 로그는 정시 실행 후 저장되지만 <b>상금·훈련·성장·말 나이의 자동 정산은 별도 개발이 필요</b>합니다. 2025년 경주 편성표를 게임용으로 재구성했으며 지역별 일부 말·기수 능력치는 임시 추정치입니다.</div>
   </>}
   <div className="section" style={{marginTop:18}}><h2>내 마주 등록 · 보유마</h2>{authenticated&&<button onClick={logout}>로그아웃</button>}</div>
   {!authenticated&&<div className="card">
     <b>이메일로 로그인</b><div className="muted">마이더비 월드에 직접 참가한 계정에만 말을 지급합니다.</div>
     <input className="field" type="email" placeholder="이메일" value={email} onChange={e=>E(e.target.value)}/>
     <input className="field" type="password" placeholder="비밀번호" value={pass} onChange={e=>P(e.target.value)}/>
     <div className="controls"><button className="primary" disabled={busy} onClick={()=>login(false)}>로그인</button>
     <button className="outline" disabled={busy} onClick={()=>login(true)}>회원가입</button></div>
    </div>}
   {authenticated&&!mine?.joined&&<div className="card">
     <b className="gold">마주 등록 후 무작위 경주마 3두 지급</b>
     <div className="muted">마이더비에 참가하지 않은 사용자는 말을 소유하지 않습니다. 한 계정당 최초 1회만 배정됩니다.</div>
     <input className="field" placeholder="마주 닉네임 (2~32자)" maxLength={32} value={nickname} onChange={e=>Nick(e.target.value)}/>
     <button className="primary wide" disabled={busy||nickname.trim().length<2} onClick={join}>{busy?"등록 처리 중…":"월드 참가 · 3두 무작위 배정"}</button>
    </div>}
   {mine?.joined&&<><div className="card">
     <b className="gold">{mine.profile?.nickname} 마주</b>
     <div className="muted">내 보유 경주마: {mine.horses?.length??0}두 · 개인목장 생성됨</div></div>
    {(mine.horses??[]).map(h=><div key={h.id} className="card">
     <div className="row" onClick={()=>Expand(expanded===h.id?null:h.id)} style={{cursor:"pointer"}}>
      <div><b className="gold">♞ {h.name}</b><div className="muted">hrNo {h.source_hr_no} · {h.age_years}세 · {sexName[h.sex]||h.sex} · {stageName[h.life_stage]||h.life_stage}</div></div>
      <span className="tag">{expanded===h.id?"접기":"능력치 보기 ›"}</span></div>
      {expanded===h.id&&<><div className="grid" style={{marginTop:12}}>
       {Object.entries(h.currentStats??{}).map(([k,v])=><div className="card" key={k} style={{margin:0,padding:10}}>
        <div className="row small"><span>{labelStat[k]||k}</span><b>{v}</b></div>
        <div className="bar"><div className="fill" style={{width:Math.min(100,Number(v))+"%"}}/></div>
       </div>)}
      </div><div className="muted" style={{marginTop:12}}>히든 특성과 최대 잠재력은 서버에 보관하며 일반 사용자에게 직접 공개하지 않습니다.</div></>}
    </div>)}
   </>}
   <div className="section" style={{marginTop:22}}><h2>NPC 조교사 · 마방</h2></div>
   <div className="card"><div className="row"><b className="gold">NPC 조교사 {trainers.length}명</b><span className="tag">1명당 최대 40두</span></div>
   <div className="controls" style={{marginTop:12,flexWrap:"wrap"}}>{["전체","서울","부산","영천"].map(track=><button key={track} className={trainerTrack===track?"primary":"outline"} onClick={()=>TrainerTrack(track)}>{track}</button>)}</div>
   {trainerError&&<div className="notice">{trainerError}</div>}
   {trainers.filter(t=>trainerTrack==="전체"||t.track===trainerTrack).map(t=><div className="line row small" key={t.id} style={{alignItems:"center"}}>
     <div><b>{t.name}</b><div className="muted">{t.track} · {t.stableName} · {t.specialties.join(" / ")}</div></div><span className="tag">{t.horseCount}/{t.capacity}두</span>
   </div>)}
   {!trainers.length&&!trainerError&&<div className="muted">조교사 명단 불러오는 중…</div>}
   <div className="muted" style={{marginTop:10}}>실제 NPC 계약 현황입니다. 내 경주마의 조교사 신청·계약 기능은 별도 개발 항목입니다.</div></div>
   <div className="section" style={{marginTop:22}}><h2>NPC 마주 성향별 번식 전환</h2></div>
   <div className="card">
    <div className="row"><b className="gold">번식마 전환 판단</b><span className="tag">매일 23:05 심사</span></div>
    <div className="muted" style={{marginTop:10}}>NPC 마주 자체에는 은퇴 기준이 없습니다. 각 NPC 마주의 성향에 따라 성적이 계속 부진한 경주마를 씨수말·번식암말로 전환합니다.
     영구적으로 경주 복귀가 불가능한 부상도 번식 전환 사유입니다. 번식 불가능한 말은 부진만으로 일반 은퇴시키지 않습니다.</div>
    <div className="card" style={{marginTop:12}}>
     <div className="row small"><span>안정형</span><b>최근 4경주 부진 평가</b></div>
     <div className="line row small"><span>균형형</span><b>최근 6경주 부진 평가</b></div>
     <div className="line row small"><span>공격형</span><b>최근 8경주 부진 평가</b></div>
     <div className="muted" style={{marginTop:9}}>각 성향별 기준은 해당 기간 전부 3위 이내 입상 실패,
      하위 40% 기록 3회/5회/7회 이상, 평균 상대 순위 하위권입니다. 임시 부상·거세마는 번식 전환에서 제외합니다.</div>
    </div>
    {npcRetireError&&<div className="notice">{npcRetireError}</div>}
    {npcRetirements&&<>
     <div className="grid" style={{marginTop:12}}>
      <div className="card"><div className="muted">누적 번식 전환</div><b className="gold">{npcRetirements.total??0}두</b></div>
      <div className="card"><div className="muted">성적 부진 원인</div><b>{npcRetirements.poorForm??0}두</b></div>
      <div className="card"><div className="muted">영구 부상 원인</div><b>{npcRetirements.injury??0}두</b></div>
      <div className="card"><div className="muted">씨수말 / 번식암말</div><b>{npcRetirements.stallions??0} / {npcRetirements.broodmares??0}두</b></div>
     </div>
     {(npcRetirements.recent||[]).length>0&&
      <div style={{marginTop:14}}>{npcRetirements.recent.map((entry,i)=><div className="line row small" key={i}>
       <div><b>{entry.horseName}</b>
        <div className="muted">마주 {entry.ownerName||"NPC"} · {entry.ownerRisk==="CONSERVATIVE"?"안정형":entry.ownerRisk==="AGGRESSIVE"?"공격형":"균형형"}</div>
        <div className="muted">{entry.reason==="POOR_FORM"?"지속적인 경주 성적 부진":"경주 복귀 불가 부상"} · 게임 {entry.gameDay}일</div></div>
       <span className="tag">{entry.newStage==="STALLION"?"씨수말":entry.newStage==="BROODMARE"?"번식암말":"기존 기록"}</span>
      </div>)}</div>}
     {(npcRetirements.recent||[]).length===0&&<div className="muted" style={{marginTop:10}}>아직 번식 전환 기록이 없습니다. 부진 누적이나 영구 부상 판정에 따라 자동으로 전환됩니다.</div>}
    </>}
   </div>
   <div className="section" style={{marginTop:22}}><h2>NPC 마주 현황</h2></div>
   <div className="card">
    {(overview?.topNpcOwners??[]).map((owner,i)=><div className="line row small" key={owner.ownerName}>
     <span>{i+1}. {owner.ownerName}</span><div><b>{owner.horseCount}두</b><div className="muted">{owner.risk==="CONSERVATIVE"?"안정형":owner.risk==="AGGRESSIVE"?"공격형":"균형형"}</div></div></div>)}
    <div className="muted" style={{marginTop:9}}>상위 15명 표시 · NPC의 실제 경매·출전 판단과 상금 정산은 운영 엔진 구현 후 활성화됩니다.</div>
   </div>
   <div className="footer">MY DERBY · WORLD CONFIG v4_world_v1 · 경제_v2 유지</div>
  </div>
  {notice&&<div className="toast">{notice}</div>}
 </div>;
}
