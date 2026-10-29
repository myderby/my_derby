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

test("16-runner dusu race finishes with all unique places and gate numbers",()=>{
 const input=makeTestRace(0,39211);
 input.runners.push(...input.runners.slice(0,4).map((h,i)=>({
  ...h,id:"extra-"+i,name:"증원"+(i+1),number:13+i,gate:13+i,
  horse:{...h.horse},jockey:{...h.jockey},strategies:[...h.strategies]
 })));
 const result=simulateRace(input);
 assert.equal(result.results.length,16);
 assert.equal(result.results.filter(x=>x.rank===16).length,1);
 assert.equal(new Set(result.results.map(x=>x.horseId)).size,16);
 assert.equal(result.events.filter(x=>x.eventType==="FINISH").length,16);
 assert.ok(result.sections.every(x=>x.ranks.length===16));
});

test("race commentary describes horses without internal strategy plan numbering",()=>{
  for(let i=0;i<3;i++){
    const result=simulateRace(makeTestRace(i,6281+i*101));
    assert.ok(result.events.length>result.results.length);
    assert.ok(result.events.every(e=>!/(\\d+안에서|전략을 전환|STRATEGY_SWITCH)/.test(e.text)));
    assert.ok(!result.events.some(e=>e.eventType==="STRATEGY_SWITCH"));
    assert.ok(result.events.some(e=>e.reasonCode==="SECTION_LEADER"));
    const top=result.events.find(e=>e.eventType==="FINISH"&&e.params.rank===1);
    assert.ok(top&&top.text.includes(result.results[0].name));
  }
});
test("every overtaking log names the exact overtaken opponent",()=>{
  const races=[makeTestRace(0,9001),makeTestRace(1,9287),makeTestRace(2,11235)];
  const overtakes=races.flatMap(r=>simulateRace(r).events.filter(e=>e.eventType==="OVERTAKE"));
  assert.ok(overtakes.length>0,"Need overtakes in test races");
  for(const e of overtakes){
    assert.equal(typeof e.params.targetHorseId,"string");
    assert.equal(typeof e.params.targetHorseName,"string");
    assert.ok(e.text.includes(e.params.targetHorseName));
    assert.ok(e.text.includes(String(e.params.targetHorseNumber)+"번"));
    assert.ok(e.params.currentRank<e.params.previousRank);
  }
});
test("lane narration comes from a recorded lane change with real direction",()=>{
  const events=simulateRace(makeTestRace(1,89134)).events.filter(e=>e.eventType==="LANE_CHANGE");
  assert.ok(events.length>0);
  for(const e of events){
    assert.notEqual(e.params.fromLane,e.params.toLane);
    assert.equal(e.params.outside,e.params.toLane>e.params.fromLane);
    assert.match(e.text,e.params.outside?/바깥쪽/:/안쪽/);
  }
});
test("falling-behind narration requires worsening rank and increasing leader gap",()=>{
  const samples=[20,39,900].flatMap(seed=>simulateRace(makeTestRace(0,seed)).events)
    .filter(e=>e.reasonCode==="FALLING_BEHIND");
  assert.ok(samples.length>0);
  for(const e of samples){
    assert.ok(e.params.currentRank>e.params.previousRank);
    assert.ok(e.params.gapIncreaseM>=2.5);
    assert.match(e.text,/밀려납니다/);
  }
});

const {selectRaceCommentary}=require("../.race-build/commentary.js");
test("1000m race commentary must reach the finish line even with 16 horses",()=>{
  const input=makeTestRace(0,19451);
  input.distanceM=1000;
  input.runners.push(...input.runners.slice(0,4).map((h,i)=>({
    ...h,id:"finish-extra-"+i,name:"완주테스트"+i,number:13+i,gate:13+i,
    horse:{...h.horse},jockey:{...h.jockey},strategies:[...h.strategies]
  })));
  const result=simulateRace(input);
  const commentary=selectRaceCommentary(result.events,70);
  assert.equal(result.distanceM,1000);
  assert.equal(result.sections.at(-1).distanceM,1000);
  assert.equal(result.events.filter(e=>e.eventType==="FINISH").length,16);
  assert.equal(commentary.filter(e=>e.eventType==="FINISH").length,16);
  assert.equal(commentary.at(-1).distanceM,1000);
  assert.ok(commentary.some(e=>e.eventType==="FINISH"&&e.params.rank===1
    &&e.text.includes(result.results[0].name)));
});
test("dense 1000m commentary keeps finish and 200m checkpoints instead of cutting at 800m",()=>{
  const crowd=Array.from({length:180},(_,i)=>({
    seq:i+1,timeSec:i*.4,distanceM:Math.min(980,i*5.4),
    horseId:"race-"+(i%8),eventType:"OVERTAKE",reasonCode:null,
    params:{},importance:2,text:"추월 중계 이벤트 "+i
  }));
  crowd.unshift({seq:0,timeSec:0,distanceM:0,horseId:null,
    eventType:"START",reasonCode:null,params:{},importance:2,text:"출발합니다!"});
  for(let n=200;n<=800;n+=200){
    crowd.push({seq:200+n,timeSec:n/14,distanceM:n,horseId:"race-1",
      eventType:"PACE",reasonCode:"SECTION_LEADER",params:{},importance:2,text:n+"m 선두!"});
  }
  crowd.push({seq:999,timeSec:80,distanceM:1000,horseId:"winner",
    eventType:"FINISH",reasonCode:null,params:{rank:1},importance:3,text:"우승마 결승선 통과!"});
  const shown=selectRaceCommentary(crowd,70);
  assert.equal(shown.length,70);
  assert.ok(shown.some(e=>e.eventType==="FINISH"&&e.distanceM===1000));
  assert.ok(shown.some(e=>e.eventType==="START"));
  for(const checkpoint of [200,400,600,800])
    assert.ok(shown.some(e=>e.reasonCode==="SECTION_LEADER"&&e.distanceM===checkpoint));
  assert.ok(shown.some(e=>e.timeSec>65), "must include events near finish");
});
