import type {RaceInput,RaceEvent,RaceResult,RaceRunner,RunnerState,Strategy,Phase,SectionRank,RaceFinisher} from "./types";

export const RACE_ENGINE_VERSION = "0.1.0";
export const TICK_SECONDS = 0.2;
const EPS=1e-7;
const clamp=(x:number,a:number,b:number)=>Math.max(a,Math.min(b,x));
const rnd=(n:number)=>Math.round(n*1000)/1000;
class Random {
  private value:number;
  constructor(seed:number){this.value=(seed>>>0)||1;}
  next():number{this.value=(Math.imul(1664525,this.value)+1013904223)>>>0;return this.value/4294967296;}
}
const phaseOf=(p:number):Phase=>p<.15?"START":p<.35?"EARLY":p<.65?"MIDDLE":p<.85?"MOVE":"FINAL";
const isFront=(s:Strategy)=>s==="FRONT"||s==="PRESS";
const isLate=(s:Strategy)=>s==="CLOSER"||s==="MOVE";
const ranker=(a:RunnerState,b:RunnerState)=>(b.distanceM-a.distanceM)||(a.number-b.number);
const mean=(a:number,b:number)=>.5*a+.5*b;
function checkStat(v:number,name:string){if(!Number.isFinite(v)||v<0||v>100)throw new Error("Invalid ability: "+name);}
export function validateRace(input:RaceInput):void {
  if(!input||typeof input!=="object")throw new Error("Missing race input");
  if(typeof input.raceId!=="string"||!input.raceId||input.raceId.length>80)throw new Error("Invalid raceId");
  if(!Number.isInteger(input.seed)||input.seed<0||input.seed>2147483647)throw new Error("Invalid seed");
  if(!Number.isInteger(input.distanceM)||input.distanceM<800||input.distanceM>3200)throw new Error("Distance must be 800..3200m");
  if(!Array.isArray(input.runners)||input.runners.length<2||input.runners.length>16)throw new Error("Race requires 2..16 horses");
  if(input.trackFactor!==undefined&&(!Number.isFinite(input.trackFactor)||input.trackFactor<.75||input.trackFactor>1.1))throw new Error("Invalid track factor");
  const ids=new Set<string>(), numbers=new Set<number>(), gates=new Set<number>();
  for(const r of input.runners){
    if(typeof r.id!=="string"||!r.id||r.id.length>80||ids.has(r.id))throw new Error("Invalid or duplicate horse ID");
    ids.add(r.id);
    if(!Number.isInteger(r.number)||r.number<1||r.number>99||numbers.has(r.number))throw new Error("Invalid or duplicate horse number");
    numbers.add(r.number);
    if(!Number.isInteger(r.gate)||r.gate<1||r.gate>16||gates.has(r.gate))throw new Error("Invalid or duplicate gate");
    gates.add(r.gate);
    if(typeof r.name!=="string"||!r.name.trim()||r.name.length>60)throw new Error("Invalid horse name");
    if(!Array.isArray(r.strategies)||r.strategies.length<1||r.strategies.length>3||r.strategies.some(s=>!["FRONT","PRESS","SAVE","MOVE","CLOSER","FREE"].includes(s)))throw new Error("Invalid strategies");
    for(const [k,v] of Object.entries(r.horse||{}))checkStat(v,"horse."+k);
    for(const [k,v] of Object.entries(r.jockey||{}))checkStat(v,"jockey."+k);
    for(const k of ["start","speed","acceleration","stamina","finishing","power","grit","stability","recovery"]){if(!(k in (r.horse||{})))throw new Error("Missing horse ability "+k);}
    for(const k of ["start","positioning","pace","judgment","urging","control","aggression","stability"]){if(!(k in (r.jockey||{})))throw new Error("Missing jockey ability "+k);}
    for(const [k,v] of Object.entries({condition:r.condition,fatigue:r.fatigue,distanceFit:r.distanceFit??75,trainerReadiness:r.trainerReadiness??75}))checkStat(v,k);
    if(!Number.isFinite(r.weightKg)||r.weightKg<45||r.weightKg>65)throw new Error("Invalid weight");
    if(r.lane!==undefined&&(!Number.isInteger(r.lane)||r.lane<1||r.lane>6))throw new Error("Invalid lane");
  }
}
function initialState(r:RaceRunner,rng:Random):RunnerState{
  const reaction=.06+(.35*(100-r.horse.start)/100)+(.12*(100-r.jockey.start)/100)+rng.next()*.1;
  return {id:r.id,number:r.number,name:r.name,distanceM:-reaction*3,speedMps:3.5+r.horse.start*.035,
    stamina:100,lane:r.lane??clamp(Math.ceil(r.gate/2),1,6),strategy:r.strategies[0],
    strategyIndex:0,elapsedSec:0,rank:0,blocked:false,finishedAt:null};
}
function strategyScore(strategy:Strategy,r:RaceRunner,st:RunnerState,phase:Phase,frontPressure:number,blocked:boolean):number{
  const p=r.horse,j=r.jockey;
  const lowStamina=st.stamina<38;
  switch(strategy){
    case "FRONT":return 50+p.start*.16+p.speed*.13+j.aggression*.08-(frontPressure*34)-(lowStamina?22:0)+(phase==="START"?16:0);
    case "PRESS":return 48+p.speed*.14+j.positioning*.14-(frontPressure*15)+(st.rank>5?4:0);
    case "SAVE":return 48+p.stamina*.18+j.pace*.14+(blocked?-9:6)+(phase==="MIDDLE"?9:0);
    case "MOVE":return 41+p.acceleration*.18+j.judgment*.11+(phase==="MOVE"?26:-9)-(lowStamina?20:0);
    case "CLOSER":return 43+p.finishing*.19+j.urging*.09+(phase==="FINAL"?25:-7)-(lowStamina?15:0);
    case "FREE":return 52+j.judgment*.22+j.pace*.09+(blocked?5:0);
  }
}
function decide(r:RaceRunner,st:RunnerState,phase:Phase,frontPressure:number,blocked:boolean,time:number,rng:Random,lastSwitch:number){
  const list=r.strategies;
  const currentScore=strategyScore(st.strategy,r,st,phase,frontPressure,blocked);
  let best={index:st.strategyIndex,score:currentScore},reason="";
  if(time-lastSwitch<4||time<5||list.length===1)return {index:st.strategyIndex,reason};
  // Jockey ability changes decision reliability, not the underlying horse physics.
  for(let i=0;i<list.length;i++){
    const error=(rng.next()-.5)*(22-r.jockey.judgment*.14);
    const score=strategyScore(list[i],r,st,phase,frontPressure,blocked)+error;
    if(score>best.score+10)best={index:i,score};
  }
  if(best.index!==st.strategyIndex){
    reason=blocked?"INSIDE_BLOCKED":frontPressure>.65?"PACE_TOO_FAST":phase==="FINAL"?"FINAL_CHARGE":
           phase==="MOVE"?"MOVE_OPPORTUNITY":st.stamina<38?"LOW_STAMINA":"BETTER_POSITION";
  }
  return {index:best.index,reason};
}
function physicalLane(r:RaceRunner,st:RunnerState,wanted:Strategy,live:RunnerState[],rng:Random){
  let target=st.lane;
  if(wanted==="SAVE")target=1;
  if(wanted==="FRONT")target=Math.min(st.lane,2);
  if(wanted==="MOVE"||wanted==="CLOSER")target=Math.min(6,Math.max(3,st.lane+1));
  if(wanted==="FREE")target=st.lane;
  if(wanted==="PRESS")target=st.lane<=2?2:3;
  if(target===st.lane)return st.lane;
  const candidate=st.lane+Math.sign(target-st.lane);
  const occupied=live.some(o=>o.id!==st.id&&o.finishedAt===null&&o.lane===candidate&&Math.abs(o.distanceM-st.distanceM)<4.2);
  const success=!occupied&&rng.next()<(0.58+r.jockey.positioning*.0035);
  return success?candidate:st.lane;
}
function blockedBy(st:RunnerState,others:RunnerState[]){
  return others.some(o=>o.id!==st.id&&o.finishedAt===null&&o.lane===st.lane&&o.distanceM>st.distanceM&&o.distanceM-st.distanceM<5.2);
}
function targetSpeed(r:RaceRunner,st:RunnerState,phase:Phase,pressure:number,blocked:boolean,trackFactor:number):number{
  const h=r.horse,j=r.jockey;
  const speedStat=.68*h.speed+.2*h.power+.12*h.acceleration;
  const baseSpeed=14.45+(speedStat-50)*.065;
  const fitness=clamp(.88+r.condition*.00135-(r.fatigue*.0007)+(r.trainerReadiness??75)*.0004,.85,1.09);
  const staminaFactor=st.stamina>=40?1:clamp(.7+(st.stamina/40)*.3,.70,1);
  const distanceFactor=clamp(.90+(r.distanceFit??75)*.0013,.9,1.03);
  const strategy=st.strategy;
  let strategyFactor=1;
  if(isFront(strategy))strategyFactor=phase==="EARLY"||phase==="START"?1.055:phase==="FINAL"?.99:1.015;
  if(strategy==="SAVE")strategyFactor=phase==="FINAL"?1.02:.978;
  if(strategy==="MOVE")strategyFactor=phase==="MOVE"?1.09:phase==="FINAL"?1.03:.965;
  if(strategy==="CLOSER")strategyFactor=phase==="FINAL"?1.095:phase==="MOVE"?1.025:.96;
  const phaseFactor=phase==="START"?.83:phase==="FINAL"?1+(h.finishing-50)*.0019+(h.grit-50)*.001:1;
  const jockeyFactor=1+(j.pace-50)*.00065+(phase==="FINAL"?(j.urging-50)*.0008:0);
  const pressurePenalty=isFront(strategy)?Math.max(0,pressure-.5)*.045:0;
  const lanePenalty=(st.lane-1)*.0025;
  const blockedFactor=blocked?.88:1;
  const weightFactor=clamp(1-(r.weightKg-54)*.005,.93,1.055);
  return clamp(baseSpeed*fitness*staminaFactor*distanceFactor*strategyFactor*phaseFactor*jockeyFactor*weightFactor*
    (trackFactor??1)*(1-pressurePenalty-lanePenalty)*blockedFactor,7,21.7);
}
function staminaCost(r:RaceRunner,st:RunnerState,phase:Phase,pressure:number,dt:number){
  const h=r.horse;
  const effort=st.strategy==="FRONT"?1.35:st.strategy==="PRESS"?1.13:st.strategy==="MOVE"&&phase==="MOVE"?1.58:
    st.strategy==="CLOSER"&&phase==="FINAL"?1.55:st.strategy==="SAVE"?.81:1;
  const pressureCost=isFront(st.strategy)?pressure*.21:0;
  const endurance=clamp(1.20-h.stamina*.0045,.75,1.2);
  const stretch=phase==="FINAL"?1.1:1;
  return dt*(.46+st.speedMps*.014)*(effort+pressureCost)*endurance*stretch*
    (1+(r.weightKg-54)*.008);
}
const copy=(s:RunnerState):RunnerState=>({...s});
export function simulateRace(input:RaceInput):RaceResult {
  validateRace(input);
  const runners=[...input.runners].sort((a,b)=>a.number-b.number);
  const byId=new Map(runners.map(r=>[r.id,r]));
  const rng=new Random(input.seed);
  let states=runners.map(r=>initialState(r,rng));
  let events:RaceEvent[]=[], sections:SectionRank[]=[];
  const event=(time:number,distance:number,horseId:string|null,eventType:RaceEvent["eventType"],reason:string|null,params:RaceEvent["params"],importance:number,text:string)=>{
    if(events.length>=620&&eventType!=="FINISH")return;
    events.push({seq:events.length+1,timeSec:rnd(time),distanceM:rnd(Math.max(0,distance)),horseId,eventType,reasonCode:reason,params,importance,text});
  };
  const lastSwitch=new Map(runners.map(r=>[r.id,0]));
  let elapsed=0, nextSection=200, lastPressureBand="";
  const startNames=states.map(s=>s.name).join(", ");
  event(0,0,null,"START",null,{runnerCount:runners.length},2,"출발! "+runners.length+"두가 경주를 시작합니다.");
  const maxTicks=Math.ceil(300/TICK_SECONDS);
  for(let tick=0;tick<maxTicks;tick++){
    const snapshot=states.map(copy);
    const active=snapshot.filter(s=>s.finishedAt===null);
    if(active.length===0)break;
    const ranks=[...snapshot].sort(ranker);
    ranks.forEach((s,i)=>{snapshot.find(q=>q.id===s.id)!.rank=i+1});
    const leaderDistance=Math.max(...active.map(s=>s.distanceM));
    const leaders=active.filter(s=>s.distanceM>=leaderDistance-15);
    const frontCount=leaders.filter(s=>isFront(s.strategy)).length;
    const frontPressure=clamp(Math.max(0,frontCount-1)/4,0,1);
    const band=frontPressure>.65?"FAST":frontPressure<.2?"SLOW":"NORMAL";
    if(band!==lastPressureBand&&(tick===0||tick%25===0)){
      event(elapsed,leaderDistance,null,"PACE",band,{frontPressure:rnd(frontPressure)},1,
        band==="FAST"?"선행 경쟁이 과열되고 있습니다.":band==="SLOW"?"선두권이 느린 페이스로 진행합니다.":"경주 페이스가 보통 수준입니다.");
      lastPressureBand=band;
    }
    const next:RunnerState[]=[];
    for(const st of snapshot){
      if(st.finishedAt!==null){next.push(st);continue;}
      const runner=byId.get(st.id)!;
      const progress=clamp(st.distanceM/input.distanceM,0,1);
      const phase=phaseOf(progress);
      const blocked=blockedBy(st,snapshot);
      const decision=decide(runner,st,phase,frontPressure,blocked,elapsed,rng,lastSwitch.get(st.id)!);
      const ns=copy(st);
      if(decision.index!==st.strategyIndex){
        ns.strategyIndex=decision.index;
        ns.strategy=runner.strategies[decision.index];
        lastSwitch.set(st.id,elapsed);
        event(elapsed,st.distanceM,st.id,"STRATEGY_SWITCH",decision.reason,
          {from:st.strategy,to:ns.strategy,fromPlan:st.strategyIndex+1,toPlan:decision.index+1},2,
          st.number+"번 "+st.name+"의 기수가 "+(st.strategyIndex+1)+"안에서 "+(decision.index+1)+"안으로 전략을 전환합니다.");
      }
      ns.lane=physicalLane(runner,st,ns.strategy,snapshot,rng);
      if(ns.lane!==st.lane&&tick%3===0)event(elapsed,st.distanceM,st.id,"LANE_CHANGE",null,{fromLane:st.lane,toLane:ns.lane},1,st.number+"번 "+st.name+"이(가) "+ns.lane+"번 진로로 이동했습니다.");
      if(blocked&&!st.blocked)event(elapsed,st.distanceM,st.id,"BLOCKED","INSIDE_BLOCKED",{lane:st.lane},1,st.number+"번 "+st.name+"의 앞길이 막힙니다.");
      if(phase==="MOVE"&&ns.strategy==="MOVE"&&st.strategy!=="MOVE")event(elapsed,st.distanceM,st.id,"MOVE","MOVE_OPPORTUNITY",{},1,st.number+"번 "+st.name+"이(가) 승부수를 시작합니다.");
      if(phase==="FINAL"&&ns.strategy==="CLOSER"&&st.distanceM<input.distanceM*.85)event(elapsed,st.distanceM,st.id,"FINAL_CHARGE",null,{},2,st.number+"번 "+st.name+"이(가) 마지막 추입을 시작합니다.");
      const desired=targetSpeed(runner,ns,phase,frontPressure,blocked,input.trackFactor??1);
      const acceleration=.48+runner.horse.acceleration*.011+(phase==="START"?runner.horse.start*.004:0);
      const stepSpeed=clamp(desired-ns.speedMps,-(1.45+runner.horse.stability*.004)*TICK_SECONDS,acceleration*TICK_SECONDS);
      ns.speedMps=clamp(ns.speedMps+stepSpeed,3.0,22);
      const distanceDelta=ns.speedMps*TICK_SECONDS;
      ns.distanceM+=distanceDelta;
      ns.stamina=clamp(st.stamina-staminaCost(runner,ns,phase,frontPressure,TICK_SECONDS),0,100);
      ns.blocked=blocked;
      ns.elapsedSec=elapsed+TICK_SECONDS;
      if(ns.distanceM>=input.distanceM-EPS){
        const fraction=clamp((input.distanceM-st.distanceM)/Math.max(EPS,ns.distanceM-st.distanceM),0,1);
        ns.finishedAt=elapsed+TICK_SECONDS*fraction;
        ns.distanceM=input.distanceM;
        event(ns.finishedAt,input.distanceM,st.id,"FINISH",null,{timeSec:rnd(ns.finishedAt)},3,
          st.number+"번 "+st.name+" 결승선 통과! "+ns.finishedAt.toFixed(2)+"초");
      }
      next.push(ns);
    }
    const newOrder=[...next].sort(ranker).filter(s=>s.finishedAt===null);
    for(const st of next){
      if(st.finishedAt!==null)continue;
      const oldRank=ranks.findIndex(s=>s.id===st.id);
      const newRank=newOrder.findIndex(s=>s.id===st.id);
      if(oldRank>=0&&newRank>=0&&newRank<oldRank&&tick%4===0){
        const overtaken=ranks[Math.max(0,oldRank-1)];
        event(elapsed+TICK_SECONDS,st.distanceM,st.id,"OVERTAKE",null,
          {previousRank:oldRank+1,currentRank:newRank+1,targetHorseId:overtaken.id},2,
          st.number+"번 "+st.name+"이(가) "+(oldRank+1)+"위에서 "+(newRank+1)+"위로 올라갑니다.");
      }
    }
    states=next;
    elapsed+=TICK_SECONDS;
    while(nextSection<=input.distanceM&&Math.max(...states.map(s=>s.distanceM))>=nextSection-EPS){
      const standings=[...states].sort((a,b)=>{
        const da=Math.min(nextSection,a.distanceM),db=Math.min(nextSection,b.distanceM);
        if(Math.abs(db-da)>EPS)return db-da;
        if(a.finishedAt!==null&&b.finishedAt!==null)return a.finishedAt-b.finishedAt;
        return a.number-b.number;
      });
      const maxPos=Math.max(...states.map(s=>Math.min(nextSection,s.distanceM)));
      const result:SectionRank={distanceM:nextSection,ranks:standings.map((st,i)=>({
        horseId:st.id,number:st.number,name:st.name,rank:i+1,
        gapM:rnd(Math.max(0,maxPos-Math.min(nextSection,st.distanceM))),strategy:st.strategy
      }))};
      sections.push(result);
      nextSection+=200;
    }
  }
  if(states.some(s=>s.finishedAt===null))throw new Error("Race exceeded maximum simulated duration");
  const finishers=[...states].sort((a,b)=>a.finishedAt!-b.finishedAt!||a.number-b.number);
  const results:RaceFinisher[]=finishers.map((s,i)=>({
    horseId:s.id,number:s.number,name:s.name,rank:i+1,timeSec:rnd(s.finishedAt!),
    finalStamina:rnd(s.stamina),strategy:s.strategy
  }));
  // Events are sorted by physical event time, then renumbered for replay.
  events.sort((a,b)=>a.timeSec-b.timeSec||a.seq-b.seq);
  events.forEach((e,i)=>e.seq=i+1);
  return {version:RACE_ENGINE_VERSION,raceId:input.raceId,track:input.track,distanceM:input.distanceM,
    seed:input.seed,durationSec:rnd(Math.max(...results.map(x=>x.timeSec))),results,sections,events,
    tickSeconds:TICK_SECONDS,simulated:true};
}
