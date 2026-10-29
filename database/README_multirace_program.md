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
- `my_derby_private.prepare_program_entries(gameDay)`: 같은 날 중복 출전, 영구 은퇴, 지역·등급 일치 확인. 2~12두 확보 가능 경주에만 출전 배정.
- `my_derby_private.send_race_slot(slot)`: DB 저장소 비밀키로 Vercel GET `/api/cron/race?slot=0|1|2`. pg_cron 1분 주기, KST 19~22시.
- `secure_program_claim_next` → 서버 TS `simulateRace` → `secure_program_stage_result` → `secure_program_publish_due` → 기존 `secure_official_race_finalize`.
- `my_derby_private.race_pending_results`에서 결과를 3분간 비공개 대기시킨 뒤 최종 순위, 200m 구간 순위, 사건 로그 기록. 상금 `economy_v2` 정산은 아직 별도 미구현.
- `POST /api/race/scheduled-test` body `{"raceId":"uuid"}`: 경주 데이터를 공식 편성에서 읽지만 **비공식** 재계산, DB 공식 전적·상금 변경 없음.

## 검증 및 알려진 제한
- 2,582개 경주의 출발 간격·결과 시각·3개 시간대 허용 장소 전체 오류 0건.
- 첫날 50경주 출전 준비 완료. 둘째 날/둘째 주(게임일 8) 50경주 출전 준비 완료.
- 실제 서버로 cron 비공식 호출 시 HTTP 200 WAITING, 실제 DB 편성 시뮬레이션 POST HTTP 200.
- 결과 STAGED→PUBLISHED 전체 흐름 **롤백 트랜잭션** 검증 통과. 실제 정시 공식 배치의 첫 19시 경주는 아직 종료 시점 이후 로그 검증 필요.
- 일부 5등급 편성에서 해당 지역 적격 NPC 경주마 12두보다 경주 수가 많아 4개 미래 경기일에 출전 불가 경주가 생길 수 있음. 등급 불일치나 한 말의 동일 날짜 중복 출전으로 강행하지 않음.
- 시즌 2 자동 생성, 7일치 훈련/노화 반영, 상금 정산·재화 배분 등은 후속 작업임.
