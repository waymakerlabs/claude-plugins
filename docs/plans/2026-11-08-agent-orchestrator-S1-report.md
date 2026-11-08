# agent-orchestrator S1 보고 — 핵심·어댑터 (2026-11-08)

- 세션: herdr pane `w2:p16`(탭 `w2:tA` "오케스트레이터 S1", agent `ao-s1`). 부모 `w2:p14`
- 리포 `/Users/peter/Dev/waymakerlabs-claude-plugins`, branch `main`, HEAD `b5691fb`(변경 없음). **commit·push 안 함**
- 상태: S1 종료 조건 충족. codex 크로스체크는 생략(새 폴더 추가뿐, 가역·저위험 — 전역 규칙상 의무 아님)

## 만든 파일 (커밋 대상 경로)

| 경로 | 줄 | 내용 |
|---|---|---|
| `tools/agent-orchestrator/bin/agent-orchestrator` | 211 | 진입점. 인자 검사(백엔드보다 먼저 → 늘 2) → 백엔드 결정(§2-2) → 어댑터 로딩(없음·끝 표시 `AO_ADAPTER_OK=1` 없음 → 12) → `op_*` 없음 → 10 → `ao_adapter_check` → 실행. 링크를 따라가 `AGENT_ORCHESTRATOR_HOME` 결정 |
| `tools/agent-orchestrator/lib/common.sh` | 80 | 이름·pane id 정규식, 한 줄 검사, `ao_json`/`ao_jsonx`(python3 한 곳, 외부 값은 환경 변수) |
| `tools/agent-orchestrator/adapters/herdr.sh` | 323 | 16개 동작. herdr 오류 코드 → 계약 코드(`*_not_found`→3, `agent_not_ready`→5, `agent_blocked`→6, `timeout`→7, 그 밖·해석 실패→4). 배치 로직은 `herdr-spawn-worker.sh` 131~195줄 이전 |
| `tools/agent-orchestrator/adapters/README.md` | 46 | 어댑터 작성 계약·함수 인자 표·Rex 추가 절차 |
| `tools/agent-orchestrator/test/run-tests.sh` | 233 | 계약 시험(PATH 격리, 케이스 총계 대조 `EXPECT=92`) |
| `tools/agent-orchestrator/test/fake-herdr.py` | 197 | 상태 파일 기반 가짜 herdr 0.9.5(압축 JSON, 오류는 stderr+exit 1, `--wait`는 `--until`에 현재 상태가 있어야 성공) |

`docs/plans/` 4개(계획·결정·지시서·이 보고)도 아직 미커밋.

## 시험 결과

```
$ tools/agent-orchestrator/test/run-tests.sh
== 집계: PASS 92 / FAIL 0 / 총 92 (기대 92)      (exit 0, 케이스 이름 고유 92개)
$ shellcheck -x bin/agent-orchestrator adapters/herdr.sh lib/common.sh test/run-tests.sh   → 0건
```

- PATH 격리: 모든 호출이 `env -i PATH="$FAKE:/usr/bin:/bin" HOME="$T/home"`. 첫 케이스 `iso-fake-herdr`가 `command -v herdr` = 가짜 경로 확인, `iso-no-herdr`가 가짜 제거 PATH에 herdr 없음 확인.
- 음성 대조(계획 §6 S1 행 그대로):
  - `AGENT_ORCHESTRATOR_BACKEND=none` → 11 (`neg-backend-none`)
  - `HERDR_ENV` 없음 → 11 (`neg-no-herdr-env`, `-op`, 설정 `backend=herdr`여도 11 `neg-config-outside`)
  - 어댑터에 없는 동작 → 10, 백엔드 호출 0 (`neg-unsupported-op`, `-no-call`)
  - 어댑터 파일 제거 → 12 (`neg-adapter-missing`), 끝 표시 제거 → 12 (`neg-adapter-broken`), lib 제거 → 12, 설정의 없는 백엔드 → 12
  - 가짜 herdr 제거(격리 PATH) → 12 (`neg-herdr-binary-missing`, `-op`)
  - codex kind로 등록된 agent 이름의 `agent-transcript <이름>` → 10 (`neg-transcript-codex`)
  - 가드 제거 시 실패 증명: 어댑터 사본에서 `--until "done"`을 지우면(grep으로 제거 확인) 빠른 완료 `agent-send --confirm`이 7 (`neg-send-until-done`)
- 종료 코드 2~7 각각 양성 케이스 있음: 2(인자 15건), 3(이름 중복·없는 pane/agent·transcript 파일 없음), 4(서버 정지·해석 불가 응답·백엔드 오류), 5(`agent_not_ready`), 6(blocked), 7(wait timeout).

## 실제 herdr pane에서 읽기 동작 (이 pane `w2:p16`, herdr 0.9.5 `/opt/homebrew/bin/herdr`)

```
backend                     → herdr                 rc=0
whoami                      → w2:p16                rc=0
whoami --field tab          → w2:tA                 rc=0
whoami --field workspace    → w2                    rc=0
list --agents               → w2:p14 discussion idle / w2:p16 ao-s1 working / w3:p2H helpai-m1-11 working / w6:p7 - idle   rc=0
list --panes                → w2:p14 논의 메인 idle / w2:p16 S1 구현 working   rc=0
agent-status ao-s1          → working               rc=0
agent-status discussion     → idle                  rc=0
agent-session-id ao-s1      → e762db50-79b0-466c-bf78-823436ffbc61   rc=0
agent-transcript ao-s1      → ~/.claude/projects/-Users-peter-Dev/e762db50-….jsonl  rc=0 (파일 1,220,319 B, 16:49 갱신)
agent-status no-such-agent  → (stderr agent_not_found) rc=3
(HERDR_ENV 제거) backend    → rc=11
```

## 실측에서 얻은 사실 (계약 변경 없음)

- herdr `agent list`에는 이름 없는 agent(herdr가 감지만 한 codex 등)가 섞인다 → `list`는 이름 칸 `-`.
- 오류 응답은 stderr에 `{"error":{"code":…}}` + exit 1. `agent wait` timeout 코드는 `timeout`.
- herdr 응답은 공백 없는 압축 JSON. `tab create`의 실제 응답 모양은 이번에 확인하지 않았다(쓰기 동작 = S2). 어댑터는 응답 안 첫 `pane_id`를 문서 순서로 찾는다(기존 인계 명령의 `grep | head -1`과 같은 기준) — **S2 실측 대상**.
- 진입점 판단: `agent-send`·`agent-wait`·`agent-status`·`agent-read`·`agent-keys`·`agent-session-id`·`agent-transcript`의 대상은 이름 또는 pane id 둘 다 받는다(herdr가 둘 다 받음). 계약 표의 `<이름>`을 넓힌 것이라 호환됨.
- `pane-open` 넘침 탭 이름 기본값은 `작업 넘침`(`AGENT_ORCHESTRATOR_OVERFLOW_TAB`로 덮어씀 — S4에서 auto-chain이 `자율체인 작업`을 넘기면 기존 동작과 같다).

## 남은 것

- S2: manifests·install.sh·uninstall-backend.sh·docs/herdr.md, 실제 `pane-open "시험 pane"`→`close` 1회(이때 `tab create`/`pane split` 응답 실측), Orca 플러그인 삭제·README 정리, push 승인.
