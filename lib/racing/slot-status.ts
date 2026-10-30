/**
 * Groups official race cards by their scheduled Korean local start hour.
 * The game currently publishes three time slots: 19, 20 and 21.
 * Never use the test-race state to infer an official slot's state.
 */
export type OfficialRaceStatus =
  | "OPEN" | "CLOSED" | "RUNNING" | "FINISHED" | "CANCELLED" | string;
export type SlotRace = {
  start_time?: string | null;
  time?: string | null;
  status?: OfficialRaceStatus | null;
};
export type SlotState = "UPCOMING" | "RUNNING" | "FINISHED" | "EMPTY";
export type SlotSummary = {
  hour: "19" | "20" | "21";
  label: "예정" | "진행중" | "종료" | "경주 없음";
  state: SlotState;
  total: number;
  finished: number;
  cancelled: number;
  completed: number;
  ongoing: number;
  firstStart: string | null;
  lastStart: string | null;
};

export const OFFICIAL_RACE_HOURS = ["19", "20", "21"] as const;

/** Support both the current daily schedule and the weekly program API shapes. */
export function officialRaceHour(race: SlotRace): SlotSummary["hour"] | null {
  const start = race.start_time ?? race.time ?? "";
  const match = /^(19|20|21):[0-5][0-9](?::[0-5][0-9])?$/.exec(start);
  return match ? (match[1] as SlotSummary["hour"]) : null;
}

export function summarizeOfficialSlot(
  allRaces: readonly SlotRace[], hour: SlotSummary["hour"]
): SlotSummary {
  const races = allRaces.filter(race => officialRaceHour(race) === hour);
  const finished = races.filter(r => r.status === "FINISHED").length;
  const cancelled = races.filter(r => r.status === "CANCELLED").length;
  const ongoing = races.filter(r =>
    r.status === "CLOSED" || r.status === "RUNNING").length;
  const completed = finished + cancelled;
  const total = races.length;
  // Cancellation before the first starter must not look like a live race.
  const state: SlotState = total === 0 ? "EMPTY" :
    completed === total ? "FINISHED" :
    ongoing > 0 || finished > 0 ? "RUNNING" : "UPCOMING";
  const label = state === "FINISHED" ? "종료" :
    state === "RUNNING" ? "진행중" :
    state === "EMPTY" ? "경주 없음" : "예정";
  const times = races.map(r => (r.start_time ?? r.time ?? "").slice(0,5)).sort();
  return { hour, label, state, total, finished, cancelled, completed, ongoing,
    firstStart: times[0] ?? null, lastStart: times[times.length - 1] ?? null };
}

export function officialSlotSummaries(
  allRaces: readonly SlotRace[]
): SlotSummary[] {
  return OFFICIAL_RACE_HOURS.map(hour => summarizeOfficialSlot(allRaces, hour));
}
