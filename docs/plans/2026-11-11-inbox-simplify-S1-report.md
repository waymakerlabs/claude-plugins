# 받은편지함 단순화 S1 보고서 (core·래퍼·시험)

- 계획: [[docs/plans/2026-11-11-inbox-simplify-plan|받은편지함 단순화 계획]] §2·§3·§5, §10 우선 적용. 브랜치 `feat/inbox-simplify`, 기준 HEAD `36b780b`. 커밋·스테이징 안 함.

## 바꾼 파일 (wc -l 전 → 후)

| 파일 | 전 | 후 |
|---|---|---|
| `tools/agent-orchestrator/lib/inbox.sh` | 371 | 270 (목표 270 이하) |
| `tools/agent-orchestrator/lib/inbox-wait.sh` | 630 | 196 (목표 200 이하) |
| `lib/inbox-sweep.sh`·`launchd/` 2개·`manifests/inbox-sweep.manifest` | 232+94+29+3 | 삭제(파일만 지움, `git rm` 안 함. `launchd/` 폴더도 비어 사라짐) |
| `bin/agent-orchestrator` | 271 | 260 (sweep 분기·머리 주석, `--session-start` JSON 예외 문구 삭제) |
| `test/run-tests.sh` | 1134 | 762 |
| `test/fake-herdr.py` | 203 | 197 (notification 분기 삭제) |
| `plugins/inbox-hooks/scripts/inbox-hook.sh` | 31 | 21 |
| `plugins/inbox-hooks/hooks/hooks.json` | 35 | 17 (SessionStart 동기 훅 삭제) |
| `plugins/inbox-hooks/scripts/test/run-tests.sh` | 99 | 98 |
| `plugins/inbox-hooks/README.md`·`.claude-plugin/plugin.json` | — | §3 요약으로 교체 · 0.2.0 |

## 시험 결과

| 묶음 | `bash` | `/bin/bash` |
|---|---|---|
| agent-orchestrator `test/run-tests.sh` | PASS 234 / FAIL 0 / 총 234 (EXPECT 234) | 같음 |
| inbox-hooks `scripts/test/run-tests.sh` | collected=9 passed=9 failed=0 skipped=0 | 같음 |
| auto-chain `run-tests.sh` (실행만) | PASS 91 / FAIL 0 | 같음 |
| review-chain `run-rc-tests.sh` (실행만) | 통과 58 · 실패 0 | 같음 |

- 하니스 점검: 전에는 306건(전부 PASS)이었다. 지운 이름 87건과 새 이름 15건을 `pass.names`로 대조했다(306 − 87 + 15 = 234). `inbox-regress-all`은 받은편지함 케이스 95건 이름 목록으로 갱신했다. 마지막 정리 뒤 core 묶음은 두 셸에서 6회 연속 FAIL 0이었다.
- shellcheck: 이 맥에 설치돼 있지 않아 **실행하지 못했다**. `bash -n`·`/bin/bash -n` 구문 검사만 통과했다.
- 지운 시험(87): `inbox-sweep-*` 32건, `inbox-check-herdr-unchanged`, `inbox-check-sweep-doc`, `inbox-pane-gen-*` 6건, `inbox-start-*` 4건, `inbox-async-start-*` 2건, `inbox-wait-session-start`, `inbox-wait-start-resume-sub`, `inbox-wait-delivered-quiet`, `inbox-wait-undelivered-renotify`, `inbox-delivered-ack`, `inbox-delivered-no-event`, `inbox-renotify-grace`, `inbox-ctx-demote`, `inbox-wait-held-no-loop`, `inbox-path-backslash`, `inbox-wait-term-{in-notify,before-notify,direct,lockwait,mark}`, `inbox-cleanup-{locked,term-lockwait}`, `inbox-wait-concurrent-3`, `inbox-wait-clear-pane`, `inbox-wait-timeout`, `inbox-wait-cursor-untouched`, `inbox-snapshot-atomic`, `inbox-sub-{del-barrier,dup,gen,known,move}`, `inbox-send-{meta-fail-times,meta-fail-events,times,superseded-unwatched}`, `inbox-ack-ts`, `inbox-ev-{schema,rotate,lag-arrival}`, `inbox-notify-record-fail`, `inbox-off-before-register`, `inbox-drain-after-register`, `inbox-drain-notify-race`, `inbox-undrain`(→ `inbox-drain`에 합침).
- 새 시험(15): `inbox-drain`, `inbox-sub-legacy`, `inbox-send-event-fail-quiet`, `inbox-watch-state-pane`, `inbox-wait-{notified,notified-quiet,ss-cursor,ss-noop,pane-auto,replace,stale-pid,off,term,term-notify,expire-rewake}`. 계획의 `inbox-sub-list`·`inbox-sub-no-key`는 기존 이름의 검사를 새 계약으로 바꿔 남겼다.
- inbox-hooks: `hook-start-json`을 지우고 `hook-start-quiet`(옛 `session-start` 모드는 무동작)와 `hook-ao-other-version`(`--status`가 2가 아니면 무동작)을 더했다. `hook-json-shape`는 네 이벤트 모두 `wait` 하나뿐인지 본다.

## 실측 (셸, 실제 Claude 세션 없음, `AO_STATE_ROOT=/tmp/inbox-live.*`, 래퍼 `inbox-hook.sh wait` 경유)

1. Stop 깨움: 대기 중 `--state`=`waiter`, send=`watched`, 대기자 rc 2, `.notified`=1, stderr에 머리·`== 경로`·`#1`.
2. SessionStart cursor 기준: ack 안 한 상태에서 새 Stop 대기자는 조용히 남는다(notified 기준). 같은 키 SessionStart 대기자는 곧바로 rc 2로 `#1`을 다시 낸다. 앞 Stop 대기자는 교체 TERM으로 rc 0.
3. 교체 TERM: D(Stop) 뒤 E(UserPromptSubmit) → D rc 0·stderr 0B, E가 새 줄 `#2`로 rc 2.
4. 만료 재등록: MAX 2초 → rc 2와 만료 안내 한 줄. 이어 뜬 Stop 대기자가 새 줄 `#3`으로 rc 2.
5. 옛 래퍼의 `inbox-wait --session-start` → rc 0, 빈 출력. events.log에는 `send`·`wake`만 남았다.

## 계획과 다르게 한 점

- §10을 그대로 따랐다. `--status`는 `inbox-wait 2`, 종료할 때 `.pid`를 지우지 않음, 깨움 출력부터 exit 2까지와 만료 때는 `trap '' TERM`, 대상이 있으면 만료 때 exit 2.
- 토큰과 `hooks.off` 확인을 10폴링마다가 아니라 매 폴링(파일 두 개) 한다. 해제·교체가 1폴링 안에 반영된다.
- `.ackts`·`.times`·`known.list`·ack 사건·`AO_INBOX_NOW`·`AO_INBOX_TRACE`도 지웠다(쓰던 곳은 sweep뿐). 잠금 겹침 시험은 trace 대신 "2000자 줄 6개가 섞이지 않았는가"로 본다.
- 구독 파일 수정은 `subs/<키>.flock`(fd 9) 안에서 한다. 정지 지점은 `notify-mid`(notified 기록 뒤, 출력 직전)와 시험 보조용 `registered:0`(등록 표식만, 멈춤 없음) 둘이다.
- `inbox-real-state-untouched`: 이 맥에서 열린 옛 core 세션이 시험 중에 실제 `wait/`·`.waiters/`·`events.log`를 써서 시각 기반 검사가 거짓 FAIL을 냈다(관측함). 그래서 시험 고유 sid·키가 든 이름, 또는 `hooks.off`, 또는 시작 뒤 `events.log`에 붙은 줄 중 시험 sid·box가 든 줄이 있는지로 바꿨다.

## 남은 위험

- `inbox-drain`이 첫 전체 실행에서 한 번 실패했다(`--drain` stdout 0, 기대 2). 단독 15회, 묶음 일부 4회, 전체 6회에서는 재현되지 않았다. 원인은 확인하지 못했다(추정: 부하 중 `ps -o lstart` 판정이 비었을 가능성, UNVERIFIED). 다시 나오면 `_aoi_mark_ok`의 lstart 비교를 먼저 본다.
- shellcheck 미실행.
- 실측은 셸로 훅 JSON을 넣은 것이다. 실제 Claude Code의 asyncRewake 전달은 S2 배포 때 확인한다.
- 옛 2.8.1 core가 도는 세션과 새 core는 `wait/` 이름이 겹치지 않는다(`<sid>.pid` 대 `<키>.pid`). `--state`는 새 표식만 보므로 옛 대기자는 `none`으로 나온다(참고값).

## 배포 (2026-11-11 23:30, 주인님 "묻지 말고 푸시·배포")

- 완료 뒤 크로스체크: codex Sol high `git diff 36b780b..b3859a8` → **SHIP**(finding 0). 계획 리뷰는 BLOCK high 4 → §10으로 모두 반영.
- main fast-forward `b3859a8` push. 판: auto-chain 2.9.0, review-chain 0.3.0, inbox-hooks 0.2.0.
- office(이 맥): 2.8.1→2.9.0·0.2.0→0.3.0·0.1.0→0.2.0. `--status` `inbox-wait 2`. 스모크(설치 판) 대기자 exit 2·`#1 probe`·`ev=wake` 1·실제 상태 변경 0.
- home-macmini: 같은 갱신, 마켓 HEAD `b3859a8`, 스모크 같은 결과, sweep LaunchAgent 0.
- gsr-macbook: Tailscale offline(23:30, 잠자기 추정). 깨어나면 자동 갱신·스모크하는 백그라운드 스크립트 `/tmp/s5-c2/macbook-deploy.sh`(최대 12시간, 결과 `/tmp/s5-c2/macbook-deploy.result`). 마켓 자동 갱신(autoUpdate true)으로도 들어온다.
- 스모크 스크립트의 확인 사건을 `wait-notify` → `wake`로 바꿨다(새 events.log 계약).
- 실제 Claude 세션의 asyncRewake 깨움은 새 세션이 열려 대기자가 뜬 뒤 events.log `wake`로 확인한다(아직 미확인).
- gsr-macbook(2026-11-12 03:49, 재시도 219회 뒤 접속): 마켓 HEAD `a8f5353`, auto-chain 2.9.0·review-chain 0.3.0·inbox-hooks 0.2.0(마켓 자동 갱신으로 이미 들어와 있었다). 스모크 대기자 exit 2·`#1 probe`·`wake` 1·실제 상태 변경 0·sweep LaunchAgent 0. **세 머신 배포 완료.**
- 실제 세션 깨움(office): 실제 events.log에 `ev=wake` 6건(23:43~00:41, `chain-grit-portal/coordinator` n=15~17 포함). 새 core의 훅 대기자가 실제 Claude 세션에서 깨운 기록이다.
