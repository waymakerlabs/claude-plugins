# auto-chain

큰 작업을 **milestone → wave → task**로 나누고, 마일스톤 하나를 Claude Code 세션 하나가 조정하며, task는 병렬 서브에이전트가 구현하는 자율 진행 skill입니다. 계획은 Opus, 검토는 다른 계열 모델(GPT-6.1 Sol, OpenCode `review-sol`)이 맡습니다. 프로젝트마다 다른 절차는 프로파일 파일로 정합니다.

## 구성

| 구성 | 설명 |
|------|------|
| skill `autonomous-chain` | 계획 세션·마일스톤 세션 절차, 조정자 규율, 검증 예산, Sol 게이트, 멈춤 조건 |
| agent `chain-planner` | 계획(Opus, high) |
| agent `chain-planner-deep` | 되돌리기 어려운 설계 계획(Opus, xhigh) |
| agent `chain-worker` | 명세가 있는 task 구현(Sonnet, high) |
| agent `chain-worker-deep` | 상태·동시성·권한 경계 task, 실패 재시도(Opus, high) |
| agent `chain-worker-xhigh` | deep으로도 실패한 task·결함 계열 재수정(Opus, xhigh). 처음부터 배정하지 않음 |
| `references/` | 계획 지침, worker 공통 지시서, Sol 검토 절차, 프로파일 형식 |

## 핵심 규칙

- 조정자는 worker의 코드를 읽지 않습니다. 보고서와 웨이브 통합 검증으로 확인합니다.
- worker는 stage·commit·push를 하지 않습니다. 커밋은 조정자가 보고서의 변경 파일 목록으로 하나씩 합니다(index 잠금 충돌 방지).
- 전체 검증은 웨이브 통합과 마일스톤 마감 때 1회씩만 합니다.
- 질문이 생겨도 멈추지 않고 추천안으로 진행하며, 권한 밖 작업만 대기열에 올립니다.
- 이 skill의 기본값이나 리뷰 SHIP은 push·외부 쓰기 승인을 만들지 않습니다.
- (1.6.0) 마일스톤은 기본 **구현 모드**: 주 흐름·회귀·데이터/권한/보안·크래시·비가역 대상·사용자 시각검증 지적만 BLOCK이고, 나머지 경계 조건은 백로그(`backlog.md`)에 쌓습니다. 전수 점검은 하지 않습니다. 사용자가 "출시 검토"·"전체 테스트"를 요청한 시점에만 `HARDEN` 마일스톤을 넣어 백로그·계열을 한 번에 정리합니다. 외부 '완료' 반영은 구현 완료 시점입니다.
- (1.6.1) Sol 무응답 대비: 재검토(delta)는 이전 세션을 재개하지 않고 새 세션으로 엽니다(맥락 누적 방지). 증거 이미지는 첨부 대신 경로만. 로그가 15분 정체하면 `SOL-STALL`로 보고, 같은 요청을 다시 보내지 않고 맥락을 줄여(r1은 영역 2개로 나눠 동시에) 1회 재시도합니다.
- (1.6.2) 실패 사다리를 등급 상향에서 시각 전환으로: 원인 모를 실패 1번 → Sol 원인 조사(읽기 전용, `references/sol-review.md` §7) → Sol 안대로 고쳤는데도 실패 → `chain-worker-xhigh`(반박된 가설 전부 첨부) → 그래도 실패 → task blocked·질문 대기열. 오타·flaky·환경 문제와 Sol 안 구현 실수는 세지 않습니다.
- (1.6.3) 수정 작업은 처음부터 `chain-worker-xhigh`: 원인 위치가 특정된 간단한 수정은 조정자 국소 경로, 그 밖의 BLOCK·회귀·원인 조사 수정은 Sonnet·deep 단계 없이 xhigh로 시작합니다. 신규 구현 task 등급은 그대로(planner 표시). 실패 사다리 = xhigh → Sol 원인 조사 → 새 xhigh(반박된 가설 첨부) → blocked.
- (1.2.0) 진행 보드와 한 줄 중간 보고를 정해진 시점에 냅니다. worker 보고서의 `- 진행:` 줄과 Sol 로그는 `Monitor`로 감시합니다.
- (1.2.0) BLOCK을 결함 계열 원장(`defect-classes.md`)에 쌓습니다. 같은 계열이 2회 나오면 위치별 수정을 멈추고 전수 점검 task로 바꿉니다.
- (1.3.0) 원인 위치가 특정된 BLOCK은 worker 없이 조정자가 직접 고치고(재현 회귀 + 영향 시험만), 재검토는 delta 검토(직전 BLOCK 해소 + 그 diff의 직접 회귀)로 받습니다. delta 밖 새 발견은 NOTE → 후속 task.
- (1.3.0) worker BLOCK 수정 지시서는 수정·재현 시험·영향 시험만 담습니다. 전수 점검·하니스 확장은 별도 task.
- (1.3.1) 국소 수정은 "코드를 읽지 않는다" 규칙의 예외로 명시. 같은 계열 2회째도 원인이 특정되면 국소 수정 먼저, 전수 점검은 마감을 막지 않는 후속 task. Sol 로그는 검토 중 `/tmp`에. 진행 보드는 웨이브·게이트·멈춤 때만, task 완료는 한 줄.
- (1.2.0) 무거운 게이트가 3회 뒤에도 BLOCK이면 계획 때 승인받은 `escalation` 사다리를 따라 진행합니다. 멈출 때는 푸시 알림을 보냅니다.
- (1.4.0) 기본 사다리 `[extra-rounds:1, carry-reversible, stop]`. 추천 수정 + delta 1회 뒤에도 BLOCK이면, 되돌릴 수 있는 제품 결함은 SHIP 없이 `carried`로 다음 웨이브에 넘기고 **조건부 마감** 절로 보고합니다. 되돌리기 어려운 대상이 걸린 BLOCK만 멈춥니다.
- (1.5.0) 파괴 검토 동시 실행. 같은 계열 2회째 BLOCK, 직전 수정이 만든 회귀, 공유 선택자·상태를 바꾼 수정이면 BLOCK 수정 커밋 뒤 Sol delta와 `chain-breaker`(Opus, 리포 쓰기 금지)를 같은 snapshot으로 동시에 띄우고, 둘의 결과를 한 번에 고칩니다. breaker 결함은 회차를 쓰지 않고, 판정은 여전히 Sol만 합니다.

## 프로젝트 프로파일

프로젝트 루트 `.claude/autonomous-chain.md`에 검증 명령, 병렬 상한, 커밋·push 정책, 시점별 추가 절차(`on-task-done` 등)를 둡니다. 없으면 기본값으로 동작합니다. 형식은 `skills/autonomous-chain/references/profile.md`를 보세요.

## 설치

```bash
/plugin install auto-chain@waymakerlabs-claude-plugins
```

1.0.x(`claude-autonomous-chain`)에서 옮길 때는 옛 플러그인을 지우고(`/plugin uninstall claude-autonomous-chain@waymakerlabs-claude-plugins`) 새 이름으로 설치합니다. 호출 이름이 `auto-chain:autonomous-chain`, 에이전트 접두사가 `auto-chain:`으로 바뀝니다. 이름을 바꾼 이유는 `claude-`로 시작하는 이름을 `claude plugin validate`가 예약어로 거부하기 때문입니다.

## 요구사항

- [Orca](https://www.onorca.dev) 데스크톱 앱(런타임 ready) — Sol 검토 탭과 마일스톤 세션 인계에 사용
- OpenCode CLI + `review-sol` 에이전트 정의(`ai-gateway-openai/gpt-6.1-sol#high`)
- 전역 CLAUDE.md의 「Orca 탭 방식 후속 세션 인계 프로토콜」(마일스톤 인계 절차)

## 설계

`docs/design/claude-autonomous-chain.md` (Sol 검토 기록: `docs/design/reviews/`)
