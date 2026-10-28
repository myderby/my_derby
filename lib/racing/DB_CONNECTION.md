# Supabase `my_derby` 경주 엔진 연결

## 현재 데이터 경로

1. **19/20/21시 테스트**: Vercel POST `/api/race/simulate` → Supabase `my_derby.race_test_fixtures` 3건 조회 → 서버 TypeScript 엔진 → 비공식 결과 반환. 원래 12두 고정 JSON을 코드에서 직접 만드는 방식에서 **DB 입력**으로 변경됨.
2. **실제 DB 경주 목록**: GET `/api/race/db-status` → `my_derby.races` 카운트. 기존 `races` 테이블에는 아직 경주가 없음.
3. **실제 출전마 미리보기**: 사용자 Supabase JWT 포함 POST `/api/race/preview` `{raceId}` → 본인 출전 경주 확인 → `race_entries`, `horses`, `horse_abilities`, `npc_jockeys`, `race_strategies`로 엔진 입력 생성 → 서버 계산 → 사용자 전용 `race_simulation_previews` 기록. **공식 결과와 구분**.
4. **미리보기 기록**: JWT 포함 GET `/api/race/preview` → 본인 기록만 반환.

## 중요한 보호 규칙

- 공식 `race_runs`, `race_results`, `race_section_ranks`, `race_event_logs`, `wallet_transactions`, `races.status`는 이 연결 단계에서 **쓰기 없음**.
- 사용자 JWT의 Auth 검증 및 RLS를 적용. 다른 마주의 말 능력치를 임의로 노출하지 않음. 출전마 중 본인에게 보이지 않는 말이 하나라도 있으면 409 응답을 반환하며 미리보기를 수행하지 않음.
- 순수 12두 테스트는 항상 `TEST_ONLY`로 표시. 비정상 DB 연결 시 저장된 샘플로 자동 대체하지 않고 명시적인 오류를 표시.
- 프로덕션 공식 경주를 실행하고 전적/재화를 정산하려면 서버 운영자 권한, 트랜잭션/중복 실행 보호, 공식 출전 스냅샷 검증 및 시즌 스케줄러를 별도 개발해야 함.
- `my_derby`는 PostgREST API 노출 스키마에 추가함. 기존 `horse_media_ai` 노출 설정은 유지함.
- `race_test_fixtures`: RLS로 테스트 3건 anon 읽기만 허용. `race_simulation_previews`: 로그인 사용자 자기 소유의 경주 미리보기만 읽기/생성 가능.

## 스키마 기대치

`horse_abilities.current_stats`는 `start,speed,acceleration,stamina,finishing,power,grit,stability,recovery`를 숫자 0~100으로 포함해야 함.
`npc_jockeys.skill_stats`는 `start,positioning,pace,judgment,urging,control,aggression,stability`를 숫자 0~100으로 포함해야 함.
`race_strategies.strategy_code`는 DB 어댑터에 정의된 전략 코드 중 하나여야 함.

본격적인 운영 월드를 생성하기 전까지는 실제 경주 엔트리 데이터가 없으므로 DB 미리보기에는 결과가 없음.
