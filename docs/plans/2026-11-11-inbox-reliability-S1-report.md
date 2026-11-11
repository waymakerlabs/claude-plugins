---
title: 받은편지함 감시 끊김 방지 — S1(도구) 보고서
date: 2026-11-11
plan: docs/plans/2026-11-11-inbox-reliability-plan.md (rev 5) §3 S1
status: done   # 시험 통과·커밋 완료. push 안 함. 독립 리뷰는 S2 크로스체크에 묶음(§5)
---

# S1 보고서 — 구독·대기자·송신 기록·events

## 1. 결과 요약

- 계획 S1의 도구를 모두 구현했다. 시험은 188개에서 265개로 늘었고, 마지막 코드로 **265/265 PASS**다.
- 커밋 세 개(`~/Dev/claude-plugins` main, origin보다 3 앞섬, push 안 함):
  - `e5f8c6d` 설계 rev 4·계획 rev 5 복원(§4 사고 참조)
  - `e71715a` 단계 A(송신 기록·감시 판정·잠금 헬퍼)와 B1(구독·Stop류 대기자·drain)
  - `7516e90` 단계 B2(SessionStart 동기 출력·pane 세대 발급·async 발급 대기·계약 진본)
- 실제 상태 폴더 `~/.local/state/agent-orchestrator`에 시험이 만든 흔적은 0이다(`inbox-real-state-untouched` PASS, 조정자 `find -newer` 대조도 0).
- `~/.local/bin` 설치 판은 바꾸지 않았다. 링크는 여전히 마켓플레이스 폴더(origin 판)를 가리키므로 **진행 중인 체인은 옛 동작 그대로**다.

## 2. 바뀐 파일

| 파일 | 내용 |
|---|---|
| `tools/agent-orchestrator/lib/inbox.sh` | `AO_STATE_ROOT`, `_aoi_flock`(fd 7·8·9), `_aoi_recv_lock`, `_aoi_claim` 분리, `_aoi_event`(events.log, 원문 없음), send의 `.times`·`known.list`·send 사건(부가 실패 = 경고+0), `--ack`의 `.ackts` 범위 행·ack 사건, `_aoi_watch_state`·`inbox-watch --state` |
| `tools/agent-orchestrator/lib/inbox-wait.sh`(새, 600줄) | `inbox-subscribe`(등록·해제 장벽·`--list`), `inbox-wait`(교체 fd 7·등록·전달 확인·폴링·통지 확정·TERM 지연·timeout), `--session-start`, `--status`(`inbox-wait 2`), `--drain`·`--undrain`, 정지 지점 |
| `tools/agent-orchestrator/bin/agent-orchestrator` | 분기 `inbox-send\|inbox-watch\|inbox-subscribe\|inbox-wait`, 머리 주석 |
| `tools/agent-orchestrator/test/run-tests.sh` | 묶음 3개 추가(송신 기록·감시 판정 14, 구독·대기자 51, SessionStart·세대 12). `EXPECT=265` |
| `docs/plans/2026-11-08-agent-orchestrator-plan.md` | 계약 진본 §1 머리·§1-1·§1-4 갱신 |

## 3. 검증

| 무엇 | 결과 |
|---|---|
| `bash test/run-tests.sh` (B2 에이전트 3회 + 조정자 2회) | 매번 `PASS 265 / FAIL 0 / 총 265 (기대 265)`, 약 71~73초 |
| `/bin/bash`(3.2.57) 1회 | 같음 (이 맥의 `bash`도 3.2.57) |
| `bash -n` 변경 파일 전부 | 통과 |
| 기존 케이스 | `inbox-regress-all`이 기존 받은편지함 케이스 116개 이름 전부 PASS를 대조 |
| 남은 대기자 프로세스 | 0 (조정자 `pgrep` 확인) |
| shellcheck | 이 맥에 없음 — 미실행 |

**실측 게이트 G0(이 세션, `/tmp/g0-test`, `claude -p`)**: 통과.
- Bash 환경 `CLAUDE_CODE_SESSION_ID` = 훅 입력 `session_id`(같은 UUID).
- Stop 훅 exit 2의 stderr 토큰이 `transcript_path` jsonl에 기록됨(`Stop hook feedback` 본문과 `hookErrors`, 2회).
- 따라서 `sid-` 키를 유지하고 전달 확인은 ①transcript 토큰 ②ack 둘 다 쓴다. §5 G0 대응(키 폐기·ack 축소)은 적용하지 않았다.

## 4. 사고: 인계 커밋 유실과 작업 리포 이동

- 인계 문서가 가리킨 커밋 `d1300d6`(설계·계획, push 안 함)이 착수 시점에 없었다. 원인은 `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins`가 `autoUpdate: true` 마켓플레이스 설치 폴더라서, Claude Code가 10:36에 그 폴더를 새로 clone(reflog `clone: from …`)해 origin 판으로 되돌린 것이다. 미추적 인계 문서도 함께 사라졌다.
- 복원: 설계 rev 4는 이전 세션 file-history 마지막 판(해시가 마지막 리뷰 기록 `b79c218…`과 같음), 계획 rev 5는 file-history 마지막 판(§6-5 포함 확인), 인계 문서는 transcript의 Write·Edit 재생으로 되살렸다.
- 작업 리포: 주인님 지시(2026-11-11)로 **`~/Dev/claude-plugins`**가 진본 작업 리포다. 임시로 만든 `~/Dev/wml-plugins-inbox`(같은 origin)는 지우지 않고 남겨 두었고 더 쓰지 않는다.
- **규칙**: 마켓플레이스 설치 폴더에서는 편집·커밋하지 않는다. push 전 작업이 다음 자동 갱신 때 사라진다.

## 5. 계획과 다르게 정한 점

1. **폴링 중 검증**: 계획은 "10폴링마다 정기 검증"이지만 매 폴링 잠금 없이 recheck하고, 달라졌을 때만 수신 잠금 안에서 다시 확인한다. 시험 표 `inbox-sub-del-running`의 "1폴링 안에 unsubscribed"를 맞추기 위해서다.
2. **TERM 지연 구간 시작점**: "6번 구간에 들어갈 때"를 "수신 잠금을 잡은 뒤"로 정했다. 잠금 대기 중 TERM은 곧바로 0(`term`)이다(`inbox-wait-term-lockwait`).
3. **재통지 횟수**: 첫 통지 0, 재통지마다 +1, 3에서 멈춘다. 첫 통지 + 재통지 3회 = 깨움 4회.
4. **깨움 출력 경로**: 진입 직후 stderr를 fd 5로 옮기고 나머지 진단은 버린다. 0·4일 때 stderr 빈 출력을 지키는 방법이다.
5. **`inbox-wait` 인자 오류 4, 대상 없음은 `why=no-target`**(§2-9 why 목록 밖 값).
6. **SessionStart 통지 예약은 새 줄만**: 이미 pending인 재통지 줄은 동기 출력에 넣지 않고 async·Stop 대기자 경로에 맡긴다("한 줄은 한 경로에서만").
7. **사건 칸 추가**: `wait-notify`에 `hook=`, `sub op=move`에 `from=`. 계획 §2-9 표 반영 여부는 S2에서 정한다.
8. **compact 첫 발급**: pane-gen이 없으면(gen 0) 같은 sid라도 1로 발급한다.
9. **`inbox-real-state-untouched` 판정**: 계획은 "실제 상태 폴더 변경 0"이지만, 진행 중인 체인 두 개가 실제 받은편지함 파일을 계속 써서 그대로는 시험과 무관하게 실패한다. 그래서 **시험이 만들 수 있는 이름**(`events.log`·`known.list`·`recv.flock`·`hooks.off`·`subs/`·`wait/`·`pane-gen/`·`*.times`·`*.ackts`·`*.waiters/`)만 센다.
10. **`--ack` 부가 기록 실패**도 send와 같이 경고 + 0(cursor 갱신 실패만 4). `known.list.flock`은 fd 9(기록 잠금을 놓은 뒤에만 잡음).
11. **정지 지점 재개 표식**: `AO_INBOX_TEST_PAUSE_MARK` 파일에 `<지점> <pid>`, `<MARK>.go[.<pid>]`로 즉시 재개. 여러 지점은 쉼표.
12. **S1을 세 단계(A·B1·B2)로 나눠 구현**했다. 첫 단일 에이전트가 큰 출력으로 API 요청 시간 초과에 걸려 결과 없이 끝났기 때문이다.

## 6. 남은 위험·미해결

- **delta F1(계획 §6-5)**: 결정적 시험 `inbox-async-start-resume-stale-issue` 통과로 구현상 닫았다. 독립 재검토는 받지 않았으므로 **S2 codex 크로스체크 범위에 F1 수정과 S1 코드 전체를 넣는다.**
- **flaky 의심 1건**: B2 작업 중 한 번 `inbox-wait-concurrent-3`이 FAIL(`생존 0, why superseded timeout`)했고 그 뒤 9회 연속 PASS(B2 에이전트 7회 + 조정자 2회). 원인 미확인(UNVERIFIED). fd 7 줄 서기 순서가 비결정적인 케이스다. 다시 나오면 원인 모를 실패 규칙(Opus xhigh)으로 넘긴다.
- **R12 TERM**: bash 3.2는 foreground 자식이 끝날 때까지 trap을 미루므로 sleep·perl 잠금을 `& wait`로 돌린다. 시험 세 개(`term-direct`·`term-lockwait`·`term-mark`)는 통과. 실제 Claude Code가 async 훅 취소 때 TERM을 보내는지는 미실측(S2 ⑩·G7).
- **pid 재사용**: lstart 1초 해상도 안의 재사용은 막지 못한다.
- **`--session-start` 출력 중 신호**: TERM·HUP·INT를 받으면 JSON이 잘린 채 끝날 수 있다. drain은 이 프로세스에 TERM을 보내지 않는다.
- **8KB 상한 극단**: 대상이 아주 많아 `==` 머리만으로 8KB를 넘으면 상한을 넘는 JSON이 나갈 수 있다(가능성 낮음).
- **시험 시간**: 약 21초 → 약 72초. 대기자 케이스가 순차로 돈다.
- G1~G5·G7은 S2 실측 게이트다.
