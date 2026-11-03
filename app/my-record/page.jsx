"use client";
import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";
const format=n=>Number(n||0).toLocaleString("ko-KR");
function Stats({value}){return <div className="record-grid">{[["출전",value.starts],["1위",value.wins],["2위",value.seconds],["3위",value.thirds]].map(([label,num])=><div className="record-stat" key={label}><span>{label}</span><strong>{format(num)}</strong></div>)}<div className="record-prize">획득 상금 <strong>{format(value.prize)} G</strong></div></div>}
export default function MyRecord(){
 const [state,setState]=useState({loading:true,data:null,error:""});
 const [achievementState,setAchievementState]=useState({items:[],error:""});
 useEffect(()=>{let active=true;const load=async()=>{try{
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if(!url||!key)throw Error("인증 설정이 없습니다.");
  const client=createClient(url,key);const {data:{session}}=await client.auth.getSession();
  if(!session)throw Error("로그인이 필요합니다.");
  const response=await fetch("/api/player/my-record",{headers:{Authorization:"Bearer "+session.access_token},cache:"no-store"});
  const body=await response.json();if(!response.ok)throw Error(body.error||"기록 조회 실패");
  if(active)setState({loading:false,data:body,error:""});
  const achievementsResponse=await fetch("/api/player/achievements",{headers:{Authorization:"Bearer "+session.access_token},cache:"no-store"});
  const achievementsBody=await achievementsResponse.json();
  if(!achievementsResponse.ok)throw Error(achievementsBody.error||"업적 조회 실패");
  const definitions=new Map((achievementsBody.definitions||[]).map(item=>[item.achievement_key,item]));
  const horses=new Map((achievementsBody.horses||[]).map(item=>[item.id,item.name]));
  const items=(achievementsBody.progress||[]).filter(item=>item.unlocked_at).map(item=>({
   ...item,definition:definitions.get(item.achievement_key),horseName:horses.get(item.subject_id)||item.horseName
  })).filter(item=>item.definition);
  if(active)setAchievementState({items,error:""});
 }catch(error){if(active){setState(current=>current.loading?{loading:false,data:null,error:error.message}:current);setAchievementState(current=>({items:current.items,error:error.message}));}}};load();return()=>{active=false};},[]);
 const data=state.data;
 const achievementCategories=[...new Set(achievementState.items.map(item=>item.definition.category))];
 const achievementLabels={CAREER_WINS:"통산 승리",GRADE_WINS:"등급별 승리",HORSE_WINS:"말 승리",HORSE_STREAK:"말 연승",WIN_ODDS:"단승 배당",PLACE_ODDS:"연승 배당",STAKES_WINS:"대상경주",COMPETITION_TITLE:"대회 호칭"};
 return <main className="shell"><header className="header"><div><div className="brand">MY DERBY</div><div className="sub">마주 기록실</div></div><div className="controls"><a className="outline" href="/" style={{textDecoration:"none"}}>홈</a><a className="outline" href="/bets" style={{textDecoration:"none"}}>베팅 이력 ›</a></div></header>
 <div className="area"><div className="section"><h2>🏅 나의 정보</h2><a href="/" style={{color:"#efc779",fontSize:12}}>돌아가기</a></div>
 {state.loading?<div className="notice">공식 경주 기록을 조회하고 있습니다.</div>:state.error?<div className="notice" role="alert">{state.error}</div>:data&&<>
 <div className="card"><div className="muted">마주</div><h2 style={{margin:"8px 0",color:"#f0c572"}}>{data.profile.nickname}</h2><div className="muted">공식 결과가 확정된 경주만 집계합니다. 출전 당시의 마주를 기준으로 합니다.</div></div>
 <div className="section"><h2>통산 전적</h2></div><div className="card"><Stats value={data.total}/></div>
 <div className="section"><h2>시즌별 전적</h2></div>{data.seasons.length?data.seasons.map(s=><div className="card" key={s.season}><b className="gold">시즌 {s.season}</b><Stats value={s}/></div>):<div className="notice">집계된 시즌 기록이 없습니다.</div>}
 <div className="section"><h2>대상경주(OPEN) 성적</h2></div><div className="card"><Stats value={data.open}/></div>
 <div className="section"><h2>🏆 대상경주 트로피</h2></div>{data.trophies.length?data.trophies.map(t=><div className="card" key={t.raceId}><b className="gold">🏆 {t.name} 우승</b><div className="muted" style={{marginTop:7}}>시즌 {t.season} · {t.track} · {t.raceNo}경주</div></div>):<div className="notice">아직 획득한 대상경주 트로피가 없습니다. OPEN 경주 우승 시 이곳에 기록됩니다.</div>}
 <div className="section" id="achievements" data-tutorial-target="achievements"><h2>🎖️ 달성 업적</h2><span className="tag">{achievementState.items.length}개</span></div>
 {achievementState.error?<div className="notice" role="alert">업적 기록을 불러오지 못했습니다. {achievementState.error}</div>:achievementState.items.length?achievementCategories.map(category=><section key={category} style={{marginBottom:18}}>
  <h3 className="gold" style={{fontSize:14,margin:"0 0 8px"}}>{achievementLabels[category]||category}</h3>
  {achievementState.items.filter(item=>item.definition.category===category).map(item=><div className="card" key={item.achievement_key+":"+item.subject_id} style={{marginBottom:8}}>
   <div className="row"><b className="gold">🏆 {item.definition.title}</b><span className="tag">달성</span></div>
   <div className="muted" style={{marginTop:7}}>{item.definition.description}</div>
   {item.horseName&&<div className="small" style={{marginTop:7}}>말: {item.horseName}</div>}
   {item.definition.competition_name&&<div className="small" style={{marginTop:7}}>대회: {item.definition.competition_name}</div>}
   <div className="muted" style={{marginTop:7}}>{format(item.progress)} / {format(item.definition.threshold)} · {new Date(item.unlocked_at).toLocaleDateString("ko-KR")}</div>
  </div>)}
 </section>):<div className="notice">아직 달성한 업적이 없습니다. 경주와 베팅 기록을 쌓으면 달성한 항목이 여기에 표시됩니다.</div>}
 </>}</div></main>;
}
