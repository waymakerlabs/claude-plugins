---
title: 받은편지함 감시 끊김 방지 — 구현 계획
status: review-capped   # rev 5 — codex 3회 + delta 1회 소진, 마지막 BLOCK F1 추천 수정 반영(재검토 없음, §6-5). SHIP 아님 — 조건부로 S1 진행
revision: 5
date: 2026-11-11
design: docs/design/inbox-reliability.md (revision 4)
contract: docs/plans/2026-11-08-agent-orchestrator-plan.md §1-4 (받은편지함 계약 진본 — S1·S3에서 이 문서의 계약을 그곳에 옮긴다)
review: required   # 훅 설치·launchd·스킬 규약 변경 포함
---

# 받은편지함 감시 끊김 방지 — 구현 계획

설계 문서(이하 "설계")의 B안(훅 `asyncRewake` 대기자)과 D안(launchd 바깥 점검)을 다섯 세션으로 나눠 구현한다. 이 문서는 세션마다 무엇을 바꾸고, 무엇으로 끝났다고 판정하고, 어떻게 되돌리는지를 정한다. 구현은 하지 않았다.

## 0. 읽는 법·개정 이력

- §1 공통 관례 → §2 계약 → §3 세션별 작업 → §4 판 올림·게시·되돌림 → §5 위험·실측 게이트 → §6 설계와 다르게 정한 점·리뷰 처리표.
- rev 1 → rev 2: 1회차 리뷰 finding 1~15를 모두 반영했다. 처리 위치는 §6-2 표에 있다. 바뀐 핵심은 아래 다섯 가지다.
  - 모든 훅이 같은 순서(owner·held 확정 → 통지)를 따른다.
  - 구독 해제는 장벽으로 동작한다.
  - 대기자를 Stop만이 아니라 SessionStart·StopFailure·UserPromptSubmit에서도 띄운다.
  - 통지는 교체 잠금 안에서만 하고, 재통지 억제는 "다음 훅 입력이 왔다"는 전달 확인에 묶는다.
  - `.watch` 형식은 바꾸지 않고, sweep은 도착 시각 사이드카로 나이를 잰다.
- rev 2 → rev 3: 2회차 리뷰 새 finding 1~10을 반영했다(처리표 §6-3). 바뀐 핵심은 아래와 같다.
  - **수신 잠금 하나(fd 8, 전역 `recv.flock`)**: 구독 변경·owner 확정·통지 예약·SessionStart 출력·대기자 등록·drain이 모두 이 잠금 안에서 목록·세대를 스냅샷하고 다시 검증한다. pane 키와 sid 키를 따로 잠그지 않으므로 bash 3.2에서 fd 하나로 끝난다.
  - **pane 수신 세대**: 같은 pane에 새 sid가 오면 옛 sid 대기자는 다음 검증에서 폐기된다.
  - **전달 확인은 transcript 증거 또는 ack뿐이다.** 훅 이벤트 이름은 대기자를 다시 띄우는 계기로만 쓴다.
  - 송신은 받은편지함 append 성공이 곧 기록 확정이다. 부가 기록 실패는 경고만 내고 exit 0이다.
  - 인계 순서를 "처리 동결 → 진행 중 처리 종료 → 처리 완료 번호까지만 ack → 구독 해제"로 고쳐 review-chain `oc-handover.md` 규칙과 맞췄다.
  - 시험 상태 루트를 격리하고(`AO_STATE_ROOT`), 실제 상태 폴더가 바뀌지 않았음을 시험 조건에 넣었다.
- rev 3 → rev 4(3회차 N1~N4, 최소 수정, 처리표 §6-4):
  - SessionStart stdout을 잠금 안에서 쓴다(8KB 상한).
  - pane 세대는 SessionStart 동기 훅만 올리고, 대기자는 발급 세대를 검증한다.
  - `ackts`에 전진 범위를 기록한다.
  - TERM 직접 주입 시험을 추가했다.

## 1. 공통 관례 (기존 `lib/inbox.sh`를 따른다)

- **셸**: macOS `/bin/bash` 3.2 호환. 연관 배열·`${var,,}`·`mapfile`·`wait -n`·`flock(1)`을 쓰지 않는다. 정규식은 `[[ =~ ]]`만 쓴다.
- **종료 코드**: 받은편지함 동작은 0 / 2(인자·대상 형식) / 4(기록·잠금·ack 실패)만 낸다(계약 §1-1 마지막 줄). 예외는 `inbox-wait`의 exit 2(깨움)다. 이것은 Claude Code 훅 규약의 값이라 `inbox-wait`만 인자 오류를 4로 낸다(§2-4).
- **오류 출력**: `ao_die <코드> <사유>`(stderr 한 줄).
- **잠금**: 커널 flock을 `/usr/bin/perl`이 상속받은 fd에 건다(기존 `_aoi_lock` 방식). 용도마다 fd와 파일을 나눈다.

  | fd | 파일 | 용도 | 쥐는 시간 |
  |---|---|---|---|
  | 9 | `<log>.flock` | 받은편지함 기록·cursor·owner·held·times (기존) | 순간 |
  | 8 | `recv.flock` (상태 루트에 하나) | **수신 잠금**: 모든 `subs/*`·`.gen`·`pane-gen/*`·`wait/*.pid`·`notified`·`hooks.off` 읽기·쓰기, 통지 예약, SessionStart 출력 결정, drain | 순간(통지 확정·출력 구간 포함, 수 ms) |
  | 7 | `wait/<sid>.swap` | 같은 sid 대기자의 교체 대기(앞 대기자가 사라질 때까지 줄 세우기) | 교체 최대 3초 |
  | 6 | `sweep/state.flock` | sweep 겹침 방지 | sweep 한 번 |

  잠금 순서는 항상 7 → 8 → 9다(역순으로 잡지 않는다 — 교착 방지). 잠금을 쥔 채 자식 프로세스를 띄우지 않는다. rev 2의 키별 fd 8(`subs/<키>.flock`)은 폐기했다(2회차 새 #1). pane 키와 sid 키를 함께 잠가야 하는데, bash 3.2에는 fd를 동적으로 여는 `{var}>` 문법이 없어 키 수만큼 fd를 고정할 수 없기 때문이다. 수신 잠금은 대기자 수와 상관없이 쥐는 시간이 수 ms라 경합 비용이 작다. 1초 폴링의 "새 줄이 있나" 확인은 잠금 없이 줄 수만 읽고, 통지할 때만 잠근다.
- **상태 루트**: `AO_STATE_ROOT`(기본 `$HOME/.local/state/agent-orchestrator`). `AO_INBOX_DIR`는 `$AO_STATE_ROOT/inbox`에서 파생된다. 끄기 표식은 `$AO_STATE_ROOT/inbox/hooks.off`다(rev 2의 `~/.config/…` 위치에서 옮겼다 — 수신 잠금 안에서 읽어야 하므로 같은 루트에 둔다). pane 받은편지함 경로도 이 루트를 따른다. 시험은 반드시 `AO_STATE_ROOT=<임시 폴더>`로 실행한다(2회차 새 #8).
- **파일 갱신**: `_aoi_put`(pid별 임시 파일 → `mv`). 생성은 `: >>`(비파괴).
- **진입점**: `bin/agent-orchestrator`의 받은편지함 분기(`inbox-send|inbox-watch)`, 69행 부근)에 새 동작 이름을 더한다. 백엔드 결정 전에 처리하므로 herdr 밖·`AGENT_ORCHESTRATOR_BACKEND=none`에서도 동작한다.
- **시험**: `test/run-tests.sh`의 `env -i` 격리(`HOME="$T/home"`, 가짜 herdr PATH), `ok`/`bad`/`chk` 헬퍼, 끝의 `EXPECT` 총계 대조를 그대로 쓴다. 경쟁 구간 시험은 시험 전용 환경 변수 `AO_INBOX_TEST_PAUSE=<지점>:<초>`로 그 지점에서 멈춰 결정적으로 만든다(기존 `AO_INBOX_TRACE`와 같은 방식). 지점 이름은 §2에 적는다.
- **상태 폴더**: `$AO_INBOX_DIR` 아래에 새 하위 폴더 `subs/`·`pane-gen/`·`wait/`·`sweep/`와 파일 `recv.flock`·`known.list`·`events.log`·`hooks.off`를 둔다.
- **시험 격리 조건**(모든 시험 묶음 공통, 2회차 새 #8): `AO_STATE_ROOT=$T/state`와 `HOME=$T/home`을 함께 지정한다. 자동 pane 대상이 끼지 않게 `HERDR_PANE_ID`는 unset하고, pane 대상이 필요한 케이스만 가짜 값을 준다. 시험 앞뒤로 실제 `~/.local/state/agent-orchestrator`의 `find … -newer` 스냅샷을 대조해 **변경 0**을 확인하는 케이스 `inbox-real-state-untouched`를 맨 끝에 둔다.
- **한 번의 Write·Edit는 약 150줄·8KB 이하**로 한다(세션 지시서에도 이 줄을 적는다).

## 2. 계약 세부

### 2-1. 새 상태 파일

| 경로(`$AO_INBOX_DIR` 기준, 받은편지함 옆 파일은 `<log>.`) | 내용 |
|---|---|
| `subs/<키>` | 줄마다 `<받은편지함 절대 경로>\t<등록한 세션 id>`. 경로 중복 없음 |
| `subs/<키>.gen` | 구독 세대(정수). 그 키의 줄이 바뀔 때마다 +1 |
| `pane-gen/<pane 키>` | **pane 수신 세대** `<gen>\t<지금 이 pane의 sid>`. SessionStart 동기 훅만 +1 한다 (2회차 새 #4, 3회차 N2) |
| `wait/<sid>.issued` | 이 sid에 발급된 pane 세대 `<pane 키>\t<gen>`. SessionStart 동기 훅만 쓴다 |
| `recv.flock` | 수신 잠금 파일(fd 8, §1) |
| `hooks.off` | 끄기 표식. 있으면 대기자 등록·통지·SessionStart 출력이 모두 무동작 |
| `<log>.ackts` | 줄마다 `<from>\t<to>\t<epoch>`. `inbox-watch --ack`가 cursor를 `from−1`에서 `to`로 **실제로 전진시킨 범위**를, 같은 fd 9 잠금 안에서 덧붙인다(2회차 새 #10, 3회차 N3). 전진이 없으면(작은 값 ack) 쓰지 않는다 |
| `wait/<sid>.pid` | 지금 대기자 `<pid> <lstart> <token>` (PID 재사용 판별, finding 5) |
| `wait/<sid>.swap` | 교체·통지 확정 잠금 파일(fd 7) |
| `wait/<sid>.notified` | 받은편지함마다 `<경로>\t<알린 마지막 줄 n>\t<pending\|ctx\|delivered>\t<알린 token>\t<재통지 횟수>`. `ctx` = SessionStart 동기 출력으로 알렸고 아직 전달 증거가 없는 상태(§2-6) |
| `<log>.waiters/<sid>` | 대기자 감시 표식. 내용은 기존 `.watch`와 같은 `<pid> <lstart> <token>` 세 칸 |
| `<log>.times` | 줄마다 `<줄 번호>\t<도착 epoch>`. `inbox-send`가 기록 잠금 안에서 쓴다 |
| `known.list` | sweep 대상 받은편지함 절대 경로 |
| `sweep/obs` | 도착 시각이 없는 줄의 관측 시각 `<경로>\t<줄 n>\t<첫 관측 epoch>` |
| `sweep/alerts` | `<경로>\t<마지막 경보 epoch>\t<경보한 backlog id>`. ack로 지우지 않는다 |
| `events.log` | 사건 기록(§2-9) |

- `<키>`는 `pane-<HERDR_PANE_ID의 :를 _>`(herdr 안) 또는 `sid-<세션 id>`(herdr 밖)이다. 설계 §5-2의 `subs/<session_id>`를 pane 키까지 넓혔다(§6-1 D1).
- **`.watch`는 형식·의미를 바꾸지 않는다**(finding 6). 기존 `inbox-watch` Monitor만 쓴다. 대기자는 `.watch`를 건드리지 않고 `<log>.waiters/<sid>`를 쓴다. 옛 판 `inbox-send`는 이 폴더를 모르므로 대기자만 있는 받은편지함을 `unwatched`로 본다. 이것은 보수적인 오답이고 거짓 `watched`는 생기지 않는다.
- **깨움 표식은 두지 않는다**(finding 7, rev 1의 `wake` 표식 폐기). 깨운 대기자는 자기 `waiters/<sid>`를 지우고 끝난다. 깨운 턴을 처리하는 동안 보낸 쪽은 `unwatched`를 받는다. 이 기록은 참고값이고, 그 줄은 다음 대기자가 시작하자마자 알린다(§2-5).

### 2-2. 감시 유효성 판정 `_aoi_watch_state` (공용)

`inbox-send`·`inbox-wait --status`·`spawn-pane-worker.sh`의 부모 확인이 모두 이 함수 하나를 쓴다(finding 7 "같은 유효성 판정").

- `monitor`: `.watch`의 pid가 살아 있고 `ps lstart`가 일치한다(기존 판정 그대로).
- `waiter`: `waiters/*` 중 하나의 pid가 살아 있고 lstart가 일치하며, 그 sid의 `wait/<sid>.pid` 토큰과 같다. 또 pane 받은편지함이면 `pane-gen`의 gen·sid가 그 sid의 `issued`와 같고, `hooks.off`가 없어야 한다. 교체로 밀려났거나 같은 pane의 새 세션에 밀려난 표식은 유효하지 않다.
- 둘 다 아니면 `none`. `inbox-send` stdout은 `monitor|waiter`면 `watched`, `none`이면 `unwatched`다. 출력 값의 종류는 그대로 두 개다.

### 2-3. owner·held 확정 `_aoi_claim` (모든 읽기 경로의 첫 단계, finding 1)

- 기존 `_aoi_watch`의 owner 블록(194~207행)을 `_aoi_claim <log> <sid>`로 떼어 낸다. 동작은 바꾸지 않는다: fd 9를 잡고, owner가 다른 sid이고 미처리 줄이 있으면 `held`를 `cursor+1..마지막 줄`로 다시 잡은 뒤 owner를 쓴다.
- **부르는 곳과 순서는 모두 같다**: ① 대상 계산 → ② 대상마다(경로 사전순) `_aoi_claim` → ③ cursor·held·notified 읽기 → ④ 출력. 이 순서를 지키는 곳은 `inbox-watch`(기존), `inbox-subscribe`, `inbox-wait`(시작할 때마다), `inbox-wait --session-start`다. ②보다 먼저 줄을 내보내는 경로는 없다.
- pane 받은편지함(`pane-<id>.log`)도 ②에 포함된다. `/clear`로 같은 pane에 새 sid가 오면 A의 미처리 줄은 B에게 `#0 [이전 세션 …]`·`[이전 세션]`으로만 보인다(rev 1 반례 해소).
- **pane 수신 세대**(2회차 새 #4, rev 4에서 3회차 N2 반영):
  - **세대를 올리는 것은 SessionStart 동기 훅(`--session-start`)뿐이다.** SessionStart는 세션 전환 이벤트(`startup|resume|clear|compact|fork`)다. 동기 훅은 수신 잠금(fd 8) 안에서 `pane-gen/<pane 키>`를 `<gen+1>\t<자기 sid>`로 바꾸고, 같은 잠금 안에서 발급 기록 `wait/<sid>.issued`에 `<pane 키>\t<gen+1>`을 쓴다. 기록된 sid가 자기 sid와 같으면(compact) 세대를 올리지 않고 현재 gen을 발급 기록으로 쓴다.
  - **Stop·StopFailure·UserPromptSubmit 대기자와 async SessionStart 대기자는 세대를 올리지 않는다.** 등록 때와 통지 직전에 `wait/<sid>.issued`의 gen과 현재 `pane-gen`의 gen·sid가 모두 같을 때만 진행한다. 다르면 세대를 건드리지 않고 `why=pane-superseded`로 끝난다(exit 0). 발급 기록이 없으면 `why=no-issue`로 끝난다. 이 플러그인이 켜진 세션은 시작 때 SessionStart가 늘 실행되므로, 발급 기록이 없는 경우는 훅 설치 전에 열린 세션뿐이다(R5와 같다).
  - async SessionStart 대기자는 같은 이벤트의 동기 훅과 병렬로 실행된다(G8). 그래서 **발급 기록과 현재 `pane-gen`의 pane·gen·sid가 모두 일치할 때까지** 최대 10초(동기 훅 timeout) 기다린다. 매 확인은 수신 잠금 안에서 하고, 0.2초 대기 간격에는 잠금을 놓는다(정지 지점 `issue-wait`). 발급 기록이 이미 있어도(resume 전 옛 기록) 일치하지 않으면 종료하지 않고 계속 기다린다. 10초가 넘으면 `why=no-issue`다(delta 재검토 F1 — rev 4의 "기록이 생길 때까지"는 옛 기록이 남은 resume에서 대기자를 조기 종료시켰다).
  - 결과: 지연된 옛 훅(A의 Stop이 `pre-register`에서 늦어짐)은 B의 SessionStart가 세대를 올린 뒤에 깨어나도 세대를 되찾지 못한다. A의 발급 gen ≠ 현재 gen이기 때문이다. 이 판단은 런타임이 옛 대기자를 자동 취소하는지와 상관없다.
  - 옛 sid가 의도적으로 돌아오는 경우(B를 닫고 A를 `--resume`)는 A의 SessionStart(resume)가 새 전환으로 세대를 올리고 A에게 새로 발급한다. 그 pane의 수신자는 **가장 최근에 SessionStart를 실행한 세션**이다.
  - 같은 pane의 `pane-` 키 구독 줄 중 옛 sid 줄은 §2-3 표대로 이어받거나 휴면으로 바뀐다.

**새 세션이 이어받는 범위**(SessionStart의 `source`로 정한다):

| `source` | pane 받은편지함 | 같은 pane 키의 구독 줄 | `sid-` 키 구독 |
|---|---|---|---|
| `compact` | 이어받음(sid 같음) | 이어받음 | 이어받음 |
| `resume` | 이어받음. sid가 바뀌었으면 `_aoi_claim`이 held 처리 | 줄의 sid를 새 sid로 고치고 claim(자동 이어받기 — 같은 대화의 재개) | 옮기지 않음(옛 sid를 알 수 없다) |
| `clear`·`fork`·`startup` | 이어받음. claim으로 held 처리 | **휴면**: 감시하지 않고 SessionStart 안내에 "이 pane에 이전 세션 구독 k개 — 이어받으려면 `inbox-subscribe`" 한 줄 | 옮기지 않음 |

- 대기자는 구독 줄의 sid가 자기 sid와 같은 것만 감시한다. 휴면 줄은 sweep만 본다.
- resume·fork 때 sid가 실제로 바뀌는지는 실측 게이트 G3이다(§5).

### 2-4. `inbox-subscribe` — 구독 해제는 장벽이다 (finding 2)

```
agent-orchestrator inbox-subscribe [--pane <pane>|--session <sid>] <대상>
agent-orchestrator inbox-subscribe --unsubscribe [--pane <pane>|--session <sid>] <대상>
agent-orchestrator inbox-subscribe --list [--pane <pane>|--session <sid>]
```

- 키는 `--pane` > `--session` > `HERDR_PANE_ID` > `CLAUDE_CODE_SESSION_ID` 순서로 정한다. 등록 sid는 `--session` 값 또는 `CLAUDE_CODE_SESSION_ID`다. 키나 sid가 없으면 2(사유 "구독 키 없음").
- `<대상>`은 `_aoi_resolve` 규칙 그대로다. 받은편지함 파일은 `: >>`로 만든다.
- **등록**: 수신 잠금(fd 8) 안에서 다음을 한다. 줄 `<경로>\t<sid>`를 추가한다(같은 경로가 다른 sid로 있으면 sid를 고친다). `.gen`을 +1 한다. 옛 owner sid의 `sid-` 키에 같은 경로가 있으면 그 줄을 지우고 그 키의 `.gen`도 +1 한다(설계 §5-2 "owner 교체 시 이동"). 그다음 `_aoi_claim <경로> <sid>`(owner·held 확정, fd 9 — 잠금 순서 8 → 9)를 한다. 잠금을 놓은 뒤 `known.list`에 추가한다.
- **해제(장벽)**: 수신 잠금 안에서 줄을 지우고 `.gen`을 +1 한 뒤 0을 돌려준다. 통지 확정(§2-5 6번)과 SessionStart 출력(§2-6)은 모두 같은 수신 잠금 안에서 "지금 이 대상이 내 sid로 구독돼 있고 세대가 스냅샷과 같다"를 다시 확인한 뒤에만 출력한다. 그래서 해제는 진행 중인 출력이 끝날 때까지 기다린다. **해제가 0으로 돌아온 뒤에는 어느 경로(async 대기자·SessionStart 동기 출력)도 그 대상을 통지하지 않는다.** 해제 직전에 이미 나간 통지는 회수할 수 없다. 그 줄은 처리하지 않았다면 ack하지 않고 남겨 새 수신자가 받게 한다(인계 순서 §2-10).
- 없는 줄을 해제하면 0이다. 빈 구독 파일은 지운다(§6-1 D6).
- `--list`: `<경로>\t<sid>\t<active|dormant>` 한 줄씩(여러 줄 출력 예외에 추가).
- stdout: 등록·해제 때 빈 출력. 종료 코드 0 / 2 인자·대상·키 / 4 기록·잠금.
- 시험 정지 지점: `sub-del-locked`(fd 8을 쥔 채 멈춤).
- **대상 스냅샷 `_aoi_targets <sid>`**(공용, 2회차 새 #1): 수신 잠금 안에서 pane 받은편지함, `subs/pane-<pane>`·`subs/sid-<sid>`의 자기 sid 줄, 그 키들의 `.gen`, `pane-gen`, `hooks.off` 유무를 **한 번에** 읽어 스냅샷으로 돌려준다. 목록과 세대를 따로 읽어 섞이는 경우는 없다. `_aoi_recheck <스냅샷>`은 같은 잠금 안에서 현재 값이 스냅샷과 같은지(대상마다 구독 membership·sid, 키 세대, pane-gen sid, `hooks.off` 없음) 본다. 출력하는 모든 경로는 "잠금 → recheck → 출력·상태 기록 → 잠금 해제" 순서다.

### 2-5. `inbox-wait` — 대기자 (훅 전용)

```
agent-orchestrator inbox-wait                  # stdin = 훅 입력 JSON. Stop·StopFailure·UserPromptSubmit·SessionStart(async)
agent-orchestrator inbox-wait --session-start  # stdin = SessionStart JSON. 동기, additionalContext 출력(§2-6)
agent-orchestrator inbox-wait --status         # 기능 조회. stdout "inbox-wait 2"(계약 판 번호), exit 0. stdin 안 읽음
agent-orchestrator inbox-wait --drain          # 되돌림 단계 B·C(§4-3). 수신 잠금 안에서 hooks.off 생성 + 모든 wait/*.pid 비움 → 잠금 밖에서 그 대기자들에 TERM. stdout 철회 수, 0/4
agent-orchestrator inbox-wait --undrain        # hooks.off 제거(다시 켜기). 0/4
```

**어느 훅에서 띄우는가**(finding 3). 설계의 "쉬기 시작하는 순간은 언제나 Stop"은 틀렸다. 사용자 중단 때는 Stop이 실행되지 않고, API 오류 때는 StopFailure가 실행된다(code.claude.com/docs/en/hooks#stop).

| 훅 | 역할 | 덮는 경우 |
|---|---|---|
| Stop (`asyncRewake`) | 기본 | 턴이 정상으로 끝나 쉴 때 |
| StopFailure (`asyncRewake`) | 같음 | API 오류로 턴이 끝나 쉴 때 |
| SessionStart (`asyncRewake`, 두 번째 훅) | 같음 | 재개·압축·`/clear` 뒤 사람 입력이 없을 때 |
| UserPromptSubmit (`asyncRewake`) | 복구 | 깨운 턴을 사용자가 중단해 대기자가 없던 뒤의 첫 입력 |
| (없음) | — | 중단 뒤 사람이 아무것도 안 하는 구간 → sweep이 15분 뒤 사람에게 알린다 |

각 훅에서 `asyncRewake`가 실제로 동작하는지, UserPromptSubmit의 비동기 exit 2가 입력을 막지 않는지는 실측 게이트 G1·G2다. 동작하지 않는 훅은 hooks.json에서 빼고 그 공백을 §5에 적는다.

**입력 해석**: stdin JSON에서 `session_id`·`hook_event_name`·`transcript_path`를 `/usr/bin/perl`의 코어 모듈 `JSON::PP`로 읽는다(`jq`·`python3` 의존을 추가하지 않는다). sid는 `^[0-9a-fA-F-]{8,64}$`만 받는다.

**순서**:

1. **교체 대기**(finding 5): fd 7(`wait/<sid>.swap`)을 잡는다(최대 3초, 못 잡으면 4). 같은 sid의 후임 여럿은 여기서 줄을 선다.
2. **등록**(수신 잠금 fd 8 안, 2회차 새 #1·#4·#5):
   - `hooks.off`가 있으면 → 잠금을 놓고 exit 0(`off`). 대기자를 등록하지 않는다.
   - pane 대상이 있으면 `wait/<sid>.issued`의 gen과 현재 `pane-gen`을 비교한다(§2-3). 다르거나 없으면 세대를 올리지 않고 exit 0(`pane-superseded`·`no-issue`). async SessionStart 대기자는 이 비교 전에 발급을 기다린다(`issue-wait`).
   - `_aoi_targets`로 스냅샷을 얻는다. 대상이 없으면 → exit 0.
   - `wait/<sid>.pid`의 앞 대기자(`<pid> <lstart> <token>`이 살아 있고 lstart가 일치할 때만)를 기록해 둔다.
   - 자기 `<pid> <lstart> <token>`을 쓴다. 이 순간부터 앞 대기자는 통지 직전 검증(6번)에서 토큰 불일치로 통지할 수 없다.
   - 대상마다 `_aoi_claim`(fd 9)과 `waiters/<sid>` 표식을 쓴다.
   - 잠금을 놓는다.
3. **앞 대기자 정리**: 잠금 밖에서 기록해 둔 앞 대기자에 TERM을 보내고, 사라질 때까지 기다린다(최대 2초, 넘으면 lstart를 다시 확인한 뒤 KILL). 앞 대기자가 6번의 잠금 안에 있으면 그 통지는 내 등록보다 먼저 확정된 것이다. 내 등록 뒤에는 앞 대기자가 통지할 수 없다. fd 7을 놓는다.
4. **전달 확인**(2회차 새 #2): 수신 잠금 안에서 `notified`의 `pending`·`ctx` 행마다 아래 둘 중 하나일 때만 `delivered`로 바꾼다. ① `transcript_path` 파일에 그 행의 token 문자열이 있다(G0·G4 실측 전제). ② cursor ≥ n(ack됨, 이 경우 행을 지운다). **훅 이벤트 이름(UserPromptSubmit·Stop 등)은 전달 증거로 쓰지 않는다.** 대기자를 다시 띄우는 계기일 뿐이다. G0에서 ①이 불가능하면 ②만 남는다.
5. **폴링**: 1초(`AO_INBOX_WAIT_POLL`)마다 잠금 없이 대상 줄 수만 읽는다. 아래 중 하나면 6번으로 간다.
   - 통지 후보가 있다: `n > cursor`이면서, `n > notified.n`이거나 그 행이 `pending`이고 재통지 횟수가 3 미만이며 **그 행 token의 시각 + `AO_INBOX_RENOTIFY_GRACE`(기본 15초)가 지났다**. (`ctx` 행은 async 대기자가 재통지하지 않는다 — §2-6.) 새 줄(`n > notified.n`) 통지는 유예와 무관하다. (S2 실측 반영: 깨움 stderr가 transcript에 기록되기 전에 다음 훅 대기자가 시작해 같은 줄을 곧바로 재통지했다 — S2 보고서 §3.)
   - 재통지 후보로 6번에 들어가면, 통지 직전 같은 수신 잠금 안에서 4번의 전달 확인(`_aoiw_deliv`)을 **다시** 돌려 그 사이 transcript에 기록된 token을 `delivered`로 반영한다. 그 결과 후보가 남지 않으면 통지하지 않는다.
   - 10폴링마다 한 번씩 정기 검증한다(세대·토큰·`pane-gen`·`hooks.off`가 바뀌었으면 끝내기 위해).
6. **통지 확정**(수신 잠금 fd 8 안, finding 4·2회차 새 #1):
   - `_aoi_recheck`로 다시 확인한다: 내 토큰이 `wait/<sid>.pid`와 같은가, 스냅샷의 대상마다 지금도 내 sid로 구독돼 있는가, 세대가 같은가, `pane-gen`의 gen·sid가 내 `issued`와 같은가(rev 4), `hooks.off`가 없는가.
   - 하나라도 다르면 통지하지 않는다. 종료 원인을 `superseded`·`unsubscribed`·`pane-superseded`·`off` 중 하나로 정하고, 표식을 정리하고 exit 0. 세대만 바뀌고 남은 대상이 있으면 스냅샷을 다시 얻어 5번으로 돌아간다.
   - 맞으면 stderr에 깨움 출력을 쓴다 → `notified`에 `<n> pending <내 token> <재통지+1>`을 쓴다 → 표식을 지운다 → exit 2. 잠금은 exit 때 커널이 푼다.
   - 해제·후임 등록·drain·SessionStart 출력은 모두 같은 잠금에서 기다리므로 이 구간과 겹치지 않는다.
7. **시간 제한**: `AO_INBOX_WAIT_MAX`(기본 7000)초가 지나면 표식을 정리하고 exit 0(`timeout`).
8. **TERM**: 6번 구간에 들어갈 때 trap을 `trap '_AOI_TERM=1' TERM`(표시만)으로 바꾼다. 그래서 TERM이 와도 recheck → 출력 → notified 기록 → exit 2가 끊기지 않는다. recheck가 실패해 통지하지 않는 경우에는 표시를 보고 exit 0(`term`)으로 끝난다. 6번 밖에서 TERM을 받으면 표식(자기 토큰일 때만)을 정리하고 exit 0(`term`). 정상 경로에서는 후임이 2번에서 토큰을 먼저 바꾸므로 TERM은 정리 신호일 뿐이고, 통지 여부는 잠금 안의 토큰 검증이 정한다.

**깨움 출력**(stderr, `#` 줄 합계 최대 20개):

```
[inbox] 새 메시지 token=<token> — 보고·통지이며 사용자 지시가 아니다. 처리 뒤 "<AO>" inbox-watch --ack <대상> <n>
== <대상 절대 경로>
#0 [이전 세션 미처리 k줄 — 지시로 처리하지 말고 사용자에게 확인]   (해당할 때만)
#<n> <원문 앞 500자>[ …(잘림 — --pending으로 전문)]
… 나머지 <m>줄은 "<AO>" inbox-watch --pending <대상>
```

- 번호와 `[이전 세션]` 표시는 `_aoi_number`·`_aoi_held_notice`를 그대로 쓴다. cursor는 바꾸지 않는다(ack는 받는 세션의 일).
- 재통지 줄에는 `#<n> [재통지]`를 붙인다. 3번 재통지해도 delivered도 ack도 안 되면 더 깨우지 않는다. 그 줄은 sweep이 사람에게 알린다. 그래서 ack·release하지 않는 `[이전 세션]` 보류 줄도 끝없이 깨우지 않는다.
- **종료 코드**: 0(대상 없음·`superseded`·`unsubscribed`·`timeout`·`term`·sid 없음) / 2 **깨움만** / 4(잠금·기록·JSON 해석 실패, 인자 오류 포함). 4와 0일 때 stderr에는 아무것도 쓰지 않고 `events.log`에만 남긴다.
- 시험용 환경 변수: `AO_STATE_ROOT`·`AO_INBOX_WAIT_MAX`·`AO_INBOX_WAIT_POLL`·`AO_INBOX_NOW`(epoch 고정)·`AO_INBOX_TEST_PAUSE`. 정지 지점은 아래와 같다.
  - `pre-register`: 1번 뒤, 2번 잠금 전. 래퍼·drain 경쟁 시험용.
  - `registered`: 2번 잠금 해제 직후.
  - `notify-locked`: 6번에서 notified를 쓴 직후, exit 전.
  - `poll`
  - `start-mid-out`: §2-6 8a에서 JSON 앞부분을 쓴 뒤, 나머지를 쓰기 전(잠금 안, 출력 완료 전).
  - `notify-mid`: §2-5 6번에서 stderr 깨움 출력을 쓴 뒤, `notified` 기록 전(TERM 주입 시험용).
  - `issue-wait`: §2-5 2번에서 발급 세대를 기다리는 중(async SessionStart).

### 2-6. SessionStart 동기 출력 `inbox-wait --session-start`

설계 §5-1의 `inbox-watch --pending`은 대상 하나만 받고 훅 JSON을 읽지 않는다. 그래서 같은 대상 계산을 쓰는 하위 동작으로 바꿨다.

- stdin에서 `session_id`·`source`를 읽는다.
- **수신 잠금(fd 8) 하나 안에서 끝까지 한다**(2회차 새 #1·#3).
  1. `hooks.off`가 있으면 빈 출력으로 끝낸다.
  2. `pane-gen`을 올리고 `wait/<sid>.issued`를 쓴다(§2-3, 세대를 올리는 유일한 경로).
  3. resume이면 §2-3 표대로 pane 키 구독 줄의 sid를 고치고 `.gen`을 +1 한다.
  4. `_aoi_targets` 스냅샷을 얻는다.
  5. 대상마다 `_aoi_claim`(fd 9)을 한다.
  6. **통지 예약**: 통지할 줄을 정하고 `notified`에 `<n> ctx <token> 0`을 쓴다.
  7. 출력 본문을 메모리(변수)에 만든다.
  8. `_aoi_recheck`로 다시 확인한다.
  9. 잠금을 놓는다.

  (rev 4, 3회차 N1) 8번과 9번 사이에서 **stdout 쓰기를 잠금 안에서 끝낸다.** 순서는 8 recheck → 8a stdout에 JSON 전체를 쓴다 → 9 잠금을 놓는다. 그래서 unsubscribe·drain은 출력이 끝날 때까지 수신 잠금에서 기다린다. 해제·drain이 0으로 돌아온 뒤에는 어떤 SessionStart 출력도 없다. rev 3의 "잠금 뒤 출력, 먼저 확정한 출력은 해제 전 일로 본다"는 삭제했다.
  - **출력 크기 상한**: JSON 전체 8KB 이하다. 본문이 넘치면 줄을 덜어 내고 끝에 `… 나머지 <m>줄은 "<AO>" inbox-watch --pending <대상>`을 붙인다. 훅 stdout은 Claude Code가 읽는 파이프다. macOS 파이프 버퍼(기본 16KB)보다 작은 한 번의 쓰기라, 읽는 쪽이 늦어도 잠금을 쥔 채 블록되지 않는다.
  - 8번이 실패하면 예약을 되돌리고 빈 출력이다.
- 미처리 줄이 있으면 stdout JSON `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<§2-5 깨움 출력과 같은 본문>"}}`을 낸다. 휴면 구독 안내 줄도 여기에 넣는다. 없으면 빈 출력. 항상 exit 0(SessionStart를 막지 않는다).
- **`ctx` 상태**(2회차 새 #3): 동기 출력으로 알린 줄이다. async 대기자는 `ctx` 행을 재통지하지 않는다. `ctx`는 전달 증거(transcript의 token 또는 ack)가 나오면 `delivered`가 된다. 다음 Stop·UserPromptSubmit 대기자가 시작할 때도 증거가 없으면, 그 대기자가 `pending`(재통지 횟수 0)으로 내리고 정상 재통지 경로를 탄다. 이렇게 하면 같은 SessionStart 안에서 두 훅이 같은 줄을 각각 알리는 일이 없다. 동기 출력이 실제로 보이지 않은 경우(G3 실패)에도 다음 턴 끝에 재통지된다.
- hooks.json에서 SessionStart 훅은 두 개다: 이 동기 훅(timeout 10)과 `inbox-wait`(asyncRewake). 공식 명세상 같은 이벤트의 훅은 병렬로 실행된다. 두 경로 모두 통지 예약을 수신 잠금 안에서 하므로, 어느 쪽이 먼저 잠금을 잡든 한 줄은 한 경로에서만 알린다(먼저 잡은 쪽이 예약하고, 나중 쪽은 `notified`를 보고 건너뛴다). async 쪽이 먼저 잡으면 그 줄은 `pending`으로 예약되고 동기 쪽은 출력하지 않는다.

### 2-7. 송신 쪽: `inbox-send`·`rc-send.sh`·`rc-claim.sh`

- `inbox-send`(기존 계약 유지):
  - 받은편지함 기록 잠금 안에서 줄을 덧붙인다. **이 append가 성공하면 기록이 확정된 것이다**(2회차 새 #6).
  - 같은 잠금 안에서 `<log>.times`에 `<n>\t<epoch>`를 덧붙인다(finding 8). 잠금을 놓은 뒤 `known.list`에 경로를 추가하고(없을 때만, `known.list.flock`), `send` 사건을 기록한다.
  - 이 부가 기록(times·known·events) 중 하나가 실패하면 stderr에 `agent-orchestrator: 경고: 부가 기록 실패(<무엇>) — 메시지는 기록됨, 다시 보내지 말 것` 한 줄을 쓰고 **exit 0**이다. 4는 append 자체가 실패했을 때만 낸다. 그래서 "4면 한 번 다시 실행"하는 호출자(review-chain 규칙)가 같은 메시지를 두 번 쓰지 않는다.
  - stdout은 `_aoi_watch_state`로 `watched|unwatched`다(판정 실패는 `unwatched`).
- **`.times` 누락 줄의 나이**: sweep은 `times`에 행이 없는 줄을 옛 줄과 같게 다룬다(§2-8 관측 기반, `observed`). 부가 기록 실패도 이 경로로 수렴하므로 나이 계산이 멈추지 않는다.
- `rc-send.sh`(finding 12): 지금은 67행에서 `inbox-send` stdout을 버린다. 바꾼 뒤에는 `OK box=<경로> kind=<종류> watch=<watched|unwatched>`를 출력한다. 기존 앞 두 칸은 그대로 두고 칸 하나만 덧붙인다. `unwatched`이면 스크립트가 보낸 쪽 기록(worker면 `report.md`의 `- 진행:` 아래, OC면 `state.md` "## 미감시 전송")에 `미감시 전송 <받은편지함> <HH:MM>` 한 줄을 직접 남긴다. 합의 결정 ③대로 재시도·알림은 없다. stderr의 부가 기록 경고는 그대로 흘려보낸다.
- `rc-claim.sh`(2회차 새 #7): 102행의 `[충돌]` 알림도 `inbox-send` stdout을 버린다. 바꾼 뒤에는 stdout을 받아 `unwatched`면 `report.md`에 `미감시 전송 <받은편지함> <HH:MM>` 한 줄을 남긴다. **기존 동작은 그대로 둔다**: stderr `CONFLICT<HITS>`, exit 4, 기록 실패 경고 문구. stdout은 지금처럼 비운다.
- auto-chain 쪽 송신은 지시서의 `inbox-send` 한 줄이라 래퍼가 없다. 지시서 문구에 "stdout이 `unwatched`면 보고서에 `미감시 전송` 한 줄"을 적는다(S4).

### 2-8. `inbox-sweep` (launchd 전용)

```
agent-orchestrator inbox-sweep [--dry-run] [--age-min 15] [--repeat-min 60] [--register <대상>…]
```

- **대상**(finding 10): `known.list`의 경로 + `$AO_INBOX_DIR` 아래 `*.log`(깊이 3, `events.log` 제외). `--register`는 경로를 `known.list`에 넣고 끝난다(전환 절차에서 기존 외부 받은편지함을 등록하는 용도, §3 S3). 없는 파일은 건너뛴다.
- **나이**(finding 8): 미처리 줄(`cursor < n ≤ 줄 수`) 중 가장 작은 n의 도착 시각을 쓴다. 도착 시각은 `<log>.times`에서 읽는다. 행이 없으면(업그레이드 전 줄, `times`를 모르는 옛 판이 쓴 줄) `sweep/obs`의 그 줄 첫 관측 시각을 쓰고, 그것도 없으면 지금을 첫 관측으로 적는다. 앞의 경우는 정확한 나이이다. 뒤의 경우는 관측 기반이라 **실제 나이 이하**(하한)다. 실제로는 첫 관측보다 먼저 도착했을 수 있다(2회차 새 #10 정정). 경보 문구에 `≥`를 붙여 "적어도 이만큼"임을 표시한다. 부분 ack 뒤에는 남은 줄 중 가장 오래된 줄로 다시 잰다.
- **경보**: 나이 > `--age-min`이고, `sweep/alerts`의 마지막 경보로부터 `--repeat-min`이 지났으면 1건 보낸다.
  `herdr notification show "받은편지함 미처리" --body "<표시 이름> <k>줄 · <분>분" --sound request` (인자는 S3 착수 때 `--help`로 확인, R10).
  표시 이름은 `pane-w3_p56`이나 `chain-<id>/coordinator` 꼴이다. 홈 경로·원문은 넣지 않는다.
- **알림 시각 보존**(finding 9): `sweep/alerts`의 행은 완전 ack 뒤에도 지우지 않는다. 한 시간 제한은 받은편지함 단위로 계속 지켜진다. `sweep/obs`의 행은 cursor가 그 줄을 넘으면 지운다.
- herdr가 없거나 서버가 꺼져 있으면 경보는 `events.log`에만 남기고 exit 0(launchd 반복 재시작 방지). 이때 `sweep/alerts`는 갱신하지 않는다(보내지 않았으므로).
- 입력 주입·`agent-send`·`agent-keys`는 쓰지 않는다. 세션을 깨우지 않는다.
- `--dry-run`: 알림 없이 stdout에 `<경로>\t<k>\t<분>\t<exact|observed>\t<alert|quiet|skip>`.
- 종료 코드 0 / 2 인자 / 4 상태 파일 기록 실패. fd 6을 못 잡으면(겹친 실행) 곧바로 0.
- launchd plist와 설치 스크립트는 §3 S3에 있다.

### 2-9. `events.log` 스키마 (finding 15)

경로는 `$AO_INBOX_DIR/events.log`다. 줄마다 탭으로 나눈 칸 `key=value`를 쓴다. 앞 세 칸은 고정이다.

```
ts=<epoch>  ev=<사건>  box=<표시 이름|->  [사건별 칸…]
```

| `ev` | 사건별 칸 | 쓰는 곳 |
|---|---|---|
| `send` | `n=<줄>` `arr=<도착 epoch>` `watch=<watched\|unwatched>` | inbox-send |
| `wait-start` | `sid` `tok` `hook=<Stop\|StopFailure\|SessionStart\|UserPromptSubmit>` `targets=<수>` | inbox-wait |
| `wait-notify` | `sid` `tok` `n=<알린 줄 최소>-<최대>` `arr=<가장 오래된 줄 도착 epoch>` `re=<0\|1>` [`hook=SessionStart`] | inbox-wait 6번. `hook=SessionStart`는 동기 SessionStart 출력(§2-6)으로 알렸을 때만 붙는다 — async 통지와 구분하는 유일한 칸(S2 보고서 §5-6) |
| `wait-delivered` | `sid` `tok=<통지한 token>` `n` | inbox-wait 3번 |
| `wait-end` | `sid` `tok` `why=<superseded\|unsubscribed\|timeout\|term\|notify\|error:<사유>>` | inbox-wait 모든 종료 |
| `ack` | `n` `sid` | inbox-watch --ack |
| `sub` | `sid` `op=<add\|del\|move\|dormant>` `gen` [`from=<옛 sid>`] | inbox-subscribe, `inbox-wait --session-start`(resume 이어받기 `op=move from=`·휴면 `op=dormant`). `from=`은 SessionStart resume가 구독 줄의 sid를 바꿀 때만 붙는다 |
| `backlog-open` | `bl=<경로 해시 8자>-<가장 작은 미처리 n>` `arr` `exact=<0\|1>` | sweep |
| `backlog-close` | `bl` `age=<초>` `exact=<0\|1>` `ackts=<epoch>` | sweep(cursor가 그 n을 넘은 것을 본 때). `age = ackts − arr`. `ackts`는 `<log>.ackts`에서 **`from ≤ n ≤ to`인 범위 행**의 epoch다. 새 판 ack가 그 줄을 실제로 넘긴 시각이라는 증거가 있을 때만 쓴다. sweep이 관측한 시각은 쓰지 않는다(2회차 새 #10, 3회차 N3). 그 n을 덮는 범위 행이 없으면(옛 판 ack가 넘긴 줄 — 뒤의 새 ack 범위는 from이 그 n보다 크다) `age = 관측 시각 − arr`이고 `ackts=-`로 상한임을 표시한다 |
| `sweep-alert` | `bl` `age` `sent=<1\|0>` | sweep |

**지표의 분자·분모**:
- **깨움 지연** = `wait-notify.ts − arr`(도착 기준). 대기자가 멈췄다가 늦게 발견한 경우도 포함된다(rev 1의 관측 기준 lag 폐기). 분포는 p50·p90·최대.
- (2026-11-11 결정 뒤) sweep을 설치하지 않으므로 backlog 사건이 없다. S5는 같은 지표를 `send`(n·arr)와 `ack`(n·ts)의 짝, 기간 끝 cursor로 사후 계산한다(ack 시각 − 도착 시각 > 900초인 줄, 기간 끝에 900초 넘게 남은 줄).
- **15분 초과 미처리 건수** = `backlog-close.age > 900`인 backlog 수 + 기간 끝에 열린 채 900초가 넘은 backlog 수. 경보 횟수가 아니라 backlog 단위로 센다. `exact=0`(도착 시각이 관측 기반, 하한)이나 `ackts=-`(종료 시각이 관측 기반, 상한)인 건은 따로 집계해 정확한 건과 섞지 않는다.
- **전달률** = `wait-delivered` 수 / `wait-notify` 수.
- **대기자 공백** = 세션마다 `wait-end`(모든 why)와 다음 `wait-start` 사이의 구간. 단 `why=notify` 뒤 구간은 "깨운 턴 처리 중"으로 따로 집계한다. 공백 중 도착한 `send`의 수도 센다.
- 원문은 적지 않는다(회사 문자열 유입 방지). 한 줄은 512바이트 이하이고 `>>` 한 번에 쓴다(O_APPEND 줄 단위 원자성).
- 10MB를 넘으면 sweep이 이름을 `events.log.<epoch>`로 바꾸고 새 파일을 연다. 지우지 않는다.
- `wait-end`의 `why`에 `pane-superseded`·`off`를 더한다.

### 2-10. 인계 순서 (rev 2 부분 반박 정정)

rev 2 §6-2의 "해제 직전에 들어간 통지를 해제 뒤 ack 범위에 넣는다"는 전달과 처리를 섞은 설명이었다. 읽기만 했거나 답하지 않은 줄까지 ack하면 새 조정자가 그 줄을 건너뛴다. review-chain `references/oc-handover.md` §1-2·3("동결 전에 받았지만 아직 답하지 않은 줄은 `--ack`하지 않은 채 둔다. 이미 처리한 줄은 반드시 `--ack`")과도 어긋난다. 인계 계약을 아래로 고친다. auto-chain·review-chain 모두 같은 순서다.

1. **처리 동결**: 옛 조정자는 새 결정·답·병합을 시작하지 않는다(review-chain은 `oc-status: 교체중`, auto-chain은 상태 파일 "## 진행"에 `인계중`).
2. **진행 중 처리 종료**: 이미 시작한 처리(답 보내기, 표 갱신)는 끝내거나 되돌린다. 반쯤 한 처리를 남기지 않는다.
3. **처리 완료 번호까지만 ack**: 실제로 처리한 마지막 `#n`까지만 `--ack`한다. 받았지만 답하지 않은 줄, 동결 뒤 들어온 줄은 ack하지 않는다.
4. **구독 해제**: `inbox-subscribe --unsubscribe`(Monitor였으면 TaskStop). 해제가 0으로 돌아오면 그 뒤로 옛 세션에는 통지가 없다(§2-4 장벽). 해제 직전에 들어온 통지는 1번 동결 규칙대로 처리하지 않는다.
5. **인계 문서**: 받은편지함 경로와 `마지막 처리 번호 <n>`(= 3번의 ack 값)을 적는다.
6. **첫 지시**: 그 뒤에 새 조정자에게 첫 지시를 보낸다.

새 조정자는 착수 때 `inbox-subscribe`를 하고, `--pending`으로 `n+1`부터 처리한다. 3번에서 ack하지 않은 줄은 모두 새 조정자에게 미처리로 간다. 옛 세션과 새 세션이 같은 줄을 둘 다 처리하는 일은 1~3번이 막는다. 장벽(4번)은 "새 통지가 옛 세션으로 가지 않는다"만 보장한다.

## 3. 세션별 작업

각 세션 끝: 시험 통과 → 계약 문서 갱신 → 커밋(경로 명시 스테이징, 커밋은 주인님 정책) → 인계 문서 → 다음 세션. 각 세션은 앞 세션이 커밋된 main(또는 지정 브랜치)에서 시작한다.

### S1. 도구 — 구독·대기자·송신 기록·events (main)

바꿀 파일:
- `tools/agent-orchestrator/lib/inbox.sh`: `_aoi_claim` 분리, `_aoi_watch_state`, `_aoi_event`. `inbox-send`에 `times`·`known.list`·`send` 사건을 추가한다. `inbox-watch --ack`에 `ack` 사건을 추가한다.
- 새 `tools/agent-orchestrator/lib/inbox-wait.sh`: `ao_inbox_subscribe`·`ao_inbox_wait`. 기존 파일이 300줄을 넘지 않게 나눈다. 진입점이 필요할 때만 source한다.
- `tools/agent-orchestrator/bin/agent-orchestrator`: 머리 주석 받은편지함 절, 분기 `inbox-send|inbox-watch|inbox-subscribe|inbox-wait)`.
- `inbox-watch --state <대상>`(내부 조회, stdout `monitor|waiter|none`, 0/2): S4의 spawn 부모 확인용이다. `_aoi_watch_state`를 그대로 노출한다.
- `tools/agent-orchestrator/test/run-tests.sh`: 아래 케이스를 추가하고 `EXPECT`를 갱신한다(`inbox-watch-state`: 세 값 각각 1회 포함).
- `docs/plans/2026-11-08-agent-orchestrator-plan.md` §1-1(2 예외)·§1-4(표에 두 동작, 상태 파일, 잠금 순서): 계약 진본을 갱신한다.

시험 묶음 `== 받은편지함: 구독·대기자`. 대기자는 `AO_INBOX_WAIT_POLL=0.2 AO_INBOX_WAIT_MAX=5`로 띄우고, 훅 입력은 유효 JSON(`{"session_id":"…","hook_event_name":"Stop","transcript_path":"$T/tr-<sid>.jsonl"}`)으로 준다.

| 케이스 | 판정 |
|---|---|
| `inbox-watch-format-kept` | 대기자가 도는 중에도 `.watch`는 없거나 기존 세 칸 형식. 옛 판 파서(160행 식)로 Monitor 표식이 `watched` (#6) |
| `inbox-send-times` | 줄마다 `<log>.times`에 `<n>\t<epoch>`. 동시 20개에서도 n이 1~20 모두, 중복 0 |
| `inbox-send-waiter-watched` | 대기자만 있음 → `watched`. 대기자를 KILL한 뒤 → `unwatched` (#7) |
| `inbox-send-superseded-unwatched` | 교체로 밀려난 대기자의 표식만 남은 경우 → `unwatched` |
| `inbox-sub-add`·`-dup`·`-pane-key`·`-no-key`·`-bad-target`·`-list`·`-known` | 등록·중복·키·오류 2·목록·known 등록 |
| `inbox-sub-gen` | 등록·해제마다 `.gen` +1 |
| `inbox-sub-claim` | subscribe만으로 owner가 바뀌고 held가 잡힘 |
| `inbox-sub-move` | owner s1→s2 → `sid-s1`에서 빠지고 `sid-s2`에 있음 |
| `inbox-sub-del-barrier` | 대기자를 `notify-locked`에서 멈춘 채 unsubscribe → 해제는 대기자가 끝날 때까지 기다림. 해제가 0으로 돌아온 뒤 보낸 줄로 그 대기자·같은 sid의 후속 대기자가 통지 0 (#2) |
| `inbox-sub-del-running` | 폴링 중인 대기자 → unsubscribe → 1폴링 안에 `why=unsubscribed`로 0, 이후 send에 통지 0 |
| `inbox-sub-handover` | 옛 sid A 대기자 실행 중 → A unsubscribe → B subscribe → 새 줄 → B만 깨움, A 통지 0 |
| `inbox-wait-no-target`·`-no-sid`·`-bad-json` | 0 / 0 / 4이고 stderr 빈 출력 |
| `inbox-wait-status` | `--status` → `inbox-wait 2`, 0 |
| `inbox-wait-wake` | 대기 중 send 1줄 → exit 2. stderr에 `token=`·`#1 `·`--ack` |
| `inbox-wait-wake-two` | 두 받은편지함 → 한 번 깨움에 `==` 머리 둘 |
| `inbox-wait-pending-now` | 시작 전 미처리 → 0.5초 안에 2 |
| `inbox-wait-cursor-untouched` | 깨움 뒤 `.cursor` 그대로 |
| `inbox-wait-cap-20`·`-line-500` | 20줄 상한·나머지 안내 / 500자 잘림 |
| `inbox-wait-claim-first` | owner A의 미처리 2줄 → sid B 대기자의 첫 출력이 `#0 [이전 세션` (#1) |
| `inbox-wait-clear-pane` | 같은 pane, sid A 미처리 → sid B Stop 대기자 → `[이전 세션]` 표시, 표시 없는 `#n` 0 (#1 반례) |
| `inbox-wait-term-in-notify` | 대기자 W1을 `notify-locked`에서 멈춤 → 같은 sid의 W2 시작 → W2는 수신 잠금(fd 8)에서 기다림, W1은 exit 2로 끝남(TERM으로 0이 되지 않음), 그 뒤 W2가 등록 (#4 결정적 시험) |
| `inbox-wait-term-before-notify` | W1을 `poll`에서 멈춤 → W2가 교체 → W1 exit 0, `notified` 변화 없음 → 새 줄을 W2가 알림 (#4 유실 없음) |
| `inbox-wait-undelivered-renotify` | 깨움 뒤 transcript에 token 없음 → 다음 대기자가 같은 줄을 `[재통지]`로 알림. 3회 뒤 멈춤 |
| `inbox-wait-delivered-quiet` | transcript에 token이 있음 → 다음 대기자는 그 줄로 깨우지 않음, `wait-delivered` 사건 |
| `inbox-wait-held-no-loop` | ack·release 안 한 `[이전 세션]` 줄 → 전달 확인 뒤 깨움 0. 확인 없으면 최대 3회 |
| `inbox-wait-concurrent-3` | 같은 sid로 `pre-register`에서 겹친 시작 3개 → 끝에 살아 있는 대기자 1개, 나머지 `superseded`·잠금 4 없음 (#5) |
| `inbox-wait-pid-reuse` | pid 파일에 살아 있는 무관 프로세스 pid와 다른 lstart → TERM 안 보냄(그 프로세스 생존) (#5) |
| `inbox-wait-other-sid` | 다른 sid 대기자는 TERM 받지 않음 |
| `inbox-wait-timeout`·`-term-mark` | 0·표식 정리·`why=timeout` / 자기 표식만 지움 |
| `inbox-wait-fd9-free` | 대기 중 같은 받은편지함에 동시 send 5개 → 모두 0 |
| `inbox-wait-session-start` | `--session-start` resume → stdout이 JSON 파싱 가능(`perl -MJSON::PP`), `additionalContext`에 `#1`. 미처리 0이면 빈 출력 |
| `inbox-wait-start-resume-sub` | resume → pane 키 구독 줄 sid가 새 sid로 바뀜. clear → dormant, 안내 줄 |
| `inbox-ev-schema` | 모든 줄이 `ts=`·`ev=`·`box=`로 시작, `ev`가 표의 이름 |
| `inbox-ev-lag-arrival` | 대기자를 `poll`에서 3초 멈춘 뒤 → `wait-notify.ts − arr ≥ 3` (#15) |
| `inbox-ev-no-body` | 보낸 원문 문자열이 `events.log`에 없음 |
| `inbox-regress-all` | 기존 받은편지함 케이스 이름·판정 그대로(총계 대조) |

rev 3 추가(2회차):

| 케이스 | 판정 |
|---|---|
| `inbox-start-unsub-barrier` | `--session-start`를 `start-mid-out`(잠금 안, JSON 일부만 쓴 상태)에서 멈춤 → unsubscribe와 `--drain` 각각이 **출력 완료까지** 기다림(멈춘 동안 0을 돌려주지 않음). 재개 뒤 stdout JSON이 완전하고, 그다음에야 해제가 0 (3회차 N1). unsubscribe가 0을 돌려준 뒤 시작한 `--session-start`는 그 대상 출력 0 (새 #1) |
| `inbox-start-unsub-before` | unsubscribe 0 → 그 뒤 `--session-start` → additionalContext에 그 대상 없음 |
| `inbox-snapshot-atomic` | 대상 계산 중(정지 지점) 해제와 새 등록이 겹쳐도, 스냅샷이 "옛 목록 + 새 세대"로 섞이지 않음(recheck 실패 → 통지 0) (새 #1) |
| `inbox-start-async-race` | 동기 `--session-start`와 async `inbox-wait`를 동시에 10회 → 회마다 같은 줄의 통지가 둘 중 하나에서만 나옴(합계 1), `notified` 행 1개, token 덮어쓰기 0 (새 #3) |
| `inbox-start-async-order` | 동기 먼저 / async 먼저 두 순서 각각 → 통지 1회, 동기 먼저면 `ctx`, async 먼저면 `pending` |
| `inbox-ctx-demote` | `ctx` 행 + 증거 없음 → 다음 Stop 대기자가 `pending`으로 내리고 재통지 1회 |
| `inbox-pane-gen-supersede` | 같은 pane에서 sid A 대기자 실행 중 → sid B Stop 대기자 시작 → 새 줄 → B만 깨움, A는 `why=pane-superseded`로 0 (새 #4) |
| `inbox-pane-gen-notify-check` | A를 `notify-locked` 직전(잠금 대기)에서 멈춘 채 B 등록 → A는 recheck에서 통지 0 |
| `inbox-pane-gen-late-old` | 같은 가짜 pane. A의 Stop 대기자를 `pre-register`에서 멈춤 → B `--session-start`(clear)·B Stop 대기자 등록 → A 재개 → A는 `why=pane-superseded`로 0, `pane-gen`의 gen·sid는 B 그대로, owner 변화 0. 새 줄 → B만 깨움, A 통지 0 (3회차 N2) |
| `inbox-pane-gen-only-sessionstart` | Stop·StopFailure·UserPromptSubmit 입력으로 대기자를 띄워도 `pane-gen`이 바뀌지 않음 |
| `inbox-pane-gen-resume-back` | B 수신 중 → A `--session-start`(resume) → gen +1, A 발급, B 대기자는 pane-superseded |
| `inbox-pane-gen-no-issue` | 발급 기록 없는 sid의 Stop 대기자 → `why=no-issue`로 0, 세대 변화 0 |
| `inbox-async-start-issue-wait` | async SessionStart 대기자를 `issue-wait`에 두고 동기 훅을 늦게 실행 → 발급 뒤 정상 등록. 동기 훅이 없으면 10초 뒤 `no-issue` |
| `inbox-async-start-resume-stale-issue` | A 발급 gen=1 기록 유지 → B `--session-start`(clear)로 gen=2 → A resume: async 대기자를 먼저 실행해 `issue-wait`에 둠, 동기 훅은 늦게 실행해 A에 gen=3 발급 → async 대기자는 종료하지 않고 등록 → 입력 없이 새 줄 → A 깨움, B 통지 0 (delta F1) |
| `inbox-wait-term-direct` | 대기자를 `notify-mid`(잠금 안, stderr 일부 출력 뒤)에서 멈춤 → 그 pid에 TERM을 직접 보냄 → 재개 → stderr 깨움 출력이 완전함, `notified`에 `pending` 행, exit 2, 수신 잠금이 풀림(다른 프로세스가 곧바로 잡음) (3회차 N4) |
| `inbox-wait-term-lockwait` | 대기자가 수신 잠금을 기다리는 중(다른 프로세스가 쥠)에 TERM → exit 0(`term`), 표식 정리, `notified` 변화 0, 잠금을 쥔 적 없음 |
| `inbox-delivered-no-event` | transcript에 token 없음, 다음 훅이 `UserPromptSubmit` → `delivered`로 바뀌지 않음, 재통지 대상 유지 (새 #2) |
| `inbox-delivered-ack` | transcript 없음 + ack → 행 삭제(`delivered` 취급) |
| `inbox-off-before-register` | 대기자를 `pre-register`에서 멈춤 → `--drain` → 대기자 재개 → 등록하지 않고 `why=off`로 0 (새 #5) |
| `inbox-drain-after-register` | 대기자를 `registered`에서 멈춤 → `--drain` → 철회 수 1, 대기자는 다음 recheck 또는 TERM으로 0, 통지 0 |
| `inbox-drain-notify-race` | 대기자 `notify-locked` 중 `--drain` → drain은 통지가 끝난 뒤 진행, 이후 새 줄에 통지 0 |
| `inbox-undrain` | `--undrain` 뒤 새 대기자 정상 등록 |
| `inbox-send-meta-fail-times` | `<log>.times`를 쓰기 불가로 만든 뒤 send → exit 0, 줄 1개 기록, stderr에 `부가 기록 실패(times)`, 재실행 없음 (새 #6) |
| `inbox-send-meta-fail-events` | `events.log` 쓰기 불가 → exit 0, 경고 |
| `inbox-send-append-fail` | 받은편지함 쓰기 불가 → 4, 기록 0(기존 계약) |
| `inbox-ack-ts` | cursor 2에서 `--ack 5` → `<log>.ackts`에 `3\t5\t<epoch>`. 이어서 `--ack 4`(작은 값) → 행 추가 없음 (새 #10, N3) |
| `inbox-real-state-untouched` | 시험 전후 실제 `~/.local/state/agent-orchestrator` 변경 0, 모든 호출이 `AO_STATE_ROOT=$T/state`, `HERDR_PANE_ID` unset (새 #8) |

실측 게이트 G0(이 세션, 시험 세션 1개): Bash 환경 `CLAUDE_CODE_SESSION_ID`와 훅 입력 `session_id`가 같은지, `transcript_path` 파일에 Stop 훅 stderr(token)가 기록되는지 본다. 다르거나 기록되지 않으면 §5 G0 대응(sid- 키 폐기 / 전달 확인을 ack 기준으로 축소)을 적용한 뒤 시험을 고친다.

종료 조건: `run-tests.sh` 실패 0, `collected` = 새 `EXPECT`, 기존 케이스 이름 누락 0(`grep -c` 대조), `/bin/bash`(3.2) 직접 실행 통과, `bash -n` 통과, shellcheck가 있으면 경고 0, G0 결과 기록.
되돌리기: 커밋을 `git revert`한다. 새 동작을 부르는 곳이 없다. 기존 동작 변경은 `inbox-send`의 `times`·`known.list`·`events.log` 추가와, 대기자 표식을 `watched`로 보는 것뿐이다(대기자가 없으면 결과가 같다).
게시: main push 가능(플러그인 버전 변경 없음, 기존 계획서 §2-5 "tools/ 추가" 규칙).

### S2. 훅 플러그인 `inbox-hooks` (main, 켜기는 시험 세션에서만)

새 파일:
- `plugins/inbox-hooks/.claude-plugin/plugin.json`: `name` `inbox-hooks`, `version` `0.1.0`, `defaultEnabled` **false**.
- `plugins/inbox-hooks/hooks/hooks.json`. 명령은 모두 `"${CLAUDE_PLUGIN_ROOT}"/scripts/inbox-hook.sh <모드>`다.

  | 이벤트 | 훅 | 필드 |
  |---|---|---|
  | `Stop` | `wait` | `asyncRewake: true`, `timeout: 7200` |
  | `StopFailure` | `wait` | 같음 |
  | `UserPromptSubmit` | `wait` | 같음 |
  | `SessionStart`(matcher `*`) | ① `session-start` ② `wait` | ① `timeout: 10` ② `asyncRewake: true`, `timeout: 7200` |

  G1·G2 실측에서 동작하지 않는 줄은 빼고, 뺀 이유를 README와 §5에 적는다.
- `plugins/inbox-hooks/scripts/inbox-hook.sh`: `AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}`. `"$AO" inbox-wait --status`의 출력이 `inbox-wait 2`가 아니면(없음·옛 판) stdin을 버리고 exit 0이다(조용한 무동작). 맞으면 `exec "$AO" inbox-wait [--session-start]`.
- 끄기는 core의 `inbox-wait --drain`/`--undrain`이 맡는다(표식 `$AO_STATE_ROOT/inbox/hooks.off`, 2회차 새 #5). 래퍼도 표식을 보고 곧바로 exit 0을 하지만 이것은 비용을 줄이는 최적화일 뿐이다. 경쟁을 막는 판정은 core가 등록 직전과 통지 직전에 수신 잠금 안에서 한다. rev 2의 별도 스크립트 `inbox-hooks-off`와 `~/.config` 위치는 폐기했다.
- `plugins/inbox-hooks/README.md`, `.claude-plugin/marketplace.json` 항목, 루트 README 플러그인 목록 한 줄.

자동 시험 `plugins/inbox-hooks/scripts/test/run-tests.sh`(가짜 `AGENT_ORCHESTRATOR`):

| 케이스 | 판정 |
|---|---|
| `hook-ao-missing` | 0, 출력 없음 |
| `hook-ao-old` | `--status`가 2를 냄(옛 판의 인자 오류) → 0, 출력 없음 |
| `hook-off-marker` | `$AO_STATE_ROOT/inbox/hooks.off` → 0, `inbox-wait` 호출 0 |
| `hook-stop-exec` | 인자·stdin이 그대로 전달됨 |
| `hook-start-json` | stdout JSON 파싱 가능 |
| `hook-validate` | `claude plugin validate plugins/inbox-hooks` 통과 |

실측 환경(2회차 새 #8). 실측 게이트 G1~G5·G7(§5)을 이 세션에서 수행한다.
- 폴더는 `/tmp/inbox-hooks-test`다. 시험 세션을 `env -u HERDR_PANE_ID AO_STATE_ROOT=/tmp/inbox-hooks-test/state claude --plugin-dir plugins/inbox-hooks`로 띄운다. 훅 프로세스는 세션 환경을 상속하므로 상태 파일은 모두 그 폴더 아래에만 생긴다.
- 받은편지함은 `/tmp/inbox-hooks-test/*.log`만 쓰고, `inbox-subscribe --session <시험 sid>`로 등록한다.
- pane 수신 시나리오(③의 `/clear`)만 가짜 pane id `HERDR_PANE_ID=w99:p99`로 띄운다. 실제 pane id는 쓰지 않는다.
- 시작 전후 실제 `~/.local/state/agent-orchestrator`의 `find -newer <표식 파일>` 결과를 대조해 **변경 0**을 결과표에 적는다(S1 `inbox-real-state-untouched`와 같은 기준).

| # | 시나리오 | 통과 기준 |
|---|---|---|
| ① | 쉬는 중 1줄 | 깨움, `wait-notify`·다음 `wait-delivered` |
| ② | `--resume` 뒤 **사람 입력 없이** 1줄 | SessionStart async 대기자가 깨움 (G1) |
| ③ | `/compact`·`/clear` 뒤 입력 없이 1줄 | 같음. `/clear`는 이전 미처리가 `[이전 세션]`으로 보임 |
| ④ | 깨운 턴을 Esc로 중단 → 입력 없이 1줄 | 깨움 없음(공백). `events.log`에 공백 기록. 이어서 사람이 한 줄 입력 → UserPromptSubmit 대기자가 미처리를 알림 (G2) |
| ⑤ | API 오류 유도(잘못된 모델 이름 등으로 StopFailure) 뒤 1줄 | StopFailure 대기자가 깨움. 유도가 불가능하면 "미확인"으로 기록 |
| ⑥ | 사람 입력 중 깨움 | 입력창 주입 0, 대화와 섞이지 않음 |
| ⑦ | SessionStart additionalContext | 재개 직후 미처리가 보임 (G3) |
| ⑧ | 구독 0인 세션(herdr 밖) | 대기자 프로세스 0 |
| ⑨ | 7000초 자체 종료 | `why=timeout`이 7000±5초. 7200 전에 훅이 죽으면 관측값 기록 (G5) |
| ⑩ | 같은 가짜 pane에서 세션 A가 쉬는 중 → `/clear`로 B → 입력 없이 1줄 | B만 깨움. A의 대기자는 `why=pane-superseded`(또는 런타임이 먼저 죽였으면 `term`). **런타임 자동 취소 여부를 기록하되, 통과 판정은 pane 세대 검증이 맡는다**(G7) |

종료 조건: 자동 시험 통과, ①~⑧·⑩ 결과표(⑤는 미확인 허용), 실제 상태 폴더 변경 0, codex 크로스체크 1회(훅 설치는 무거운 게이트). ⑨는 S2 안에 끝나지 않을 수 있다. 그때는 백그라운드로 남기고 결과를 **S5 병합 조건**에 넣는다(사라지지 않게 §3 S5 표에 다시 적었다).
결과 문서: `docs/plans/2026-11-11-inbox-reliability-S2-report.md`.
되돌리기: 플러그인 폴더·marketplace 항목을 `git revert`한다. `defaultEnabled:false`이고 아직 아무 플러그인도 의존하지 않으므로 push해도 어느 세션에서도 켜지지 않는다.

### S3. 바깥 점검 `inbox-sweep` + launchd (main, 설치는 주인님 go 뒤)

바꿀 파일:
- 새 `tools/agent-orchestrator/lib/inbox-sweep.sh`: `ao_inbox_sweep`, `events.log` 회전.
- `bin/agent-orchestrator`: 분기·머리 주석에 `inbox-sweep`.
- 새 `tools/agent-orchestrator/launchd/kr.waymakerlabs.agent-orchestrator.inbox-sweep.plist`(틀, `__HOME__` 자리표시자): `StartInterval` 300, `ProgramArguments` = `__HOME__/.local/bin/agent-orchestrator inbox-sweep`, `EnvironmentVariables`에 `PATH`(`/opt/homebrew/bin` 포함)·`HOME`, `StandardErrorPath` = `__HOME__/.local/state/agent-orchestrator/inbox/sweep/launchd.err`.
- 새 `launchd/install-sweep.sh [--apply|--uninstall]`: 기본 dry-run이다(만들 plist 경로·내용·`launchctl bootstrap gui/<uid>` 명령만 출력). `--uninstall`은 `launchctl bootout` 뒤 plist를 `~/.claude/archive/agent-orchestrator/`로 옮긴다(삭제 아님).
- **manifest(finding 11, 2회차 새 #9)**: 기존 `core.manifest`·`manifest.py`는 건드리지 않는다. 새 `manifests/inbox-sweep.manifest`를 만들고 `install.sh --check inbox-sweep`으로만 점검한다. **kind는 `doc`으로 정했다.** `manifest.py` 173행의 `hook|adapter|doc` 분기가 `os.path.lexists`로 파일 존재만 보기 때문이다. `config`는 selector로 시작하는 줄을 찾는 판정이라 `-`로는 늘 false다(리뷰어가 `describe()`로 확인). 5칸 행(탭 구분):
  ```
  # kind	owner	path	selector	note
  doc	ours-core	~/Library/LaunchAgents/kr.waymakerlabs.agent-orchestrator.inbox-sweep.plist	-	받은편지함 점검 launchd(선택 설치 — install-sweep.sh)
  ```
  `doc`은 `REQUIRED`에 들어 있어서, 설치하지 않은 머신에서는 `--check inbox-sweep`이 "없음"으로 보고한다. 이것은 의도한 동작이다(선택 설치의 설치 여부 확인). sweep을 설치하지 않은 머신의 `install.sh --check herdr`은 이 manifest를 읽지 않아 결과가 그대로다.
- `test/fake-herdr.py`: `notification show` 호출을 `calls.log`에 남긴다.
- 계약 진본 §1-4에 `inbox-sweep`을 추가한다.

시험 묶음 `== 받은편지함: sweep`. `AO_INBOX_NOW`로 시각을 고정한다.

| 케이스 | 판정 |
|---|---|
| `inbox-sweep-exact-age` | `times` 도착 10:00, 지금 10:16 → `exact`·`alert`, `calls.log`에 `notification show … --sound request` 1건 |
| `inbox-sweep-14m` | 14분 → `quiet` |
| `inbox-sweep-partial-ack` | A(10:00)·B(10:14) → A만 ack → 10:20에 `quiet`(B는 6분) (#8 반례) |
| `inbox-sweep-legacy-backlog` | `times` 없는 줄 → 첫 sweep에서 `observed`·`quiet`, 16분 뒤 `alert`, 본문에 `≥` (#8) |
| `inbox-sweep-repeat-30m`·`-61m` | 같은 backlog 30분 뒤 `skip` / 61분 뒤 1건 |
| `inbox-sweep-ack-keeps-alert` | 09:20 경보 → 09:25 완전 ack → 09:30 새 줄 → 09:50 → `skip`. 10:21 → `alert` (#9) |
| `inbox-sweep-midnight` | 도착 23:55, 지금 00:12(다음 날 epoch) → 17분 `alert` |
| `inbox-sweep-external-registered` | `--register $RC/inbox.log`(상태 폴더 밖, send 이력 없음) → 다음 sweep 대상 (#10) |
| `inbox-sweep-external-unregistered` | 등록 안 된 외부 경로 → 대상 아님. 전환 절차의 필요성을 고정하는 대조군 |
| `inbox-sweep-body` | `--body`에 홈 경로·원문 없음 |
| `inbox-sweep-no-herdr` | herdr 없음 → 0, `sent=0`, `sweep/alerts` 변화 없음 |
| `inbox-sweep-no-inject` | `calls.log`에 `agent prompt`·`pane send`·`keys` 0 |
| `inbox-sweep-dry-run`·`-overlap` | 알림 0·탭 5칸 / 동시 2회 → 알림 1건 |
| `inbox-sweep-backlog-events` | `backlog-open`·`backlog-close age=`·`sweep-alert bl=` 짝이 맞음 |
| `inbox-ev-rotate` | 10MB → `events.log.<epoch>`로 이동, 새 파일, 삭제 0 |
| `inbox-sweep-install-dry` | 기본 실행 → 격리 HOME의 `~/Library/LaunchAgents` 변경 0(스냅샷 대조) |
| `inbox-check-herdr-unchanged` | 새 manifest 추가 뒤 `install.sh --check herdr` 출력·종료 코드가 S3 전 기준값과 같음 (#11) |
| `inbox-check-sweep-doc` | 격리 HOME에 plist가 있으면 `--check inbox-sweep`이 "있음", 없으면 "없음"·종료 1 (2회차 새 #9) |
| `inbox-sweep-ackts-age` | 도착 10:00, `ackts` 10:14, sweep 관측 10:20 → `backlog-close age=840 exact=1` (2회차 새 #10) |
| `inbox-sweep-no-ackts` | 옛 판 ack(ackts 없음) → `age=관측−도착`, `ackts=-` |
| `inbox-sweep-old-then-new-ack` | #1 도착 10:00 → sweep 관측 → **옛 판 방식**(cursor 파일만 갱신)으로 #1 ack 10:14 → 새 판 `--ack 2` 10:25(`ackts` 행 `2\t2\t10:25`) → 10:30 sweep → #1의 `backlog-close`는 `ackts=-`·`age=관측−도착`(상한), 10:25로 확정하지 않음 (3회차 N3) |
| `inbox-sweep-times-missing` | 부가 기록 실패로 `times` 행이 빠진 줄 → `observed`로 나이를 재고 멈추지 않음 (2회차 새 #6) |

**외부 받은편지함 전환 절차(finding 10)**: sweep 설치 직후 한 번, 진행 중인 review-chain 체인마다 `inbox-sweep --register <리포>/.review-chain/<id>/inbox.log`와 `workers/*/inbox.log`를 실행한다. 대상 목록은 `find ~/Dev -path '*/.review-chain/*/inbox.log' -maxdepth 6`로 만든다(읽기만). auto-chain 받은편지함은 상태 폴더 안이라 자동으로 대상이다.

> **2026-11-11 주인님 결정(S3 마감 때)**: sweep 알림을 쓰지 않는다 — "메시지가 남아 있어도 따로 알릴 필요 없다". 이 방식(훅 대기자)이 안 되면 완전히 다른 방법으로 간다. 그래서 launchd는 설치하지 않고, `inbox-sweep`·`install-sweep.sh` 코드는 리포에 남긴다(필요해지면 `install-sweep.sh --apply` 한 번으로 켠다). 합의 결정 ②를 이것으로 바꾼다. 아래 종료 조건의 `--apply`·launchd 실측·외부 받은편지함 등록은 하지 않는다.

종료 조건(원래): 시험 통과·총계 대조, `plutil -lint` 통과. 이 맥에서 `install-sweep.sh` dry-run 출력을 주인님께 보이고 **go를 받은 뒤** `--apply`를 실행한다. 그다음 `launchctl print gui/<uid>/kr.waymakerlabs.agent-orchestrator.inbox-sweep`로 등록을 확인한다. **launchd 경유 실제 알림 확인**(finding 11 뒷부분): `known.list`에 `/tmp/ao-sweep-probe/x.log`를 등록하고, `times`에 도착 시각을 20분 전으로 적은 시험 줄 1개를 둔다. 다음 launchd 주기(5분 안)에 화면 알림이 뜨고 `sweep-alert sent=1`이 생기는지 본다. 끝나면 cursor를 ack해 닫고 등록을 지운다. office·home 설치는 S5 체크리스트다.
되돌리기: `install-sweep.sh --uninstall`, 코드는 `git revert`.

### S4. 스킬 문구 교체·판 올림 (브랜치 `feat/inbox-hooks`)

바꿀 파일(받은편지함 절만):
- `plugins/auto-chain/skills/autonomous-chain/SKILL.md` 「세션 간 메시지」
  - "받기" 줄: 조정자는 상태 파일을 만든 직후(worker 실행 단계와 상관없이) `"$AO" inbox-subscribe "$IB/coordinator.log"`. `--ack`·`--pending`·`--release`·`#0` 규칙은 유지한다. 깨움 출력의 `#n`은 Monitor 이벤트와 같게 다룬다.
  - **체인을 띄운 부모**: pane 받은편지함은 훅으로 자동이다. 단, 부모 세션이 inbox-hooks를 적용하기 전에 열린 세션이면 대기자가 없다. 그래서 부모는 자식을 띄우기 전에 `"$AO" inbox-wait --status`와 자기 pane 받은편지함의 `_aoi_watch_state`(spawn 스크립트가 출력)를 보고, `none`이면 지금처럼 Monitor `inbox-watch`를 켠다(finding 14 "부모는 할 일 없음" 정정).
  - 인계 순서는 §2-10을 그대로 옮긴다.
    1. 처리 동결
    2. 진행 중 처리 종료
    3. **실제로 처리한 마지막 번호까지만** `--ack`(받았지만 답하지 않은 줄은 ack하지 않는다)
    4. `inbox-subscribe --unsubscribe "$IB/coordinator.log"`(Monitor였으면 TaskStop도)
    5. 인계 문서에 "받은편지함 동결 · 마지막 처리 번호 <n>"
    6. 첫 지시

    rev 2의 "Monitor 중지 → ack" 순서는 이것으로 바꾼다. 새 조정자는 착수 때 `inbox-subscribe`를 하고 `--pending`으로 n+1부터 처리한다.
  - **훅이 없는 도구 대체 문단**(R3): Codex·OpenCode·kiro-cli, 또는 `inbox-wait --status`가 2가 아닌 환경에서는 지금처럼 Monitor `inbox-watch`, `timeout_ms: 1800000`, 만료되면 다시 켠다.
  - 송신 문구: "stdout이 `unwatched`면 자기 보고서·상태 파일에 `미감시 전송 <대상> <HH:MM>` 한 줄. 재시도·입력 주입 없음"(합의 결정 ③).
- `references/pane-worker.md` §4·§8 인계 절(169행 부근): 같은 교체.
- `references/task-brief.md` 17·24행: worker 착수 직후 `inbox-subscribe <내 받은편지함>`, 송신 뒤 `unwatched` 기록. 훅이 없으면 Monitor.
- `scripts/spawn-pane-worker.sh`(설계 §6 "띄울 때 계약"): 부모 pane 받은편지함을 `inbox-wait --status`와 `_aoi_watch_state` 판정(새 내부 동작 `inbox-watch --state <대상>`, stdout `monitor|waiter|none`, S1에 포함)으로 확인한다. `none`이면 stderr 경고 한 줄과 성공 줄 뒤 `parent_watch=none`을 낸다. 기동은 계속한다.
- review-chain
  - `SKILL.md` §4·§5, `references/messages.md` §1 "전달 방식", `references/worker-brief.md`의 받은편지함 감시 절, `references/oc-handover.md`: Monitor 안내를 `inbox-subscribe`로 바꾸고, 훅 없는 대체 문단을 둔다.
  - `scripts/rc-watch.sh`: `--subscribe <inbox>`·`--unsubscribe <inbox>` 인자를 더하고 `inbox-subscribe`로 exec한다(기존 인자 유지).
  - **`scripts/rc-send.sh`**(finding 12): §2-7대로 `watch=` 칸과 `unwatched` 기록.
  - **`scripts/rc-claim.sh`**(2회차 새 #7): §2-7대로 `[충돌]` 알림의 감시 상태를 기록한다. `CONFLICT` stderr·exit 4·stdout 빈 출력은 보존한다.
  - `references/oc-handover.md` §1: 2번 "Monitor를 TaskStop으로 멈추고"를 §2-10 순서(동결 → 진행 중 처리 종료 → 처리분만 ack → 구독 해제)로 고친다. 3번 "답하지 않은 줄은 ack하지 않는다" 규칙은 그대로 둔다(계획이 이 규칙에 맞췄다).
- `plugin.json`: auto-chain `2.7.0 → 2.8.0`, review-chain `0.1.4 → 0.2.0`, 둘 다 `dependencies: ["inbox-hooks"]`. 문서상 "A plugin that an enabled plugin depends on starts enabled regardless"(code.claude.com/docs/en/plugins-reference `defaultEnabled`)이므로 체인 플러그인을 쓰는 머신에서만 inbox-hooks가 켜진다. marketplace.json 버전 동기화, 각 CHANGELOG.

시험:
- auto-chain `scripts/test/run-tests.sh` 기존 이름 전부 PASS + `spawn-parent-unhooked-warn`(경고·`parent_watch=none`·기동 계속)·`spawn-parent-waiter-ok`.
- review-chain 시험(없으면 `scripts/test/run-tests.sh` 신설): `rc-send-watch-field`(출력 `OK box=… kind=… watch=unwatched`, 앞 두 칸 그대로), `rc-send-unwatched-record`(report.md에 `미감시 전송` 한 줄), `rc-send-watched-norecord`, `rc-send-meta-warn-no-retry`(부가 기록 경고 + exit 0일 때 rc-send가 4를 내지 않고 재실행 안내도 없음), `rc-claim-conflict-kept`(충돌 시 stderr `CONFLICT…`·exit 4·stdout 빈 출력이 이전과 같음), `rc-claim-unwatched-record`(OC 감시 없을 때 report.md에 `미감시 전송`), `rc-watch-subscribe`.
- 문구 잔존 검사: `grep -rn "timeout_ms: 1800000\|Monitor.*inbox-watch\|rc-watch.sh <" plugins/auto-chain plugins/review-chain`의 결과가 "훅이 없는 도구" 대체 문단 밖에서 0.
- `claude plugin validate`로 세 플러그인 통과.
- **G6 실측**(dependencies 활성화): 깨끗한 설정 폴더(`CLAUDE_CONFIG_DIR=/tmp/inbox-g6`)에서 브랜치 마켓플레이스를 추가하고 auto-chain만 설치 → inbox-hooks가 켜지는지 본다. `/plugin` 목록과 대기자 `wait-start`로 확인한다. auto-chain을 끄면 inbox-hooks도 꺼지는지 본다. 켜지지 않으면 S4를 BLOCK으로 두고 주인님께 대안(설치 안내 한 줄로 수동 켜기)을 보고한다. `defaultEnabled:true`는 합의 조건(분리 + 체인 사용자만) 위반이라 대안에서 뺐다.

종료 조건: 위 통과, G6 통과, **codex 크로스체크 1회(스킬 규약 = 무거운 게이트)**, 브랜치에만 push.
되돌리기: 브랜치라 main 영향 없음. 병합 뒤 되돌림은 §4-3.

### S5. 전환 (main 병합 + 관찰)

**병합 조건**(모두 충족해야 한다):

| # | 조건 | 확인 방법 (finding 13) |
|---|---|---|
| C1 | 세 머신 `agent-orchestrator`가 새 계약 판 | `"$AO" inbox-wait --status` → `inbox-wait 2`, exit 0 |
| C2 | 세 머신에서 실제 훅 입력으로 동작 | 머신마다 아래 스모크를 실행한다. `S=$(mktemp -d)`. 모든 호출에 `env -u HERDR_PANE_ID AO_STATE_ROOT=$S/state HOME=$S`를 붙인다(2회차 새 #8). 순서: `inbox-subscribe --session <시험 uuid> $S/x.log` → `printf '{"session_id":"<uuid>","hook_event_name":"Stop","transcript_path":"%s"}' $S/t.jsonl \| "$AO" inbox-wait &` → `inbox-send $S/x.log probe` → 대기자 exit **2**, stderr에 `#1`, `$S/state/inbox/events.log`에 `wait-notify`. 앞뒤로 실제 `~/.local/state/agent-orchestrator`의 `find -newer` 결과 변경 0 |
| C3 | 7000초 자체 종료(S2 ⑨, G5) | 결과가 S2 보고서에 있다. 없으면 병합하지 않는다 |
| C4 | G1~G4·G6 결과 | S2·S4 보고서에 통과 또는 대응 적용이 적혀 있다 |
| ~~C5~~ | ~~이 맥 sweep 설치·launchd 알림 확인~~ | **뺐다**(2026-11-11 결정, §3 S3 머리 인용) |
| C6 | 되돌림 리허설 | §4-3 단계 B+C·D를 시험 세션 하나에서 한 번 실행해 대기자 철회와 Monitor 복귀를 확인한다 |

**병합 뒤 순서**:
1. 병합·push → 세 머신 자동 갱신 → `installed_plugins.json`에서 auto-chain 2.8.0·review-chain 0.2.0·inbox-hooks 0.1.0을 실측한다.
2. **진행 중 체인은 바로 바꾸지 않는다.** gira-defect-night·grit-portal은 다음 인계 때 새 조정자가 새 스킬로 `inbox-subscribe`한다. 그 전까지 옛 조정자는 Monitor로 계속 받는다. 옛 Monitor와 새 대기자가 같은 받은편지함을 함께 들으면(새 세션이 같은 파일을 subscribe한 경우) 같은 줄이 두 번 보일 수 있다. 처리한 `#n`은 `--ack`만 한다는 기존 규칙으로 견딘다. 이 경우는 인계 순서(§2-10 1~4: 동결·처리분만 ack·Monitor TaskStop/구독 해제)가 막는다.
3. **활성 부모 세션**: 체인을 띄운 부모 `[OC]`가 inbox-hooks 이전에 열린 세션이면 대기자가 없다. S4 부모 문구대로 `none`이면 Monitor를 유지한다. 전환 확인 표에 부모 행을 따로 둔다.
4. ~~office·home의 sweep 설치~~ — 하지 않는다(2026-11-11 결정).

**확인**(1주 관찰, 결과는 `docs/plans/2026-11-11-inbox-reliability-S5-report.md`):
- 체인마다: 새 조정자 `sub op=add` → `wait-start` → `wait-notify` → `wait-delivered`가 한 번 이상.
- 부모마다: `waiter` 또는 `monitor` 판정 기록.
- 지표(§2-9): 깨움 지연 p50·p90·최대, 15분 초과 backlog 수, 전달률, 대기자 공백 최장과 공백 중 도착 수.
- 종료 조건: 두 체인 모두 새 방식으로 한 번 이상 인계 완료, 1주 동안 "사람이 물어서 발견한 미처리" 0건. 있으면 사례로 기록하고 원인을 분석한다.

## 4. 판 올림·하위호환·게시·되돌림

### 4-1. 판 올림

| 대상 | 판 | 언제 | 하위호환 |
|---|---|---|---|
| agent-orchestrator(`tools/`) | 판 번호 없음(커밋으로 식별), 기능 조회 `inbox-wait --status` = `inbox-wait 2` | S1·S3 main | 기존 동작의 인자·출력·종료 코드 변경 0. `.watch` 형식 그대로. `inbox-send`의 `watched`는 대기자 표식만큼 넓어진다 |
| inbox-hooks | 0.1.0 신규, `defaultEnabled:false` | S2 main | 의존하는 플러그인이 없으면 켜지지 않는다. 켜졌는데 `agent-orchestrator`가 옛 판이면 래퍼가 무동작 |
| auto-chain | 2.7.0 → 2.8.0 | S4 브랜치 → S5 병합 | 2.8.0 세션만 `inbox-subscribe`를 쓴다. 2.7.0 세션(진행 중 체인)의 Monitor와 같은 파일·cursor를 공유한다 |
| review-chain | 0.1.4 → 0.2.0 | 〃 | `rc-watch.sh` 기존 인자 유지. `rc-send.sh` 출력은 칸 추가뿐이다 |

### 4-2. 순서 제약

- 스킬(S4)이 `inbox-subscribe`를 부르기 전에 세 머신의 `~/.local/bin/agent-orchestrator`가 그 동작을 알아야 한다. 링크 대상이 마켓플레이스 사본 안 `tools/`이므로 S1 push 뒤 자동 갱신으로 들어온다. S5 C1·C2로 확인한다.
- 옛 판 `inbox-send`(갱신 전 머신)는 `times`를 쓰지 않는다. sweep은 그 줄을 `observed`로 잰다(§2-8).

### 4-3. 되돌림 단계 (finding 14)

문제의 크기에 따라 아래 단계 중 필요한 곳까지 한다. 각 단계는 따로 실행하고 확인할 수 있다.

| 단계 | 무엇을 | 방법 | 확인 |
|---|---|---|---|
| A. 코드 게시 되돌림 | 새 세션이 새 스킬·훅을 읽지 않게 | 병합 커밋 `git revert` → auto-chain 2.8.1·review-chain 0.2.1(내용은 2.7.0·0.1.4)·inbox-hooks 0.1.1(래퍼가 곧바로 exit 0) → push → 자동 갱신 | 세 머신 `installed_plugins.json` 판 |
| B+C. 끄기와 실행 중 대기자 철회 (한 명령, 2회차 새 #5) | 열린 세션이 훅 정의를 다시 읽지 않아도(R5), 시작 중이던 훅이 늦게 등록하려 해도 새 통지가 0이게 | 머신마다 `agent-orchestrator inbox-wait --drain`. 수신 잠금 안에서 `hooks.off`를 만들고 모든 `wait/*.pid`를 비운다. 잠금 밖에서 그 대기자들에 TERM을 보내고 철회 수를 출력한다. 이 잠금 뒤에는 ① 시작 중인 대기자가 등록 단계(§2-5 2번)에서 `hooks.off`를 보고 0으로 끝나고 ② 이미 등록된 대기자가 통지 직전 recheck에서 토큰 불일치·`hooks.off`로 0으로 끝나며 ③ SessionStart 동기 출력도 빈 출력이다. 판정이 core에 있으므로 래퍼가 옛 캐시여도 같다. 구독 파일은 남긴다(archive-first, 다시 켤 때 `--undrain`) | `--drain` 직후 새 줄 1개 → 어느 세션도 깨우지 않음, `events.log` `why=off`·`term`, `pgrep -f 'inbox-wait'` 0 |
| D. Monitor 복귀 | 받는 쪽이 다시 받게 | 진행 중 조정자·worker·부모에게 사용자가 탭에서 "Monitor `inbox-watch <받은편지함>`을 켜라"고 한 줄 알린다. 입력 주입은 하지 않는다. 2.8.1 스킬 문구가 Monitor이므로 새 세션은 자동이다 | 각 받은편지함 `inbox-watch --state` = `monitor` |

- `--drain`·`--undrain`은 S1의 계약이고, 경쟁 시험(`inbox-off-before-register`·`inbox-drain-after-register`·`inbox-drain-notify-race`)도 S1에 있다.
- 리허설: S5 C6(시험 세션 하나에서 B+C → D 순서로 실행. 대기자를 `pre-register`에 세운 상태에서 drain해 늦은 등록이 막히는지도 본다).

## 5. 위험·실측 게이트

### 5-1. 실측 게이트

통과하지 못하면 "대응"을 적용하고, 그 결과를 해당 세션 보고서에 적는다.

| 게이트 | 무엇을 | 세션 | 실패 시 대응 |
|---|---|---|---|
| G0 | Bash 환경 sid = 훅 입력 sid인가. `transcript_path`에 Stop 훅 stderr(token)가 기록되는가 | S1 | sid가 다르면 `sid-` 키를 버리고 pane 키만 쓴다(herdr 밖은 Monitor 대체). transcript에 없으면 **전달 확인은 ack만 인정한다**(2회차 새 #2). 훅 이벤트 이름은 대기자를 다시 띄우는 계기로만 쓰고 전달 증거로 쓰지 않는다. 그 결과 ack 전까지는 줄마다 최대 3회 재통지된다(R7) |
| G1 | SessionStart의 `asyncRewake` 훅이 입력 없이 쉬는 세션을 깨우는가 | S2 ② | 안 되면 재개 직후 공백이 남는다. sweep이 받치고, 스킬 문구에 "재개 직후 `--pending`"을 유지한다 |
| G2 | UserPromptSubmit의 비동기 exit 2가 입력 처리를 막거나 섞이지 않는가. 중단 뒤 복구가 되는가 | S2 ④ | 섞이면 UserPromptSubmit 줄을 빼고, 중단 뒤 공백은 sweep만 받친다(§5-2 R2) |
| G3 | resume·compact·clear·fork 때 sid가 바뀌는지, additionalContext가 보이는지 | S2 ②③⑦ | 표(§2-3)를 실측대로 고친다. 안 보이면 스킬에 `--pending`을 유지한다 |
| G4 | 깨움 stderr가 transcript에 남는가(G0과 같은 질문을 실제 플러그인 경로에서) | S2 ① | G0 대응과 같다 |
| G5 | `asyncRewake` `timeout: 7200`이 지켜지는가, 7000초 자체 종료 | S2 ⑨ → S5 C3 | 일찍 죽으면 `AO_INBOX_WAIT_MAX` 기본값을 관측값 −200초로 낮추고 계약에 적는다 |
| G6 | `dependencies`로 inbox-hooks가 켜지고 꺼지는가(2.1.322, Kiro 프록시) | S4 | S4를 BLOCK으로 두고 주인님께 수동 켜기 안내안을 보고한다. `defaultEnabled:true`는 쓰지 않는다. **S4 결과**: 켜짐 통과(새 설치·2.7.0→2.8.0 갱신 모두 `+ 1 dependency: inbox-hooks`, 훅 `wait-start` 실측). 꺼짐은 따라오지 않는다 — `disable auto-chain` 뒤에도 inbox-hooks enabled, `uninstall` 뒤에는 `claude plugin prune`이 지운다. 되돌림은 core `--drain`이 맡으므로 BLOCK 아님(S4 보고서 §2) |
| G7 | 같은 pane에서 새 세션이 시작될 때 런타임이 옛 세션의 async 훅을 취소하는가 | S2 ⑩ | **정확성은 이 결과에 기대지 않는다.** pane 세대 검증(§2-3)이 통과 판정을 맡는다. 결과는 R6(남은 프로세스 수) 추정에만 쓴다 |
| G8 | 같은 이벤트의 동기·async 훅이 실제로 병렬로 실행되는가 | S2 ②③ | 순서와 상관없이 수신 잠금으로 직렬화되므로 대응이 필요 없다. 결과만 기록한다 |

### 5-2. 남은 위험

| # | 항목 | 대응 |
|---|---|---|
| R1 | 깨운 턴을 사용자가 중단한 뒤 사람이 아무것도 하지 않는 구간 | 훅 이벤트가 없어 대기자를 띄울 수 없다. **알림 없음**(2026-11-11 결정) — `events.log` 공백 지표로 크기만 재고 S5 판정에 쓴다 |
| R2 | 대기자 만료(7000초) 뒤 쉬는 세션 | 같다. 필요하면 세션 안 CronCreate 주기 턴을 별도로 검토한다(이번 범위 밖) |
| R3 | 훅이 없는 도구(Codex·OpenCode·kiro-cli) | `inbox-watch` Monitor를 그대로 둔다. S4 대체 문단. (sweep 알림은 2026-11-11 결정으로 쓰지 않는다) |
| R4 | 진행 중 체인(gira-defect-night·grit-portal) | 다음 인계 때만 새 방식으로 바꾼다. 같은 cursor를 공유해 섞여도 줄이 빠지지 않는다 |
| R5 | 이미 열린 세션이 새 훅 정의를 다시 읽는지(UNVERIFIED) | 새 세션부터 적용으로 본다. 끄기는 core의 `hooks.off` 판정(§4-3 B+C)이라 재적재와 상관없다 |
| R6 | 남은 대기자 프로세스(세션 종료 뒤 최대 7000초) | 1초 폴링 bash 1개. `--drain`으로 철회. S5에서 동시 대기자 수를 관찰한다 |
| R7 | 재통지 3회 상한 뒤 처리 안 된 줄 | 자동 깨움은 멈추고 sweep이 사람에게 알린다. 상한은 S5 지표로 조정한다 |
| R8 | 깨움이 사람 입력과 섞이는가 | 실측(09:18)에서 섞이지 않았다. S2 ⑥에서 다시 본다 |
| R9 | `herdr notification show`의 정확한 인자 | S3 착수 때 `--help`로 한 번 확인한다 |
| R10 | SessionStart 동기 훅과 async 훅의 실행 순서 | 통지 예약이 수신 잠금 안에서 일어나 한 줄은 한 경로에서만 알린다(§2-6, S1 `inbox-start-async-race`) |
| R11 | 수신 잠금 경합(세션 수십 개가 동시에 훅 실행) | 잠금 구간은 파일 몇 개 읽기·쓰기라 수 ms다. 폴링은 잠금 없이 줄 수만 본다. S5에서 `wait-end why=error:lock` 수를 본다. 문제가 되면 상태 루트를 머신 단위에서 pane 단위로 나누는 안을 백로그로 둔다 |
| R12 | bash에서 TERM 지연 trap(§2-5 8번)의 실제 동작 | S1 `inbox-wait-term-direct`·`inbox-wait-term-lockwait`(통지 임계구역 안에 TERM을 직접 넣는 시험)로 고정한다. `inbox-wait-term-in-notify`는 교체 직렬화 시험으로만 남긴다(3회차 N4) |

## 6. 설계와 다르게 정한 점·리뷰 처리

### 6-1. 설계와 다르게 정한 점 (리뷰에서 반대가 없으면 따른다)

- **D1 구독 키에 pane을 더했다.** 설계는 `subs/<session_id>`만 정했다. herdr 안 조정자·worker는 pane이 바뀌지 않으므로 pane 키가 재개를 견딘다. `sid-` 키는 herdr 밖 세션용이다(G0 결과에 따라 폐기할 수 있다).
- **D2 대기자를 띄우는 훅이 넷이다**(설계 §5-1·§4 "언제나 Stop" 정정). 설계 rev 3에 반영했다.
- **D3 `.watch`는 바꾸지 않고, 깨움 표식은 두지 않는다.** 대기자 표식은 `<log>.waiters/<sid>`를 쓴다. 깨운 턴을 처리하는 동안의 `unwatched`는 참고값으로 받아들인다.
- **D4 sweep 나이는 도착 시각 사이드카 `<log>.times`로 잰다.** 사이드카가 없는 줄은 관측 기반 `≥`로 따로 표시한다(설계 §5-6 "가장 오래된 줄의 시각" 구체화).
- **D5 훅 켜기 = `defaultEnabled:false` + 체인 플러그인의 `dependencies`.** G6에서 실측한다.
- **D6 빈 구독 파일 삭제는 archive-first 대상에서 뺀다.** 우리가 만든 상태 파일의 정리이고 이력은 `events.log`에 남는다. `events.log`는 이름만 바꾸고 지우지 않는다.
- **D7 SessionStart 명령은 `inbox-wait --session-start`다**(설계 §5-1의 `inbox-watch --pending` 대체).
- **D8 `inbox-wait`만 인자 오류를 4로 낸다**(훅에서 2는 깨움).
- **D9 재통지 억제는 전달 확인에 묶는다.** rev 1의 `seen`(알리면 곧바로 억제)은 폐기했다. 확인 전에는 최대 3회 재통지하고, 끝없는 깨움은 상한으로 막는다.
- **D10 review-chain 외부 받은편지함은 `known.list`와 `--register` 전환 절차로 sweep 대상에 넣는다.**
- **D11 `events.log`에 원문을 적지 않는다.**
- **D12 되돌림을 세 단계로 나눴다**(§4-3 A, B+C, D). `--drain`(끄기 표식 + 대기자 철회를 한 장벽으로)과 `--undrain`이 새로 생겼다.
- **D13 수신 잠금을 하나로 합쳤다**(rev 3). 키별 잠금은 bash 3.2에서 여러 fd를 동시에 쥐기 어렵고, 목록·세대 스냅샷의 원자성도 보장하기 어렵다.
- **D14 같은 pane의 가장 최근 세션이 그 pane 받은편지함의 수신자다**(rev 3, `pane-gen`).
- **D15 인계 계약은 "처리분만 ack"다**(rev 3, §2-10). 설계 §6 인계 행의 "옛 조정자 `--unsubscribe` → ack → 인계"를 "동결 → 진행 중 처리 종료 → 처리분만 ack → 구독 해제 → 인계 문서 → 첫 지시"로 바꿨다(설계 rev 4).
- **D16 송신 성공 = append 성공이다**(rev 3). 부가 기록 실패는 경고 + exit 0이다.

### 6-2. 1회차 리뷰(codex Sol high, BLOCK) 처리표

| # | 등급 | 처리 | 반영 위치 |
|---|---|---|---|
| 1 | BLOCK | 반영. 모든 읽기 경로의 첫 단계를 `_aoi_claim`으로 통일했다. 이어받는 범위를 `source`별 표로 정했다 | §2-3, §2-6, S1 `inbox-wait-claim-first`·`-clear-pane` |
| 2 | BLOCK | 반영. 해제를 fd 8 장벽으로 하고, 대기자는 매 폴링·통지 직전에 `.gen`과 토큰을 다시 확인한다 | §2-4, §2-5 5·6번, S1 `inbox-sub-del-barrier`·`-running`·`-handover` |
| 3 | BLOCK | 반영. SessionStart(async)·StopFailure·UserPromptSubmit에서도 띄운다. 중단 뒤 무입력 구간은 sweep이 받친다. 실측 게이트로 둔다 | §2-5 표, S2 ②~⑤, §5-1 G1·G2, §5-2 R1, 설계 rev 3 §4·§5 |
| 4 | BLOCK | 반영. 통지 확정을 fd 7 교체 잠금 안에서 하고, TERM은 fd 7을 잡은 뒤에만 보낸다. 억제는 전달 확인 뒤에만 한다. 결정적 시험을 넣었다 | §2-5 2·3·6번, D9, S1 `inbox-wait-term-in-notify`·`-term-before-notify`·`-undelivered-renotify` |
| 5 | MAJOR | 반영. pid 파일에 `<pid> <lstart> <token>`, 교체를 fd 7로 직렬화했다 | §2-1, §2-5 2번, S1 `inbox-wait-concurrent-3`·`-pid-reuse` |
| 6 | MAJOR | 반영. `.watch` 형식을 유지하고 별도 `waiters/` 파일을 둔다 | §2-1, D3, S1 `inbox-watch-format-kept` |
| 7 | MAJOR | 반영. wake 표식을 폐기했다. 유효성 판정을 하나로 만들고 spawn 부모 확인도 같은 판정을 쓴다 | §2-1, §2-2, S4 spawn |
| 8 | MAJOR | 반영. `<log>.times` 사이드카를 두고, 없는 줄은 관측 기반 `≥`로 표시한다. 부분 ack·옛 backlog·자정 시험을 넣었다 | §2-7, §2-8, S3 `inbox-sweep-partial-ack`·`-legacy-backlog`·`-midnight` |
| 9 | MAJOR | 반영. `sweep/alerts`를 분리해 ack 뒤에도 보존한다 | §2-8, S3 `inbox-sweep-ack-keeps-alert` |
| 10 | MAJOR | 반영. `--register`와 전환 절차, 등록 안 된 대조군을 넣었다 | §2-8, S3 전환 절차·`-external-*` |
| 11 | MAJOR | 반영. 기존 manifest·해석기를 건드리지 않고 별도 `inbox-sweep.manifest`를 두며 기존 kind만 쓴다. `--age-min 0` 확인은 도착 시각을 앞당긴 시험 줄과 실제 launchd 주기로 바꿨다 | S3 manifest·종료 조건, `inbox-check-herdr-unchanged` |
| 12 | MAJOR | 반영. `rc-send.sh`를 S4 목록에 넣었다. `watch=` 칸을 추가하고 미감시를 직접 기록한다 | §2-7, S4 review-chain·시험 |
| 13 | MAJOR | 반영. 기능 조회 `--status`와 유효 JSON 실훅 스모크(exit 2까지)를 나눴다. 7000초를 C3 필수로 했다 | §2-5, S5 C1~C3 |
| 14 | MAJOR | 반영. 게시·세션 끄기·대기자 철회·Monitor 복귀 4단계, 활성 부모 문구, 리허설 C6을 넣었다 | §4-3, S4 부모, S5 C6·3번 |
| 15 | MAJOR | 반영. 스키마를 다시 정의했다(도착 시각·통지·전달·종료 원인·backlog id), 분자·분모도 명시했다 | §2-9, S1 `inbox-ev-*` |
| R6(rev 1) | — | `defaultEnabled:true` 대안을 삭제했다(합의 조건 위반) | §5-1 G6, S4 |

**부분 반박 (finding 2 범위) — rev 3에서 정정, 철회한 부분 있음**: 장벽은 "해제가 0으로 돌아온 뒤의 통지"만 막는다. 해제 직전에 이미 나간 통지를 회수할 수 없다는 점은 유지한다(2회차 리뷰도 조건부로 타당하다고 판정했다). rev 2의 "그 통지를 해제 뒤 ack 범위에 넣는다"는 **철회한다.** 전달과 처리를 섞은 설명이었고, `oc-handover.md` §1-3의 "답하지 않은 줄은 ack하지 않는다"와 어긋났다. 중복 처리를 막는 것은 장벽이 아니라 인계 계약(§2-10: 동결 → 진행 중 처리 종료 → 처리분만 ack)이다.

### 6-3. 2회차 리뷰(codex, BLOCK) 처리표

| # | 등급 | 처리 | 반영 위치 |
|---|---|---|---|
| 새 1 | BLOCK | 반영. 수신 잠금 하나(fd 8, `recv.flock`) 안에서 목록·세대 스냅샷(`_aoi_targets`)을 얻고, 출력 직전 `_aoi_recheck`로 membership·sid·세대·pane-gen·`hooks.off`를 다시 확인한다. SessionStart 동기 출력도 같은 잠금 안에서 출력을 결정한다. 키별 잠금을 버린 이유(bash 3.2 fd)도 적었다 | §1 잠금 표, §2-4 끝, §2-5 2·6번, §2-6, S1 `inbox-start-unsub-barrier`·`-before`·`inbox-snapshot-atomic` |
| 새 2 | MAJOR | 반영. 전달 확인은 transcript token 또는 ack만 인정한다. 이벤트 이름은 복구 계기로만 쓴다. G0 대안 문구를 고쳤다 | §2-5 4번, §5-1 G0, S1 `inbox-delivered-no-event`·`-ack` |
| 새 3 | MAJOR | 반영. 통지 예약을 수신 잠금으로 직렬화하고 `ctx` 상태를 따로 뒀다. 동시·순서 시험을 넣었다 | §2-1 notified, §2-6, S1 `inbox-start-async-race`·`-order`·`inbox-ctx-demote`, §5-1 G8 |
| 새 4 | MAJOR | 반영. `pane-gen` 수신 세대를 두고 등록·통지 직전에 검증한다. 런타임 자동 취소(G7)에는 기대지 않는다 | §2-1, §2-3, §2-5 2·6번, S1 `inbox-pane-gen-*`, S2 ⑩, §5-1 G7 |
| 새 5 | MAJOR | 반영. `hooks.off`를 core가 등록 직전·통지 직전에 수신 잠금 안에서 본다. `--drain`이 같은 잠금 안에서 표식 생성 + pid 비우기를 한다. 경쟁 시험 3개를 넣었다 | §2-5 명령·2번, §4-3 B+C, S1 `inbox-off-before-register`·`inbox-drain-*` |
| 새 6 | MAJOR | 반영. append 성공 = 확정, 부가 기록 실패는 경고 + exit 0이다. `.times`가 빠지면 sweep은 관측 기반으로 잰다. 실패 주입 시험을 넣었다 | §2-7, S1 `inbox-send-meta-fail-*`, S3 `inbox-sweep-times-missing`, S4 `rc-send-meta-warn-no-retry` |
| 새 7 | MAJOR | 반영. `rc-claim.sh`를 S4에 넣었다. CONFLICT·exit 4·stdout을 보존한다 | §2-7, S4 review-chain·시험 `rc-claim-*` |
| 새 8 | MAJOR | 반영. `AO_STATE_ROOT`로 상태 루트를 격리하고 `HERDR_PANE_ID`를 unset한다. 실제 상태 폴더 변경 0을 시험 조건으로 했다 | §1, S1 `inbox-real-state-untouched`, S2 실측 환경, S5 C2 |
| 새 9 | MINOR | 반영. kind를 `doc`으로 정하고 5칸 행을 적었다 | S3 manifest, `inbox-check-sweep-doc` |
| 새 10 | MINOR | 반영. `age = ackts − arr`(`<log>.ackts`), 관측 기반은 `ackts=-`로 표시한다. "실제 나이 이상"을 "이하(하한)"로 정정했다 | §2-1, §2-8 나이, §2-9 `backlog-close`·건수, S1 `inbox-ack-ts`, S3 `inbox-sweep-ackts-age`·`-no-ackts` |
| 부분 반박 지적 | — | 받아들였다. 인계 계약을 고쳤다 | §2-10, S4 인계 문구·`oc-handover.md`, §6-2 끝, 설계 rev 4 §6 |

**1회차 부분 판정 항목의 해소 여부**:

| 1회차 # | 2회차 판정 | rev 3 처리 |
|---|---|---|
| 1 | 부분(다른 sid 기존 대기자 무효화 없음) | 새 4의 `pane-gen`으로 해소 |
| 2 | 부분(SessionStart 동기·스냅샷이 장벽 밖) | 새 1로 해소 |
| 4 | 부분(이벤트 이름 대체 규칙) | 새 2로 해소 |
| 11 | 부분(kind 모순) | 새 9로 해소 |
| 12 | 부분(`rc-claim.sh` 누락) | 새 7로 해소 |
| 14 | 부분(drain·시작 경쟁) | 새 5로 해소 |
| 15 | 부분(backlog 종료 나이 기준) | 새 10으로 해소 |

### 6-4. 3회차 리뷰(codex, BLOCK 2·MAJOR 2) 처리표 — rev 4, 최소 수정

| # | 등급 | 처리 | 반영 위치 |
|---|---|---|---|
| N1 | BLOCK | 반영. SessionStart stdout 쓰기를 수신 잠금 안으로 옮겼다(recheck → 출력 → 잠금 해제). 출력은 8KB 이하이고, 넘치면 "나머지 `--pending`" 안내로 자른다. rev 3의 "먼저 확정한 출력은 해제 전 일" 재정의는 삭제했다. 시험 정지 지점을 `start-mid-out`(출력 완료 전)으로 바꾸고, unsubscribe와 drain이 출력 완료까지 기다리는지 본다 | §2-6 8a·크기 상한, §2-5 정지 지점, S1 `inbox-start-unsub-barrier` |
| N2 | BLOCK | 반영. `pane-gen`을 올리는 것은 SessionStart 동기 훅뿐이고, 발급 기록 `wait/<sid>.issued`를 남긴다. 나머지 대기자와 async SessionStart는 발급 gen = 현재 gen일 때만 등록·통지하고, 다르면 세대를 건드리지 않고 `pane-superseded`로 끝난다. 의도적 resume은 SessionStart(resume)가 새 전환이다. "가장 최근에 시작하거나 훅을 실행한 세션" 문구를 "가장 최근에 SessionStart를 실행한 세션"으로 고쳤다 | §2-1, §2-2, §2-3 pane 수신 세대, §2-5 2·6번, §2-6 2번, S1 `inbox-pane-gen-late-old`·`-only-sessionstart`·`-resume-back`·`-no-issue`·`inbox-async-start-issue-wait` |
| N3 | MAJOR | 반영. `ackts`는 실제 전진 범위 `<from> <to> <epoch>`를 기록한다. 범위로 덮이지 않는 줄(옛 판 ack)은 `ackts=-`, 관측 기반 상한이다 | §2-1, §2-9 `backlog-close`, S1 `inbox-ack-ts`, S3 `inbox-sweep-old-then-new-ack` |
| N4 | MAJOR | 반영. 통지 임계구역 안에 TERM을 직접 넣는 시험과 잠금 대기 중 TERM 시험을 따로 추가했다. R12 근거를 이 시험으로 바꿨다. `inbox-wait-term-in-notify`는 교체 직렬화 시험으로 남는다 | §2-5 정지 지점 `notify-mid`, S1 `inbox-wait-term-direct`·`-lockwait`, §5-2 R12 |

**이전 회차 부분 판정 항목의 해소 여부**(문서상 계약 기준, 구현·실측 통과는 아니다):

| 회차·# | 3회차 판정 | rev 4 처리 |
|---|---|---|
| 2회차 #1 | 부분(SessionStart stdout이 장벽 밖) | N1로 해소 |
| 2회차 #4 | 부분(늦은 옛 훅의 세대 재탈취) | N2로 해소 |
| 2회차 #5 | 부분(SessionStart 출력이 drain 장벽 밖) | N1로 해소(drain도 출력 완료까지 기다림) |
| 2회차 #10 | 부분(신구 ack 혼용) | N3으로 해소 |
| 1회차 #1 | 부분(옛 훅 세대 재탈취) | N2로 해소 |
| 1회차 #2 | 부분(SessionStart 실제 출력 장벽) | N1로 해소 |
| 1회차 #14 | 부분(늦은 동기 출력) | N1로 해소 |
| 1회차 #15 | 부분(신구 ack 혼용 집계) | N3으로 해소 |
| 1회차 #4 | 해소·시험 보완 | N4로 시험 보완 |

새 설계 확장은 하지 않았다. 새로 생긴 상태 파일은 `wait/<sid>.issued` 하나이고, 새로 생긴 정지 지점은 `start-mid-out`·`notify-mid`·`issue-wait`이다.

### 6-5. delta 재검토(codex, BLOCK 1) — 리뷰 상한 도달, 조건부

- 결과: N1·N3·N4 해소, N2 부분. 새 F1 [BLOCK] — 옛 `.issued`가 남은 resume에서 async SessionStart 대기자가 동기 발급 전에 검증해 조기 종료(`/tmp/xc-result-20261111-102154.md`).
- 처리: 리뷰어 추천안 그대로 §2-3 async 대기 조건을 "발급 기록·현재 pane-gen 일치까지 대기"로 고치고 S1 시험 `inbox-async-start-resume-stale-issue`를 더했다.
- **상태: 리뷰 SHIP 아님.** 무거운 게이트 3회 + delta 1회를 모두 썼다. 대상이 구현 전 계획 문서(되돌릴 수 있음)이므로 review-protocol 규칙대로 멈추지 않고 진행하되, F1 수정은 **재검토를 받지 않은 미해결 항목**으로 둔다. S1 구현 뒤 결정적 시험 통과로 닫고, S2 크로스체크 범위에 F1 수정을 넣는다.
