# 인계: 받은편지함 감시 끊김 방지 — S5 착수 (2026-11-11)

이전 세션: `[OC] 받은편지함 S4`(pane w3:p67, 탭 w3:t21). S4를 마감하고 브랜치에 커밋했다. 이 문서가 진본이다.

## 1. 저장소 상태

- 저장소: **`/Users/peter/Dev/claude-plugins`**(진본). 마켓 설치 폴더 `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins`는 **편집·커밋 금지**. `~/Dev/wml-plugins-inbox`는 쓰지 않고 지우지도 않는다.
- branch **`feat/inbox-hooks`**, HEAD = 이 문서를 담은 커밋(직전 `212b3cb`). upstream 없음, **push 안 함**. main은 `4cb3e31`(origin/main보다 S1~S3만큼 앞섬, push 안 함).
- `git status --short`(인계 직전): `?? .claude/` 한 줄. 서브에이전트 worktree라 커밋·삭제하지 않는다(`.claude/worktrees/agent-a901c063fd5940415` 포함).
- S4 커밋: `f71c17d`(구현) → `b463863`(크로스체크 1회차 수정) → `212b3cb`(2회차 low) → 보고서·이 문서.

## 2. 읽을 문서

- **S4 보고서** `docs/plans/2026-11-11-inbox-reliability-S4-report.md`: §2 G6(켜짐 통과·꺼짐 비연동), §4 계획과 다르게 정한 점, §7 남은 위험.
- 계획 rev 5 `docs/plans/2026-11-11-inbox-reliability-plan.md` **§3 S5**(병합 조건 C1~C6, 병합 뒤 순서, 1주 관찰), §4-3 되돌림 단계, §2-9 지표.
- S2 보고서 §4(⑨ G5 = C3 근거), S3 보고서 §7(sweep 알림 안 씀 결정).

## 3. 합의 결정 (바꾸지 않는다)

1. 감시 유지는 훅 `asyncRewake` 대기자. 입력창 주입은 어떤 형태로도 하지 않는다.
2. 바깥 sweep 알림은 쓰지 않는다(launchd 미설치, 코드는 리포에 남김).
3. 훅은 `inbox-hooks`(`defaultEnabled:false`, 체인 플러그인 `dependencies`로만 켜짐).
4. `unwatched`면 보낸 쪽은 기록만 한다.

## 4. 확인된 것 (S4 끝, HEAD `212b3cb`)

- 시험: auto-chain PASS 91/0, review-chain 통과 58/0, inbox-hooks 8/8(`bash`·`/bin/bash` 같음). core 306/306은 S3 기준(S4는 core를 고치지 않음).
- `claude plugin validate`: 세 플러그인 통과.
- G6: dependency로 켜짐(새 설치·2.7.0→2.8.0 갱신 모두), 훅 `wait-start` 실측. 꺼짐은 연동 안 됨 → 수동 안내(inbox-hooks README).
- codex Sol high: 1회차 BLOCK(medium 1·low 2, 모두 수정) → 2회차 **SHIP**(low 1, 수정).
- 실제 `~/.local/state/agent-orchestrator` 변경 0, 전역 settings 변경 0, `~/.local/bin` 변경 0.

## 5. 첫 착수 지점 — 계획 S5 중 "병합 전에 이 맥에서 할 수 있는 것"

S5의 본체(main 병합·push·세 머신 갱신·1주 관찰)는 모두 주인님 go가 필요하다. 그래서 순서는 아래다.

1. **C6 되돌림 리허설**(이 맥, 시험 상태 루트만): 계획 §4-3 B+C → D를 시험 세션 하나에서 한 번. `AO_STATE_ROOT=/tmp/...`, 리포 판 AO(`tools/agent-orchestrator/bin/agent-orchestrator`), `env -u HERDR_PANE_ID`. 대기자를 `AO_INBOX_TEST_PAUSE=pre-register`에 세운 상태에서 `--drain` → 늦은 등록이 막히는지, 새 줄 1개가 아무도 깨우지 않는지, `events.log` `why=off|term`, `pgrep -f inbox-wait` 0, 그 뒤 `--undrain`과 Monitor 복귀(`inbox-watch --state` = `monitor`). S2의 `/tmp/inbox-hooks-test/launch.sh` 방식(`--plugin-dir`+`--settings`)으로 실제 Claude 세션을 써도 된다.
2. **C2 스모크(이 맥, 리포 판 AO)**: 계획 S5 표 C2 명령 그대로. 세 머신 중 이 맥만. 실제 상태 폴더 `find -newer` 전후 0.
3. 결과를 `docs/plans/2026-11-11-inbox-reliability-S5-report.md` 뼈대에 적고 커밋(브랜치 `feat/inbox-hooks`).
4. **여기서 멈추고 주인님께 묻는다**: ① 브랜치·main push ② main 병합(`feat/inbox-hooks` → main, fast-forward 가능) — C1(세 머신 `inbox-wait 2`)·C2(office·home 스모크)는 push 뒤 자동 갱신으로만 확인할 수 있다는 점을 함께 알린다.
5. go를 받으면 계획 S5 "병합 뒤 순서"와 "확인(1주 관찰)"으로 간다. 진행 중 체인은 다음 인계 때만 새 방식으로 바꾼다.

## 6. 수정 범위·자율 결정·멈춤 예외

- 이 세션이 `~/Dev/claude-plugins`의 단독 편집 소유자다(브랜치 `feat/inbox-hooks`).
- 범위: S5 보고서·인계, 계획서 S5 반영, 리허설·스모크에서 드러난 결함 수정(해당 플러그인·`tools/agent-orchestrator`).
- 건드리지 않는 것: 전역 `~/.claude/settings.json`, 실제 `~/.local/state/agent-orchestrator/*`(읽기만), `~/.local/bin`, `~/Library/LaunchAgents`, 마켓 설치 폴더, 다른 세션 입력창, 진행 중 체인(`[OC] GRIT 포털` w3:p5X·`[OC] 백로그 야간` w3:p50 등).
- 설계·구현 세부는 계획서 추천안대로 자율 결정, 다르게 정한 점은 S5 보고서에.
- 원인 모를 실패 1번 → Opus xhigh 서브에이전트에 조사·수정.
- 서브에이전트 지시서에 "한 번의 Write·Edit는 100줄·6KB 이하".
- **멈추고 묻는 경우**: push(브랜치 포함), main 병합, `~/.local/bin` 교체, 실제 상태 폴더 쓰기, 합의 결정(§3) 변경, 진행 중 체인에 영향, 전역 settings에서 플러그인 켜기, 다른 머신(office·home)에서 실행.

## 7. 부모·정리

- 부모 pane: `w3:p67`(탭 w3:t21). 새 세션은 첫 착수 전에 `"$AO" close w3:p67`로 닫는다. 실패해도 무시한다. 그 밖의 pane은 닫지 않는다.
- 받은편지함: S4 세션은 받은편지함 Monitor·구독을 쓰지 않았다. 동결할 것이 없다.
- 참고 자료(삭제 금지): `/tmp/inbox-g6`·`/tmp/inbox-g6-up`·`/tmp/inbox-g6-run`(G6), `/tmp/s4-*`, `/tmp/xc-*-20261111-170052*`·`/tmp/xc-*-20261111-170741*`(크로스체크), `/tmp/inbox-hooks-test/`(S2).
