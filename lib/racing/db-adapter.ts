import type {HorseAbilities,JockeyAbilities,RaceInput,RaceRunner,Strategy} from "./types";

type RecordLike=Record<string,unknown>;
const isObject=(v:unknown):v is RecordLike=>v!==null&&typeof v==="object"&&!Array.isArray(v);
function object(v:unknown,label:string):RecordLike{if(!isObject(v))throw new Error(label+" is missing or invalid");return v;}
function positive(v:unknown,label:string){if(typeof v!=="number"||!Number.isFinite(v)||v<0||v>100)throw new Error(label+" must be a number 0..100");return v;}
function toNumber(v:unknown,label:string){const n=typeof v==="number"?v:Number(v);if(!Number.isFinite(n))throw new Error("Invalid "+label);return n;}
const HORSE_KEYS=["start","speed","acceleration","stamina","finishing","power","grit","stability","recovery"] as const;
const JOCKEY_KEYS=["start","positioning","pace","judgment","urging","control","aggression","stability"] as const;
export function readHorseStats(value:unknown):HorseAbilities{
 const data=object(value,"horse current_stats");
 return Object.fromEntries(HORSE_KEYS.map(k=>[k,positive(data[k],"horse."+k)])) as unknown as HorseAbilities;
}
export function readJockeyStats(value:unknown):JockeyAbilities{
 const data=object(value,"jockey skill_stats");
 return Object.fromEntries(JOCKEY_KEYS.map(k=>[k,positive(data[k],"jockey."+k)])) as unknown as JockeyAbilities;
}
const MAP:Record<string,Strategy>={
 FRONT:"FRONT",LEAD:"FRONT",FRONT_ESCAPE:"FRONT",ESCAPE:"FRONT",
 PRESS:"PRESS",PRESSING:"PRESS",FRONT_PRESS:"PRESS",OUTSIDE_PRESS:"PRESS",
 SAVE:"SAVE",INSIDE_SAVE:"SAVE",INSIDE:"SAVE",
 MOVE:"MOVE",MID_MOVE:"MOVE",CORNER_MOVE:"MOVE",OUTSIDE_MOVE:"MOVE",
 CLOSER:"CLOSER",CLOSE:"CLOSER",LATE:"CLOSER",
 FREE:"FREE",JOCKEY:"FREE",JOCKEY_DECISION:"FREE"
};
export function readStrategies(plans:{plan_no:number;strategy_code:string}[]):Strategy[]{
 const ordered=[...plans].sort((a,b)=>a.plan_no-b.plan_no);
 if(ordered.length===0)return ["FREE"];
 if(ordered.length>3)throw new Error("Maximum 3 race strategies");
 return ordered.map(p=>{const val=MAP[p.strategy_code];if(!val)throw new Error("Unsupported strategy "+p.strategy_code);return val;});
}
export interface DbRaceRow { id:string; track:string; distance_m:number; status:string; }
export interface DbEntryRow {
 id:string;horse_id:string;owner_user_id:string|null;jockey_id:string|null;
 gate_no:number|null;weight_kg:number|null;status:string;snapshot:unknown;
}
export interface DbHorseRow {id:string;name:string;condition_score:number;fatigue:number;life_stage:string;racing_retired_permanently:boolean;breeding_retired_at?:string|null;}
export interface DbAbilityRow {horse_id:string;current_stats:unknown;distance_affinity?:unknown;}
export interface DbJockeyRow {id:string;skill_stats:unknown;}
export interface DbStrategyRow {race_entry_id:string;plan_no:number;strategy_code:string;}
export function makeRaceInputFromDatabase(params:{
 race:DbRaceRow;entries:DbEntryRow[];horses:DbHorseRow[];
 abilities:DbAbilityRow[];jockeys:DbJockeyRow[];strategies:DbStrategyRow[];
 seed:number
}):RaceInput{
 const {race,entries,horses,abilities,jockeys,strategies,seed}=params;
 if(race.status!=="CLOSED"&&race.status!=="FINISHED")throw new Error("Race must be closed before preview");
 if(entries.length<2||entries.length>12)throw new Error("Need 2..12 confirmed runners");
 const out:RaceRunner[]=entries.map((entry,i)=>{
   const h=horses.find(h=>h.id===entry.horse_id);
   const a=abilities.find(a=>a.horse_id===entry.horse_id);
   const j=jockeys.find(j=>j.id===entry.jockey_id);
   if(!h||!a||!j||!entry.jockey_id)throw new Error("Missing horse, abilities or jockey for entry "+entry.id);
   if(h.life_stage!==undefined&&h.life_stage!=="RACING"||h.racing_retired_permanently===true||h.breeding_retired_at!=null)throw new Error("BREEDING_RETIREMENT_PERMANENT: 은퇴·번식마는 경주에 출전할 수 없습니다: "+h.name);
   if(h.life_stage!=="RACING"||h.racing_retired_permanently)throw new Error("RACE_ENTRY_NOT_ELIGIBLE: retired breeding horses cannot race ("+h.name+")");
   if(entry.gate_no===null||entry.weight_kg===null)throw new Error("Missing confirmed gate or weight for "+h.name);
   const snap=isObject(entry.snapshot)?entry.snapshot:{};
   const distanceFitRaw=isObject(a.distance_affinity)?a.distance_affinity[String(race.distance_m)]:undefined;
   const trainerReadyRaw=snap.trainerReadiness;
   const snapshotHorse=snap.horse;
   const snapshotJockey=snap.jockey;
   return {
     id:entry.horse_id,number:i+1,name:h.name,gate:entry.gate_no,
     horse:readHorseStats(snapshotHorse??a.current_stats),
     jockey:readJockeyStats(snapshotJockey??j.skill_stats),
     strategies:readStrategies(strategies.filter(p=>p.race_entry_id===entry.id)),
     condition:toNumber(snap.condition??h.condition_score,"condition"),
     fatigue:toNumber(snap.fatigue??h.fatigue,"fatigue"),
     weightKg:toNumber(entry.weight_kg,"weight"),
     distanceFit:distanceFitRaw===undefined?75:toNumber(distanceFitRaw,"distance fit"),
     trainerReadiness:trainerReadyRaw===undefined?75:toNumber(trainerReadyRaw,"trainer readiness")
   };
 });
 return {raceId:race.id,track:race.track,distanceM:race.distance_m,seed,runners:out};
}
