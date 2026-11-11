# 인계: 받은편지함 감시 끊김 방지 — S4 착수 (2026-11-11)

이전 세션: `[OC] 받은편지함 S3`(pane w3:p65, 탭 w3:t1Z). S3(sweep)를 마감하고 커밋했다. 이 문서가 진본이다.

## 1. 저장소 상태

- 저장소: **`/Users/peter/Dev/claude-plugins`**. 진본 작업 리포.
  - `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins`는 자동 갱신되는 설치 폴더다. **편집·커밋 금지**.
  - `~/Dev/wml-plugins-inbox`는 쓰지 않는다(삭제도 하지 않는다).
- 인계 시점: branch `main`, HEAD는 이 문서를 담은 커밋(직전 `a63bfec`). `origin/main`보다 앞서 있고(S1·S2·S3), **push하지 않았다**(주인님 go 대기).
- `git status --short`(인계 직전): `?? .claude/` 한 줄뿐이다. 서브에이전트 worktree이므로 커밋·삭제하지 않는다. `.claude/worktrees/agent-a901c063fd5940415`도 남긴다.
- S3 커밋 순서: `5189cea`(구현) → `34b500e`·`e19b2ce`(크로스체크 1·2회차 수정) → `5094b07`(보고서) → `eabfe4a`(G5) → `a63bfec`(sweep 알림 안 씀 결정) → 이 문서.

## 2. 읽을 문서

- **S3 보고서**: `docs/plans/2026-11-11-inbox-reliability-S3-report.md`. 특히 §7 주인님 결정, §3 계획과 다르게 정한 점, §5 남은 위험.
- S2 보고서 `…-S2-report.md`: §4 실측표(⑨ G5 통과 반영됨), §4 관측 메모("ack는 출력 없음이 정상" 문구 후보), §5-1(`--settings` `enabledPlugins`로 켜기 — G6 사전 정보).
- 구현 계획 rev 5 `docs/plans/2026-11-11-inbox-reliability-plan.md`: **§3 S4 절**, §2-10 인계 순서, §2-7 송신 쪽, §5 G6.
- 계약 진본: `docs/plans/2026-11-08-agent-orchestrator-plan.md` §1-4.

## 3. 합의 결정 (바꾸지 않는다)

1. 감시 유지는 훅의 `asyncRewake` 대기자가 맡는다. 입력창 주입은 어떤 형태로도 하지 않는다.
2. **(2026-11-11 S3 마감 때 변경)** 바깥 sweep 알림은 쓰지 않는다. launchd를 설치하지 않고, sweep 코드는 리포에 남긴다. 주인님 말씀: "메시지가 남아 있어도 따로 알릴 필요 없다. 이 방식도 안 되면 완전히 다른 방법을 찾는다." 그러므로 S4 문구에 "sweep이 알린다"를 쓰지 않는다.
3. 훅은 `inbox-hooks` 플러그인이 담당한다(`defaultEnabled:false`, review-chain·auto-chain의 `dependencies`로만 켜진다).
4. 감시가 없으면(`unwatched`) 보낸 쪽은 상태 파일에 기록만 한다.

## 4. 확인된 것

- 자동 시험: core 306/306(`bash`·`/bin/bash`), inbox-hooks 8/8.
- S2 실측 ①~⑩ 모두 통과(⑨ G5 7001초 포함). S5 병합 조건 C3 충족, C5는 결정으로 뺐다.
- codex 크로스체크: S2 SHIP(delta), S3 1·2회차 BLOCK(4·2건, 모두 수정) → 3회차 **SHIP**. S2 뒤 수정 `94c3ffd`도 S3 1회차 범위에서 결함 없음.
- 실제 `~/.local/state/agent-orchestrator` 변경 0. `~/Library/LaunchAgents` 변경 0.

## 5. 첫 착수 지점 — 계획 S4(스킬 문구 교체·판 올림, 브랜치 `feat/inbox-hooks`)

1. main HEAD에서 `git switch -c feat/inbox-hooks`.
2. 계획 §3 S4를 그대로 진행한다.
   - 대상: auto-chain `SKILL.md`·`references/pane-worker.md`·`task-brief.md`·`scripts/spawn-pane-worker.sh`, review-chain `SKILL.md`·`references/*`·`scripts/rc-watch.sh`·`rc-send.sh`·`rc-claim.sh`
   - `plugin.json` 판 올림: auto-chain 2.8.0, review-chain 0.2.0, 둘 다 `dependencies: ["inbox-hooks"]`. marketplace 동기화·CHANGELOG도 함께.
   - 시험 표 전부를 수행한다.
3. 문구 원칙: 결정 2가 바뀌었으므로 R1·R2 공백을 "sweep이 알린다"로 설명하지 않는다. 필요하면 "재개 직후 `--pending`"처럼 받는 쪽이 스스로 확인하는 문구만 쓴다.
4. **G6 실측**: 깨끗한 `CLAUDE_CONFIG_DIR`에서 브랜치 마켓을 추가하고 auto-chain만 설치했을 때 inbox-hooks가 켜지는지 본다. 켜지지 않으면 S4를 BLOCK으로 두고 대안을 보고한다. `defaultEnabled:true`는 쓰지 않는다.
5. 종료 조건: 시험 통과, G6 통과, codex 크로스체크 1회(스킬 규약 = 무거운 게이트), **브랜치에만 push**(push는 주인님 go 뒤).
6. 결과: `docs/plans/2026-11-11-inbox-reliability-S4-report.md`, S5 인계.

## 6. 수정 범위·자율 결정·멈춤 예외

- 이 세션이 `~/Dev/claude-plugins`의 단독 편집 소유자다.
- S4 범위: `plugins/auto-chain/**`·`plugins/review-chain/**`(받은편지함 절·스크립트·판), `.claude-plugin/marketplace.json`, 계획서 S4 관련 반영, S4 보고서·S5 인계. `tools/agent-orchestrator`는 S4가 요구하는 경우만 고친다(예: `inbox-watch --state` 확인).
- 건드리지 않는 것: 전역 `~/.claude/settings.json`, 실제 `~/.local/state/agent-orchestrator/*`(읽기만), `~/.local/bin`, `~/Library/LaunchAgents`, 마켓 설치 폴더, 다른 세션 입력창, 진행 중인 체인(`[OC] GRIT 포털`·`[OC] 백로그 야간` 등).
- 설계·구현 세부는 계획서 추천안대로 정하고, 다르게 정한 점은 S4 보고서에 적는다.
- 원인 모를 실패가 1번이라도 나면 Opus xhigh 서브에이전트에 조사·수정을 맡긴다.
- 서브에이전트 지시서에 "한 번의 Write·Edit는 100줄·6KB 이하"를 적는다.
- **멈추고 묻는 경우**: push(브랜치 포함), `~/.local/bin` 교체, 실제 상태 폴더 쓰기, 합의 결정(§3) 변경, 진행 중인 체인에 영향, 전역 settings에서 플러그인 켜기, main 병합.

## 7. 부모·정리

- 부모 pane: `w3:p65`(탭 w3:t1Z). 새 세션은 첫 착수 전에 `"$AO" close w3:p65`로 닫는다. 실패해도 무시한다.
- 그 밖의 pane은 닫지 않는다. 시험 pane `w3:p64`는 G5 확인 뒤 주인님 지시로 이미 닫았다. `w3:p66`(gira 수리봇)은 다른 작업이다.
- 받은편지함: 이 세션은 받은편지함 Monitor를 쓰지 않았으므로 동결할 것이 없다.
- `/tmp/inbox-hooks-test/`·`/tmp/xc-*-20261111-*`·`/tmp/s3-*`는 참고 자료로 남긴다(삭제 금지).
