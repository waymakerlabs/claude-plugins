# S5 수정 지시서 — codex 크로스체크 1회차 BLOCK 3·NOTE 4 반영

리포 `/Users/peter/Dev/waymakerlabs-claude-plugins`, 현재 branch `feat/agent-orchestrator-2.3.0`, HEAD `1304c1d`. **git 명령(add·commit·switch·stash·reset) 금지** — 파일만 고친다. 메인이 커밋한다(tools 변경은 따로 커밋해 main에 cherry-pick 하므로, tools 변경과 문서 변경이 서로 의존하지 않게 한다).

codex 결과: `/tmp/xc-result-20261108-182002.md`. 메인이 BLOCK 1~3을 원본 줄에서 확인함(`tools/agent-orchestrator/adapters/herdr.sh:192-215`, 초안 38·129·177~182줄).

## 수정 가능 파일
- `tools/agent-orchestrator/adapters/herdr.sh`, `tools/agent-orchestrator/bin/agent-orchestrator`, `tools/agent-orchestrator/docs/herdr.md`, `tools/agent-orchestrator/adapters/README.md`, `tools/agent-orchestrator/test/run-tests.sh`, `tools/agent-orchestrator/test/fake-herdr.py`(필요할 때만)
- `tools/agent-orchestrator/manifests/herdr.manifest`(S5 보고 §4-4의 allow 8줄 반영)
- `docs/plans/2026-11-08-agent-orchestrator-rules-draft.md`, `docs/plans/2026-11-08-agent-orchestrator-S5-report.md`(끝에 "## 6. 1회차 크로스체크 반영" 절 추가)
- 그 밖(plugins/**, 전역 ~/.claude·~/.codex, 원격) 수정 금지.

## 1. self-name 계약 다시 정하기 (BLOCK 1·2, NOTE 1)

사용자 결정(바꾸지 말 것): 탭·pane 이름은 `[OC]`/`[WO]`/`[RV]` 역할 접두어 + 한글 본문, 단계는 본문에. **사용자가 붙인 이름은 본문을 두고 접두어만 붙인다.** 주제가 크게 바뀌면 다시 바꾼다.

새 계약(이대로 구현):
- `self-name <탭 이름> [<pane 이름>]` — 인자는 `[XX] 본문` 형식 권장. 대상마다 현재 label로 판정:
  - 비었거나 **숫자만**(herdr 기본 번호) → 인자 그대로 붙인다.
  - 이미 `[XX] ` 접두어가 있다(XX = 대문자 2자) → 유지(stderr 경고 "유지").
  - 그 밖(사용자 이름, 영문 포함) → **본문은 그대로 두고 인자의 접두어만 앞에 붙인다**(`Peter review` → `[OC] Peter review`). 인자에 접두어가 없으면 유지.
  - ASCII를 기본값으로 보던 판정(`AO_ASCII_RE`)은 없앤다.
- `self-name --force <탭 이름> [<pane 이름>]` — 판정 없이 바꾼다. 주제가 바뀔 때, **현재 이름을 이 세션이 붙였을 때만** 쓴다(규칙 문서에 그렇게 적는다).
- 읽기: `whoami --field tab-label` / `whoami --field pane-label` 추가(현재 label 한 줄, 없으면 빈 출력). 이름 확인은 이것으로 한다.
- 종료 코드는 기존 계약(0·2·3·4) 안에서. 인자 검사(진입점)도 맞춘다.
- 시험: 위 경우마다 케이스(빈 값·숫자·접두어 있음·사용자 영문 `Peter review`·사용자 한글·`--force`·인자에 접두어 없음·`tab-label`/`pane-label` 읽기). 기존 `self-name-*` 케이스 이름은 유지하고 기대값만 새 계약에 맞춘다. 기대 총계(`EXPECT`) 갱신. **가드 제거 시 실패 증명** 1건: 사본 어댑터에서 "사용자 이름 보존" 분기를 지우면 `Peter review` 케이스가 FAIL하는지.
- `docs/herdr.md` 「이름」 항목·`adapters/README.md`·진입점 머리 주석을 새 계약으로.

## 2. 초안 고치기 (BLOCK 1·2·3, NOTE 2~4)
- 38·129줄 근처 이름 규칙 문안을 새 `self-name`/`--force`/`whoami --field tab-label|pane-label` 계약으로. "사용자 이름은 본문 두고 접두어만" 문장 유지. §3·§4(codex·홈 문안)도 같게.
- 140줄 근처 확인 절차: 탭·pane 둘 다 `whoami --field tab-label`/`pane-label`로 확인(NOTE 1).
- 177~182줄 helpai 메모리 절차: 첫 단계에서 같은 셸에 `AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}`를 정의하고 이후 모든 호출이 `"$AO"`를 쓰게(BLOCK 3). 다른 메모리 블록도 `"$AO"`를 정의 없이 쓰는 곳이 있는지 전수 확인.
- 103줄 근처 codex 문안: ③→① 폴백 시 "인계 전 완료·회수" 조건 추가(NOTE 2, SKILL.md §1-1과 같게).
- 208줄 근처 HISTORY 문안: "세 머신 같게" 같은 과장을 실제 범위로(홈은 이름 규칙만, office gira 메모리는 **주인님 결정 대기**로 명시)(NOTE 3).
- 235줄 근처 줄 수: 블록 정의와 시뮬레이션이 같게(울타리 내용 그대로 보존 기준)(NOTE 4). `/tmp/s5/sim.py`가 있으면 고쳐 다시 돌려 수치 갱신.

## 확인과 반환
- `bash tools/agent-orchestrator/test/run-tests.sh` 전부 PASS(총계 대조), `bash plugins/auto-chain/skills/autonomous-chain/scripts/test/run-tests.sh` 90/90 유지(auto-chain이 self-name을 부르지 않는지 확인).
- 이 herdr 안에서 실제 `whoami --field tab-label`·`pane-label` 1회(읽기만, rename 하지 말 것).
- 금지 표현은 전역 CLAUDE.md 목록을 따른다.
- 반환: `<바뀐 파일 수> 파일 — tools 시험 N/N, auto-chain 90/90, 남은 문제 1줄` 한 줄만.
