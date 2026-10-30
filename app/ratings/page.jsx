"use client";
import HorseLink from "../components/HorseLink";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
export default function Ratings(){
 const [token,setToken]=useState(""),[board,setBoard]=useState(null),[error,setError]=useState("");
 useEffect(()=>{
  let live=true;
  const c=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
  c.auth.getSession().then(({data})=>{if(live)setToken(data.session?.access_token||"")}).catch(e=>setError(e.message));
  const {data:{subscription}}=c.auth.onAuthStateChange((_e,s)=>{if(live)setToken(s?.access_token||"")});
  return()=>{live=false;subscription.unsubscribe()};
 },[]);
 const load=async(access=token)=>{
  if(!access)return;
  try{
   const r=await fetch("/api/player/ratings",{headers:{Authorization:"Bearer "+access},cache:"no-store"});
   const v=await r.json();
   if(!r.ok)throw new Error(v.error||"레이팅 조회 오류");
   setBoard(v);setError("");
  }catch(e){setError(e.message)}
 };
 useEffect(()=>{if(token)void load(token)},[token]);
 return <main className="shell"><header className="header"><a className="brand" href="/" style={{textDecoration:"none"}}>MY DERBY</a><span className="coin">📊 레이팅</span></header>
 <div className="area"><div className="controls"><a href="/world" className="outline" style={{textDecoration:"none"}}>‹ 월드</a><a href="/entries" className="outline" style={{textDecoration:"none"}}>출전 신청 ›</a></div>
 <div className="section"><h2>경주마 레이팅 · 등급</h2><button disabled={!token} onClick={()=>load()}>새로고침 ↻</button></div>
 <div className="notice"><b>2025 KRA 레이팅 안내 기반 게임용 자동 평가</b><br/>
 실제 마사회 핸디캡퍼의 공식 평가가 아닙니다. 기존 경주마의 초기 레이팅은 원래 등급에서 추정했으며, 공식 게임 경주가 끝날 때마다 갱신됩니다.</div>
 {error&&<div role="alert" className="notice">{error}</div>}
 {!token&&<div className="notice"><a href="/world">로그인</a> 후 본인 경주마를 확인해주세요.</div>}
 {board&&<>
 <div className="card small"><b className="gold">기본 등급 기준</b><div className="muted">1등급 81+ · 2등급 66~80 · 3등급 51~65 · 4등급 36~50 · 5등급 ≤35 · 6등급 미부여</div>
 <div className="muted">6등급 우승·누적 입상 시 최초 26~32점. 1~5등급 핸디캡: 1점당 0.5kg, 암말 2kg 감량.</div></div>
 {(board.horses||[]).map(h=><div className="card" key={h.id}>
 <div className="row"><div><b className="gold"><HorseLink horseId={h.id}>{h.name}</HorseLink></b><div className="muted">현재 출전등급 {h.grade??"-"}등급 · 레이팅 기준 {h.ratingGrade??"-"}등급</div></div>
 <div style={{textAlign:"right"}}><b>{h.rating==null?"미부여":h.rating+"점"}</b><div className="tag">{h.pendingGrade?"등급 전환 대기":"적용 중"}</div></div></div>
 {h.seed==="LEGACY_GRADE_ESTIMATE_NOT_KRA_OFFICIAL"&&<div className="muted">※ 기존 등급에서 추정한 초기 레이팅을 사용했습니다.</div>}
 {(h.recent||[]).length>0&&<div style={{marginTop:12}}>
 <b>최근 게임 경주 레이팅 변화</b>
 {h.recent.map((x,i)=><div className="line row small" key={i}>
 <span>게임 {x.game_day}일 · {x.race_grade}등급 {x.finishing_rank}위</span>
 <b>{x.old_rating==null?"미부여":x.old_rating} → {x.new_rating??"미부여"} ({x.delta>0?"+":""}{x.delta})</b>
 </div>)}</div>}
 </div>)}
 {(!board.horses||board.horses.length===0)&&<div className="notice">보유 경주마가 없습니다.</div>}
 </>}
 <div className="footer">MY DERBY · KRA 2025 설명서 기반 게임 추정 레이팅</div>
 </div></main>;
}