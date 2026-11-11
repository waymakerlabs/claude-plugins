# 인계: 받은편지함 감시 끊김 방지 — S3 착수 (2026-11-11)

이전 세션: `[OC] 받은편지함 S2`(pane w3:p63, 탭 w3:t1Y). S2(훅 플러그인)를 끝내고 커밋했다. 이 문서가 진본이다.

## 1. 저장소 상태

- 저장소: **`/Users/peter/Dev/claude-plugins`** (worktree 없음, 직접). 진본 작업 리포.
  - `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins`는 자동 갱신 설치 폴더 — **편집·커밋 금지**.
  - `~/Dev/wml-plugins-inbox`는 쓰지 않는다(삭제도 하지 않는다).
- branch `main`, HEAD는 이 문서를 담은 커밋. `origin/main`보다 앞섬, **push 안 함**(주인님 go 대기).
- S2 커밋: `3e6793b`(플러그인·재통지 유예) → `59449dc`·`51797b3`·`f1dd046`(크로스체크 1~3회차 수정) → concurrent-3 수정 → 이 문서 커밋.
- `git status --short`: 인계 커밋 뒤 확인값은 §8에 적는다.

## 2. 읽을 문서

- **S2 보고서**: `docs/plans/2026-11-11-inbox-reliability-S2-report.md` — §3 재통지 유예(계약 반영 필요), §5 계획과 다르게 정한 점, §6 크로스체크, §7 남은 위험, §8 concurrent-3 조사.
- S1 보고서: `docs/plans/2026-11-11-inbox-reliability-S1-report.md`.
- 구현 계획 rev 5: `docs/plans/2026-11-11-inbox-reliability-plan.md` — **§3 S3 절**, §2-9 events.log 스키마, §5 게이트.
- 계약 진본: `docs/plans/2026-11-08-agent-orchestrator-plan.md` §1-4.

## 3. 합의된 결정 (주인님, 2026-11-11 — 바꾸지 않는다)

1. 감시 유지는 훅의 `asyncRewake` 대기자. 입력창 주입은 어떤 형태로도 하지 않는다.
2. 바깥 sweep(launchd 5분): 미처리 15분 초과, 받은편지함당 1시간 1번, `herdr notification show`로 사람에게만.
3. 훅은 `inbox-hooks` 플러그인(`defaultEnabled:false`, review-chain·auto-chain `dependencies`로만 켜짐).
4. `unwatched`면 보낸 쪽은 상태 파일에 기록만.

## 4. S2에서 확인된 것

- 자동 시험: core 271/271(bash·`/bin/bash` 3.2), inbox-hooks 8/8, `claude plugin validate` 통과.
- 실측 ①~⑧·⑩ 통과(G1~G4·G7 통과, G8 병렬로 보임). 결과표는 S2 보고서 §4.
- codex 크로스체크(Sol high): 1~3회차 BLOCK(4·2·1건, 모두 수정) → 한도 도달 뒤 delta 재검토 **SHIP**.
- 실제 `~/.local/state/agent-orchestrator` 변경 0.
- `defaultEnabled:false` 플러그인은 `--plugin-dir`만으로는 disabled — 시험 세션에만 `--settings`의 `enabledPlugins`로 켰다(S4 G6 사전 정보).

## 5. 첫 착수 지점 — 계획 S3(바깥 점검 `inbox-sweep` + launchd)

0. **먼저 계약 반영 2건**(S2에서 미룬 것): ① 계획 §2-5 재통지 조건에 "그 행 token 시각 + `AO_INBOX_RENOTIFY_GRACE`(기본 15초) 경과"와 "통지 직전 `_aoiw_deliv` 재확인"을 적고 계약 진본 §1-4에도 반영. ② 계획 §2-9 사건 표에 `wait-notify hook=`·`sub op=move from=` 칸 추가(S2 보고서 §5-6에서 반영하기로 정함).
1. 계획 §3 S3 그대로: `lib/inbox-sweep.sh`, `bin/agent-orchestrator` 분기, launchd plist 틀, `install-sweep.sh`(기본 dry-run), `manifests/inbox-sweep.manifest`(kind `doc`), 시험 표 전부.
2. 종료 조건: 시험 통과·총계 대조, `plutil -lint`. `install-sweep.sh` dry-run 출력을 주인님께 보이고 **go를 받은 뒤에만** `--apply`. 그 뒤 launchd 경유 실제 알림 확인(계획 S3 끝).
3. S3 크로스체크: 계획에 따라 결정(launchd 설치는 배포 설정 → 무거운 게이트).
4. 결과: `docs/plans/2026-11-11-inbox-reliability-S3-report.md`, S4 인계.

## 6. 넘겨받는 미결

- **⑨ G5(7000초 자체 종료)**: StopFailure 대기자 PID 73717(시작 epoch 1794373297, 14:01:37)을 `/tmp/inbox-hooks-test/g5-watch.sh`가 감시한다. 결과는 `/tmp/inbox-hooks-test/g5.result`(15:58 무렵). 결과를 S2 보고서 §4 ⑨ 줄에 옮기고, `why=timeout`이 7000±5초가 아니면 계획 §5 G5 대응을 적용한다. 판정은 **S5 병합 조건**이다. 시험 세션(pane `w3:p64`, 모델 `claude-bogus-9-9` — StopFailure 유도용)은 그때까지 그대로 두고, 결과를 본 뒤 `/exit`하고 pane을 닫아도 된다.
- **`inbox-wait-concurrent-3` 간헐 실패**: 원인(정리 중 TERM)을 찾아 고쳤다(S2 보고서 §8). 크로스체크 SHIP 뒤 변경이라 **S3 크로스체크 범위에 이 커밋을 넣는다.** 에이전트 worktree `.claude/worktrees/agent-a901c063fd5940415`는 남겨 두었다(삭제 금지, `git add`에서 제외).
- push(S1·S2 커밋), `~/.local/bin` 설치 판 교체: 주인님 go 대기. 교체 전까지 실제 세션에서 플러그인을 켜도 래퍼는 조용히 아무것도 하지 않는다.

## 7. 수정 범위·자율 결정·멈춤 예외

- 이 세션이 `~/Dev/claude-plugins`의 단독 편집 소유자다.
- S3 범위: `tools/agent-orchestrator/**`(sweep·launchd·manifest·시험), 계획서·계약 진본의 §5-0 반영, S3 보고서·S4 인계.
- 건드리지 않는 것: `plugins/auto-chain`·`plugins/review-chain`(S4), 전역 `~/.claude/settings.json`, 실제 `~/.local/state/agent-orchestrator/*`(읽기만), `~/.local/bin`, `~/Library/LaunchAgents`(go 전), 다른 세션 입력창.
- 설계·구현 세부는 계획서 추천안대로. 다르게 정한 점은 S3 보고서에.
- 원인 모를 실패 1번이면 Opus xhigh 서브에이전트에 조사·수정을 맡긴다.
- 서브에이전트 지시서에 "한 번의 Write·Edit 100줄·6KB 이하"를 적는다.
- **멈추고 묻는 경우**: push, `~/.local/bin` 교체, launchd `--apply`, 실제 상태 폴더 쓰기, 합의 결정(§3) 변경, 진행 중 체인에 영향, 전역 settings에서 플러그인 켜기.

## 8. 부모·정리

- 부모 pane: `w3:p63`(탭 w3:t1Y). 새 세션은 첫 착수 전에 `"$AO" close w3:p63`로 닫는다. 실패해도 무시.
- **닫지 말 것**: 부모 외 아무것도 닫지 않는다. 특히 시험 pane `w3:p64`는 ⑨ 결과 전까지 둔다. 진행 중 체인 `[OC]`·`[WO]` pane 포함.
- 받은편지함: 이 세션은 받은편지함 Monitor를 쓰지 않았다(동결할 것 없음).
- `/tmp/inbox-hooks-test/`·`/tmp/g0-test/`·`/tmp/rewake-test/`, `/tmp/xc-*-20261111-*`는 참고 자료로 남긴다(삭제 금지).
