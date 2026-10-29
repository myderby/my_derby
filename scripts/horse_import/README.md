# 실경주 기록 기반 경주마 능력치: kra_v1

- 입력: 사용자 제공 과거 한국 경마 경주결과 CSV (2019-05-26 ~ 2026-10-25).
- 16,706행 → 고유 hrNo **1,386두**. hrNo 문자열에서 **선행 0 유지**, 이름은 마지막 `] ` 이후만 사용하며 가장 최근 이름을 선택.
- 1두=1개의 `my_derby.horses` 레코드 + 1개의 `my_derby.horse_abilities` 레코드.
- 실제 경주 데이터는 사용자가 제공한 CSV만 기반. 혈통 유전 정보(부마·모마)가 없으므로 **gene_stats는 빈 객체**.
- `current_stats`: start/speed/acceleration/stamina/finishing/power/grit/stability/recovery (0~100). 동일 장소·거리·연도 경쟁자 중위값을 기준으로 기록 정규화, 경주등급과 근래/최상위/통산 경기력 반영.
- 서울의 `seG1fAccTime`, `seG3fAccTime`은 남은 거리 기준 누적 경과시간이므로 `rcTime`에서 뺀 값을 막판 200·600m 시간으로 변환하고, 부경은 `bu_1fGTime`, `bu_3fGTime` 사용.
- `potential_stats`는 **경험 기반 예측 상한**으로 연령·실적 추이·기록 수에 따라 현재 점수 위로 성장 여지를 부여함. 절대적 또는 의학적 보증 아님.
- `hidden_traits`는 FAST_START, LATE_KICK, SPRINTER, STAYER, CONSISTENT, VARIABLE_FORM, LATE_DEVELOPMENT, BIG_RACE_EXPERIENCE, TRAFFIC_RECOVERY, UNDETERMINED 중 근거 있는 태그(최대 4개). 모두 `inferred: true`, `confidence` 포함.
- `distance_affinity`는 1000~2300m 관측 기록과 보수적인 외삽을 사용. `estimation_metadata`에 경기 수, 처음/마지막 날짜, 모델 버전, 신뢰도 저장.

## 재생성
```bash
pip install pandas numpy
python scripts/horse_import/build_horse_abilities.py "경주기록.csv" --output-dir ./import_output
```

출력: `my_derby_horse_abilities.csv`, `my_derby_horse_abilities.jsonl`, `my_derby_horse_abilities_report.json`.
원본 CSV/가공 결과는 코드 저장소에 기본 커밋하지 않습니다.

## 적재 순서
1. `database/migrations/20261029_horse_ability_import.sql` 실행.
2. 가공 JSONL의 각 `hrNo,payload`를 `my_derby.horse_import_stage`에 넣음 (`ON CONFLICT` upsert).
3. `database/import_horses_kra_v1.sql`을 실행해 PAUSED 검증 월드로 수입.
4. `select count(*),count(distinct source_hr_no) from my_derby.horses where source_model_version='kra_v1';`로 1,386 검증.

## 게임 운영 주의
실제 은퇴 여부, 현재 건강, 원본 기록이 없는 회복력·유전적 최대치는 **확정할 수 없음**. 수입 시 사용한 마지막 경주 당시 연령, `condition_score=80`과 `fatigue=0`은 **임시 초기값**. 검증 월드는 `PAUSED`여서 19/20/21시 정식 경주·정산이 자동 실행되지 않음. `life_stage=RACING`은 마지막 관측 당시 현역이라는 뜻이지 2026-10-29 현재도 현역이라는 인증이 아님. 실제 게임 시즌의 소유·이동·은퇴 여부는 별도 절차로 결정.
