import type {RaceInput, RaceRunner, Strategy} from "./types";
export const TEST_SLOTS=[
  {time:"19:00",track:"서울",distanceM:1200,grade:"6등급"},
  {time:"20:00",track:"부경",distanceM:1400,grade:"5등급"},
  {time:"21:00",track:"영천",distanceM:1600,grade:"4등급"},
] as const;
const names=["가을바람","골든레이스","블루라이트","실버윈드","레드스타","블랙스톰",
  "노던퀸","새벽별","그린문","다크호프","스피드링","원더레이스"];
const patterns:Strategy[][]=[
 ["FRONT","PRESS","SAVE"],["PRESS","MOVE","CLOSER"],["SAVE","CLOSER","FREE"],["FRONT","SAVE","PRESS"],
 ["CLOSER","MOVE","PRESS"],["PRESS","SAVE","MOVE"],["FRONT","PRESS","FREE"],["MOVE","CLOSER","SAVE"],
 ["SAVE","PRESS","CLOSER"],["PRESS","FRONT","MOVE"],["CLOSER","MOVE","FREE"],["PRESS","SAVE","FRONT"]
];
export function makeTestRace(slotIndex:number,seed=6281+slotIndex*101):RaceInput{
  if(!Number.isInteger(slotIndex)||slotIndex<0||slotIndex>2)throw new Error("Invalid slot");
  if(!Number.isInteger(seed)||seed<0||seed>2147483647)throw new Error("Invalid seed");
  const slot=TEST_SLOTS[slotIndex];
  const runners:RaceRunner[]=names.map((name,i)=>{
    // Reproducible demonstration ratings, NOT values from Supabase or real horses.
    const v=(key:number)=>45+((i*29+slotIndex*17+key*13)%46);
    return {id:"demo-"+String(i+1),number:i+1,name,gate:i+1,
      condition:65+((i*11+slotIndex*7)%30),fatigue:(i*7+slotIndex*3)%23,
      weightKg:52+(i%5),distanceFit:55+((i*13+slotIndex*9)%40),trainerReadiness:64+(i*3%27),
      strategies:patterns[i],horse:{
        start:v(1),speed:v(2),acceleration:v(3),stamina:v(4),finishing:v(5),
        power:v(6),grit:v(7),stability:v(8),recovery:v(9)
      },jockey:{
        start:v(11),positioning:v(12),pace:v(13),judgment:v(14),
        urging:v(15),control:v(16),aggression:v(17),stability:v(18)
      }
    };
  });
  return {raceId:"TEST-"+slot.time+"-"+slotIndex,track:slot.track,
    distanceM:slot.distanceM,seed,runners,trackFactor:1};
}
