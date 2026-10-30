"use client";
const LABELS={start:"출발",speed:"스피드",acceleration:"가속력",stamina:"지구력",finishing:"막판 탄력",power:"파워",grit:"근성",stability:"안정성",recovery:"회복력"};
export default function HorseDiscovery({discovery,compact=false}){
 if(!discovery||discovery.status!=="OK")return <div className="notice">
  🔒 경주마의 실제 능력·잠재력·히든 특성은 공개되지 않습니다.
  {discovery?.status==="NO_ABILITY"?" 아직 이 말의 능력 데이터가 없습니다.":" 내가 소유한 말의 관찰 보고서만 확인할 수 있습니다."}
 </div>;
 return <div className="horse-discovery">
  <div className="notice" style={{marginBottom:12}}>🔍 마주가 관찰로 알아낸 추정 정보입니다. 실제 능력 수치와 최대 성장치·미발견 히든 특성은 공개되지 않습니다.</div>
  <div className="horse-discovery-counts">
   <span>조교 관찰 <strong>{discovery.trainingCount||0}회</strong></span>
   <span>목장 관찰 <strong>{discovery.ranchCount||0}회</strong></span>
   <span>실전 관찰 <strong>{discovery.raceCount||0}회</strong></span>
  </div>
  <div className="horse-discovery-stats">{Object.entries(LABELS).map(([key,label])=>{
    const info=discovery.stats?.[key]||{};
    return <div className="horse-discovery-stat" key={key}>
      <span>{label}</span><div><b>{info.label||"미확인"}</b>
      {Array.isArray(info.range)&&<small>추정 {info.range[0]}~{info.range[1]}</small>}
      <small>{info.stage>1?"신뢰도 "+(info.confidence||0)+"%":"분석 전"}</small></div>
    </div>;
   })}</div>
  <div className="horse-discovery-section">
   <div><b>🌱 성장 가능성</b><span>{discovery.growth?.label||"분석 중"}</span></div>
   <div><b>🧠 기질</b><span>{discovery.temperament||"관찰 중"}</span></div>
   <div><b>🏇 거리 적성</b><span>{discovery.distance||"경주 자료 부족"}</span></div>
  </div>
  <div className="horse-discovery-section">
   <strong>✨ 발견된 히든 특성</strong>
   {discovery.traits?.length?<div className="horse-discovery-tags">
     {discovery.traits.map(item=><span key={item.code}>{item.name}</span>)}
    </div>:<p className="muted">🔒 아직 발견되지 않았습니다. 조교·목장 관찰과 다양한 공식 경주 경험을 축적해 주세요.</p>}
  </div>
  <div className="horse-discovery-advice"><b>🏠 담당 조교사 분석</b>
   <p>{discovery.trainerAdvice||"아직 평가 자료가 없습니다."}</p></div>
  {!compact&&<div className="controls" style={{marginTop:12}}>
    <a href="/training" className="outline" style={{textDecoration:"none"}}>조교 훈련 ›</a>
    <a href="/ranch" className="outline" style={{textDecoration:"none"}}>개인목장 관찰 ›</a>
   </div>}
 </div>;
}
