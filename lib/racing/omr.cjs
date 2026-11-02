"use strict";

/** Expand numbered OMR rows into individual per-combination tickets.
 * Row 1 alone: box (all combinations from row 1).
 * 2-leg: row1 x row2; for triples with 2 rows: row1 x choose-two(row2).
 * 3-leg: row1 x row2 x row3. Ordered tickets retain permutations.
 * Empty intermediate rows do not implicitly shift picks into a different leg.
 */
const BET_TYPES={
 WIN:{legs:1,ordered:true}, PLACE:{legs:1,ordered:true},
 QUINELLA:{legs:2,ordered:false}, QUINELLA_PLACE:{legs:2,ordered:false},
 EXACTA:{legs:2,ordered:true},TRIO:{legs:3,ordered:false},TRIFECTA:{legs:3,ordered:true}
};
function expandOmr(type, rows, order=[]){
 const rule=BET_TYPES[type];
 if(!rule||!Array.isArray(rows))return [];
 const clean=Array.from({length:rule.legs},(_,i)=>
   Array.isArray(rows[i])?[...new Set(rows[i].filter(x=>typeof x==="string"&&x))]:[]);
 if(!clean[0].length)return [];
 let active=1;
 while(active<rule.legs&&clean[active].length)active++;
 if(clean.slice(active).some(x=>x.length))return [];
 const ordered=rule.ordered;
 const candidates=[];
 if(rule.legs===1)for(const a of clean[0])candidates.push([a]);
 else if(rule.legs===2){
  if(active===1){
   for(let i=0;i<clean[0].length;i++)for(let j=0;j<clean[0].length;j++)
    if(i!==j&&(ordered||j>i))candidates.push([clean[0][i],clean[0][j]]);
  }else for(const a of clean[0])for(const b of clean[1])candidates.push([a,b]);
 }else if(active===1){
  const a=clean[0];
  for(let i=0;i<a.length;i++)for(let j=0;j<a.length;j++)for(let k=0;k<a.length;k++)
   if(i!==j&&i!==k&&j!==k&&(ordered||(i<j&&j<k)))
     candidates.push([a[i],a[j],a[k]]);
 }else if(active===2){
  for(const a of clean[0])for(let j=0;j<clean[1].length;j++)
   for(let k=0;k<clean[1].length;k++)
    if(j!==k&&(ordered||j<k))candidates.push([a,clean[1][j],clean[1][k]]);
 }else{
  for(const a of clean[0])for(const b of clean[1])for(const c of clean[2])
    candidates.push([a,b,c]);
 }
 const dedup=new Map();
 for(const picks of candidates){
   if(new Set(picks).size!==rule.legs)continue;
   const canonical=ordered?picks:[...picks].sort((a,b)=>{
     const ai=order.indexOf(a),bi=order.indexOf(b);
     return ai>=0&&bi>=0?ai-bi:a.localeCompare(b);
   });
   const key=canonical.join(":");
   if(!dedup.has(key))dedup.set(key,canonical);
 }
 return [...dedup.values()];
}
module.exports={expandOmr,BET_TYPES};
