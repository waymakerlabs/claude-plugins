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
| `SessionStart`(`*`) | ① `inbox-hook.sh session-start` ② `inbox-hook.sh wait` | ① 동기 `timeout: 10`(미처리 줄을 additionalContext로) ② 위와 같음 |

판정·잠금·구독·세대 검증은 모두 core(`tools/agent-orchestrator`의 `inbox-wait`)가 한다. 래퍼 `scripts/inbox-hook.sh`는 다음만 한다.

- `AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}`
- AO가 없거나 `"$AO" inbox-wait --status`가 `inbox-wait 2`가 아니면(옛 판) stdin을 버리고 exit 0(조용한 무동작).
- `$AO_STATE_ROOT/inbox/hooks.off`가 있으면 곧바로 exit 0(비용 절감용. 경쟁 판정은 core가 수신 잠금 안에서 한다).
- 그 밖에는 `exec "$AO" inbox-wait [--session-start]`.

구독이 없는 세션에서는 core가 곧바로 0으로 끝나 대기자 프로세스가 남지 않는다.

## 끄기

```bash
agent-orchestrator inbox-wait --drain     # hooks.off 생성 + 대기자 철회
agent-orchestrator inbox-wait --undrain   # 다시 켜기
```

플러그인 자체는 체인 플러그인을 꺼도 따라 꺼지지 않는다(Claude Code 2.1.322 실측, S4 보고서 §2). 체인 플러그인을 끈 머신에서 이것까지 끄려면 `claude plugin disable inbox-hooks@waymakerlabs-claude-plugins`, 체인 플러그인을 지웠다면 `claude plugin prune`이 남은 의존을 지운다.

## 시험

```bash
bash plugins/inbox-hooks/scripts/test/run-tests.sh
```

가짜 `AGENT_ORCHESTRATOR`와 임시 `AO_STATE_ROOT`만 쓴다. 실측 결과는 `docs/plans/2026-11-11-inbox-reliability-S2-report.md`에 있다.
