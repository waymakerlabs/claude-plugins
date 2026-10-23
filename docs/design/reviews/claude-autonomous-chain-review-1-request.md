# Sol 검토 요청 — claude-autonomous-chain 설계 (1차)

당신은 독립 리뷰어입니다. **읽기 전용**으로 작업합니다. 아래 결과 파일 1개 외에는 어떤 파일도 만들거나 고치지 않고, git 명령으로 상태를 바꾸지 않습니다. 추론과 응답은 한국어로 합니다.

## 검토 대상

- `/Users/peter/Dev/claude-plugins/docs/design/claude-autonomous-chain.md`

## 대조할 원자료 (필요한 부분만 읽기)

- 원형 규약: `/Users/peter/.config/opencode/skills/autonomous-chain/SKILL.md`
- GIRA 실제 운영 방식: `/Users/peter/Dev/gira/.kiro/steering/gira-kiro-execution.md` (1~23행, 94~116행), `/Users/peter/Dev/gira/.kiro/steering/giki-kiro-execution.md` (1~54행)
- GIRA 기록 시점: `/Users/peter/Dev/gira/.claude/skills/gira-progress/SKILL.md` §4, `references/milestone-lifecycle.md` §3
- GIRA worker 지시서: `/Users/peter/Dev/gira/docs/plans/gira-kiro-task-brief.md`
- 전역 지침(변경 대상): `/Users/peter/.claude/CLAUDE.md` 운영 규칙 절, 「Orca 탭 방식 후속 세션 인계 프로토콜」

## 사용자 요구 (설계가 충족해야 할 것)

1. 간단한 구현은 Claude Code 안에서 병렬 서브에이전트로 진행해 조정자 컨텍스트를 최소화한다. 더 작은 수정은 직접 해도 되고, 직접/병렬 선택은 조정자 판단.
2. worker 모델은 Opus 5.5 high와 Sonnet 5.5 high 중 상황에 맞게.
3. plan은 Opus 5.5 high 기본, 복잡하면 xhigh. 복잡한 plan은 Orca를 통해 OpenCode GPT-6.1 Sol high로 검토.
4. 단위는 milestone → wave → task, plan 과정에서 Opus가 나눈다.
5. 마일스톤마다 Orca로 새 Claude Code 세션을 열어 진행. 따로 지시가 없으면 다음 마일스톤으로 계속. 질문은 별도로 정리하고 추천안으로 진행.
6. 마일스톤 최종 검토와 고위험 task 리뷰는 Sol.
7. wrap-up·진행 기록 시점은 GIRA에서 정한 방식(task 가벼운 기록 / 웨이브 통합 / 마일스톤 마감)을 따라 속도를 지킨다.
8. 스킬은 모든 프로젝트에 범용이되, task/wave/milestone 이후 동작은 프로젝트별로 설정 가능.
9. 전역 CLAUDE.md의 충돌 규칙은 변경한다.

## 판정 기준

- BLOCK은 다음에 한정합니다: 위 요구의 누락·모순, 구현하면 실제로 오동작할 구체적 설계 결함(예: 병렬 worker 간 git index 충돌, 자동 진행이 멈춰야 할 상황을 놓침, 검토가 실패했는데 통과로 처리되는 경로), 권한·데이터 경계 오류, 핵심 검증 누락.
- 취향, 문구, 대안 제시, 범위 밖 개선은 BLOCK이 아니라 NOTE로 분류합니다.
- 설계 문서 §17의 "구현 전 확인할 전제"는 미확인으로 이미 표시돼 있으므로, 그 자체를 BLOCK으로 보지 말고 전제가 틀렸을 때 설계가 안전하게 실패하는지를 봅니다.

## 결과 파일 (이 파일만 작성)

`/Users/peter/Dev/claude-plugins/docs/design/reviews/claude-autonomous-chain-review-1-result.md`

형식:

```
# 판정: SHIP | BLOCK

## BLOCK
- [B1] <설계 문서 절 번호> — <결함> / 근거: <파일:행 또는 요구 번호> / 제안: <최소 수정>

## NOTE
- [N1] ...

## 확인한 근거
- 읽은 파일과 범위
```

결과 파일 작성이 끝나면 마지막 줄에 `REVIEW-DONE`을 적고 종료합니다.
