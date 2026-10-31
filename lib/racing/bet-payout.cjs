"use strict";

/**
 * An approximate, pre-purchase win payout based on actual stakes already in
 * this wager-type pool, plus the prospective purchase.
 *
 * Every payout is backed only by this wager type's pool; AI odds are excluded.
 * PLACE and QUINELLA_PLACE may have multiple winning selections, so this
 * calculation is an upper bound if the selected ticket wins.
 */
function estimatePayout({pool, combinationPool, stake}) {
  const total=Number(pool);
  const selected=Number(combinationPool);
  const wager=Number(stake);
  if (![total,selected,wager].every(Number.isSafeInteger)) return null;
  if (total<0 || selected<0 || selected>total || wager<100 || wager>10000) return null;
  const projectedPool=total+wager;
  const projectedCombination=selected+wager;
  if (!Number.isSafeInteger(projectedPool)||!Number.isSafeInteger(projectedCombination)) return null;
  const distributable=Math.floor(projectedPool*0.9);
  const estimatedRefund=Math.floor((distributable*wager)/projectedCombination);
  if (!Number.isSafeInteger(estimatedRefund)) return null;
  return {estimatedRefund,estimatedOdds:estimatedRefund/wager};
}

module.exports={estimatePayout};
