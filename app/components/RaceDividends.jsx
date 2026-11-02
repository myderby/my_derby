"use client";

const betTypes=[
 ["WIN","단승"],["PLACE","연승"],["QUINELLA","복승"],
 ["QUINELLA_PLACE","복연승"],["EXACTA","쌍승"],
 ["TRIO","삼복승"],["TRIFECTA","삼쌍승"]
];
const prettyOdds=n=>n===null||n===undefined?"—":Number(n).toFixed(2)+"배";
const selectionLabel=(type,nums)=>(nums||[]).map(n=>String(n)+"번")
 .join(["EXACTA","TRIFECTA"].includes(type)?" → ":" - ");

export default function RaceDividends({result}){
 if(!result||result.status==="PENDING")return <div className="notice">
  승식별 배당 정산 결과를 확인하는 중입니다.
 </div>;
 if(result.status==="HISTORIC_NOT_RECORDED")return <div className="notice">
  이 경주는 최종 배당 기록 저장 기능이 도입되기 전에 정산되었습니다.
  관중 베팅 이력이 이미 삭제되어 정확한 최종 배당은 복원할 수 없습니다.
 </div>;
 if(result.status!=="RECORDED")return null;
 const combos=Array.isArray(result.winningCombinations)?result.winningCombinations:[];
 const horses=Array.isArray(result.runnerOdds)?result.runnerOdds:[];
 const pools=Array.isArray(result.pools)?result.pools:[];
 return <>
  <div className="section"><h2>💰 공식 승식별 적중 배당</h2></div>
  <div className="card">
   <div className="race-entry-wrap" role="region" tabIndex={0} aria-label="승식별 적중 조합 및 최종 배당">
    <table className="race-entry-table dividend-result-table">
     <thead><tr>
      <th scope="col">승식</th>
      <th scope="col">적중 조합</th>
      <th scope="col">실제 지급 배당</th>
     </tr></thead>
     <tbody>{betTypes.flatMap(([type,label])=>{
      const matching=combos.filter(x=>x.type===type);
      const pool=pools.find(x=>x.type===type);
      return matching.length?matching.map((row,index)=><tr key={type+"-"+index}>
       <td>{index===0?<b>{label}</b>:""}</td>
       <td className="dividend-horses">{selectionLabel(type,row.numbers)}</td>
       <td className="dividend-value">{row.payoutOdds!=null?
        prettyOdds(row.payoutOdds):
        <span className="muted">{pool?.payoutRule==="NO_WINNER_REFUND"?
         "적중 베팅 없음 · 환급":pool?.pool===0?"베팅 없음":"적중 베팅 없음"}</span>}</td>
      </tr>):<tr key={type}>
       <td><b>{label}</b></td><td>—</td><td className="muted">적중 조합 없음</td>
      </tr>;
     })}</tbody>
    </table>
   </div>
   <div className="muted" style={{marginTop:9,fontSize:11}}>
    실제 지급 배당은 정산 완료 시 적중 조합에 지급된 총 골드 ÷ 해당 조합의 베팅 원금입니다.
    적중 조합에 베팅한 사람이 없으면 배당률을 표시하지 않습니다.
   </div>
  </div>
  <div className="section"><h2>🏇 마번별 최종 단승·연승 배당</h2></div>
  <div className="card">
   <div className="race-entry-wrap" role="region" tabIndex={0} aria-label="출전마별 확정 시점 단승 및 연승 배당">
    <table className="race-entry-table dividend-result-table">
     <thead><tr>
      <th scope="col">마번</th><th scope="col">경주마</th>
      <th scope="col">단승</th><th scope="col">연승(참고)</th>
     </tr></thead>
     <tbody>{horses.map(h=><tr key={h.horseId}>
      <td>{h.number}번</td><td>{h.name}</td>
      <td className="dividend-value">{prettyOdds(h.winOdds)}</td>
      <td className="dividend-value">{prettyOdds(h.placeOddsUpper)}</td>
     </tr>)}</tbody>
    </table>
   </div>
   <div className="muted" style={{marginTop:9,fontSize:11}}>
    경주 마감 시점의 실제 승식 풀을 기준으로 저장한 배당입니다.
    연승은 여러 말에 동시에 지급되므로 마번별 참고 배당은 상한치이며,
    적중마의 실제 지급 배당은 위 표에서 확인할 수 있습니다.
    베팅 금액이 없는 마번은 —로 표시합니다.
   </div>
  </div>
 </>;
}
