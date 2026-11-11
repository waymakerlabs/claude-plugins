# 인계: 받은편지함 감시 끊김 방지 — S1 착수 (2026-11-11)

이전 세션: `[OC] 받은편지함 설계 논의`(pane w3:p5P, 탭 w3:t1N). 주인님과 설계를 합의하고 계획을 리뷰까지 마쳤다. 이 문서가 진본이다.

## 1. 저장소 상태

- 저장소: `/Users/peter/.claude/plugins/marketplaces/waymakerlabs-claude-plugins` (worktree 없음, 직접)
- branch `main`, HEAD `d1300d6` (`docs(agent-orchestrator): 받은편지함 감시 끊김 방지 설계·구현 계획 (review-capped)`)
- upstream: `origin/main`보다 **1 커밋 앞섬, push 안 함**(push는 주인님 지시 때만)
- `git status --short`(인계 시점): 이 인계 문서 1개만 미추적

## 2. 읽을 문서

- 설계(합의본, rev 4): `docs/design/inbox-reliability.md`
- 구현 계획(rev 5): `docs/plans/2026-11-11-inbox-reliability-plan.md` — **S1 절과 §1·§2 전체, §5 실측 게이트, §6-5**
- 계약 진본: `docs/plans/2026-11-08-agent-orchestrator-plan.md` §1-4 (S1에서 새 계약을 여기로 옮긴다)
- 기존 구현: `tools/agent-orchestrator/lib/inbox.sh`, `bin/agent-orchestrator`, `test/run-tests.sh`

## 3. 합의된 결정 (주인님, 2026-11-11 — 바꾸지 않는다)

1. 감시 유지는 Claude Code 훅의 `asyncRewake` 대기자가 맡는다. 입력창 주입은 어떤 형태로도 하지 않는다.
2. 바깥 sweep(launchd 5분): 미처리 15분 초과, 받은편지함당 1시간 1번, `herdr notification show`로 사람에게만 알린다.
3. 훅은 새 플러그인 `inbox-hooks`로 분리해 waymakerlabs 마켓플레이스에 등록한다. `defaultEnabled:false`이고 review-chain·auto-chain의 `dependencies`로만 켜진다. 설명·키워드·README 첫 줄에 "review-chain·auto-chain이 쓰는 받은편지함 훅(단독 사용 안 함)"이라고 종속을 표시한다.
4. `unwatched`면 보낸 쪽은 상태 파일에 기록만 남긴다.

## 4. 리뷰 결과

- 리뷰어: codex `gpt-6.1-sol` high, 읽기 전용, 무거운 게이트.
- 1회차 BLOCK(15건) → 2회차 BLOCK(10) → 3회차 BLOCK(4) → delta BLOCK(1, F1). 결과 파일은 `/tmp/xc-result-20261111-093929.md`, `-095630.md`, `-101440.md`, `-102154.md`다(/tmp라 사라질 수 있으며, 처리표는 계획 §6-2~§6-5에 있다).
- **SHIP 아님(review-capped).** delta F1(resume 때 옛 `.issued`로 async 대기자가 조기 종료)은 추천 수정만 반영했고 재검토는 받지 않았다. **S1 시험 `inbox-async-start-resume-stale-issue` 통과로 닫고, S2 크로스체크 범위에 넣는다.**

## 5. 실측 사실 (Claude Code 2.1.322, Kiro 프록시, `/tmp/rewake-test`)

- Stop 훅 `asyncRewake` + exit 2로 **쉬는 세션이 깨어났다**(시스템 알림, 입력창 주입 0). 연속 줄, 작업 중 도착, 20분 쉰 뒤에도 깨어났고 대기자는 턴마다 1개로 교체됐다.
- 장시간 생존: 대기자 pid 68286이 09:18:09~10:32:47(**약 75분**) 살아 있었다. 종료 원인은 시간 제한이 아니라 주인님의 시험 pane 입력(새 턴 → 교체 TERM)이다. **7200초 제한이 실제로 지켜지는지(R1)는 아직 모른다.** 계획대로 S2 실측 게이트에서 확인한다.
- `herdr` 0.9.5에는 `notification show --body --sound`가 있다. 에이전트 간 메시지·깨우기 기능은 없다.

## 6. 첫 착수 지점

계획 **S1(도구)**: `lib/inbox.sh`·`bin/agent-orchestrator`에 `inbox-subscribe`·`inbox-wait`(+`--session-start`·`--status`·`--drain`)·`inbox-watch --state`, 송신 쪽 사이드카(`.times`·`.ackts`·`known.list`), `events.log`, 수신 잠금 `recv.flock`을 만든다. 시험은 `test/run-tests.sh`에 계획이 정한 이름 그대로 넣고, 결정적 정지 지점으로 경쟁을 고정한다. 계약 진본 §1-4를 갱신한다.

- 시험은 반드시 `AO_STATE_ROOT=<임시 폴더>`로 돌리고 `HERDR_PANE_ID`를 unset한다. 실제 `~/.local/state/agent-orchestrator/` 변경 0을 통과 조건으로 둔다.
- bash 3.2(macOS), 잠금은 기존 관례(`/usr/bin/perl` flock, fd 7→8→9 순서)를 따른다.
- 종료 조건: S1 절의 시험 전부 PASS + 기존 시험 전부 PASS(`skipped`·`collected` 총계와 대조) + 실제 상태 폴더 불변. 커밋은 S1 경로만 명시해 스테이징한다.
- S1이 끝나면 S1 보고서(`docs/plans/2026-11-11-inbox-reliability-S1-report.md`)와 다음 세션 인계를 쓰고 S2로 넘긴다(session-handoff 스킬).

## 7. 수정 범위·소유자

- 이 세션이 플러그인 리포의 단독 편집 소유자다(다른 세션 없음).
- S1 범위: `tools/agent-orchestrator/**`, 계약 진본 §1-4, 이 인계·S1 보고서. **스킬 문구(plugins/auto-chain·review-chain)·`inbox-hooks` 플러그인·launchd는 S2~S4이므로 건드리지 않는다.**
- 건드리지 않는 것: 진행 중인 체인 받은편지함 `~/.local/state/agent-orchestrator/inbox/*`(읽기만), 전역 `~/.claude/settings.json`, 다른 세션 입력창.

## 8. 자율 결정과 멈춤 예외

- 설계·구현 세부는 계획서 추천안대로 정하고 진행한다. 계획과 다르게 정한 점은 S1 보고서에 적는다.
- 원인 모를 실패가 1번 나면 Opus xhigh 서브에이전트에 조사와 수정을 맡긴다(전역 규칙).
- **멈추고 주인님께 묻는 경우**: push, `~/.local/bin` 설치 판 교체, 실제 상태 폴더 쓰기, 합의 결정(§3) 변경, 진행 중 체인에 영향을 주는 변경.

## 9. 부모·정리

- 부모 pane: `w3:p5P`(탭 w3:t1N). 새 세션은 첫 착수 전에 `"$AO" close w3:p5P`로 닫는다. 실패해도 무시하고 진행한다.
- 같은 탭의 시험 pane `w3:p5T`(rewake-test)는 이전 세션이 닫았다. `/tmp/rewake-test/`는 참고 자료로 남겨 둔다(삭제 금지).
- **닫지 말 것**: `w3:p56`(`[OC]` 야간 결함 자동처리), `w3:p5X`(`[OC]` GRIT 포털 조정 4), `w3:p5Y`(`[WO]` grit-planner-m3) — 부모 `w3:p5P` 외에는 아무것도 닫지 않는다.
- 받은편지함: 이 세션은 받은편지함 Monitor를 쓰지 않았다(동결할 것 없음).
