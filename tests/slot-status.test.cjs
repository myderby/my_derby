const test = require("node:test");
const assert = require("node:assert/strict");
const {officialSlotSummaries,officialRaceHour,summarizeOfficialSlot} =
  require("../.race-build/slot-status.js");
const race=(time,status)=>({start_time:time,status});

test("official home always has exactly three ordered 19/20/21 cards",()=>{
 const slots=officialSlotSummaries([]);
 assert.deepEqual(slots.map(s=>s.hour),["19","20","21"]);
 assert.deepEqual(slots.map(s=>s.label),["경주 없음","경주 없음","경주 없음"]);
});
test("official race slots honor actual starts, not arbitrary source hour",()=>{
 assert.equal(officialRaceHour({start_time:"19:45:00"}),"19");
 assert.equal(officialRaceHour({time:"20:48"}),"20");
 assert.equal(officialRaceHour({time:"21:00"}),"21");
 assert.equal(officialRaceHour({time:"17:00"}),null);
});
test("a slot with all OPEN races is 예정 even after a cancellation",()=>{
 const s=summarizeOfficialSlot([
  race("19:00","OPEN"),race("19:03","CANCELLED"),race("20:00","FINISHED")],"19");
 assert.equal(s.label,"예정");
 assert.equal(s.total,2);
 assert.equal(s.completed,1);
});
test("CLOSED, RUNNING and some FINISHED with pending races are 진행중",()=>{
 for(const status of ["CLOSED","RUNNING","FINISHED"]){
  const s=summarizeOfficialSlot([race("19:00",status),race("19:03","OPEN")],"19");
  assert.equal(s.label,"진행중",status);
 }
});
test("all official races FINISHED -> 종료; cancelled also terminal",()=>{
 const s=summarizeOfficialSlot([
  race("19:00","FINISHED"),race("19:03","FINISHED"),
  race("19:06","CANCELLED"),race("20:00","RUNNING")],"19");
 assert.equal(s.label,"종료");
 assert.equal(s.finished,2);
 assert.equal(s.completed,3);
 assert.equal(s.firstStart,"19:00");
 assert.equal(s.lastStart,"19:06");
 assert.equal(s.total,3);
});
test("a multi-hour game day gives three independent statuses",()=>{
 const slots=officialSlotSummaries([
  race("19:00","FINISHED"),race("19:03","FINISHED"),
  race("20:00","FINISHED"),race("20:03","OPEN"),
  race("21:00","OPEN"),race("21:03","OPEN")]);
 assert.deepEqual(slots.map(x=>x.label),["종료","진행중","예정"]);
});
