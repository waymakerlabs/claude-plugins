# S4 보고 — auto-chain 2.3.0 (브랜치 `feat/agent-orchestrator-2.3.0`)

- 작성: 2026-11-08, handoff `/Users/peter/Dev/HANDOFF-2026-11-08-agent-orchestrator-S4.md`
- 기준: HEAD `893ea33`(= origin/main) → 로컬 커밋 `3d6420b`(구현) + 이 보고 커밋. **push 안 함.**
- 상태: 구현·시험 끝, codex 크로스체크(무거운 게이트) 대기 — 메인이 실행.

## 바뀐 파일 (`git diff --stat 893ea33..3d6420b` 18 files, +915 −753)

| 파일 | 변경 |
|---|---|
| `.claude-plugin/marketplace.json` | auto-chain 항목만: version 2.3.0, description, keywords에서 herdr·orca 제거·`agent-orchestrator` 추가(3줄) |
| `plugins/auto-chain/.claude-plugin/plugin.json` | 2.3.0, description(3단계·orca 서술 제거) |
| `plugins/auto-chain/README.md` | 2.3.0 이력 줄 추가, 요구사항 절에서 herdr·Orca 서술 제거 → 3단계 + `tools/agent-orchestrator` |
| `skills/autonomous-chain/SKILL.md` | description, reference 목록, §1-1(백엔드 선택 → 실행 단계 3단계, 10·11·12 내려감, ① 인계 전 회수, 가이드 충돌 검사 "3단계 우선·명시적 pane 요구면 ③ 허용"), §1, §2(①은 `Agent` model·effort), §3-1(③ planner만 남긴 채 인계, ①이면 인계 전 회수·`## 시간`), §4 worker 기동, §6 `worker:opencode-*` 칸 → `headless-run.sh`, §9 인계·진행 중 worker, §10 정지 감시(③ 웨이브에만, `agent-stall-watch.sh`) |
| `references/pane-worker.md` (신규) | 옛 `backend-herdr.md`를 ③ 전용·동작 이름으로 축소. 절 번호 §0~§8 유지 |
| `references/backend-herdr.md` | 포인터 7줄(새 문서·툴 특이사항·래퍼 안내) |
| `references/backend-orca.md` | **삭제**(복원: 태그 `auto-chain-v1.7.1-orca`) |
| `references/task-brief.md` | §1-1 worker 메시지 → `agent-orchestrator agent-send`, 10·11·12면 `- 진행:` 줄만, ① worker는 메시지 없이 반환 |
| `references/sol-review.md` | §3 실행 분기 → `review_view` headless/pane, orca 분기 삭제, §4 STALL 화면 확인, §5-6 정리 |
| `references/profile.md` | 키 `review_view`(기본 `headless`) |
| `scripts/spawn-pane-worker.sh` (신규) | ROLE·PERM_FLAGS·첫 지시·성공 줄만. `${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}` 호출, 5번째 인자 → `pane-open --parent`, 10·11·12 같은 코드 전달 |
| `scripts/agent-stall-watch.sh` (신규) | 판정 로직은 2.2.2 그대로, `agent-status`·`agent-transcript`만 사용. jsonl 칸 비면 재조회, 10이면 `transcript unsupported` 줄, 그 밖 rc는 `agent-orchestrator rc=<n>` 줄 |
| `scripts/headless-run.sh` (신규) | `opencode:<agent>`·`codex` 비리뷰 실행, review-run.sh와 같은 RUN·done 형식(verdict 대신 `changed`) |
| `scripts/herdr-spawn-worker.sh`·`herdr-stall-watch.sh` | 호환 래퍼(`exec` 새 스크립트) |
| `scripts/review-run.sh`·`review-wait.sh` | 머리 주석의 참조 경로만 |
| `scripts/test/run-tests.sh` | 아래 시험 |

메인 추가 지시(작업 중 수신) 반영: 역할 접두어 — `PANE_LABEL` 기본 `[WO] <name>`, 넘침 탭 기본 `[WO] 자율체인 작업`, 인계 탭 예시 `[OC] <한글> M<n+1>`, 리뷰 pane `[RV] …`, 시험 기대값 `pane rename w1:p9 [WO] sp-a`. `tools/agent-orchestrator` 코드는 건드리지 않음(`git diff 893ea33..3d6420b -- tools/` 0줄).

## 시험

| 묶음 | 명령 | 결과 |
|---|---|---|
| auto-chain | `bash plugins/auto-chain/skills/autonomous-chain/scripts/test/run-tests.sh` | **PASS 90 / FAIL 0**, rc 0 |
| agent-orchestrator | `bash tools/agent-orchestrator/test/run-tests.sh` | **PASS 123 / FAIL 0 / 총 123 (기대 123)** |

- 기존 56건: 착수 전 이름 목록(`/tmp/ac-s4-names-before.txt`, 56줄)과 이후 목록 `comm -23` → **누락 0**, 중복 0.
- 신규 34건: `ao-fake-herdr`(PATH의 herdr가 가짜인지), spawn 새 경로 `sp-parent`·`sp-jsonl`·`sp-jsonl-unsupported`, 래퍼 경로 `w-sp-*` 11건(기존 sp 계열 전부 + 신규 3), spawn 계약 `spc-pass-10/11/12`(같은 코드·stderr 사유), `spc-place-4`, `spc-parent-arg`, `spc-missing-12`, `spc-whoami`, `spc-noparent`, 정지 감시 `sw-wrapper`·`sw-transcript-unsupported`·`sw-transcript-kind10`·`sw-transcript-lookup`·`sw-ao-rc`·`sw-ao-missing`, headless `hr-opencode`·`hr-runfile`·`hr-msg-order`·`hr-badarg`·`hr-wait`.
- 음성 대조 `sp-neg-until`(·`w-sp-neg-until`): `tools/agent-orchestrator`를 `$T/ao`로 복사, 사본 `adapters/herdr.sh`에서 `--until "done"` 제거(원본엔 있고 사본엔 없음을 grep으로 먼저 확인), `AGENT_ORCHESTRATOR_HOME=$T/ao`로 spawn → rc 6.
- 하니스 전제: 가짜 herdr를 PATH 맨 앞에 두고 첫 케이스로 확인, `HOME`을 임시 폴더로 바꿔 실제 config·transcript를 읽지 않음, `HERDR_PANE_ID`·`AGENT_ORCHESTRATOR_BACKEND`·`AGENT_ORCHESTRATOR_HOME` unset, `AGENT_ORCHESTRATOR`는 개발 사본. shellcheck `-S warning` 신규·변경 스크립트 전부 0건, `bash -n` 전부 통과.
- 실제 herdr pane 스모크(읽기만): 개발 사본 `agent-orchestrator backend` → `herdr` rc 0, `agent-stall-watch.sh`(STALL_ONCE, 자기 pane, jsonl 칸 비움) rc 0·출력 없음(working·진척 10분 미만), `agent-transcript` 경로 실재. pane 기동 실기 시험은 하지 않음(S6 첫 웨이브에서 확인).

## 종료 검사 — `grep -rn -i 'herdr\|orca' plugins/auto-chain`

총 **31줄 / 9파일**, 허용 목록 밖 **0**.

| 파일 | 줄 | 허용 근거 |
|---|---|---|
| `README.md` | 5 | 버전 이력 줄(2.0.0·2.1.0·2.2.0·2.2.2) 4 + 2.3.0 이력 줄 1(옛 이름·태그 언급) |
| `SKILL.md` | 1 | §1-1 가이드 충돌 검사의 옛 스크립트 이름(호환 안내) |
| `references/pane-worker.md` | 1 | 제목의 옛 경로 표기 |
| `references/backend-herdr.md` | 2 | 옛 경로 포인터 파일 + `docs/herdr.md` 포인터 |
| `scripts/agent-stall-watch.sh`·`spawn-pane-worker.sh` | 1·1 | 머리 주석의 옛 이름 |
| `scripts/herdr-spawn-worker.sh`·`herdr-stall-watch.sh` | 1·1 | 래퍼 파일 호환 주석 |
| `scripts/test/run-tests.sh` | 18 | 시험 하니스(가짜 herdr 바이너리·어댑터 사본 변형·래퍼 경로 케이스) |

계획 §3의 허용 목록(CHANGELOG·README 버전 이력·`docs/herdr.md` 포인터·래퍼 호환 주석)에 **시험 하니스**를 더했다(가짜 바이너리 이름이 herdr일 수밖에 없음). 범위 밖이라 손대지 않은 잔존: 루트 `README.md:466`(auto-chain 소개 문단에 herdr·Orca 서술), `docs/auto-chain-guide.html` 19줄 — S6 전 정리 대상으로 넘긴다.

## 로컬 커밋

- `3d6420b` feat(auto-chain): 2.3.0 실행 3단계와 agent-orchestrator 이관
- (이 보고) docs(plans): agent-orchestrator S4 보고

## 크로스체크 때 볼 곳

- `scripts/spawn-pane-worker.sh` — `fail()`의 코드 전달 분기, `agent-start` rc 3 처리, 5번째 인자 없을 때 `whoami` 경로, `pane-open` stderr 경고 출력, `name_count`의 탭 구분 파싱, `agent-transcript` 실패 시 `jsonl=` 값.
- `scripts/agent-stall-watch.sh` `check_one` — `agent_status` rc 0·3 외 처리, jsonl 칸 빈 값·`unverified` 재조회와 중복 억제 키(키는 tsv의 원래 jsonl 칸으로 만든다), `unsupported` 분기.
- `scripts/headless-run.sh` — `codex` 경로의 샌드박스 값(`workspace-write`), `changed` 판정, opencode `-m` 생략 분기. 실제 CLI로는 돌려 보지 않음(가짜 opencode만).
- `SKILL.md` §1-1·§3-1·§9 — ① 내려감과 "인계 전 회수" 조건이 세 곳에서 서로 맞는지, ③ planner 예외가 ③에만 걸리는지.
- `references/pane-worker.md` §8 — `agent-send --confirm`이 옛 `--wait --timeout 60000`(until 없음)을 대신하는 것의 의미 차이.
- `references/task-brief.md` §1-1 — worker가 `agent-send`로 조정자 pane id를 대상으로 쓰는 경로(어댑터 `agent prompt <pane id>`).
- `test/run-tests.sh` — 래퍼 경로 루프에서 `spawn()` 재정의, `HOME`·`HERDR_*` 격리가 그 아래 모든 케이스에 걸리는지, `sp-jsonl`이 앞 절에서 만든 transcript 파일에 기대는 순서 의존.
- `.claude-plugin/marketplace.json` — auto-chain 항목 외 변경 없는지(3줄 diff).
