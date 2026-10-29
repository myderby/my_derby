import type {RaceEvent} from "./types";

/**
 * Screen commentary, not the raw engine audit log. Keeps the entire race's
 * START, all 200m SECTION_LEADER checkpoints and all FINISH events even when
 * plentiful overtakes/lane changes would otherwise push them off the UI.
 *
 * The original race events are neither mutated nor truncated in persistence.
 */
export function selectRaceCommentary(
  events:RaceEvent[]|null|undefined,
  maxEntries=100
):RaceEvent[]{
  if(!events?.length)return [];
  const visible=events.filter(e=>
    !!e.text?.trim() &&
    e.eventType!=="STRATEGY_SWITCH" &&
    (e.importance>=2 || e.eventType==="FINISH")
  ).sort((a,b)=>a.timeSec-b.timeSec||a.seq-b.seq);
  const cap=Math.max(40,Math.floor(Number.isFinite(maxEntries)?maxEntries:100));
  if(visible.length<=cap)return visible;

  const mustKeep=new Set<number>();
  for(let i=0;i<visible.length;i++){
    const e=visible[i];
    if(e.eventType==="START" || e.eventType==="FINISH" ||
       e.reasonCode==="SECTION_LEADER")mustKeep.add(i);
  }
  // Usually <=33 events (16 starters + 16 section checkpoints + START).
  // Handle unusual races by never losing FINISH events.
  if(mustKeep.size>cap){
    const prioritized=[...mustKeep].sort((a,b)=>{
      const priority=(e:RaceEvent)=>e.eventType==="FINISH"?3:e.eventType==="START"?2:1;
      return priority(visible[b])-priority(visible[a]) || a-b;
    }).slice(0,cap);
    return prioritized.map(i=>visible[i]).sort((a,b)=>a.timeSec-b.timeSec||a.seq-b.seq);
  }

  const extra=[...visible.keys()].filter(i=>!mustKeep.has(i));
  const allowance=cap-mustKeep.size;
  if(allowance>0){
    // Sample across the complete race duration, not only early log entries.
    for(let i=0;i<allowance;i++){
      const index=Math.min(extra.length-1,Math.floor((i+.5)*extra.length/allowance));
      if(index>=0)mustKeep.add(extra[index]);
    }
  }
  return [...mustKeep].map(i=>visible[i])
    .sort((a,b)=>a.timeSec-b.timeSec||a.seq-b.seq);
}
