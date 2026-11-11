# 받은편지함 감시 끊김 방지 — S4 보고서 (스킬 문구 교체·판 올림)

작성 2026-11-11, 세션 `[OC] 받은편지함 S4`(pane w3:p67). 계획: `docs/plans/2026-11-11-inbox-reliability-plan.md` rev 5 §3 S4. 브랜치 `feat/inbox-hooks`(push 안 함).

## 1. 결과 요약

- auto-chain 2.7.0 → **2.8.0**, review-chain 0.1.4 → **0.2.0**, 둘 다 `"dependencies": ["inbox-hooks"]`. marketplace.json 동기화. CHANGELOG 파일은 두 플러그인에 없어 README 「핵심 규칙」 판 항목으로 대신했다.
- 받기 문구: Monitor → `inbox-subscribe`(review-chain은 `rc-watch.sh --subscribe`). 훅이 없는 도구만 Monitor 대체 문단. 인계 순서는 계획 §2-10(동결 → 진행 중 처리 종료 → 처리분만 ack → 구독 해제 → 인계 문서 → 첫 지시). "sweep이 알린다" 문구 없음.
- 스크립트: `rc-watch.sh --subscribe/--unsubscribe`, `rc-send.sh` `watch=` 칸 + 미감시 기록, `rc-claim.sh` `[충돌]` 미감시 기록(CONFLICT·exit 4·빈 stdout 보존), 새 `rc-note-unwatched.sh`(기록 직렬화), `spawn-pane-worker.sh` 부모 감시 `none` 경고 + `parent_watch=none`.
- **G6 켜짐 통과**, 꺼짐은 연동 안 됨(§2, BLOCK 아님으로 판단).
- 시험 전부 통과(§3), codex 크로스체크 1회차 BLOCK → 2회차 **SHIP**(§5).
- 커밋(브랜치 `feat/inbox-hooks`, **push 안 함**): `f71c17d`(구현) → `b463863`(1회차 수정) → `212b3cb`(2회차 low) → 이 보고서·S5 인계.

## 2. G6 실측 — `dependencies`로 inbox-hooks가 켜지고 꺼지는가

Claude Code 2.1.322(Kiro 프록시). 전역 settings·실제 상태 폴더는 건드리지 않았다(`find ~/.local/state/agent-orchestrator -newer <시작 표식>` 결과 0줄).

| # | 절차 | 결과 |
|---|---|---|
| ① 새 설치 | `CLAUDE_CONFIG_DIR=/tmp/inbox-g6` → `plugin marketplace add <리포>`(브랜치 작업 트리) → `plugin install auto-chain@waymakerlabs-claude-plugins` | `Successfully installed … (+ 1 dependency: inbox-hooks)`. `plugin list`: auto-chain 2.8.0 ✔ enabled, inbox-hooks 0.1.0 ✔ enabled. settings.json `enabledPlugins`에 두 항목 모두 `true`로 기록 |
| ② 판 올림 경로 | `/tmp/inbox-g6-up`: main 사본 마켓으로 auto-chain 2.7.0 설치(의존 없음, inbox-hooks 미설치) → 매니페스트 3개를 브랜치 판으로 교체 → `marketplace update` → `plugin update auto-chain` | `updated from 2.7.0 to 2.8.0 … (+ 1 dependency: inbox-hooks)`. inbox-hooks ✔ enabled. 세 머신 자동 갱신 경로와 같은 모양 |
| ③ 훅 실제 동작 | ①의 설정으로 `claude -p --session-id <uuid>`(시험 상태 루트 `AO_STATE_ROOT=/tmp/inbox-g6-run/state`, 리포 판 AO, `AO_INBOX_WAIT_MAX=60`, 사전 `inbox-subscribe --session <uuid>`) | `events.log`: `wait-start hook=SessionStart targets=1` → 60초 뒤 `why=timeout` → `wait-start hook=UserPromptSubmit` → `why=term`. 의존으로 켜진 inbox-hooks의 훅이 실제로 실행됐다. (`-p` 본체는 Kiro 프록시 응답 없이 120초 시간 초과 — 훅 판정과 무관) |
| ④ 끄기 | ①에서 `plugin disable auto-chain` | auto-chain ✘ disabled, **inbox-hooks는 ✔ enabled 그대로**. settings에 `inbox-hooks…: true`가 명시 기록돼 있어 연동해서 꺼지지 않는다 |
| ⑤ 제거 | ②에서 `plugin uninstall auto-chain` | inbox-hooks ✔ enabled로 남고 "1 auto-installed dependency no longer needed … Run `claude plugin prune`". `plugin prune` 뒤 `enabledPlugins: {}` — 제거됨 |

판정: **켜짐은 통과**(새 설치·판 올림 둘 다). **꺼짐은 계획의 기대("auto-chain을 끄면 inbox-hooks도 꺼진다")와 다르다** — disable은 의존을 끄지 않고, uninstall도 `prune` 전까지 남긴다.

영향 판단(BLOCK 아님으로 정함, 근거): G6의 실패 대응 조건은 "켜지지 않으면"이다. 꺼짐이 따라오지 않아도 ① inbox-hooks는 구독(`inbox-subscribe`)한 받은편지함과 pane 받은편지함만 통지하고, 체인 스킬을 끈 머신에서는 새 구독이 생기지 않는다 ② 되돌림은 플러그인 끄기가 아니라 core `inbox-wait --drain`(§4-3 B+C)이 맡는다 ③ 수동으로 끄려면 `claude plugin disable inbox-hooks@waymakerlabs-claude-plugins` 또는 체인 플러그인 제거 뒤 `claude plugin prune`. 이 세 줄을 inbox-hooks README와 계획 §5-1 G6 행에 적는다. 남는 비용은 체인을 끈 머신에서 pane 세션마다 대기자 1개(R6과 같은 크기).

## 3. 자동 시험

| 묶음 | main(`4cb3e31`) | 브랜치(`f71c17d`) | 비고 |
|---|---|---|---|
| auto-chain `scripts/test/run-tests.sh` | PASS 88 / FAIL 0 | PASS 91 / FAIL 0 (`bash`·`/bin/bash` 같음) | 추가 3: `spawn-parent-unhooked-warn`·`spawn-parent-waiter-ok`·`spawn-parent-oldao-silent` |
| review-chain `scripts/test/run-rc-tests.sh` | 통과 34 · 실패 0 | 통과 56 · 실패 0 (두 bash 같음) | 추가 22: `rc-send-watch-field`(4)·`-unwatched-record`(8)·`-watched-norecord`(1)·`-meta-warn-no-retry`(1)·`rc-claim-conflict-kept`(1)·`-unwatched-record`(3)·`rc-watch-subscribe`(4) |
| inbox-hooks `scripts/test/run-tests.sh` | — | collected 8 · passed 8 · skipped 0 | 변경 없음 |
| `claude plugin validate` | — | auto-chain·review-chain·inbox-hooks ✔ | 마켓 전체 validate는 기존 `claude-organizer` 이름 예약 오류로 실패(S4와 무관, main에서도 같음) |

- main 수치는 임시 worktree(`/tmp/s4-main-wt`, 확인 뒤 제거)에서 같은 명령으로 잰 대조군이다.
- 문구 잔존 검사(`grep -rn "timeout_ms: 1800000\|Monitor.*inbox-watch\|rc-watch.sh <"`): 명령 문구는 auto-chain SKILL.md 「훅이 없는 도구의 대체」, review-chain messages.md §1·SKILL.md의 "훅이 없는 도구" 문단, rc-watch.sh 머리 주석의 대체 표시 줄에만 남는다. 그 밖의 줄은 설명문(README 판 기록, "Monitor를 켜지 않는다")과 부모 `none` 조건부 안내(계획 S4가 요구), spawn 경고 문구다.
- "sweep"·"launchd" 문구: 체인 플러그인에 0건(남은 `SWEEP`은 auto-chain의 전수 점검 task 이름으로 무관).
- 실제 상태 폴더: 시험 전후 `find ~/.local/state/agent-orchestrator -newer /tmp/s4-stamp` 0줄.

## 4. 계획과 다르게 정한 점

1. **G6 꺼짐**: 계획은 "auto-chain을 끄면 inbox-hooks도 꺼지는지 본다"였고 실제로는 꺼지지 않는다. BLOCK으로 두지 않고 수동 끄기 안내를 inbox-hooks README·계획 G6 행에 적었다(§2 판단 근거).
2. **review-chain 시험 파일 이름**: 계획의 "없으면 `run-tests.sh` 신설" 대신 기존 `run-rc-tests.sh`에 추가했다.
3. **review-chain 시험의 상태 루트 고정**: 기존 시험이 `AO_STATE_ROOT`를 고정하지 않았다(실제 상태 폴더에 쓸 수 있었다). 시험 머리에서 `$TMP/ao-state`로 고정하고 `HERDR_PANE_ID`·`CLAUDE_CODE_SESSION_ID`를 지웠다.
4. **골든 대조**: 0.1.4 골든 파일은 그대로 두고 `norm()`이 OK 줄 끝 ` watch=…`와 "기록 생략" 경고 줄만 지우게 했다. 새 동작은 신규 시험이 직접 확인한다.
5. **rc-send 기록 위치**: OC→worker는 `state.md` "## 미감시 전송" 절(없으면 만든다), worker→OC는 `report.md` `- 진행:` 줄 아래. report.md·state.md가 없으면 rc-send는 경고 한 줄, rc-claim은 조용히 생략(기존 stderr `CONFLICT…` 한 줄 골든 보존).
6. **spawn 부모 판정**: `inbox-wait --status`가 `inbox-wait 2`가 아니면 판정하지 않는다(칸·경고 없음, 옛 판 = Monitor 경로). 시험 `spawn-parent-oldao-silent` 추가. 기존 `sp-jsonl`·`sp-jsonl-unsupported` 시험은 실제 리포 AO를 쓰고 시험 HOME에 부모 대기자가 없어 꼬리 ` parent_watch=none`이 붙으므로, 시험에서 그 꼬리만 떼어 비교하게 고쳤다.
7. **CHANGELOG**: 두 플러그인에 CHANGELOG 파일이 없다. 저장소 관례(README 「핵심 규칙」 맨 위 판 꼬리표 항목)로 대신했다.
8. **문구 "ack는 출력 없음이 정상"**(S2 관측 메모)을 받기 문단에 넣었다.

## 5. codex 크로스체크 (Sol high, 무거운 게이트)

리뷰어는 매번 `-s read-only`·`--ephemeral`, 로그 머리 `sandbox: read-only` 확인. 리뷰어는 쓰기 시험을 돌리지 않았고 전체 시험은 메인이 돌렸다(§3).

| 회차 | 대상 | 판정 | finding | 반영 커밋 |
|---|---|---|---|---|
| 1 (`20261111-170052`) | `4cb3e31..f71c17d` | BLOCK | medium 1·low 2 | `b463863` |
| 2 (`20261111-170741`) | `f71c17d..b463863` | **SHIP** | low 1 | `212b3cb` |

1회차(모두 실제 결함으로 확인):
1. medium — rc-send·rc-claim의 미감시 기록이 잠금 없는 읽기→임시→`mv`라 동시 송신에서 서로 지움 → 새 도우미 `scripts/rc-note-unwatched.sh`가 `<파일>.flock` 커널 잠금(perl flock, 10초 상한) 안에서 고친다. 시험 `rc-note-concurrent`(rc-send OC→worker 15 + worker→OC 15 + rc-claim 충돌 15 동시 → state.md 15줄·report.md 30줄). 잠금을 끈 돌연변이 사본에서 FAIL 1 확인.
2. low — rc-watch.sh 머리 주석이 HERDR_PANE_ID를 세션 id처럼 설명 → "키는 pane, 등록 sid는 CLAUDE_CODE_SESSION_ID(없으면 2)"로 정정.
3. low — pane-worker.md 재지시 문구 "Monitor 알림으로 깨어난다", review-chain plugin.json 설명의 Monitor 수신 → 구독·훅 깨움으로.

2회차 low: `rc-note-concurrent`의 임시 파일 잔존 검사가 두 glob 중 하나만 맞아도 `ls` 실패로 거짓 통과 → `find`로 바꿈. 잔존 파일을 일부러 만든 사본에서 FAIL 확인.

## 6. 자가 반증(5항) 요약

- ⓐ 키: 해당 없음(캐시 없음). 구독 키는 core 소관, 문구만 정정(1회차 #2).
- ⓑ 돌연변이: spawn 성공 줄에서 `$PARENT_WATCH` 제거 → FAIL 1(`spawn-parent-unhooked-warn`), 기록 잠금 제거 → FAIL 1, 잔존 파일 주입 → FAIL 1. 총계는 §3.
- ⓒ 쓰기 경로: 기록 파일은 `$RC`(절대 경로·존재 검사) 아래 `workers/<이름>/report.md`·`state.md`, 이름은 `^[a-z][a-z0-9_-]{0,31}$` 검사(rc-send.sh:42, rc-claim.sh `chk_name`). `..` 불가.
- ⓓ TOCTOU: 미감시 기록의 읽기~`mv`는 같은 `.flock` 잠금 안. 사람이 편집기로 같은 파일을 동시에 고치는 경우는 막지 못한다(§7).
- ⓔ 호출부: `rc-send.sh` 출력 `OK box=` 소비자는 문서(messages.md) 하나뿐(grep), 앞 두 칸 유지. spawn 성공 줄 소비자는 SKILL.md·pane-worker.md 설명이며 칸 추가뿐.

## 7. 남은 위험·S5로 넘길 것

- **G6 꺼짐 비연동**(§2): 체인 플러그인을 끈 머신에서도 inbox-hooks가 남는다. 수동 끄기 안내를 README에 적었다.
- **미감시 기록과 사람 편집의 충돌**: report.md·state.md를 worker·OC가 Edit로 고치는 순간과 rc-send 기록이 겹치면 한쪽이 사라질 수 있다(같은 세션 안의 일이라 드묾). 실패는 경고만.
- **실제 훅 깨움 end-to-end**는 S2에서 inbox-hooks 단독으로 실측했고, 이번 스킬 문구대로 체인을 돌린 실측은 없다 — S5 관찰 항목(새 조정자 `sub op=add` → `wait-start` → `wait-notify` → `wait-delivered`).
- **push 안 함**: 브랜치 `feat/inbox-hooks` push는 주인님 go 대기. S5 병합 조건 C1(세 머신 `inbox-wait 2`)은 main push 뒤 자동 갱신으로만 충족된다(`~/.local/bin` 링크가 마켓 사본을 가리킴, S3 보고서 §5).
- shellcheck 미실행(설치 안 됨).
