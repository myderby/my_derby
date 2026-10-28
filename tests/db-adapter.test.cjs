const test=require("node:test");
const assert=require("node:assert/strict");
const {makeRaceInputFromDatabase,readStrategies}=require("../.race-build/db-adapter.js");
const {simulateRace}=require("../.race-build/engine.js");
const hs={start:70,speed:77,acceleration:76,stamina:80,finishing:75,power:74,grit:71,stability:77,recovery:73};
const js={start:70,positioning:80,pace:82,judgment:81,urging:78,control:77,aggression:72,stability:76};
const rows=()=>{
 const race={id:"4b5f766e-16fb-45c4-a088-b86e0525b859",track:"서울",distance_m:1200,status:"CLOSED"};
 const entries=["f1","f2"].map((id,i)=>({id,horse_id:"h"+i,owner_user_id:"user",jockey_id:"j"+i,gate_no:i+1,weight_kg:54,status:"CONFIRMED",snapshot:{}}));
 const horses=entries.map((e,i)=>({id:e.horse_id,name:"TEST "+i,condition_score:85,fatigue:10}));
 const abilities=entries.map(e=>({horse_id:e.horse_id,current_stats:hs,distance_affinity:{"1200":88}}));
 const jockeys=entries.map(e=>({id:e.jockey_id,skill_stats:js}));
 const strategies=entries.map(e=>({race_entry_id:e.id,plan_no:1,strategy_code:"LEAD"}));
 return {race,entries,horses,abilities,jockeys,strategies,seed:170};
};
test("build race engine input from real my_derby schema columns",()=>{
 const input=makeRaceInputFromDatabase(rows());
 assert.equal(input.runners.length,2);
 assert.equal(input.runners[0].strategies[0],"FRONT");
 assert.equal(input.runners[0].distanceFit,88);
 assert.equal(simulateRace(input).results.length,2);
});
test("reject non closed race and missing sensitive abilities",()=>{
 const x=rows();x.race.status="OPEN";assert.throws(()=>makeRaceInputFromDatabase(x),/closed/i);
 const y=rows();y.abilities=[];assert.throws(()=>makeRaceInputFromDatabase(y),/Missing/);
});
test("strategy mappings preserve 1,2,3 order and reject unknown",()=>{
 assert.deepEqual(readStrategies([{plan_no:2,strategy_code:"MID_MOVE"},{plan_no:1,strategy_code:"LEAD"}]),["FRONT","MOVE"]);
 assert.deepEqual(readStrategies([]),["FREE"]);
 assert.throws(()=>readStrategies([{plan_no:1,strategy_code:"INVALID"}]),/Unsupported/);
});
