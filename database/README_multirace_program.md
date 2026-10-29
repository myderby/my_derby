# 2026-10-29 rank/stTime 기반 다경주 시간표 운영

## 배포 상태 및 편성
- 사용자 제공 2025 원본 25,526 출전마 행에서 고유 2,430경주를 `my_derby.race_program_source_2025`에 등록.
- 2025년 출전 편성 49주간 + 누락 주간(5, 40, 41)을 이전 정상 주간으로 보완해 첫 시즌 52주/2,582경주 편성. 재사용 여부 `source_week_reused`로 명시.
- 19시 부산·영천 (원본 금요일), 20시 서울·영천 (원본 토요일), 21시 서울·부산 (원본 일요일).
- CSV `rank` → `races.class_name` 변경 없이 저장, 원본 `stTime`은 `prize_policy.source_st_time`에 별도 보존.
- 19/20/21시 게임 시간대 안에서 `stTime` 오름차순으로 **3분 간격 시작**. 최종 결과는 해당 시작 시각 +3분에 DB 확정.
- 동일 경주장의 원본 `rcNo`가 여러 시간대에 겹칠 수 있어 내부 `races.race_no`는 원본 번호 + 슬롯*20. UI는 `source_rc_no`를 표시.
- 기존 잘못 편성된 156개 구 일정은 `CANCELLED`, 게임일 `>=10000`으로 보존(과거 출전 신청 데이터 보존).
- 52일 시즌 이후의 다음 시즌 캘린더 생성은 아직 미구현.

## 경주 실행
- `my_derby_private.prepare_program_entries(gameDay)`: 같은 날 중복 출전, 영구 은퇴, 지역·등급 일치 확인. CSV `dusu`와 동일한 7~16두가 확보된 경주에만 `READY` 표시 및 정식 출전 확정.
- `my_derby_private.send_race_slot(slot)`: DB 저장소 비밀키로 Vercel GET `/api/cron/race?slot=0|1|2`. pg_cron 1분 주기, KST 19~21시대.
- `secure_program_claim_next` → 서버 TS `simulateRace` → `secure_program_stage_result` → `secure_program_publish_due` → 기존 `secure_official_race_finalize`.
- `my_derby_private.race_pending_results`에서 결과를 3분간 비공개 대기시킨 뒤 최종 순위, 200m 구간 순위, 사건 로그 기록. 상금 `economy_v2` 정산은 아직 별도 미구현.
- `POST /api/race/scheduled-test` body `{"raceId":"uuid"}`: 경주 데이터를 공식 편성에서 읽지만 **비공식** 재계산, DB 공식 전적·상금 변경 없음.

## 검증 및 알려진 제한
- 2,582개 경주의 출발 간격·결과 시각·3개 시간대 허용 장소 전체 오류 0건.
- 첫날 50경주 출전 준비 완료. 둘째 날/둘째 주(게임일 8) 50경주 출전 준비 완료.
- 실제 서버로 cron 비공식 호출 시 HTTP 200 WAITING, 실제 DB 편성 시뮬레이션 POST HTTP 200.
- 결과 STAGED→PUBLISHED 전체 흐름 **롤백 트랜잭션** 검증 통과. 실제 정시 공식 배치의 첫 19시 경주는 아직 종료 시점 이후 로그 검증 필요.
- 2025년 CSV의 추가 경주마 후보 3,152두를 NPC에게 등록(기존 경주마 능력치는 유지). 새로 수집된 후보는 레이팅·통산 성적 기반 임시 능력치로 표시(실측 구간기록 기반 능력치 아님). 역사적 기수 156명을 추가해 한 기수의 일일 출전 상한 8회를 유지. 1·2·11주차 50경주씩 `dusu`와 실제 출전마 수 일치 검증 완료. 다른 미래 주차는 00:05 KST 자동 출전 준비 후 추가 검증 필요.
- 시즌 2 자동 생성, 7일치 훈련/노화 반영, 상금 정산·재화 배분 등은 후속 작업임.

## CSV `dusu` 기준 출전두수 (2026-10-29 추가)
- 원본 CSV **25,526행 / 경주 2,430개 / `dusu` 최대 16**. 1개 경주는 제공된 출전마 행이 11개인데 `dusu=10`; 사용자 지정 `dusu`가 우선입니다.
- `race_program_source_2025.source_runner_count`와 `races.target_runner_count`, `prize_policy.source_dusu`에 저장됨. 첫 52주 모든 2,582경주에 연결.
- 출전 임계치는 `actual_confirmed == target_runner_count`; 부족하면 `entry_status='INSUFFICIENT_ELIGIBLE_HORSES'`로 표시하고 **실제 공식 경주를 실행하지 않습니다**.
- TypeScript 엔진, 출전 DB 어댑터, 로그인 사용자 미리보기, 공식 claim/stage/finalize가 모두 최대 16두까지 확장됨.
- 실제 모델 기반 경주마 1,386두의 기존 `current_stats`·`potential_stats`·히든특성은 변경하지 않음. 신규 후보 3,152두는 원본 2025 경주계획의 레이팅·통산기록을 토대로 한 **저신뢰도 추정치**이며 추후 정교한 경주기록 분석으로 대체해야 함.
- 52주 계획에 NPC·사용자 출전마를 한꺼번에 미리 고정하지 않음. 해당 날짜 00:05(KST) 일일 준비 배치로 필요한 두수만큼 출전마를 배정하고 이후 DB 결과를 검증함.
- 마이그레이션: `database/migrations/20261029_dusu_exact_runner_count.sql`; 향후 원본 CSV 재입력은 `scripts/schedule/import_source_csv.py` 실행.


## 영천 게임 거리: 부산경남 거리 분포와 동일 비율 (v1)
- 부산경남 2025 원본 703경주: 1000m 13 / 1200m 191 / 1300m 96 / 1400m 149 / 1600m 127 / 1800m 113 / 2000m 14.
- 제주 원본 707경주를 부산 거리 비율로 재배분(최대 잔여수 방식): **1000m 13 / 1200m 192 / 1300m 96 / 1400m 150 / 1600m 128 / 1800m 114 / 2000m 14**.
- 같은 원본 경주가 몇 번째 주간에 재사용되어도 동일한 거리로 편성되도록 `race_program_source_2025.game_distance_m`를 별도 보관합니다. 원본 `distance_m`은 수정하지 않습니다.
- 배분 우선순위는 원본 제주 거리(짧은 것부터), 날짜, 경주번호입니다. 즉 상대적으로 짧은 경주는 신규 단거리, 긴 경주는 신규 중장거리를 받습니다. 유전적 거리 적성 자체를 재산정하지는 않습니다.
- 첫 52주 영천 752경주에도 게임 거리로 변경. 기존 `rank`, `dusu`, 출전 배정, `stTime`, 3분 결과 확정 시간에는 영향 없음.
- `races.prize_policy.source_distance_m`에 원본 제주 거리, `game_distance_m`에 실제 게임 거리, `distance_policy`에 버전 기록. 새로운 `csv2025_rank_sttime_v2` 영천 경주가 생성되어도 트리거가 같은 정책을 자동 적용.
- 운영 완료 경주가 있으면 거리 변경을 거절하도록 마이그레이션에서 보호합니다. 이 정책은 시즌 1의 CSV 기반 다경주 편성에 적용되며, 별도 레거시 3경주/일 생성기는 사용하지 않아야 합니다.
- 마이그레이션: `database/migrations/20261029_yeongcheon_busan_distance_mix.sql`.
