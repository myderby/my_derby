const test=require("node:test");
const assert=require("node:assert/strict");
const {formatRaceTime}=require("../lib/racing/format-race-time.cjs");
test("1000m result: 72.4 seconds -> 1 minute 12.40 seconds",()=>{
 assert.equal(formatRaceTime(72.4),"1분 12.40초");
});
test("race result just above 2 minutes",()=>{
 assert.equal(formatRaceTime(128.765),"2분 08.77초");
});
test("59.999 crosses minute boundary after rounding",()=>{
 assert.equal(formatRaceTime(59.999),"1분 00.00초");
});
test("replay at 10ths of seconds",()=>{
 assert.equal(formatRaceTime(65.04,1),"1분 05.0초");
});
test("no time does not create fictional recorded 0 seconds",()=>{
 for(const v of [null,undefined,"",-1,Number.NaN,Number.POSITIVE_INFINITY])assert.equal(formatRaceTime(v),"—");
});
test("0 seconds valid elapsed time",()=>{
 assert.equal(formatRaceTime(0),"0분 00.00초");
});
