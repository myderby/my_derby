const test=require("node:test");
const assert=require("node:assert/strict");
const {estimatePayout}=require("../lib/racing/bet-payout.cjs");

test("pre-purchase quote includes new wager in total pool and chosen combination",()=>{
  const q=estimatePayout({pool:100000,combinationPool:10000,stake:1000});
  assert.deepEqual(q,{estimatedRefund:8263,estimatedOdds:8.263});
});
test("only buyer in pool pays out 90% of its own stake, never fabricates odds",()=>{
  assert.deepEqual(estimatePayout({pool:0,combinationPool:0,stake:1000}),
    {estimatedRefund:900,estimatedOdds:0.9});
});
test("when all previous wagers target same combination, applies exactly 90% takeout",()=>{
  assert.deepEqual(estimatePayout({pool:9000,combinationPool:9000,stake:1000}),
    {estimatedRefund:900,estimatedOdds:0.9});
});
test("stake change recalculates refund dynamically",()=>{
  const before=estimatePayout({pool:5000,combinationPool:1000,stake:100});
  const after=estimatePayout({pool:5000,combinationPool:1000,stake:1000});
  assert.ok(after.estimatedRefund>before.estimatedRefund);
});
test("rounding uses integer gold units and preview never exceeds pool budget",()=>{
  const q=estimatePayout({pool:100,combinationPool:1,stake:101});
  assert.equal(q.estimatedRefund,178);
  assert.ok(q.estimatedRefund<=Math.floor(201*0.9));
});
test("invalid stakes and mismatched pools never produce a displayed refund",()=>{
  for (const args of [
    {pool:0,combinationPool:0,stake:0},
    {pool:0,combinationPool:0,stake:99},
    {pool:100,combinationPool:101,stake:100},
    {pool:-1,combinationPool:0,stake:100},
    {pool:100,combinationPool:0,stake:100.5},
    {pool:NaN,combinationPool:0,stake:100}
  ]) assert.equal(estimatePayout(args),null);
});
