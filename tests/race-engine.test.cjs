const test=require("node:test");
const assert=require("node:assert/strict");
const {simulateRace,validateRace}=require("../.race-build/engine.js");
const {makeTestRace}=require("../.race-build/demo.js");
test("12 horse race finishes with valid ordered results",()=>{
 const result=simulateRace(makeTestRace(0));
 assert.equal(result.results.length,12);
 assert.deepEqual(result.results.map(r=>r.rank),Array.from({length:12},(_,i)=>i+1));
 assert.ok(result.results.every(r=>r.timeSec>0&&Number.isFinite(r.timeSec)));
 assert.ok(result.results.every((r,i,a)=>i===0||r.timeSec>=a[i-1].timeSec));
 assert.ok(result.events.some(e=>e.eventType==="START"));
 assert.equal(result.events.filter(e=>e.eventType==="FINISH").length,12);
 assert.equal(result.sections.length,6);
 assert.ok(result.sections.every(s=>s.ranks.length===12&&new Set(s.ranks.map(x=>x.horseId)).size===12));
});
test("same seed and input reproduce exact race event log",()=>{
 const race=makeTestRace(1,12345);
 assert.deepEqual(simulateRace(race),simulateRace(race));
});
test("different seeds can produce different results",()=>{
 const a=simulateRace(makeTestRace(0,20));
 const b=simulateRace(makeTestRace(0,89));
 assert.notDeepEqual(a.events,b.events);
});
test("test slots simulate distances and 200m intervals",()=>{
 for(let slot=0;slot<3;slot++){
   const input=makeTestRace(slot);
   const result=simulateRace(input);
   assert.equal(result.sections.at(-1).distanceM,input.distanceM);
   assert.equal(result.sections.length,input.distanceM/200);
   assert.ok(result.durationSec<300);
 }
});
test("malformed or duplicate runners rejected",()=>{
 const bad=makeTestRace(0);bad.runners[1].number=bad.runners[0].number;
 assert.throws(()=>validateRace(bad),/duplicate/);
 const bad2=makeTestRace(1);bad2.runners[0].horse.speed=101;
 assert.throws(()=>simulateRace(bad2),/ability/);
});
test("increasing quality substantially improves average placing",()=>{
 let better=0,base=0;
 for(let i=0;i<15;i++){
  let race=makeTestRace(1,100+i);
  const a=simulateRace(race).results.find(x=>x.horseId==="demo-1").rank;
  const improved=makeTestRace(1,100+i);
  improved.runners[0].horse.speed=99;
  improved.runners[0].horse.stamina=99;
  improved.runners[0].horse.acceleration=99;
  improved.runners[0].horse.finishing=99;
  const b=simulateRace(improved).results.find(x=>x.horseId==="demo-1").rank;
  base+=a;better+=b;
 }
 assert.ok(better<base,JSON.stringify({better,base}));
});
