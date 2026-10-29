# MY DERBY — rank / stTime 다경주 운영 (2026-10-29)

## 자료와 변환

사용자 제공 `Supabase Snippet Untitled query (51).csv`를 기준으로
**25,526개 마필 출전 행 → 2,430개 고유 경주**를 추출하여
`my_derby.race_program_source_2025`에 저장함.
경주 식별: `(rcDate,meet,rcNo)`; 출전마마다 반복된 행을 중복 계산하지 않음.

- `rank`는 출전 순위가 아니라 **경주 등급/조건**이며,
  `my_derby.races.class_name`으로 원문을 그대로 보존.
- `rcDist`는 거리, `rcNo`는 원본 경주번호.
- 원본 `stTime`은 11~18시대이므로 게임 19~21시를 **원본 원문대로 사용할 수 없음**.
  같은 시간대 내에서 원본 `stTime` 순서대로 재배치하고 메타데이터에 원본 유지.
- 원본 금요일: 부산경남→부산 / 제주→영천, 게임 **19:00~**
- 원본 토요일: 서울→서울 / 제주→영천, 게임 **20:00~**
- 원본 일요일: 서울→서울 / 부산경남→부산, 게임 **21:00~**
- **출발 3분 간격**, 결과 공개 목표는 **출발 시각+3분**.
- 2025년 52주 중 49주에 원본 경주가 있으며
  없는 **5·40·41주**는 직전 유효 주 편성을 재사용하고
  `source_week_reused`로 표시.
- 2025년 8월 2일과 9일에는 토요일 부산경마가 예외로 등장했으므로
  31·32주 해당 14경주를 허용된 19시 및 21시 블록에 분산.
  배치 후 2,582경주 전부 지역 블록·등급·3분 간격·출발 중복 검증 통과.
- 내부 `race_no`는 동일 지역이 2개 블록에 출전할 때 고유성을 위해
  `source_rc_no + 20 * slot_index`를 사용함.
  **사용자 UI에는 `prize_policy.source_rc_no`만 표시**.

## DB 상태 (배포 후 읽기 확인)

- `my_derby.races` 새 버전 `csv2025_rank_sttime_v2`: **2,582경주** (52개 날짜).
- 이전 잘못된 156개 경주는 삭제하지 않고
  `CANCELLED` 및 `race_day+10000` 형태로 아카이빙.
- 기존 사용자의 이전 출전 신청 1건은
  같은 주차·경주장·경주 등급의 신규 경주로 이관하여 유지.
- 첫날 50개 경주에 NPC 출전 슬롯 144개, 지역/등급 적합, 경주당 2~4두,
  중복 마필 출전 없음.
- 다음 주차 편성은 매일 한국시간 09:05에
  `my_derby_private.prepare_program_entries(currentGameDay)`로 출전마 배정.
  이용 가능한 등급별 마필 부족 시 해당 경주는 미편성 표시;
  **동일 말을 당일 여러 공식 경주에 중복 출전시키지 않음**.

## 실제 자동 처리 (코드와 DB가 한 세트)

- Supabase pg_cron 19:00~19:59, 20:00~20:59, 21:00~22:59(KST)
  매분 `my_derby_private.send_race_slot(slot)` 호출.
- 각 호출은 Vercel 서버의
  `GET /api/cron/race?slot=0|1|2`를 개인 CRON_SECRET으로 인증하여 실행.
- `secure_program_claim_next`는 출발 시각이 지난 `OPEN` 경주 한 건을
  행 잠금으로 선점하고 고정된 입력·시드를 기록.
- TypeScript `simulateRace`가 경기 결과를 계산한 뒤
  `secure_program_stage_result`에 임시 보관. 즉시 공식 `FINISHED`로 처리하지 않음.
- `secure_program_publish_due`는
  `scheduled stTime + 3분`이 지나면 미리 계산된 결과를 공식
  `secure_official_race_finalize`로 전달해 순위·구간·사건 로그를 확정.
  재시도 및 중복 호출에 대비한 잠금과 유니크 제약 적용.
- 분 단위 스케줄러이므로 서버 지연 시 결과 공개는 목표 시각보다
  **늦을 수 있으며 초 단위 정시를 보장하지 않음**.
- 상금·훈련·성장·나이 정산은 아직 정식 적용하지 않음.

## 운영 및 테스트

- `GET /api/world/schedule`: 오늘 전체 경주
- `GET /api/world/program?week=1`: 1~52주 상세
- `GET /api/race/health`: 배포된 엔진의 DB 입력 검증(공식 상태 불변)
- `POST /api/race/scheduled-test`: `{"raceId":"<uuid>"}`
  1경주를 새로운 난수 시드로 비공식 실행; 결과/상금/전적 미변경.
- 홈의 `경주 테스트` 버튼: 다음 경주 강제 시뮬레이션 또는
  오늘의 전 경주 순차 강제 시뮬레이션.
- 경주 데이터 원본 CSV는 Git 저장소에 올리지 않았고,
  재생성 시 `python3 scripts/schedule/import_source_csv.py original.csv`
  로 import SQL 생성 가능.

**필수 주의**: 이 스케줄은 원본 2025년 데이터의 등급·거리·순서를
재현한 **게임용 시즌 시간표**이지 실제 2026년 KRA 경주 일정이 아님.
시즌 2 이후의 신규 52주 경주 편성은 별도 시즌 전환 처리 필요.
