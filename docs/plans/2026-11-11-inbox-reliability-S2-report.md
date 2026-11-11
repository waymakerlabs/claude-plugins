# 받은편지함 감시 끊김 방지 — S2 보고서 (훅 플러그인 inbox-hooks)

작성 2026-11-11, 세션 `[OC] 받은편지함 S2`(pane w3:p63). 계획: `docs/plans/2026-11-11-inbox-reliability-plan.md` rev 5 §3 S2.

## 1. 결과 요약

- 새 플러그인 `plugins/inbox-hooks` 0.1.0(`defaultEnabled:false`), marketplace 항목, 루트 README 한 줄. 커밋 `3e6793b`(push 안 함).
- 실측 ①~⑧·⑩ 통과. ⑨(7000초)는 백그라운드 관측 중(§4).
- 실측 ①에서 core 결함 1건을 찾아 고쳤다(§3, 재통지 유예).
- 실제 `~/.local/state/agent-orchestrator`: 이 시험으로 인한 변경 0. `find -newer /tmp/inbox-hooks-test/real-state.marker`(13:42 표식) 결과는 15:02 기준 1줄로, `inbox/chain-grit-portal/coordinator.log` 14:37 변경이다. 내용은 진행 중인 다른 체인(`gira-backlog-night` 조정자)이 보낸 안내 줄이고, 시험 상태(`/tmp/inbox-hooks-test/state`)와 무관하다.
- codex 크로스체크: §6.

## 2. 자동 시험

| 묶음 | 결과 |
|---|---|
| `plugins/inbox-hooks/scripts/test/run-tests.sh` | collected=8 passed=8 failed=0 skipped=0 (`bash`, `/bin/bash` 3.2 각 1회) |
| `tools/agent-orchestrator/test/run-tests.sh` | PASS 266/266(EXPECT 266) — §2-1 참고 |
| `bash -n` | 래퍼·시험·`lib/inbox-wait.sh` 통과 |
| shellcheck | 이 머신에 없음(미실행) |
| `claude plugin validate plugins/inbox-hooks` | 통과(디렉터리 제출 검사의 LICENSE 없음·icon 없음 안내는 마켓 등록과 무관) |

inbox-hooks 시험 케이스: `hook-ao-missing`·`hook-ao-old`·`hook-off-marker`·`hook-stop-exec`(인자·stdin·exit 2 전달)·`hook-start-json`·`hook-validate`, 추가 `hook-bad-mode`·`hook-json-shape`.

### 2-1. core 시험 반복

- 수정 뒤 `bash` 3회 266/266, `/bin/bash` 단독 266/266.
- 실측 세션과 **동시에** 돌린 `/bin/bash` 1회가 264/266(FAIL 2)이었다. 그 실행은 출력을 남기지 않아 케이스 이름을 모른다. 단독 재실행은 통과. 부하 의존 flaky로 추정(UNVERIFIED) — 반복 결과는 §2-2.

### 2-2. 반복 실행

| 시점(HEAD) | 결과 |
|---|---|
| `3e6793b`(재통지 유예) | bash 4회 266/266, `/bin/bash` 1회 266/266 |
| `59449dc`(1회차 수정) | bash 3회 270/270, `/bin/bash` 1회 270/270 |
| `51797b3`(2회차 수정) | bash 1회 269/271(**`inbox-wait-concurrent-3` FAIL**, `inbox-regress-all` 연쇄), bash 1회·`/bin/bash` 1회 271/271 |
| `f1dd046`(3회차 수정) | bash 2회 271/271, `/bin/bash` 1회 271/271 |

`inbox-wait-concurrent-3`(겹친 시작 3개 → 생존 1)은 S1에서 10회 중 1회, 이번 세션에서 11회 중 1회 실패했다. 증상은 같다(`생존 0 rc 000 why superseded timeout`). 인계 문서 §7 규칙에 따라 Opus xhigh 서브에이전트에 원인 조사와 근본 수정을 맡겼다(§8).

## 3. 실측에서 찾아 고친 결함: 깨운 직후 중복 재통지

- 증상(① 1회차, 13:45:13): Stop 대기자가 #1을 알린 그 초에, 깨운 턴의 `UserPromptSubmit` 대기자가 시작하면서 같은 줄을 `[재통지]`로 다시 알렸다(`wait-notify … re=1`). 세션은 같은 알림을 두 번 받아 ack를 두 번 실행했다.
- 원인: 깨움 stderr가 transcript에 기록되기 전에 다음 대기자가 `_aoiw_deliv`를 돌린다. 전달 증거(token)가 아직 없으니 행이 `pending`으로 남고, 재통지 조건(`pending`·횟수 < 3)이 곧바로 참이 된다. 계획 §2-5의 "다음 훅 입력이 전달 확인" 전제가 실제 순서(asyncRewake 출력 → 즉시 UserPromptSubmit → 나중에 transcript)와 맞지 않았다.
- 수정(`lib/inbox-wait.sh`): 재통지 후보는 그 행 token의 epoch로부터 `AO_INBOX_RENOTIFY_GRACE`(기본 15초)가 지난 뒤에만 낸다(`_aoiw_grace_over`). 유예가 끝나 통지하기 직전에 수신 잠금 안에서 `_aoiw_deliv`를 다시 돌려, 그 사이 transcript에 기록된 token을 `delivered`로 반영한다. 새 줄(`n > notified.n`) 통지는 유예와 무관하다.
- 시험: `inbox-renotify-grace` 추가. 기존 시험은 `BASE2`에 `AO_INBOX_RENOTIFY_GRACE=0`을 줘 판정을 바꾸지 않았다. `inbox-regress-all` 대상 116 → 117.
- 재실측: ①b·④·⑥·② 이후 모든 깨움에서 `re=1` 0건, 깨움마다 `wait-delivered` 1건.

## 4. 실측 결과표

환경: `/tmp/inbox-hooks-test`, `launch.sh` = `env -u HERDR_PANE_ID AO_STATE_ROOT=/tmp/inbox-hooks-test/state AGENT_ORCHESTRATOR=<리포 판> claude --plugin-dir plugins/inbox-hooks --settings test-settings.json`. 시험 pane `w3:p64`(이 세션이 연 pane). Claude Code 2.1.322, Kiro 프록시.

| # | 시나리오 | 결과 | 근거(`state/inbox/events.log`) |
|---|---|---|---|
| ① | 쉬는 중 1줄 | 통과 | 13:45:13 `wait-notify n=1-1 re=0`(Stop) → 세션이 "Stop hook feedback"으로 받아 ack. 수정 뒤 13:52 `n=2` → `wait-delivered n=2` |
| ② | `--resume` 뒤 입력 없이 1줄 (G1) | 통과 | 13:56:00 SessionStart async 대기자 `w38255` 시작 → 13:56:21 새 줄에 `wait-notify n=7-8`·`wait-delivered n=8`, 사람 입력 없음 |
| ③ | `/compact` 뒤 입력 없이 1줄 | 통과 | compact 뒤 `hook=SessionStart` 대기자 `w64847` → `n=9` 깨움·delivered |
| ③ | `/clear` 뒤 입력 없이 1줄 (가짜 pane `w99:p99`) | 통과 | clear 직후 동기 SessionStart가 A의 미처리 #1을 additionalContext로 알림(`s69974`), 새 줄 #2에 B의 async 대기자가 `n=1-2` 깨움. 화면에 `#1: [이전 세션] … clear 전 미처리 줄`·`#0` 안내 |
| ④ | 깨운 턴 Esc 중단 → 입력 없이 1줄 (G2) | 통과(계획 기대보다 좋음) | 중단 뒤에도 그 턴의 UserPromptSubmit 대기자 `w93460`이 살아 있어 #4에 `n=3-4` 깨움. 계획이 예상한 "공백"은 생기지 않았다. 사람 입력 단계는 필요 없어 생략 |
| ⑤ | StopFailure(없는 모델 `claude-bogus-9-9`) 뒤 1줄 | 통과 | 14:01:16 `hook=StopFailure` 대기자 `w72891` → 14:01:36 `n=1-1` 깨움·delivered. 화면에는 깨운 턴도 API 오류로 응답 없음(전달은 transcript token으로 확인) |
| ⑥ | 사람 입력 중 깨움 | 통과 | 입력창에 `사람이입력중인문장`이 남은 상태에서 #5 깨움·처리, 입력창 내용 그대로·주입 0 |
| ⑦ | SessionStart additionalContext (G3) | 통과 | resume 때 `hook_additional_context`로 #7 전달(transcript), `wait-notify … hook=SessionStart` |
| ⑧ | 구독 0인 세션 | 통과 | 13:44 첫 세션·14:00 새 세션 모두 `why=no-target`, 대기자 프로세스 0 |
| ⑨ | 7000초 자체 종료 (G5) | 관측 중 | StopFailure 대기자 `w73717`(시작 1794373297)를 `g5-watch.sh`가 감시, 결과 `/tmp/inbox-hooks-test/g5.result` |
| ⑩ | 같은 가짜 pane에서 A → `/clear` B → 1줄 (G7) | 통과 | 14:00 clear 순간 A의 Stop 대기자 `w69092` `why=pane-superseded`. 런타임 자동 취소 아님(core가 세대 검증으로 끝냄). 새 줄은 B만 깨움 |

G4(깨움 stderr가 transcript에 남는가, 플러그인 경로): 통과 — 모든 깨움에서 `token=` 이 jsonl에 기록되고 `wait-delivered`가 났다.
관측 메모:
- 깨운 턴 하나마다 대기자가 `UserPromptSubmit` → `Stop` 순으로 교체된다(앞 것은 `superseded`). 세션당 살아 있는 대기자는 늘 1개였다.
- 시험 세션 모델이 ack 출력이 없어서 기록을 확신하지 못하고(UNVERIFIED라 적음) 한 번 중복 실행한 일이 있다. ack는 단조 증가라 해는 없다. S4 스킬 문구에 "ack는 출력 없음이 정상"을 적을 후보.
- 입력창이 빈 줄이 아닌 상태에서 `agent-send "/exit"`는 기존 텍스트에 붙어 일반 프롬프트가 된다(시험 조작 실수, 훅과 무관).

G8(같은 이벤트의 동기·async 병렬): resume·clear에서 동기 `s…`와 async `w…`의 `ts`가 같은 초 — 병렬 실행으로 보인다(UNVERIFIED, 순서는 수신 잠금이 직렬화).

## 5. 계획과 다르게 정한 점

1. **`defaultEnabled:false` 플러그인의 시험 켜기**: `--plugin-dir`만으로는 `inbox-hooks@inline`이 `✘ disabled`로 로드된다(`claude plugin list` 확인). 시험 세션에만 `--settings /tmp/inbox-hooks-test/test-settings.json`(`{"enabledPlugins":{"inbox-hooks@inline":true}}`)을 줘 켰다. 전역 settings는 건드리지 않았다. S4 G6(`dependencies`로 켜지는가)의 사전 정보다.
2. **hooks.json은 계획 표 그대로**(4 이벤트, SessionStart 2개). G1·G2 모두 동작해 뺀 줄이 없다.
3. **래퍼 추가 동작**: 알 수 없는 모드 → 조용한 무동작(`hook-bad-mode`), `--status` 호출 시 stdin을 `/dev/null`로 막아 훅 JSON을 그대로 core에 넘긴다.
4. **시험 2개 추가**: `hook-bad-mode`, `hook-json-shape`(이벤트·필드·순서·`defaultEnabled` 구조 검사).
5. **core 재통지 유예**(§3): 계획에 없던 동작이다. 계획 §2-5 재통지 조건에 "그 행 token 시각 + 유예 경과"를 더한 것으로 계약 진본 반영이 필요하다 → S3 인계 첫 할 일.
6. **S1 보고서 §5-7(사건 칸 `hook=`·`from=`)**: 계획 §2-9 표에 **반영하기로 정한다**. 실측에서 `wait-notify … hook=SessionStart`가 동기 통지와 async 통지를 구분하는 유일한 칸이었다. 반영은 S3에서 sweep 지표 정의와 함께 한다(이 세션은 계획서를 고치지 않았다).
7. **실측 pane**: 계획은 가짜 pane만 언급했지만 시험 세션을 띄울 실제 pane이 필요해 `pane-open`으로 `w3:p64`를 열었다. 세션 환경에서는 `HERDR_PANE_ID`를 지웠으므로(③/⑩만 `w99:p99`) 실제 pane 키 상태는 생기지 않았다.

## 6. codex 크로스체크 (Sol high, 무거운 게이트)

범위: S1 코드 전체(`e71715a`·`7516e90`, delta F1 포함) + S2(`3e6793b`). 리뷰어는 매번 `-s read-only`·`--ephemeral`, 결과 파일 `/tmp/xc-result-<ts>.md`.

| 회차 | 대상 | 판정 | finding | 반영 커밋 |
|---|---|---|---|---|
| 1 (`20261111-140305`) | S1 전체 + S2 | BLOCK | high 1·medium 3 | `59449dc` |
| 2 (`20261111-142054`) | `59449dc` | BLOCK | high 1·medium 1 (1회차 #1 부분 해소, #4 수정의 새 결함) | `51797b3` |
| 3 (`20261111-143719`) | `51797b3` | BLOCK | high 1 (잠금 해제 경계 TERM) | (delta 수정 커밋) |
| delta (`20261111-144112`, 한도 도달 뒤 1회) | `_aoi_funlock` 순서 | **SHIP** | 0 | — |

1회차 finding(모두 실제 결함으로 확인·수정, 고치기 전 코드에서 새 시험 FAIL 확인):
1. 종료 정리가 fd 8 없이 후임 대기자의 pid를 지울 수 있음 → 정리를 수신 잠금 안에서(`inbox-cleanup-locked`).
2. `awk -v`가 경로의 백슬래시를 해석해 notified 행을 못 찾음 → 재통지 상한·유예 우회 → `ENVIRON`으로 비교(`inbox-path-backslash`). 같은 방식 7곳.
3. 깨움 출력 뒤 notified 기록 실패면 exit 4에 stderr 본문이 남음 → 기록을 먼저(`inbox-notify-record-fail`).
4. SessionStart JSON 8KB 상한 미보장(긴 대상 30개 → 15,684바이트) → 축약 안내(`inbox-ss-cap-8k`).

2회차: ① `_AOI_LOCK8`이 잠금을 잡기 전에도 설정돼, 잠금 대기 중 TERM이면 정리가 보유로 오판 → 실제 획득 표시 `_W_L8`(`inbox-cleanup-term-lockwait`). ② 축약 안내의 `--list`가 sid 키 구독을 못 보여 줌 → `--list --session <sid>`·pane 키 명령을 그대로 적음.
3회차: `_aoi_funlock`이 fd를 닫은 뒤·변수를 비우기 전 TERM이면 같은 오판 → 변수를 먼저 비우고 닫음(`lib/inbox.sh`). 커널이 종료 때 fd를 닫으므로 비운 뒤 신호도 안전(delta 리뷰가 Bash 3.2·실제 flock 11개 시나리오로 확인).

**판정 기록**: 회차 한도(3회) 뒤 추천 수정 + delta 재검토 1회로 SHIP. review-protocol §2의 한도 도달 처리 1단계에서 닫혔으므로 "조건부 마감"이 아니다. 단 리뷰어는 /tmp 쓰기가 막혀 전체 시험 스위트를 돌리지 못했고(메모리 내 헬퍼 시험만), 전체 시험은 메인이 돌렸다(§2).

리뷰어가 지적한 시험 공백: `inbox-wait-term-lockwait`은 외부 잠금을 TERM 직후 풀어 주도록 바꿨기 때문에, 더 이상 "잠금 경합이 계속되는 동안의 종료"를 검사하지 않는다. 그 경로는 새 시험 `inbox-cleanup-term-lockwait`이 맡는다. 조정 이유: 정리가 이제 fd 8을 최대 2초 기다린다.

## 7. 남은 위험

- ⑨ G5 결과 미확정 — S5 병합 조건.
- 재통지 유예 15초: transcript 기록이 15초보다 늦으면 한 번 중복 재통지가 남는다(상한 3회는 그대로). 실측 기록 지연은 1초 안팎이었다.
- 동시 부하 때 core 시험 FAIL 2(이름 미기록) — §2-2.
- ~/.local/bin 판은 아직 옛 판이라 실제 세션에서 플러그인을 켜도 래퍼가 조용히 아무것도 하지 않는다(의도된 안전판). 교체는 주인님 go.

## 8. `inbox-wait-concurrent-3` 간헐 실패 — 원인과 수정

Opus xhigh 서브에이전트(worktree 격리)에 조사·근본 수정을 맡겼다. 보고 원문 `/tmp/concurrent3-report.md`.

- 원인: `_aoiw_cleanup`(EXIT trap)이 TERM을 막지 않았다. 앞 대기자 A가 superseded로 정리하는 도중, 후임 B의 `_aoiw_reap`가 보낸 TERM이 도착하면 `_aoiw_on_term`의 `exit 0`이 정리를 중간에서 끊는다. 그래서 `wait-end` 사건과 표식·pid 정리가 빠졌다. 시험은 superseded 2개를 5초까지 기다리다가 생존 대기자의 MAX(5초)를 넘겼다. 실패 회차의 xtrace에서 `_aoiw_unmark → _aoiw_on_term → exit 0` 순서를 확인했다(확신도 높음).
- S1부터 있던 경쟁이다. 59449dc에서 정리에 fd 8 획득이 들어가며 창이 넓어졌다. 의심 지점이던 fd 7 순서·reap 2초×2는 원인이 아니었다(정상 회차 수렴 약 1.2초).
- 수정: 정리 첫머리에서 `trap ':' TERM HUP INT`(4줄, 시험 변경 없음). 커밋은 HEAD 직전의 `fix(agent-orchestrator): inbox-wait-concurrent-3 …`.
- 검증: 에이전트가 단독 반복으로 수정 전 4/20·2/20·1/25 실패, 수정 후 40/40 통과를 확인했고, 전체 6회 271/271을 돌렸다. 메인은 main에 적용한 뒤 `bash` 1회·`/bin/bash` 1회 271/271로 확인했다.
- 남은 위험: 정리가 fd 8을 2초 넘게 기다리면 후임이 KILL해 `wait-end`가 빠진다(드묾, 상태는 lstart 검사로 회복). bash 5.x는 미검증(이 머신에 없음, 대기자는 `/bin/bash`로 돈다).
- **리뷰 범위**: 이 수정은 크로스체크 SHIP 뒤의 변경이라 독립 리뷰를 받지 않았다. S3 크로스체크 범위에 넣는다.
- 에이전트 worktree `.claude/worktrees/agent-a901c063fd5940415`(브랜치 `worktree-agent-a901c063fd5940415`, 커밋 없음)는 지우지 않고 남겨 두었다.
