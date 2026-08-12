# orca-codex-delegate

Claude Code가 코디네이터, Codex가 실행자인 [Orca](https://www.onorca.dev) orchestration 위임 절차를 담은 skill입니다. Claude Code 자체가 아니라 [Orca](https://www.onorca.dev) 데스크톱 앱과 그 orchestration 기능이 설치되어 있어야 동작합니다.

## 스킬

| 스킬 | 설명 |
|------|------|
| `orca-codex-delegate` | Run/Task/dispatch 명령 순서, worker 프로필(`orca-review` 읽기전용 / `orca-implement` 쓰기), 대기·수신 규율, 실측 함정, finding 보고 형식을 담은 절차 문서. 자동 매칭 트리거: "codex한테 시켜/맡겨", "codex로 크로스체크해줘", "codex로 구현위임" 같은 요청, 또는 사용자 CLAUDE.md가 정의한 Agent 도구 호출 직전 자기점검/고위험 plan·완료 게이트가 발동했을 때. |

## 다루는 것

- **크로스체크 프로토콜(읽기전용)** — Claude가 만든 것을 codex가 외부 시각으로 검토. `orca-review` 프로필.
- **구현위임 프로토콜(쓰기)** — codex가 구현한 것을 Claude가 직접 검토(codex 자체 재검토 요구 안 함). `orca-implement` 프로필.
- **공통 실측 함정 6건** — `--worktree active` 오조준, `check --wait` replay·다중 JSON 파싱, `run-create` 재호출 바인딩 이동, `worker-read`/`worker-release`의 `dispatch_not_found` 등.
- 사용자·리포별 절대경로·인증정보·고정 handle/worktree ID는 포함하지 않습니다 — 실행 시 Orca가 반환한 값을 그대로 씁니다.

## 다루지 않는 것

- Orca CLI 자체의 기본 사용법 — [`orca-cli`](https://github.com/stablyai/orca)/`orchestration` skill을 먼저 참조하세요. 이 skill은 그 위에 있는 Codex 특화 정책 레이어입니다.
- 다른 Claude Code 세션으로의 full handoff(다른 패턴).
- "고위험 변경" 여부 판단 기준 — 그건 각자 프로젝트/CLAUDE.md가 정의합니다(여기서 중복 정의하면 드리프트가 생깁니다).

## 설치

```bash
/plugin install orca-codex-delegate@waymakerlabs-claude-plugins
```

## 요구사항

- [Orca](https://www.onorca.dev) 데스크톱 앱 실행 중 + orchestration 기능 활성화 (`orca status --json`으로 확인)
- Codex CLI 설치·인증, 그리고 읽기전용/쓰기 프로필(`orca-review`/`orca-implement`)이 있으면 더 안전합니다(skill 본문 §2 참조).
