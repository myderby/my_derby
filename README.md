# MY DERBY

가상의 경마 세계를 운영하는 모바일 마주 경영 시뮬레이션 게임의 웹 MVP입니다.

이 저장소는 **모바일 웹 인터페이스 체험판**용입니다. 공식 경주 엔진, NPC 의사결정 및 경제 거래는 구현 예정이며 화면에 표시하는 일부 데이터는 시연용입니다.

## Supabase 경주 엔진 연결 (2026-10-28)

- `my_derby.race_test_fixtures`에서 19·20·21시 테스트 출전마를 읽고 서버에서 경주 엔진으로 계산합니다.
- 연결 확인: `GET /api/race/db-status` (통합 스모크 테스트: `?smoke=1`).
- 테스트 실행: `POST /api/race/simulate` 본문 `{"slot":0}` (0=19시,1=20시,2=21시).
- 로그인 사용자용: `GET/POST /api/race/preview` (Authorization: Bearer <Supabase user access token>).
- 데이터베이스 구조: `database/migrations/20261028_simulation_adapter.sql`.
- **공식 경주 결과, 재화, 시즌은 계산/저장하지 않습니다.** 실제 운영 데이터가 아직 0건이고 관리자 서버 키가 연결되지 않았습니다.
- `npm run test:race`: 경주 엔진과 DB 입력 매핑 자동 테스트 9개.
- 자세한 보호 범위와 필드 계약: `lib/racing/DB_CONNECTION.md`.
