# inbox-hooks

> review-chain·auto-chain이 쓰는 받은편지함 훅(단독 사용 안 함). Inbox hooks used by review-chain and auto-chain — not for standalone use.

`defaultEnabled: false`다. 직접 설치·켜지 않는다. review-chain·auto-chain의 `dependencies`로만 켜진다(계획 2026-11-11 S4).

## 하는 일

쉬고 있는 Claude Code 세션이 구독한 agent-orchestrator 받은편지함에 새 줄이 오면 세션을 깨운다. 입력창 주입은 어떤 형태로도 하지 않는다. 깨우기는 Claude Code 훅의 `asyncRewake` 대기자(exit 2 + stderr)만 쓴다.

| 이벤트 | 훅 | 필드 |
|---|---|---|
| `Stop` | `inbox-hook.sh wait` | `asyncRewake: true`, `timeout: 7200` |
| `StopFailure` | `inbox-hook.sh wait` | 같음 |
| `UserPromptSubmit` | `inbox-hook.sh wait` | 같음 |
| `SessionStart`(`*`) | `inbox-hook.sh wait` | 같음 |

래퍼 `scripts/inbox-hook.sh`는 다음만 한다.

- `AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}`
- AO가 없거나 `"$AO" inbox-wait --status`가 `inbox-wait 2`가 아니면 stdin을 버리고 exit 0(조용한 무동작). 알 수 없는 모드(옛 `session-start` 포함)도 같다.
- `$AO_STATE_ROOT/inbox/hooks.off`가 있으면 곧바로 exit 0.
- 그 밖에는 `exec "$AO" inbox-wait`.

core(`tools/agent-orchestrator`의 `inbox-wait`) 동작 요약(계획 2026-11-11-inbox-simplify §3·§10):

- 키는 `pane-<HERDR_PANE_ID>`(herdr 안) 또는 `sid-<session_id>`. 대상은 `subs/<키>`의 경로들과, pane 키면 그 pane 받은편지함이다. 대상이 없으면 곧바로 0으로 끝나 대기자 프로세스가 남지 않는다.
- 같은 키의 앞 대기자는 TERM으로 끝낸다(`wait/<키>.pid`, pid·시작 시각으로 판정).
- 대상마다 `max(cursor, notified)`보다 줄이 늘면 stderr로 깨움을 내고 exit 2. SessionStart 대기자는 `cursor`를 기준으로 삼아, `/clear`·`/compact`·재개 직후 안 읽은 줄을 곧바로 알린다.
- 깨움 목록은 항상 `cursor+1`부터 보인다. 이미 처리한 `#n`이 다시 오면 `--ack`만 한다.
- 7000초 동안 새 줄이 없으면 한 줄 안내와 함께 exit 2로 끝나 다음 Stop에서 대기자가 다시 뜬다.

## 끄기

```bash
agent-orchestrator inbox-wait --drain     # hooks.off 생성 + 대기자 TERM(보낸 수 출력)
agent-orchestrator inbox-wait --undrain   # 다시 켜기
```

플러그인 자체는 체인 플러그인을 꺼도 따라 꺼지지 않는다(Claude Code 2.1.322 실측, S4 보고서 §2). 체인 플러그인을 끈 머신에서 이것까지 끄려면 `claude plugin disable inbox-hooks@waymakerlabs-claude-plugins`, 체인 플러그인을 지웠다면 `claude plugin prune`이 남은 의존을 지운다.

## 시험

```bash
bash plugins/inbox-hooks/scripts/test/run-tests.sh
```

가짜 `AGENT_ORCHESTRATOR`와 임시 `AO_STATE_ROOT`만 쓴다. 실측 결과는 `docs/plans/2026-11-11-inbox-reliability-S2-report.md`에 있다.
