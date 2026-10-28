export type Strategy = "FRONT" | "PRESS" | "SAVE" | "MOVE" | "CLOSER" | "FREE";
export type EventType = "START" | "PACE" | "STRATEGY_SWITCH" | "BLOCKED" | "LANE_CHANGE" | "OVERTAKE" | "MOVE" | "FINAL_CHARGE" | "FINISH";
export type Phase = "START" | "EARLY" | "MIDDLE" | "MOVE" | "FINAL";

export interface HorseAbilities {
  start: number; speed: number; acceleration: number; stamina: number;
  finishing: number; power: number; grit: number; stability: number; recovery: number;
}
export interface JockeyAbilities {
  start: number; positioning: number; pace: number; judgment: number;
  urging: number; control: number; aggression: number; stability: number;
}
export interface RaceRunner {
  id: string; number: number; name: string; gate: number; lane?: number;
  horse: HorseAbilities; jockey: JockeyAbilities;
  strategies: Strategy[]; condition: number; fatigue: number;
  weightKg: number; distanceFit?: number; trainerReadiness?: number;
}
export interface RaceInput {
  raceId: string; track: string; distanceM: number; seed: number;
  runners: RaceRunner[]; trackFactor?: number;
}
export interface RunnerState {
  id: string; number: number; name: string; distanceM: number; speedMps: number;
  stamina: number; lane: number; strategy: Strategy; strategyIndex: number;
  elapsedSec: number; rank: number; blocked: boolean; finishedAt: number | null;
}
export interface RaceEvent {
  seq: number; timeSec: number; distanceM: number; horseId: string | null;
  eventType: EventType; reasonCode: string | null;
  params: Record<string, string | number | boolean>; importance: number;
  text: string;
}
export interface SectionRank {
  distanceM: number;
  ranks: {horseId: string; number: number; name: string; rank: number; gapM: number; strategy: Strategy}[];
}
export interface RaceFinisher {
  horseId: string; number: number; name: string; rank: number; timeSec: number;
  finalStamina: number; strategy: Strategy;
}
export interface RaceResult {
  version: string; raceId: string; track: string; distanceM: number; seed: number;
  durationSec: number; results: RaceFinisher[]; sections: SectionRank[];
  events: RaceEvent[]; tickSeconds: number; simulated: true;
}
