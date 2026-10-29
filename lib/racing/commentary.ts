import type {RaceEvent} from "./types";

/**
 * Every observable race event is shown, in chronological order.
 * Internal plan switching remains private to the engine; it is not
 * a sports-broadcast event. There is deliberately no count/importance cap.
 *
 * The screen receives both engine events (with importance/reasonCode)
 * and official persisted events (which include only seq/time/distance/type/text).
 */
export function selectRaceCommentary(
  events:RaceEvent[]|null|undefined
):RaceEvent[]{
  if(!events?.length)return [];
  return events
    .filter(e=>!!e.text?.trim()&&e.eventType!=="STRATEGY_SWITCH")
    .sort((a,b)=>a.timeSec-b.timeSec||a.seq-b.seq);
}
