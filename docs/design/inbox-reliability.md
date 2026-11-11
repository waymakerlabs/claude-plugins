---
title: 받은편지함 감시가 끊기지 않게 하는 설계
status: agreed   # 2026-11-11 주인님 합의(추천안 전부). rev 3·4 = 구현 계획 1·2회차 리뷰(codex BLOCK) 반영 정정 — 합의 결정 ①②③ 변경 없음
revision: 4
date: 2026-11-11
review: required   # 훅 설치·스킬 규약 변경 포함
---

# 받은편지함 감시가 끊기지 않게 하는 설계

세션 간 메시지(받은편지함, `agent-orchestrator inbox-*`)가 받는 쪽 감시가 꺼져 있어 몇 시간씩 읽히지 않는 문제를 없앤다. 감시를 켜고 다시 켜는 일을 에이전트의 기억에서 빼고 Claude Code 훅이 맡게 한다.

## 1. 문제와 사고 사례

2026-11-10 하루에 같은 모양의 사고가 두 번 났다. 보낸 쪽은 `inbox-send`가 `unwatched`를 돌려줬지만 아무것도 하지 않았고, 받는 쪽은 감시를 켜지 않은 채 쉬고 있었다. 사람이 물어볼 때까지 아무도 몰랐다.

| # | 받은편지함 | 보낸 시각 | 발견 | 방치 | 받는 쪽이 감시를 안 켠 이유 |
|---|---|---|---|---|---|
| 1 | `pane-w3_p56.log`(부모 `[OC]` 야간 결함) | 20:57 M3 조정자 `blocked` | 22:15 주인님 "반응이 없네" | 1시간 18분 | 부모가 체인을 띄운 11:03은 2.6.0(16:09) 전이라 부모 감시 규칙이 없었다 |
| 2 | `chain-grit-portal/coordinator.log` | 22:20 부모의 push 질문 | 11-11 05:32 확인 | 7시간 12분 이상 | 규칙이 "첫 ③ worker 기동 전에 켠다"인데 이 체인은 ①만 써서 켤 시점이 오지 않았다 |

두 사고 모두 메시지는 파일에 안전하게 남아 있었다. 잃은 것은 시간이다.

## 2. 원인

- **감시의 수명을 에이전트 기억이 쥔다.** 받는 쪽은 Monitor 도구로 `inbox-watch`를 건다. Monitor는 최대 30분에 꺼지고(도구 설명 "Deadlines above 1800000ms are capped"), 세션 재개·인계 때 다시 켜야 한다. 켜는 시점·다시 켜는 일 모두 스킬 문구와 에이전트 기억에 달려 있다.
- **켜야 할 조건이 받는 사람보다 좁다.** 조정자 규칙은 "③ worker를 띄울 때"이지만, 그 받은편지함에는 부모 세션도 보낸다(사고 2).
- **보낸 쪽에 할 일이 없다.** `unwatched`는 "참고값"이라 재시도·사람 알림 같은 다음 행동이 정해져 있지 않다.
- **이력이 없다.** `<log>.watch` 표식은 감시가 끝나면 지워지므로 끊김 빈도를 셀 수 없다.

메시지가 와도 세션이 못 깨는 것은 아니다 — 켜진 Monitor의 이벤트는 쉬는 세션에 새 턴을 연다(grit-portal 조정자 화면에서 M1-DRY-1 진행 감시 이벤트로 깨어난 것을 봤다).

## 3. 확인한 사실

**문서**(code.claude.com/docs/en/hooks, /channels, 2026-11-11 열람)

- 비동기 훅 출력은 "next conversation turn"에 전달된다. 예외: "an `asyncRewake` hook that exits with code 2 wakes Claude immediately even when the session is idle." 출력(stderr, 없으면 stdout)은 시스템 알림으로 들어간다.
- `asyncRewake`에는 `timeout`이 적용된다("Claude Code still enforces `timeout` on a hook you run with `asyncRewake`").
- Stop 훅은 매 턴 끝에 실행되고 턴 종료를 막을 수 있다(`decision: block`). 막기로 이어지는 연속은 8회가 상한이고 입력에 `stop_hook_active`가 온다.
- SessionStart 훅은 `startup|resume|clear|compact|fork`에 실행되고 `additionalContext`를 덧붙인다.
- FileChanged 훅은 파일 변경을 감지하지만 결정 제어가 없고 출력은 다음 턴에 간다 — 쉬는 세션을 깨우지 못한다.
- channels(MCP가 세션에 메시지를 밀어 넣음)는 연구 미리보기, claude.ai/Console 인증 필요, Bedrock 미지원, 허용 목록 플러그인만.

**외부 사례**: Orca(stablyai/orca)도 같은 문제를 겪었다(이슈 #9968, "worker_done only persists … does not wake an idle coordinator", 3일 5회). 해결(#12584)은 쉬는 조정자 pane에 안내 한 줄과 Enter를 자동 입력하는 것이다 — 우리가 2.6.0에서 금지한 입력 주입이다.

**herdr 0.9.5**(이 머신): 사람용 화면 알림 `herdr notification show --sound done|request`, 상태 감지 `herdr agent wait`·이벤트 `pane.agent_status_changed`가 있다. 에이전트 간 메시지·입력 주입 없는 깨우기는 없다.

**실측**(2026-11-11, Claude Code 2.1.322, Kiro 프록시, 시험 세션 `/tmp/rewake-test` 전용 `--settings`): Stop 훅 하나(`asyncRewake: true`, `timeout: 7200`)가 받은편지함 줄 수와 cursor를 1초마다 비교하고, 새 줄이면 내용을 stderr에 쓰고 종료 코드 2.

| 시험 | 결과 (`hook.trace`) |
|---|---|
| 쉬는 중 1줄 | 08:52:32 감지 → 세션이 "Stop hook feedback"으로 받아 처리, cursor=1 |
| 연달아 2줄 | 08:53:01 한 번에 2줄, cursor=3 |
| 작업 중(sleep 25) 1줄 | 08:53:43 감지·처리, 하던 작업도 완료 |
| 대기자 중복 | 턴마다 새 대기자, 앞의 것은 TERM으로 정리 — 항상 1개 |
| 20분 쉰 뒤 1줄 | 09:14:54 20분 산 대기자가 감지·처리 |
| 사람이 그 세션에 직접 입력 | 대화가 정상 진행되고 끝에 대기자 교체(09:18) |
| 입력창 | 주입 0 |

## 4. 선택지 비교

| 안 | 방식 | 에이전트 기억 의존 | 판정 |
|---|---|---|---|
| A. 규칙 보강 | "받은편지함이 생기면 항상 감시"·`unwatched`면 사람 알림 | 그대로 | 같은 사고가 다른 모양으로 남는다 |
| **B. Stop 훅 대기자** | 턴 끝마다 `asyncRewake` 대기자 1개, 새 줄이면 종료 코드 2로 깨움 | 없음 | **채택** — 실측 통과(§3) |
| C. channels | MCP 서버가 세션에 직접 넣음 | 없음 | 보류 — 미리보기·인증 조건(이 환경은 Kiro 프록시) |
| D. 바깥 상주 점검 | launchd가 모든 받은편지함의 미처리 줄 나이를 보고 사람에게 알림 | 없음 | **B와 함께** — 세션은 못 깨우지만 B가 놓친 경우를 사람에게 보인다 |
| (기각) 입력 주입 | Orca 방식 | 없음 | 2.6.0 원칙 위반 — 사용자 입력과 섞인다 |

B가 맞는 이유: 세션이 쉬기 시작하는 대부분의 순간에 훅이 실행되고, 그 지점에 대기자를 붙이면 된다. (rev 3 정정) rev 2는 "쉬기 시작하는 순간은 언제나 Stop"이라고 적었지만 틀렸다. 공식 명세상 사용자 중단 때는 Stop이 실행되지 않고, API 오류 때는 StopFailure가 실행된다. 재개 직후 사람 입력이 없으면 Stop도 없다. 그래서 대기자를 Stop·StopFailure·SessionStart(async)에서 띄우고, 중단 뒤에는 UserPromptSubmit에서 다시 띄운다. 중단 뒤 사람이 아무것도 하지 않는 구간은 훅이 없어 남는다. 그 구간은 D(sweep)가 사람에게 알린다.

## 5. 추천 설계

### 5-1. 구성

```
보내는 쪽 ── inbox-send ──▶ <log>  (지금과 같음)
                              │
받는 세션 ── Stop·StopFailure·SessionStart·UserPromptSubmit 훅 ─▶ inbox-wait (asyncRewake 대기자, 세션당 1개)
                              │ owner·held 확정 → 새 줄 → stderr "#n …" + exit 2 → 세션 깨움
             SessionStart 훅 ─▶ inbox-wait --session-start  (재개·압축·/clear 직후 미처리를 additionalContext로, rev 3)
                              │
launchd ─▶ inbox-sweep (5분마다) ─▶ 미처리 N분 초과 → herdr notification show
```

### 5-2. 구독 — 이 세션이 어떤 받은편지함을 듣는가

- **pane 받은편지함**: 훅 환경의 `HERDR_PANE_ID`로 자동. 등록 없음.
- **그 밖(체인 조정자·worker)**: 구독 파일 `~/.local/state/agent-orchestrator/inbox/subs/<session_id>`에 받은편지함 경로를 한 줄씩. 등록은 `agent-orchestrator inbox-subscribe <대상>`. 체인 스킬은 조정자·worker 기동 절차 안에서 이 명령을 부른다 — 사람·에이전트가 "감시를 켠다"는 단계가 따로 없다.
- 세션 id가 바뀌면(재개) 구독 파일은 `<log>.owner` 갱신과 같은 시점에 옮긴다(지금의 owner·held 규칙을 그대로 쓴다).

### 5-3. 대기자 `inbox-wait`

- 훅 입력(stdin JSON)에서 `session_id`를 읽고, 구독 대상 전부의 `줄 수 > cursor`를 1초마다 본다(`tail -F` 대신 폴링 — 여러 파일·로테이션에 단순).
- 세션당 1개: `<state>/wait/<session_id>.pid`를 `flock`으로 잡고, 앞 대기자는 TERM. 실측과 같은 방식.
- 새 줄이면 지금 `inbox-watch`와 같은 `#n <원문>` 꼴로 stderr에 쓰고(최대 20줄, 넘으면 "나머지 `--pending`") exit 2. 처리 뒤 `--ack`는 지금 규칙 그대로.
- 대기자는 `<log>.watch` 표식을 지금처럼 쓴다 → 보내는 쪽 `watched`가 계속 의미를 갖는다.
- 시간 제한: `timeout` 7200초(실측 확인 중), 대기자 스스로 7000초에 exit 0. 쉬는 동안에는 다시 뜨지 않으므로 그 뒤는 D가 받친다(§8).
- (rev 3 정정, 구현 계획 rev 2 §2) 위 문장 가운데 세 가지를 바꿨다. ① `<log>.watch`는 기존 형식 그대로 Monitor만 쓰고, 대기자는 별도 표식 `<log>.waiters/<sid>`를 쓴다(새 형식은 옛 파서가 `unwatched`로 읽는다). ② 재통지 억제는 "알렸다"가 아니라 "전달이 확인됐다"(다음 훅 입력·ack)에 묶고, 확인 전에는 최대 3회 다시 알린다. ③ 교체(앞 대기자 TERM)와 통지 확정은 같은 짧은 잠금으로 직렬화해 통지가 TERM에 잘리지 않게 한다. 구독 해제는 그 뒤 통지가 없음을 보장하는 장벽이다.
- (rev 4 정정, 구현 계획 rev 3 §1·§2) ④ 구독 목록·세대·대기자 등록·통지 예약·SessionStart 출력은 상태 루트 하나의 수신 잠금 안에서 스냅샷과 재검증으로 처리한다(동기·async 두 경로 모두). ⑤ 같은 pane에 새 세션이 오면 pane 수신 세대가 바뀌어 옛 세션 대기자는 통지하지 못한다. ⑥ 전달 확인은 transcript 증거 또는 ack만 인정한다. ⑦ 송신은 받은편지함 append가 성공하면 확정이고, 부가 기록(도착 시각·목록·사건) 실패는 경고만 낸다.

### 5-4. Stop 훅이 턴 종료를 막는가

막지 않는다. 미처리 줄이 이미 있으면 대기자가 곧바로 exit 2로 깨우므로 같은 효과이고, `decision: block`의 8회 상한·무한 반복 위험을 피한다.

### 5-5. 설치 위치

훅은 auto-chain·review-chain이 함께 쓰는 새 플러그인(가칭 `inbox-hooks`)의 `hooks/hooks.json`에 둔다. 기존 `minimal-statusline`과 같은 구조다. 구독이 없고 pane 받은편지함도 비어 있으면 대기자는 그 받은편지함 파일만 지켜보며 아무 출력이 없다(평소 비용 = 프로세스 1개·1초 폴링).

### 5-6. 바깥 점검 `inbox-sweep`

- launchd 5분 주기. 모든 `*.log`에서 `cursor` 뒤 가장 오래된 줄의 시각을 본다. (rev 3) 줄 머리 `HH:MM:SS`에는 날짜가 없으므로, `inbox-send`가 줄 번호별 도착 시각을 `<log>.times`에 적고 sweep은 그것을 쓴다. 상태 폴더 밖 받은편지함(review-chain `$RC/inbox.log`)은 `known.list` 등록으로 대상에 넣는다. 한 시간 1번 제한은 ack 뒤에도 유지된다.
- 15분 넘게 미처리이면 `herdr notification show "받은편지함 미처리" --body "<받은편지함> <n>줄 · <분>분" --sound request`, 같은 받은편지함은 1시간에 1번만.
- 세션을 깨우지 않는다(입력 주입 금지). 사람에게 보이게 하는 것까지만 한다.

## 6. 계약 변경

| 대상 | 지금 | 바꾼 뒤 |
|---|---|---|
| `inbox-send` | stdout `watched\|unwatched` 참고값 | 그대로. 단 `unwatched`면 보낸 쪽은 자기 보고서·상태 파일에 "미감시 전송" 한 줄을 남긴다(사람·sweep이 찾을 근거) |
| `inbox-watch`(Monitor) | 받는 쪽 필수 | 훅이 없는 도구(Codex·OpenCode 등)의 대체 수단으로만 남긴다 |
| 새 `inbox-subscribe <대상>` / `--unsubscribe` | 없음 | 세션 구독 등록·해제 |
| 새 `inbox-wait`(훅 전용) | 없음 | §5-3 |
| 새 `inbox-sweep`(launchd 전용) | 없음 | §5-6 |
| auto-chain SKILL「세션 간 메시지」 | "Monitor를 켠다·만료되면 다시 건다" | "기동 때 `inbox-subscribe`" 한 줄로 줄인다. 체인을 띄우는 부모는 pane 받은편지함이라 할 일 없음 |
| review-chain `rc-watch.sh`·messages.md | Monitor 안내 | 같은 방식으로 바꾼다 |
| 인계 순서 | 옛 조정자가 Monitor 정지 → ack → 인계 | (rev 4) 옛 조정자: 처리 동결 → 진행 중 처리 종료 → **실제로 처리한 번호까지만** ack(답하지 않은 줄은 ack하지 않음, review-chain `oc-handover.md` 규칙과 같음) → `--unsubscribe` → 인계 문서에 마지막 처리 번호 → 첫 지시. 새 조정자 `inbox-subscribe` → `--pending`부터 처리 |
| `rc-send.sh`·`rc-claim.sh` (rev 4) | `inbox-send` stdout을 버림 | 감시 상태를 받아 `unwatched`면 보고서에 기록. 기존 출력·종료 코드 유지 |

**띄울 때 계약(질문 4)**: 자식 기동 도구가 부모 pane에 훅이 설치돼 있는지(`<pane log>.watch`가 살아 있는지) 확인하고, 없으면 기동은 하되 stderr 경고와 상태 파일 기록을 남긴다. 기동 거부는 하지 않는다(훅 없는 도구에서 체인을 못 쓰게 되므로).

## 7. 측정

- 대기자 시작·깨움·종료와 sweep 경보를 `~/.local/state/agent-orchestrator/inbox/events.log`에 한 줄씩(시각·받은편지함·세션·사건).
- 지표: 줄 도착 → 깨움까지 걸린 시간, 미처리 15분 초과 건수, 대기자가 없던 구간 길이.
- 지금 구조는 이력이 없어서 과거 빈도는 셀 수 없다. 측정은 이 설계와 함께 시작한다.

## 8. 남은 위험·미확인

| 항목 | 상태 | 대응 |
|---|---|---|
| `asyncRewake` `timeout` 7200초가 실제로 지켜지는가 | 시험 중(20분 생존 확인) | 지켜지지 않으면 대기자 자체 종료 시각을 그 값 아래로 |
| 대기자 만료 뒤 쉬는 세션 | 구조상 공백 | D(sweep)가 사람에게 알림. 필요하면 CronCreate로 세션 안에서 주기 턴을 여는 방안 추가 검토 |
| 재개·압축 뒤 SessionStart `--pending` | 미시험 | 2단계 실측 게이트 G1·G3(구현 계획 §5-1) |
| 사용자 중단 뒤 사람이 아무것도 하지 않는 구간 (rev 3) | 훅 이벤트가 없어 구조상 공백 | 다음 입력 때 UserPromptSubmit 대기자가 복구, 그 전까지는 D가 알림 |
| 사람이 입력 중일 때 깨움 | 시험에서 대화와 섞이지 않음(시스템 알림) | 계속 관찰 |
| 다른 훅 제공 도구가 같은 세션에 붙을 때 | 해당 없음(herdr 훅은 SessionStart 상태 보고만) | — |
| channels | 이 환경에서 쓸 수 없을 가능성 큼(UNVERIFIED) | 쓸 수 있게 되면 B를 대신할 후보 |

## 9. 단계별 구현 계획

**합의된 결정(2026-11-11)**: ① sweep 경보 = 미처리 15분 초과, 같은 받은편지함 1시간 1번 ② 훅은 새 플러그인 `inbox-hooks`로 분리 ③ `unwatched`면 보낸 쪽은 상태 파일에 기록만 남긴다(재시도·입력 주입 없음, 알림은 sweep이 맡는다).

세부 구현 계획은 별도 문서로 작성·리뷰한 뒤 새 세션에서 진행한다. 각 단계는 따로 끝나고 되돌릴 수 있다.

1. **도구** — `lib/inbox.sh`에 `inbox-wait`·`inbox-subscribe`·`events.log`. `test/run-tests.sh`에 대기자 1개 유지·깨움·cursor 시험 추가.
2. **훅 플러그인** — `inbox-hooks`(Stop asyncRewake + SessionStart `--pending`). 시험 세션에서 재개·압축 시험.
3. **sweep** — `inbox-sweep` + launchd plist(주인님 go 뒤 설치).
4. **스킬 문구** — auto-chain·review-chain의 Monitor 절차를 `inbox-subscribe`로 교체, 판 올림.
5. **전환 확인** — 진행 중인 체인이 다음 인계 때 새 방식으로 넘어간 것을 `events.log`로 확인.
