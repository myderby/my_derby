const test=require("node:test");
const assert=require("node:assert/strict");
const {expandOmr}=require("../lib/racing/omr.cjs");
const box=(type,rows)=>expandOmr(type,rows,["1","2","3","4","5","6","7"]);
const asText=arr=>arr.map(x=>x.join("-")).sort();
test("WIN and PLACE row one create a ticket per selected horse",()=>{
 assert.deepEqual(asText(box("WIN",[["1","4","6"]])),["1","4","6"]);
 assert.deepEqual(asText(box("PLACE",[["2","4"]])),["2","4"]);
});
test("QUINELLA same row 1/4/6 gives exactly three unordered pairs",()=>{
 assert.deepEqual(asText(box("QUINELLA",[["1","4","6"],[]])),["1-4","1-6","4-6"]);
});
test("QUINELLA two rows 2,4 / 3,5 gives all four cross combinations",()=>{
 assert.deepEqual(asText(box("QUINELLA",[["2","4"],["3","5"]])),["2-3","2-5","3-4","4-5"]);
});
test("QUINELLA_PLACE shares unordered cross or box rules",()=>{
 assert.equal(box("QUINELLA_PLACE",[["1","4","6"],[]]).length,3);
 assert.equal(box("QUINELLA_PLACE",[["2","4"],["3","5"]]).length,4);
});
test("EXACTA one row 1/4/6 generates six ordered permutations",()=>{
 assert.deepEqual(asText(box("EXACTA",[["1","4","6"]])),
  ["1-4","1-6","4-1","4-6","6-1","6-4"]);
});
test("EXACTA first row 1,2 / second 3,4 yields four directional pairs",()=>{
 assert.deepEqual(asText(box("EXACTA",[["1","2"],["3","4"]])),
  ["1-3","1-4","2-3","2-4"]);
});
test("TRIO first row 3/4/5/6 generates four unordered triples",()=>{
 assert.deepEqual(asText(box("TRIO",[["3","4","5","6"]])),
  ["3-4-5","3-4-6","3-5-6","4-5-6"]);
});
test("TRIO first row 3 / second row 4/5/6 generates three triples",()=>{
 assert.deepEqual(asText(box("TRIO",[["3"],["4","5","6"]])),
  ["3-4-5","3-4-6","3-5-6"]);
});
test("TRIO rows 3,4 / 5,6 / 7 generate four triples",()=>{
 assert.deepEqual(asText(box("TRIO",[["3","4"],["5","6"],["7"]])),
  ["3-5-7","3-6-7","4-5-7","4-6-7"]);
});
test("TRIFECTA one row 3/4/5 creates six ordered triples",()=>{
 assert.equal(box("TRIFECTA",[["3","4","5"]]).length,6);
});
test("TRIFECTA two rows 3 / 4,5,6 requires ordered second and third",()=>{
 assert.equal(box("TRIFECTA",[["3"],["4","5","6"]]).length,6);
});
test("TRIFECTA three lines generates directional Cartesian products",()=>{
 assert.deepEqual(asText(box("TRIFECTA",[["3","4"],["5","6"],["7"]])),
 ["3-5-7","3-6-7","4-5-7","4-6-7"]);
});
test("overlapping box rows never buy a horse against itself or duplicate unordered ticket",()=>{
 assert.deepEqual(asText(box("QUINELLA",[["1","2"],["2","3"]])),["1-2","1-3","2-3"]);
 assert.deepEqual(asText(box("TRIO",[["1","2"],["2","3"],["3","4"]])),["1-2-3","1-2-4","1-3-4","2-3-4"]);
 assert.equal(box("EXACTA",[["1"],["1"]]).length,0);
});
test("empty intermediate row is not silently collapsed into another leg",()=>{
 assert.deepEqual(box("TRIO",[["1"],[],["3"]]),[]);
});
