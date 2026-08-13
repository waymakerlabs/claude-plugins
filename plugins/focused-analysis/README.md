# focused-analysis

어려운 진단성 질문("이게 정상인가 결함인가", "근본 원인이 뭔가")에 대해 **Opus 서브에이전트**와
**Orca+codex 오케스트레이션**을 동시에 독립 실행해 교차검증한 뒤, Claude가 두 결과를 종합해 최종
판단을 내리는 skill입니다. [`orca-codex-delegate`](https://github.com/waymakerlabs/claude-plugins)
플러그인이 함께 설치되어 있어야 동작합니다(Orca/codex 실행 메커니즘은 그 skill을 그대로 따릅니다).

## 스킬

| 스킬 | 설명 |
|------|------|
| `focused-analysis` | Opus 서브에이전트 트랙 + Orca/codex 트랙을 동시에 실행하고, 둘 다 완료된 뒤에만(barrier) 종합 판단을 내리는 절차. 자동 매칭 트리거: "집중 분석해줘", "상세 분석해줘" 같은 강조된 분석 요청. |

## 다루는 것

- **이중 트랙 동시 실행** — `Agent` 도구(model: opus)와 Orca Run/Task/dispatch(codex, `orca-review`
  프로필 + 명시적 모델·effort override)를 같은 메시지에서 병렬로 시작.
- **barrier 종합** — 하나만 도착해도 종합하지 않고 둘 다 기다린 뒤, 일치/불일치 지점을 명시적으로
  구분해 보고.
- 강조 없는 일반 분석 요청과의 경계 — 매번 쓰면 비용이 2배이므로, 트리거 문구가 명확할 때만 발동.

## 다루지 않는 것

- Orca/codex 실행 메커니즘 자체(Run/Task/dispatch 명령, worktree 선택, 실측 함정) — 이건
  [`orca-codex-delegate`](https://github.com/waymakerlabs/claude-plugins)를 참조합니다.
- 3개 이상 트랙으로 확장하는 judge-panel류 패턴 — 그건 `Workflow` 도구(사용자의 명시적 다중 에이전트
  오케스트레이션 요청이 있을 때)의 영역입니다.

## 설치

```bash
/plugin install focused-analysis@waymakerlabs-claude-plugins
/plugin install orca-codex-delegate@waymakerlabs-claude-plugins
```

## 요구사항

- [Orca](https://www.onorca.dev) 데스크톱 앱 실행 중 + orchestration 기능 활성화
- Codex CLI 설치·인증 + `orca-review` 프로필(읽기전용 정책, `orca-codex-delegate` skill 참조)
