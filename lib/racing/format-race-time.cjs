"use strict";

/**
 * Race clock displayed in Korean minute/second notation.
 * Rounds in integer sub-second units first so 59.999s becomes 1m 00.00s.
 * Non-numeric or negative time values are intentionally not fabricated.
 */
function formatRaceTime(seconds, precision=2){
 if(seconds===null||seconds===undefined||seconds==="")return "—";
 const value=Number(seconds);
 if(!Number.isFinite(value)||value<0||!Number.isInteger(precision)||precision<0||precision>3)return "—";
 const scale=10**precision;
 const units=Math.round(value*scale);
 const min=Math.floor(units/(60*scale));
 const rest=(units-min*60*scale)/scale;
 return `${min}분 ${rest.toFixed(precision).padStart(precision===0?2:precision+3,"0")}초`;
}
module.exports={formatRaceTime};
