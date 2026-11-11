# 받은편지함 훅 대기자 단순화 — 구현 계획 (최소 판)

- 상태: 초안. 저장소 `claude-plugins`, 브랜치 `feat/inbox-hooks`, 기준 HEAD `4186f6e`.
- 앞 계획: [[docs/plans/2026-11-11-inbox-reliability-plan|받은편지함 감시 끊김 방지 계획]](rev 5). 이 문서는 그 §2-1~§2-10 중 대부분을 걷어낸다.
- 판: agent-orchestrator 기능 조회 `inbox-wait 3`, auto-chain 2.9.0, review-chain 0.3.0, inbox-hooks 0.2.0.

## 1. 목표·비목표

목표:

- 받는 쪽 훅 경로를 "구독 목록 + 세션당 대기자 하나 + 안 읽은 줄이 있으면 exit 2"로 줄인다.
- 상태 파일은 `subs/<키>`(지금 위치, 경로 칸만 읽음)·`wait/<키>.pid`·`<log>.notified` 셋만 쓴다. 잠금은 기존 `<log>.flock`(fd 9)만 쓴다.
- 이번 작업 전 `inbox.sh`(커밋 `e71715a^`, 241줄)의 Monitor 동작을 그대로 둔다: owner·held·`[이전 세션]`, `--ack`·`--pending`·`--release`.
- `inbox-send` stdout `watched|unwatched`와 review-chain의 "unwatched면 보낸 쪽 기록만" 규칙을 유지한다.
- 되돌림 수단 `--drain`/`--undrain`을 유지한다(잠금 없이 표식 + TERM).

비목표:

- 전달 확인(transcript token), 재통지, 교체 잠금, 세대 검증을 다시 만들지 않는다.
- 바깥 점검(inbox-sweep·launchd)을 두지 않는다. 오래 안 읽힌 줄을 사람에게 알리는 기능은 없다.
- 입력창 주입을 하지 않는다.
- 2.8.1(세 머신 배포됨)은 새 판 배포 전까지 고치지 않는다. Agent worker 완료 한 줄(2.8.1)은 그대로 둔다.
- 옛 상태 파일(`subs/<키>.gen`·`pane-gen/`·`wait/<sid>.*`·`*.waiters/`·`*.times`·`known.list`·`sweep/`)을 지우지 않는다(archive-first). 새 core는 읽지 않는다.

## 2. 남기는 계약과 지우는 것

### 2-1. 키와 새 상태 파일

- `<키>` = `pane-<HERDR_PANE_ID의 :를 _>`(herdr 안) 또는 `sid-<세션 id>`(밖). 지금 규칙 그대로다.
  - 사용자 출발점은 `subs/<sid>`였다. pane 키를 남기는 이유: `/clear`·`/compact`·재개 뒤에도 같은 pane이면 구독이 그대로라 이어받기 코드가 필요 없다. 체인 세션은 모두 herdr pane에서 돈다.
  - 대기자 쪽 sid는 훅 JSON `session_id`, `inbox-subscribe` 쪽은 `CLAUDE_CODE_SESSION_ID`다. pane 안에서는 sid를 쓰지 않는다.
- 구독 파일은 지금 위치 `subs/<키>`를 그대로 쓴다. 읽을 때 첫 칸(경로)만 본다(`cut -f1`). 그래서 2.8.1 세션이 만든 `<경로>\t<sid>` 줄도 새 core가 그대로 읽고, 열린 체인의 구독을 옮기는 코드가 필요 없다. 새로 쓰는 줄은 경로 한 칸이다. `subs/<키>.gen`은 읽지도 쓰지도 않는다(남겨 둔다).
- 대기자 표식은 `wait/<키>.pid`다. 옛 core는 `wait/<sid>.pid`(접두어 없음)를 쓰므로 이름이 겹치지 않는다.

| 파일 | 내용 | 쓰는 쪽 |
|---|---|---|
| `subs/<키>` | 줄마다 받은편지함 절대 경로(옛 줄은 뒤에 `\t<sid>`, 무시). 경로 중복 없음 | `inbox-subscribe` (`_aoi_put`, `subs/<키>.flock` fd 9 안) |
| `wait/<키>.pid` | `<pid> <lstart> <token>` (기존 `.watch`와 같은 세 칸) | 대기자 |
| `<log>.notified` | 정수 하나. 깨움으로 알린 마지막 줄 번호 | 대기자 (`_aoi_put`) |
| `inbox/hooks.off` | 있으면 대기자 즉시 0 | `--drain`/`--undrain` |

pane 받은편지함(`pane-<키>.log`)은 키가 pane이면 `.subs`에 없어도 대상에 자동으로 들어간다.

### 2-2. 명령 계약

| 명령 | 인자 | stdout | 종료 |
|---|---|---|---|
| `inbox-send [--raw] <대상> <줄>` | 그대로 | `watched\|unwatched` | 0 / 2 / 4 (기존) |
| `inbox-watch <대상>`·`--ack`·`--pending`·`--release` | 그대로 | 그대로 | 0 / 2 / 4 (e71715a^ 그대로) |
| `inbox-watch --state <대상>` | 그대로 | `monitor\|waiter\|none` | 0 / 2 |
| `inbox-subscribe <대상>` | `[--pane <p>\|--session <sid>]` | 없음 | 0 / 2 키 없음·형식 / 4 기록 |
| `inbox-subscribe --unsubscribe <대상>` | 같음 | 없음 | 0 (없어도 0) / 2 / 4 |
| `inbox-subscribe --list` | 같음 | 줄마다 경로(한 칸) | 0 / 2 |
| `inbox-wait` | stdin 훅 JSON | 없음. 깨움은 stderr | 0 / 2 깨움 / 4 JSON·인자 |
| `inbox-wait --status` | 없음 | `inbox-wait 3` | 0 |
| `inbox-wait --drain` | 없음 | TERM 보낸 수 | 0 / 4 |
| `inbox-wait --undrain` | 없음 | 없음 | 0 / 4 |
| `inbox-wait --session-start` | stdin 버림 | 없음 | 항상 0 (옛 래퍼 호환용 무동작) |

- `--list`는 `<경로>\t<sid>\t<active|dormant>`에서 경로 한 칸으로 바뀐다. 쓰는 곳은 rc 시험 하나(`cut -f1`)라 그대로 통과한다.
- `--state`의 `waiter` 판정: 그 경로를 담은 `subs/*`(또는 pane 키)의 `wait/<키>.pid`가 살아 있고 lstart가 맞으며 `hooks.off`가 없다. `spawn-pane-worker.sh`가 이 값을 쓴다.
- 깨운 대기자는 끝났으므로 깨운 턴 동안 보낸 쪽은 `unwatched`를 받는다. 지금과 같은 참고값이다.
- `inbox-subscribe`는 지금처럼 `_aoi_claim <sid>`(owner·held)를 부른다. pane 안에서 sid가 없으면 claim만 건너뛴다.
- `events.log`는 `send`·`wake` 두 사건만 한 줄씩 남긴다(`ts ev box n`). 실패는 무시한다(경고도 없음).

### 2-3. 지우는 것 (git rm 또는 함수 삭제)

| 위치 | 지우는 것 |
|---|---|
| `lib/inbox-sweep.sh` | 파일 전체 (git rm) |
| `launchd/install-sweep.sh`, `launchd/kr.waymakerlabs.agent-orchestrator.inbox-sweep.plist` | 파일 전체 (git rm, 세 머신 미설치) |
| `manifests/inbox-sweep.manifest` | 파일 전체 (git rm) |
| `test/fake-herdr.py` | sweep용 notification 6줄 |
| `bin/agent-orchestrator` | `inbox-sweep` 분기·머리 주석 46~50행, `--session-start` JSON 예외 문구(6행) |
| `lib/inbox.sh` | `_aoi_flock`의 fd 7·8 지원, `_aoi_recv_lock`·`_aoi_recv_unlock`, `_aoi_known_add`, `_aoi_meta_warn`·`_aoi_meta_fail`, `ao_inbox_append`의 `.times`, `_aoi_watch_state`의 `waiters`·`pane-gen`·`issued` 판정, `_aoi_cleanup`의 fd 7·8, `AO_INBOX_TRACE`·`AO_INBOX_NOW` |
| `lib/inbox-wait.sh` | `_aoiw_pause`, `_aoiw_gen`·`_aoiw_genup`, `_aoiw_subs_del`의 세대, `_aoiw_sub_add`의 owner move, `_aoiw_sub_list`의 active/dormant, `_aoiw_lock`(fd 7), `_aoiw_snap`, `_aoiw_issue_ok`, `_aoiw_recheck`, `_aoiw_adopt`, `_aoiw_unmark`, `_aoiw_deliv`, `_aoiw_grace_over`, 재통지 칸, `--session-start` 본문(issued·pane-gen 발급·additionalContext), drain의 수신 잠금 |
| `plugins/inbox-hooks/hooks/hooks.json` | SessionStart 동기 훅(`session-start`) 한 줄 |
| `plugins/inbox-hooks/scripts/inbox-hook.sh` | `session-start` 모드 |

남기는 함수: `inbox.sh`의 e71715a^ 함수 전부 + `_aoi_flock`(fd 9만)·`_aoi_box_name`·`_aoi_pane_key`·`_aoi_mark_ok`·`_aoi_claim`·`_aoi_event`(축소). `inbox-wait.sh`는 `_aoiw_json`·`_aoiw_sub_key`·`ao_inbox_subscribe`(축소)와 새 `_aoiw_fmt`(지금 형식에서 재통지 표시만 뺌)·대기 루프·drain만 남긴다.

## 3. 새 대기자 동작 순서

`inbox-wait`(훅 Stop·StopFailure·UserPromptSubmit·SessionStart, 모두 asyncRewake):

1. `hooks.off`가 있으면 exit 0.
2. stdin JSON에서 `session_id`·`hook_event_name`을 읽는다(`_aoiw_json`, perl JSON::PP). 해석 실패 4, sid 형식 오류 0.
3. 키 = pane 키(HERDR_PANE_ID) 또는 `sid-<session_id>`. 대상 = `subs/<키>` 첫 칸 경로들 + pane 키면 pane 받은편지함. 대상이 없으면 exit 0.
4. 대상마다 `_aoi_claim <sid>`(owner·held, fd 9). 새 세션이면 미처리 줄이 `[이전 세션]` 보류가 된다.
5. 앞 대기자: `wait/<키>.pid`를 읽어 둔다. 자기 `<pid> <lstart> <token>`을 쓴다(`_aoi_put`). 읽어 둔 pid가 살아 있고 lstart가 맞으면 TERM. 기다리지 않는다.
6. 기준: 대상마다 `base = max(cursor, notified)`. 단 `hook_event_name = SessionStart`면 `base = cursor`(notified 무시).
7. 1초(`AO_INBOX_WAIT_POLL`)마다 대상 줄 수 `n`을 읽는다. 잠금 없음.
8. 10폴링마다 `wait/<키>.pid` 토큰이 내 것인지, `hooks.off`가 없는지 본다. 아니면 exit 0.
9. 어느 대상이든 `n > base`면 깨운다:
   - stderr에 깨움 출력(지금 형식, 재통지 표시 없음): 머리 줄 → `== <경로>` → `#0` 보류 안내(해당 시) → `#<k> <원문 앞 500자>` → 20줄 넘으면 `--pending` 안내.
   - 깨운 대상마다 `<log>.notified`에 `n`을 쓴다(현재 값보다 클 때만).
   - `events.log`에 `wake` 한 줄. 내 토큰일 때만 `.pid`를 지운다. exit 2.
10. `AO_INBOX_WAIT_MAX`(기본 7000)초가 지나면 내 토큰일 때만 `.pid`를 지우고 exit 0.
11. TERM: 내 토큰일 때만 `.pid`를 지우고 exit 0. 깨움 출력 도중 TERM은 막지 않는다(중복·누락 아님, §4).

SessionStart 동기 출력은 뺀다. 6번의 "SessionStart면 cursor 기준"이 같은 일을 한다. `/clear`·`/compact`·재개 직후 async 대기자가 안 읽은 줄을 곧바로 깨움으로 알린다. 그래서 동기 훅·additionalContext JSON·8KB 상한 처리가 모두 필요 없다.

`--drain`: `hooks.off`를 만들고, `wait/*.pid` 중 살아 있고 lstart가 맞는 pid에 TERM을 보내고, 그 수를 stdout에 낸다. 잠금 없음. 늦게 시작한 대기자는 1번에서 끝나고, 이미 돈 대기자는 8번(최대 10초)에서 끝난다. `--undrain`: `hooks.off` 삭제.

## 4. 알려진 빈틈과 받아들이는 이유

공통 규칙 하나로 견딘다. **깨움 목록에 이미 처리한 `#n`이 다시 오면 `--ack`만 한다.** 깨움 출력은 항상 `cursor+1`부터 보여 주므로(notified부터가 아니다), 새 줄 하나가 오면 안 읽은 줄 전부가 다시 보인다.

| 빈틈 | 결과 | 받아들이는 이유 |
|---|---|---|
| 깨운 턴을 사용자가 중단해 처리하지 못함 | 다음 대기자는 `notified` 기준이라 같은 줄로 다시 깨우지 않는다. 다음 새 줄이나 재개·`/clear` 때 함께 보인다 | 사람이 화면 앞에 있는 경우다. 재통지 3회·유예·transcript 확인을 지우는 대가 |
| 깨움 stderr가 런타임에서 유실 | 위와 같다 | S2 실측에서 유실은 없었다(G4). 다음 새 줄에서 회복 |
| 두 세션이 같은 파일을 구독 | 둘 다 깨거나, 늦게 뜬 쪽은 `notified` 때문에 그 줄로 깨지 않는다 | 정상 체인에서는 받은편지함 하나에 받는 쪽 하나다. 인계 때 옛 쪽이 `--unsubscribe`한다 |
| 대기자 교체 경합(앞 대기자가 TERM 직전에 깨움) | 중복 깨움 | 위 공통 규칙 |
| 깨운 턴 동안 대기자 없음 | 보낸 쪽 `unwatched`(참고값). 그 줄은 턴이 끝난 뒤 Stop 대기자가 알린다(`n > notified`) | 지금도 같다 |
| 아무도 구독하지 않은 받은편지함 | 아무도 모른다. 바깥 점검(sweep)이 없다 | review-chain은 `unwatched`를 보낸 쪽 기록에 남긴다. sweep은 설치된 적이 없다 |
| 중단 뒤 사람이 아무것도 안 함 | 새 줄이 와도 깨움은 Stop 대기자가 남아 있을 때만 | S2 ④에서 중단 뒤에도 UserPromptSubmit 대기자가 살아 있었다 |
| 옛 inbox-hooks 0.1.0 래퍼가 새 core를 만남 | 래퍼가 `inbox-wait 2`만 받으므로 조용해진다. 그 세션은 깨지 않는다 | §8 배포 순서로 막는다(열린 체인 세션에 Monitor 안내) |
| 2.8.1 세션의 옛 `subs/` 구독 | 새 core가 경로 칸만 읽으므로 그대로 이어진다. 옛 sid 칸은 무시돼, 같은 pane에서 세션이 바뀌어도 새 세션이 받는다 | 의도한 동작이다. `[이전 세션]` 보류(owner·held)가 앞 세션 줄을 구분한다 |
| `--drain` 직후 최대 10초 | 이미 폴링 중인 대기자가 그 사이 깨울 수 있다 | TERM이 먼저 도착한다. 되돌림 상황에서 깨움 한 번은 무해 |

판 호환 판단: core `--status`는 `inbox-wait 3`을 낸다. 새 래퍼(0.2.0)·`spawn-pane-worker.sh`·스킬 문구는 `inbox-wait 2` 또는 `3`을 받는다. 새 래퍼가 옛 core(2)를 만나도 옛 core는 기능이 더 많으므로 동작한다. 새 core는 옛 래퍼가 부르는 `--session-start`를 무동작 0으로 받아 둔다. 옛 래퍼만 새 core에 막히며, 이것은 §8 순서로 다룬다.

## 5. 시험

`tools/agent-orchestrator/test/run-tests.sh` 받은편지함 절(지금 약 610줄 추가분, 이름 138건 안팎).

남길 것:

- e71715a^에 있던 받은편지함 시험 51건 전부(send·watch·ack·pending·release·owner·held·잠금 겹침). `AO_INBOX_TRACE`를 쓰던 겹침 시험은 trace 대신 결과 파일 줄 수로 본다.
- `inbox-watch-state*`(monitor·none), `inbox-watched`·`inbox-send` stdout 시험.
- `inbox-wait-status`(기대값만 `inbox-wait 3`), `inbox-wait-timeout`, `inbox-wait-wake*`, `inbox-wait-held`, `inbox-wait-cursor`, `inbox-wait-line`(500자 잘림)·`inbox-wait-pending`(20줄 상한), `inbox-wait-no*`(대상 없음·sid 없음).

지울 것:

- `inbox-sweep-*` 전부(install·uninstall·dry·repeat·truncated·external·no).
- `inbox-pane-gen*`, `inbox-start-*`, `inbox-async-start*`, `inbox-wait-session`, `inbox-wait-delivered`·`inbox-wait-undelivered`, `inbox-wait-other`·`inbox-owner-held`의 세대 부분, `inbox-sub-del*`(장벽), `inbox-wait-fd`, `inbox-wait-term*`(통지 확정 구간 TERM), `inbox-send-meta*`, `AO_INBOX_TEST_PAUSE` 쓰는 경쟁 시험 전부, `inbox-off-before-register`·`inbox-drain-after-register`·`inbox-drain-notify-race`.

새로 쓸 것(10건):

| 이름 | 확인 |
|---|---|
| `inbox-sub-list` | subscribe 2회 같은 경로 → `--list` 한 줄, unsubscribe 뒤 빈 출력, 없는 경로 unsubscribe 0 |
| `inbox-sub-nokey` | pane·sid 둘 다 없음 → 2 |
| `inbox-wait-pane-auto` | `HERDR_PANE_ID`만 있고 subs 없음 → pane 받은편지함 새 줄에 exit 2 |
| `inbox-wait-notified` | 깨움 뒤 `.notified`=n, 같은 sid 새 Stop 대기자는 새 줄 전에는 깨지 않음(타임아웃 0) |
| `inbox-wait-ss-cursor` | `.notified`=n·cursor<n 상태에서 SessionStart 대기자는 곧바로 exit 2 |
| `inbox-wait-replace` | 같은 키 대기자 A 뒤 B → A는 TERM으로 0, `.pid`는 B 토큰 |
| `inbox-wait-stale-pid` | A가 B의 `.pid`를 지우지 않음(A 종료 순서를 B 등록 뒤로) |
| `inbox-wait-off` | `hooks.off` → 즉시 0, stderr 빈 출력 |
| `inbox-drain` | 대기자 2개 → `--drain` stdout 2, 둘 다 0으로 끝남, `--undrain` 뒤 다시 깨움 |
| `inbox-wait-ss-noop` | `--session-start` → stdout 빈 출력, 0 |

`watch-state-waiter`(대기자 살아 있을 때 `--state`=`waiter`)는 기존 시험을 새 파일 위치로 고쳐 남긴다.

다른 시험:

- `plugins/inbox-hooks/scripts/test/run-tests.sh`: `session-start` 모드 시험을 빼고, 래퍼가 `inbox-wait 2`·`3` 모두 통과·그 밖은 무동작인지 본다.
- `plugins/review-chain/.../run-rc-tests.sh`: `rc-watch-subscribe`는 그대로 통과해야 한다(`cut -f1`). 다른 rc 시험은 바꾸지 않는다.
- `plugins/auto-chain/.../run-tests.sh`: `spawn-parent-*`의 가짜 AO 기본 상태값을 `inbox-wait 3`으로, `inbox-wait 2`도 판정하는 경우 1건 추가.
- 하니스 점검: 세 시험 묶음의 PASS·FAIL 총계와 이름 목록(`pass.names`)을 지우기 전·후로 대조한다. 지운 이름 목록은 보고서에 적는다.
- 실측(한 번, 이 맥): 시험 상태 폴더(`AO_STATE_ROOT=/tmp/...`)의 Claude 세션 하나에서 Stop 깨움·`/clear` 뒤 깨움·교체 TERM을 본다. S2의 `launch.sh` 방식을 따른다.

## 6. 스킬·README 수정 목록

공통 문구(두 체인 같은 뜻):

- 받기: "받은편지함이 정해지면 `"$AO" inbox-subscribe <받은편지함>` 한 번. pane 받은편지함은 구독 없이 자동. 깨움에 처리한 `#n`이 다시 오면 `--ack`만 한다."
- 훅 없는 도구: "Codex·OpenCode·kiro-cli, 또는 `inbox-wait --status`가 `inbox-wait 2`·`3`이 아니면 Monitor `inbox-watch <받은편지함>`." 판정 문구는 이 한 곳(체인마다 진본 한 곳)에만 둔다.
- 인계: "① 처리한 마지막 번호까지 `--ack` ② `--unsubscribe` ③ 인계 문서에 받은편지함 경로 ④ 새 조정자가 `inbox-subscribe` 뒤 `--pending`." `[이전 세션]` 보류 처리(확인 뒤 `--release`)는 지금 문구를 그대로 둔다.
- 지우는 문구: `--list`의 active/dormant, 재통지·유예, delivered, sweep 15분 알림, SessionStart additionalContext, 세대·pane-superseded 설명.

| 파일 | 고칠 곳 |
|---|---|
| `plugins/auto-chain/skills/autonomous-chain/SKILL.md` | 43·44행(받기·대체), 51행(pane 받은편지함 자동), 53행(조정자 구독), 54행(인계 순서) |
| `plugins/auto-chain/skills/autonomous-chain/references/pane-worker.md` | 75행(조정자 구독), 169행(인계 순서) |
| `plugins/auto-chain/skills/autonomous-chain/references/task-brief.md` | 24행(worker 착수 구독). §7 완료 한 줄(2.8.1)은 그대로 |
| `plugins/auto-chain/skills/autonomous-chain/scripts/spawn-pane-worker.sh` | 42·152~156행: `inbox-wait 2`·`3` 모두 판정 |
| `plugins/auto-chain/README.md` | 2.9.0 항목 추가(단순화·sweep 삭제) |
| `plugins/review-chain/skills/review-chain/SKILL.md` | 113행(대체), 받기·인계 문구 |
| `plugins/review-chain/skills/review-chain/references/messages.md` | 17행(대체 진본), 깨움 처리 규칙 |
| `references/oc-handover.md`·`state-files.md`·`worker-brief.md`·`launch.md` | 인계 4단계, 상태 파일 표에서 subs 형식 |
| `plugins/review-chain/skills/review-chain/scripts/rc-watch.sh` | 주석 19~21행만(동작 그대로) |
| `plugins/review-chain/README.md` | 0.3.0 항목 |
| `plugins/inbox-hooks/README.md` | 18~31행: 판정 설명을 §3 요약으로, `--session-start` 삭제 |
| `plugins/inbox-hooks/hooks/hooks.json` | SessionStart 동기 훅 삭제(async 대기자는 유지) |
| `plugins/inbox-hooks/scripts/inbox-hook.sh` | `session-start` 모드 삭제, `inbox-wait 2\|3` 통과 |
| `tools/agent-orchestrator/bin/agent-orchestrator` | 머리 주석 5~6·39~50행, `inbox-sweep` 분기 |
| 세 `plugin.json` + `.claude-plugin/marketplace.json` | 판 동기화: auto-chain 2.9.0, review-chain 0.3.0, inbox-hooks 0.2.0 |
| 루트 `README.md` | inbox-hooks·sweep 언급이 있으면 맞춘다 |

`rc-send.sh`·`rc-claim.sh`·`rc-note-unwatched.sh`는 고치지 않는다(`watched|unwatched` 계약이 그대로다).

## 7. 세션 나누기

브랜치 `feat/inbox-simplify`(main에서). 두 세션으로 나눈다.

**S1. core·래퍼·시험 (main 세션 하나)**

- 할 일: §2-3 삭제(git rm 포함), `inbox.sh` 축소, `inbox-wait.sh` 재작성(§3), `inbox-hook.sh`·`hooks.json`, 세 시험 묶음 정리(§5), `bin/agent-orchestrator` 주석·분기.
- 큰 파일은 뼈대 Write 뒤 함수 단위 Edit(한 번 150줄·8KB 이하).
- 종료 조건: ① 세 시험 묶음 FAIL 0, PASS·지운 이름 목록을 보고서에 대조 ② `shellcheck` 변경 파일 경고 0(기존 수준) ③ 이 맥 실측 세션 1회(Stop 깨움·`/clear` 뒤 깨움·교체 TERM) 통과 ④ §9 줄 수 확인 ⑤ 커밋(경로 지정). 보고서 `docs/plans/2026-11-11-inbox-simplify-S1-report.md`.

**S2. 스킬·README·판·배포**

- 할 일: §6 문구, 판 동기화(plugin.json·marketplace.json), 루트 README 534행 확인, rc·auto-chain 시험 재실행, main 병합, push, 세 머신 갱신(§8).
- 종료 조건: ① 두 체인 스킬에 `inbox-subscribe`·인계 4단계 문구가 진본 한 곳씩, 지운 문구(dormant·재통지·sweep·additionalContext) grep 0 ② 세 머신 `installed_plugins.json` 판과 `agent-orchestrator inbox-wait --status` = `inbox-wait 3` 출력 첨부 ③ 머신마다 시험 세션 1회 깨움 확인.
- 이 묶음은 배포(되돌리기 어려움)라 종료 직후 크로스체크 1회 의무.

## 8. 배포·되돌림

배포 순서(머신마다 office·home-macmini·gsr-macbook):

1. push 전에 열린 체인 세션 목록을 본다(`agent-orchestrator list`). core는 마켓 폴더 symlink(`~/.local/bin/agent-orchestrator` → marketplaces/…)라 `claude plugin update` 순간 core가 바뀐다. 이때 이미 열린 세션의 0.1.0 래퍼는 `inbox-wait 3`을 모르고 조용해진다(§4).
2. 그래서 push → 머신마다 `claude plugin marketplace update waymakerlabs-claude-plugins` → `claude plugin update auto-chain` `review-chain` `inbox-hooks`를 한 번에 하고, 열린 체인 세션에는 사용자가 탭에서 "Monitor `inbox-watch <받은편지함>` 켜라" 한 줄을 알린다. 다음 인계부터 새 세션은 새 래퍼(0.2.0)를 읽는다.
3. 확인: `inbox-wait --status` = `inbox-wait 3`, `installed_plugins.json` 판 셋, 시험 상태 폴더 깨움 1회.
4. 옛 sweep: 세 머신 모두 미설치(S5 보고). `ls ~/Library/LaunchAgents | grep inbox-sweep`가 0인지만 본다.

되돌림(작은 것부터):

| 단계 | 방법 | 확인 |
|---|---|---|
| A. 깨움 끄기 | 머신마다 `agent-orchestrator inbox-wait --drain` | stdout 수, 10초 뒤 `pgrep -f 'inbox-wait'` 0 |
| B. Monitor 복귀 | 열린 세션에 Monitor `inbox-watch` 안내. 스킬 대체 문단이 그대로 쓰인다 | `inbox-watch --state` = `monitor` |
| C. 코드 되돌림 | 병합 커밋 `git revert` → 판 올림(auto-chain 2.9.1·review-chain 0.3.1·inbox-hooks 0.2.1, 내용은 2.8.1·0.2.0·0.1.0) → push → 세 머신 update | `--status` = `inbox-wait 2` |

- C 뒤 옛 core는 `subs/<키>`의 경로 한 칸 줄을 sid 없는 줄로 읽는다. 그 줄은 옛 recheck에서 `unsubscribed`로 끝날 수 있다. C를 하면 열린 세션은 B(Monitor)로 받고, 다음 인계에서 옛 문구로 다시 구독한다.
- 옛 상태 파일은 지우지 않았으므로 C에 이행 작업이 없다.

## 9. 목표 줄 수

| 파일 | 지금 | 목표 |
|---|---|---|
| `lib/inbox.sh` | 371 | 270 이하 (e71715a^ 241 + 대상·`--state` 판정) |
| `lib/inbox-wait.sh` | 630 | 200 이하 |
| `lib/inbox-sweep.sh` | 232 | 0 (git rm) |
| `launchd/`·`manifests/inbox-sweep.manifest` | 126 | 0 (git rm) |
| `plugins/inbox-hooks/scripts/inbox-hook.sh` | 31 | 25 이하 |
| `plugins/inbox-hooks/hooks/hooks.json` | 35 | 32 이하 |
| `test/run-tests.sh` 받은편지함 절 | 약 610 추가분 | 약 300 (51 + 유지 15 + 새 10, 70건 안팎) |

합계: core 받은편지함 코드 1233줄 → 470줄 이하. S1 보고서에 `wc -l` 출력을 붙인다.

## 10. 리뷰 반영 (codex Sol high 1회, BLOCK high 4 — 모두 반영, 이 절이 §3·§4·§8보다 우선)

1. **깨움 중 TERM**(§3 9·11번): 깨움 출력 시작부터 exit 2까지 TERM을 무시한다(`trap '' TERM`). A가 `notified`를 쓰고 TERM으로 0이 되어 그 줄을 영영 놓치는 경우를 막는다. 시험 `inbox-wait-term-notify` 1건(정지 지점 1개만 남긴다: `notify-mid`).
2. **`.pid`를 지우지 않는다**(§3 9·10·11번): 종료할 때 `wait/<키>.pid`를 지우지 않는다. 살아 있는지는 pid·lstart로 판정하므로 죽은 표식은 무시된다. 확인→삭제 사이에 후임 표식을 지우는 경합이 사라진다. 시험 `inbox-wait-stale-pid`를 이 뜻으로 바꾼다.
3. **7000초 만료**(§3 10번): 구독 대상이 있으면 만료 때 exit 2로 깨운다. stderr는 한 줄 `[inbox] 대기 만료(재등록) — 새 메시지 없음. 할 일 없으면 아무 말 없이 쉬어라`. 다음 Stop에서 대기자가 다시 뜬다. 기존 판도 만료 뒤 대기자가 없던 빈틈이다. 시험 `inbox-wait-expire-rewake`(짧은 MAX → exit 2 → 새 대기자 → 새 줄 깨움).
4. **배포 호환**(§4 마지막 행·§8): core `--status`를 **`inbox-wait 2` 그대로 둔다**(판 3 도입 안 함). 옛 0.1.0 래퍼가 새 core를 계속 부르고, 새 core는 같은 stdin·종료 코드 계약(0/2/4)을 지킨다. 옛 래퍼의 `--session-start`는 무동작 0. 그래서 열린 2.8.1 세션도 끊기지 않고, Monitor 안내 단계가 필요 없다. 래퍼·스킬·`spawn-pane-worker.sh`의 판정 문구도 바꾸지 않는다.
