# 인계: 받은편지함 감시 끊김 방지 — S2 착수 (2026-11-11)

이전 세션: `[OC] 받은편지함 S1`(pane w3:p5Z, 탭 w3:t1W). S1(도구)을 끝내고 커밋했다. 이 문서가 진본이다.

## 1. 저장소 상태

- 저장소: **`/Users/peter/Dev/claude-plugins`** (worktree 없음, 직접). 주인님 지시로 이곳이 진본 작업 리포다.
  - `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins`는 자동 갱신되는 설치 폴더다. **편집·커밋 금지**(10:36 자동 재clone으로 push 전 커밋이 사라진 사고, S1 보고서 §4).
  - `~/Dev/wml-plugins-inbox`는 임시 clone이다. 쓰지 않는다(삭제도 하지 않는다).
- branch `main`, HEAD는 이 문서를 담은 커밋(직전 코드 커밋 `7516e90`). `origin/main`보다 4 커밋 앞섬, **push 안 함**.
- `git status --short`(인계 시점): 비어 있음.

## 2. 읽을 문서

- S1 보고서: `docs/plans/2026-11-11-inbox-reliability-S1-report.md` — 특히 §5 계획과 다르게 정한 점, §6 남은 위험.
- 구현 계획 rev 5: `docs/plans/2026-11-11-inbox-reliability-plan.md` — **§3 S2 절**(396~446행), §5 실측 게이트 G1~G8, §4-3 되돌림, §6-5.
- 설계 rev 4: `docs/design/inbox-reliability.md`.
- 계약 진본: `docs/plans/2026-11-08-agent-orchestrator-plan.md` §1-4(S1에서 갱신됨).
- 구현: `tools/agent-orchestrator/lib/inbox.sh`, `lib/inbox-wait.sh`(600줄), `test/run-tests.sh`(EXPECT 265).

## 3. 합의된 결정 (주인님, 2026-11-11 — 바꾸지 않는다)

1. 감시 유지는 Claude Code 훅의 `asyncRewake` 대기자가 맡는다. 입력창 주입은 어떤 형태로도 하지 않는다.
2. 바깥 sweep(launchd 5분): 미처리 15분 초과, 받은편지함당 1시간 1번, `herdr notification show`로 사람에게만 알린다.
3. 훅은 새 플러그인 `inbox-hooks`로 분리해 waymakerlabs 마켓플레이스에 등록한다. `defaultEnabled:false`이고 review-chain·auto-chain의 `dependencies`로만 켜진다. 설명·키워드·README 첫 줄에 "review-chain·auto-chain이 쓰는 받은편지함 훅(단독 사용 안 함)"이라고 종속을 표시한다.
4. `unwatched`면 보낸 쪽은 상태 파일에 기록만 남긴다.

## 4. S1에서 확인된 것

- 자동 시험 265/265 PASS(5회, `/bin/bash` 3.2.57 포함), `bash -n` 통과, 실제 상태 폴더에 시험 흔적 0, 남은 대기자 0.
- 실측 게이트 **G0 통과**(`/tmp/g0-test`): Bash `CLAUDE_CODE_SESSION_ID` = 훅 `session_id`, Stop 훅 exit 2 stderr 토큰이 transcript jsonl에 기록됨.
- 리뷰: 계획은 review-capped(SHIP 아님). S1 코드는 독립 리뷰를 받지 않았다.

## 5. 첫 착수 지점 — 계획 S2(훅 플러그인 `inbox-hooks`)

계획 §3 S2 그대로:
1. `plugins/inbox-hooks/`(plugin.json `defaultEnabled:false`, `hooks/hooks.json` Stop·StopFailure·UserPromptSubmit·SessionStart 2개, `scripts/inbox-hook.sh` 래퍼, README, marketplace.json 항목, 루트 README 한 줄).
2. 자동 시험 `plugins/inbox-hooks/scripts/test/run-tests.sh`(hook-ao-missing·-ao-old·-off-marker·-stop-exec·-start-json·-validate).
3. 실측 ①~⑩ (`/tmp/inbox-hooks-test`, `env -u HERDR_PANE_ID AO_STATE_ROOT=/tmp/inbox-hooks-test/state claude --plugin-dir plugins/inbox-hooks`). 래퍼의 `AO`는 **`AGENT_ORCHESTRATOR=/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/bin/agent-orchestrator`로 지정**한다(`~/.local/bin`은 아직 옛 판이라 `--status`가 `inbox-wait 2`를 내지 않는다 — 교체는 주인님 go).
4. ⑨(7000초)는 백그라운드로 두고 결과를 S5 병합 조건에 넘길 수 있다.
5. **codex 크로스체크 1회**(무거운 게이트, `review-protocol` 스킬). 범위: S2 플러그인 + **S1 코드 전체(`e71715a`·`7516e90`) + delta F1 수정**. 커밋 해시로 범위를 고정하고, 리뷰 중에는 커밋하지 않는다.
6. 결과: `docs/plans/2026-11-11-inbox-reliability-S2-report.md`. S1 보고서 §5의 7번(사건 칸 `hook=`·`from=`)을 계획 §2-9에 반영할지 S2 보고서에서 정한다.

종료 조건: 계획 S2 절의 종료 조건(자동 시험, ①~⑧·⑩ 결과표, 실제 상태 폴더 변경 0, 크로스체크). 끝나면 S2 보고서와 S3 인계를 쓰고 `session-handoff`로 S3을 연다.

## 6. 수정 범위·소유자

- 이 세션이 `~/Dev/claude-plugins`의 단독 편집 소유자다.
- S2 범위: `plugins/inbox-hooks/**`, `.claude-plugin/marketplace.json`, 루트 README 한 줄, S2 보고서·S3 인계. S1 코드의 버그 수정은 허용(시험 함께).
- 건드리지 않는 것: `plugins/auto-chain`·`plugins/review-chain`(S4), launchd·`inbox-sweep`(S3), 전역 `~/.claude/settings.json`, 실제 `~/.local/state/agent-orchestrator/*`(읽기만), `~/.local/bin`, 다른 세션 입력창.

## 7. 자율 결정과 멈춤 예외

- 설계·구현 세부는 계획서 추천안대로 정하고 진행한다. 다르게 정한 점은 S2 보고서에 적는다.
- 원인 모를 실패가 1번 나면 Opus xhigh 서브에이전트에 조사와 수정을 맡긴다. `inbox-wait-concurrent-3` flaky가 다시 나오면 이 규칙을 적용한다.
- 서브에이전트에 큰 구현을 맡길 때는 단계로 나누고 "한 번의 Write·Edit 100줄·6KB 이하"를 지시서에 적는다(S1에서 단일 에이전트가 API 시간 초과로 결과 없이 끝남).
- **멈추고 주인님께 묻는 경우**: push, `~/.local/bin` 설치 판 교체, 실제 상태 폴더 쓰기, 합의 결정(§3) 변경, 진행 중 체인에 영향을 주는 변경, 전역 settings에서 플러그인 켜기.

## 8. 부모·정리

- 부모 pane: `w3:p5Z`(탭 w3:t1W). 새 세션은 첫 착수 전에 `"$AO" close w3:p5Z`로 닫는다. 실패해도 무시하고 진행한다.
- **닫지 말 것**: 부모 `w3:p5Z` 외에는 아무것도 닫지 않는다(진행 중 체인 `[OC]`·`[WO]` pane 포함).
- 받은편지함: 이 세션은 받은편지함 Monitor를 쓰지 않았다(동결할 것 없음).
- `/tmp/g0-test/`·`/tmp/rewake-test/`는 참고 자료로 남겨 둔다(삭제 금지).
