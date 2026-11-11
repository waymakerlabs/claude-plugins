# 받은편지함 감시 끊김 방지 — S5 보고서 (2026-11-11)

계획 rev 5 §3 S5, 인계 `2026-11-11-inbox-reliability-S5-handoff.md` §5. 이 문서는 병합 전 단계(§5-1~3)까지의 결과다. 병합·push·1주 관찰은 주인님 go 뒤에 §5 이하에 이어 적는다.

## 1. 요약

- **C6 되돌림 리허설 통과**(이 맥, 시험 상태 루트 `/tmp/s5-c6/w/state`, 리포 판 AO).
- **C2 스모크 통과**(이 맥만, 리포 판 AO). office·home은 미실행(다른 머신 실행은 go 대상).
- **C1 미충족(예상대로)**: 이 맥의 `~/.local/bin/agent-orchestrator`는 마켓 설치 사본을 가리키고 아직 옛 판이다. `inbox-wait --status` → `알 수 없는 동작: inbox-wait`, rc=2. push 뒤 자동 갱신으로만 충족된다.
- C3(S2 보고서 ⑨, 7001초)·C4(S2 G1~G5, S4 G6) 근거는 기존 보고서에 있다. C5는 뺐다.
- 실제 `~/.local/state/agent-orchestrator` 변경 0(두 스크립트 모두 `find -newer` 전체 0). `~/.local/bin`·전역 settings 변경 0. 코드 수정 없음.

## 2. 병합 조건 현황

| # | 상태 | 근거 |
|---|---|---|
| C1 | 이 맥 미충족(옛 판), office·home 미확인 | push → 자동 갱신 뒤 `inbox-wait --status` = `inbox-wait 2` 확인 필요 |
| C2 | 이 맥 리포 판 통과, office·home 미실행 | §4. 세 머신 모두 갱신된 설치 판으로 다시 돌려야 한다 |
| C3 | 충족 | S2 보고서 ⑨ |
| C4 | 충족 | S2 보고서 G1~G5, S4 보고서 §2 G6 |
| C6 | 충족 | §3 |

## 3. C6 되돌림 리허설 (§4-3 B+C → D)

스크립트 `/tmp/s5-c6/run.sh`, 결과 `/tmp/s5-c6/result.txt`. 모든 호출에 `env -u HERDR_PANE_ID AO_STATE_ROOT=$S/state HOME=$S`.

구성: 세션 A가 `x.log`, 세션 B가 `y.log`를 `--session`으로 구독. A의 Stop 대기자를 등록 완료 상태로, B의 Stop 대기자를 `AO_INBOX_TEST_PAUSE=pre-register:20`으로 등록 직전에 세운 뒤 `--drain`.

| 확인 | 결과 |
|---|---|
| drain 전 `inbox-watch --state x.log` | `waiter` |
| `--drain` 출력(철회 수) | `1`(등록된 A만), rc 0 |
| 등록된 대기자 A | exit 0, stderr 0바이트, `wait-end why=off` |
| 늦은 등록 B(재개 뒤) | exit 0, stderr 0바이트, `wait-end why=off`, `wait-start` 없음(등록 안 됨) |
| drain 뒤 새 줄 x·y 각 1개 | `send ... watch=unwatched` 두 줄 |
| drain 뒤 새 Stop 훅 A·B | 둘 다 exit 0, stderr 0, `why=off`(깨움 0) |
| drain 뒤 state x·y | `none`·`none` |
| `pgrep -f inbox-wait` | 0 |
| D: Monitor `inbox-watch x.log` 기동 | state `monitor`, 새 줄 `send` → `watched` |
| Monitor 출력 | drain 중 도착한 줄 `#1 [이전 세션]`(+`#0` 안내), 새 줄 `#2` 모두 표시 |
| `--undrain` | rc 0, `hooks.off` 제거 |

판정: `why=term`은 나오지 않았다. A는 drain의 TERM으로 끝났지만 TERM 처리기(`lib/inbox-wait.sh:256`)가 `hooks.off`가 있으면 `why=off`를 먼저 고르기 때문이다(코드 확인). 그래서 drain 뒤에는 `term` 대신 `off`가 남는 것이 정상이다. 계획 확인 칸 "`why=off`·`term`"은 둘 중 하나로 읽고, 핵심인 통지 0·대기자 0이 충족하므로 통과로 둔다.

Monitor 출력의 `[이전 세션]` 표시: drain 중 도착한 줄은 구독 세션 A가 owner로 claim한 상태였으므로 새 Monitor에는 보류 줄로 보인다. 계획 §2-3 동작 그대로다. 실제 되돌림 때 D 안내문에 "`[이전 세션]` 줄은 사용자 확인 뒤 처리" 한 줄이 필요하다(§6 위험 1).

리허설 스크립트 첫 실행은 내 스크립트 실수(A·B를 같은 `x.log`에 구독시켜 B가 구독을 가져가 A가 `why=no-target`)로 의도한 구성이 아니어서 대상 분리 뒤 다시 돌렸다. 도구 결함이 아니다. 첫 실행이 남긴 Monitor 프로세스 2개는 `pkill -f 's5-c6/w/x.log'`로 정리했다.

## 4. C2 스모크 (이 맥, 리포 판)

스크립트 `/tmp/s5-c2/run.sh`, 결과 `/tmp/s5-c2/result.txt`, 상태 `/tmp/s5-c2/run.mDCv`. 계획 S5 표 C2 순서 그대로(`env -u HERDR_PANE_ID AO_STATE_ROOT=$S/state HOME=$S`).

```
status: inbox-wait 2 rc=0
subscribe rc=0
send: watched rc=0
대기자 exit=2
#1 17:14:47 probe
ev=wait-notify  sid=cccccccc-…-000000000003  n=1-1  arr=1794384887  re=0
실제 상태 폴더 find -newer: 0
```

## 5. 다르게 정한 점

- C6을 실제 Claude 세션(`/tmp/inbox-hooks-test/launch.sh`) 대신 훅 입력 JSON을 직접 넣는 셸 리허설로 했다. drain 판정이 core에 있고(§4-3), 실제 세션 훅 경로는 S2 G1~G4로 이미 실측됐기 때문이다.

## 6. 남은 위험·다음

1. 되돌림 D 단계 안내문에 `[이전 세션]` 보류 줄 처리 안내가 없다. 실제 되돌림 때 안내 한 줄에 "#0/`[이전 세션]` 줄은 사용자 확인 뒤 `--ack`/`--release`"를 덧붙인다.
2. C1·office·home C2는 push 뒤에만 확인할 수 있다.

## 7. 병합·push (주인님 go, 2026-11-11 17:21)

- `git push -u origin feat/inbox-hooks`(새 브랜치) → `main`에 `--ff-only` 병합 → `git push origin main`: `d681522..2662c2c`. 병합 커밋 없음.
- 이 맥 자동 갱신(17:22 확인): 마켓 사본 HEAD `2662c2c`. `installed_plugins.json` auto-chain 2.8.0·review-chain 0.2.0·inbox-hooks 0.1.0(`lastUpdated` 08:21:58Z).
- **C1 이 맥 충족**: `~/.local/bin/agent-orchestrator inbox-wait --status` → `inbox-wait 2`, rc 0.
- **C2 이 맥 설치 판 통과**: 같은 스모크를 `AO=~/.local/bin/agent-orchestrator`로 다시 실행(`/tmp/s5-c2/result-installed.txt`). 대기자 exit 2, `#1 probe`, `wait-notify` 1, 실제 상태 폴더 `find -newer` 0.
- office·home C1·C2: 미실행(다른 머신 실행은 go 대상).
- 진행 중 체인(gira-defect-night·grit-portal)은 바꾸지 않았다. 다음 인계 때 새 조정자가 새 스킬로 전환한다(계획 S5 병합 뒤 순서 2).

## 8. 참고 사례 — 다른 체인의 회수 지연 2건 (받은편지함 경로 아님)

주인님 전달(2026-11-11). 상태 파일·보고서 mtime·실제 받은편지함·`events.log`를 읽기만 해서 확인했다.

| 체인 | 지연 | worker 방식 | 조정자 기록 |
|---|---|---|---|
| gira-backlog-night | M1-W3-T06(보고서 13:07:20)·M2-W1-T01(13:06:34) → 17:11 회수, **약 4시간** | ① `Agent`(상태 파일 39·40행) | "완료 알림이 이 세션에 오지 않았다, 원인 미확정"(state.md 62행) |
| grit-portal | M4-W4-T07(보고서 15:43:27) → 17:0x, **약 1시간 20분** | ① `Agent` bg(state.md 79행) | "T07·T01c 합친 진행 감시가 이벤트 없이 만료, 16:01 감시 시작 뒤 줄 변화 없음" |

**이번 변경(S1~S4)이 이 두 건을 막는가: 아니다.**

- 이번 변경이 덮는 것은 `inbox-send`로 받은편지함에 쓴 줄을 쉬는 세션에 알리는 경로다. 두 건 모두 ① `Agent` worker인데, ① worker는 메시지를 보내지 않고 반환 한 줄로 끝난다(task-brief.md 13행 "완료 알림이 조정자에게 간다"). 두 체인 `coordinator.log`에도 해당 시각 worker 줄이 없다(gbn 1줄, 12:08. grit 5줄, 마지막 14:37).
- 실제 `events.log`는 `send` 153·`ack` 3뿐이고 `wait-*`가 0이다. 두 조정자는 2.8.0 이전 세션이라 대기자가 없다(계획대로 다음 인계부터 전환).
- 원인 ① gbn: Claude Code의 백그라운드 `Agent` 완료 알림이 조정자 세션에 닿지 않은 것으로 보인다. 런타임 쪽이라 우리 리포에서 고칠 수 없고, 원인은 확인하지 못했다(UNVERIFIED).
- 원인 ② grit: 스킬의 표준 진행 감시 스크립트(SKILL.md 482~496행)는 기동마다 새 `mktemp` 캐시를 쓰므로 첫 루프에서 `- 진행: 완료`를 출력해야 한다. "변화 없어 알림 없음"이 났다면 그 세션이 스크립트를 고쳐 썼을 가능성이 높다(UNVERIFIED, 그 세션의 Monitor 명령은 못 봤다). 진행 감시는 웨이브마다 띄우게 돼 있지만(SKILL.md 482행) 완료 판정은 worker 반환으로만 한다고 적혀 있고(500행), 진행 감시가 30분마다 만료되면 다시 띄워야 한다. 그래서 완료 알림이 빠지면 받쳐 주는 것은 이 감시 하나뿐이다.

**막으려면(제안, 미반영)**:
1. ① `Agent` worker도 끝낼 때 조정자 받은편지함에 `inbox-send … done <보고서>` 한 줄을 보낸다. 2.8.0 조정자는 `coordinator.log`를 구독하므로 완료 알림이 빠져도 훅 대기자가 깨운다. task-brief.md §7·SKILL.md 「세션 간 메시지」 문구 변경이며 합의 결정 §3과 충돌하지 않는다. 남는 구멍: 조정자가 쉬지 않고 다른 일을 하는 중이면 깨움은 턴이 끝날 때 온다(지연은 턴 길이).
2. 진행 감시 절에 "재기동 직후 각 보고서 `- 진행:` 줄을 직접 읽어 확인하고, 표준 스크립트를 고쳐 쓰지 않는다"를 추가한다.
3. 진행 감시가 `- 진행: 완료`를 알렸는데 worker 반환이 없으면, 반환을 기다리지 말고 보고서로 회수한다(500행 "완료 판정은 반환"의 예외로 명시).
