# My Derby official regional race program (2026-10-29)

This application uses **2025 race-plan data supplied by the user**, only as the template for a new fictional world program.

| Historical meet | Game track | KST time |
|---|---|---|
| 서울 | 서울 | 19:00 |
| 부산경남 / 부경 | 부산 | 20:00 |
| 제주 | 영천 | 21:00 |

- 52 real-world dates from `worlds.season_anchor_date`, each with 3 scheduled races, 12 entrants, six grade rotation 6->5->4->3->2->1, seven in-game days per real day.
- 1,386 older horses retain result-derived `kra_v1` abilities. The source file lacked 제주 horses and had only nine 부경 horses, so **144 plan-only starters** were imported as `entry_estimate_v1` with weak confidence, and 54 synthetic NPC jockeys were created. Never present these ability values as observed race timing.
- `GET /api/world/schedule` is the today's public official calendar.
- `POST /api/race/scheduled-test` simulates actual scheduled entries, any time, **without official writes**, enabling replay with a fresh random seed.
- `GET /api/cron/race?slot=0,1,2` requires `CRON_SECRET` and claims/simulates/finalizes a single official race, each once, only when KST time has arrived. Supabase `pg_cron` at UTC 10/11/12 with `pg_net` triggers these endpoints. There is no public, unauthenticated official race reset.
- Official results and 200m checkpoints, events are saved. **Economy_v2 payouts are NOT implemented; stored prize_amount=0 and prize_status=PENDING_ECONOMY_V2.** No financial ledger adjustments may be made before that system is implemented.
- The first season has 52 dates pre-programmed; ongoing season-2 program rollover, automated fatigue/growth, dynamic entries, late scratches and horse aging still need dedicated processors. Calendar displays advance with KST days; do not claim those extra processors run.
- Historical plans from 2025 are **not** official 2026 races; this is a fictional game program generated from statistical patterns.

### Live schedule, results and tests

- Public upcoming program: `/schedule` and `GET /api/world/program` (52-week timetable, normalized meet labels).
- Home current official slots: `GET /api/world/schedule`.
- User-triggered sequential forced simulations: `POST /api/race/scheduled-test` body `{"slot":0}`, then slot 1 and 2. Can replay with different seeds; **not official results**.
- Official race results after cron: `/race/result/<raceId>` and `GET /api/race/official/<raceId>`. Race info, order, 200m checkpoints and event logs are visible; hidden genetic/potential stats are not exposed.
- Supabase cron KST 19/20/21: `0,5,10,15 10/11/12 * * *` respectively in UTC. The 00 slot is first run; 05/10/15 retries are idempotent. A separate job refreshes upcoming programs at 00:05 UTC (09:05 KST).
- Backend `secure_official_race_input` and `secure_official_race_finalize` use private dispatch token and SQL transaction locks. Never place `CRON_SECRET` in GitHub.
- Audit and reproducibility: `my_derby.official_race_process_audit`, `race_runs.race_input`, `race_runs.random_seed`.
- Manual safety test: three schedule-based races computed via real HTTP successfully; official finalize and public result construction tested in rolled-back database subtransactions (no premature official result).
