# 마이더비 V4 월드 · 마주 배정

현재 DB 검증: 1,386두, NPC 마주 80명(1,109두), 신규 사용자 배정 대기 277두.
NPC는 가상의 **시스템 마주 001~080**이며 실제 마주가 아닙니다.

## 사용자가 마주로 등록하는 방법
`/world`에서 로그인 후 닉네임을 입력하고 **월드 참가**를 누릅니다.
서버는 Supabase Auth JWT에서 `auth.uid()`를 검증하고 PostgreSQL RPC `my_derby.join_world(p_nickname)`로 3두를 무작위 배정합니다.
수량 검증과 소유권 변경은 같은 DB 트랜잭션에서 처리하며 재요청 시 다시 지급하지 않습니다.
계정이 한 명 등록되어 있더라도 `my_derby.profiles`가 없다면 다른 앱에서 쓰는 계정일 수 있으므로 **사전 동의 없이 강제 배정하지 않습니다**.
첫 참가 시 개인목장과 시설 5종(레벨1)을 함께 만듭니다.

## 실제 월드 API
- `GET /api/world/overview`: 비개인화 월드 주차·52일 시즌·19/20/21시 시각·NPC 보유 집계
- `POST /api/world/join`: Auth bearer JWT + `{"nickname":"마주닉네임"}` -> 3두 최초 배정
- `GET /api/world/mine`: Auth bearer JWT -> 소유마 이름, hrNo, 현재 능력치만 노출. **히든 특성, 유전/최대 성장치는 client에 반환하지 않음**.

## 시간·경주 규칙
- KST 실세계 1일 = 게임 7일(1주), 52일 = 게임 1시즌.
- 슬롯: KST 19:00 / 20:00 / 21:00.
- `my_derby.world_clock(world_id)`는 월드가 ACTIVE이고 시작일이 지정돼 있을 때만 현재 주차를 계산합니다.
- 현재 월드 `PAUSED` 및 `automatic_processing_enabled=false`. **매일 훈련·경제_v2·교배·NPC 경주 신청·결과 정산 및 정시 시뮬레이션은 아직 실행되지 않습니다.**
- 운영 시작 전에 `season_anchor_date`를 실제 시작 날짜로 재설정하고, 공용 경주 편성, NPC trainers/jockeys, 안전한 단일 실행·경제 원장·지속성 tick 프로세서를 완료해야 합니다.
- 이전에 등록한 CSV 기록을 신뢰해 실제 은퇴·건강·유전값을 확정하지 마세요.

## 보안
- 개인 가입 API는 자기 Auth UID만 사용하며 동시 가입을 DB advisory lock으로 직렬화합니다.
- NPC 명단은 집계된 가상 NPC 이름만 공개합니다.
- `horse_abilities`의 hidden_traits/potential_stats/gene_stats는 Auth client SELECT 권한에서 제외됩니다.
- 운영 재화, race_runs, race_results, season_number를 아직 변경하지 않습니다.
- 데이터 원본: 업로드된 KRA 과거 경주 결과에서 추정한 kra_v1 능력치.
