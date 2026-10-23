---
name: autonomous-chain
description: >-
  여러 세션 분량의 큰 작업, 설계 판단이 큰 구조 변경, 또는 사용자가 "자율체인으로" 진행을 명시 요청할 때 사용.
  milestone → wave → task로 나누고, Opus(chain-planner)가 계획, GPT-6.1 Sol(OpenCode review-sol, Orca 탭)이
  검토, Claude worker 서브에이전트(chain-worker)가 병렬 구현한다. 마일스톤 하나를 세션 하나가 조정하고
  Orca 탭으로 다음 마일스톤 세션을 연다. 프로젝트별 추가 절차는 `.claude/autonomous-chain.md` 프로파일이 정한다.
  작은 수정, 범위가 닫힌 일반 기능, 질문, 규약 검토에는 쓰지 않는다.
---

# autonomous-chain — 마일스톤 단위 자율 진행

> 이 문서를 열었다면 체인을 시작하거나 이어받는 중이다. 절차를 기억으로 재구성하지 말고 아래를 따른다.
> 설계 근거: 이 플러그인 리포의 `docs/design/claude-autonomous-chain.md`.

reference 경로(이 SKILL.md와 같은 디렉터리 기준): `references/planning.md`, `references/task-brief.md`, `references/sol-review.md`, `references/profile.md`. 서브에이전트에게는 **절대 경로**로 넘긴다.

## 1. 적용 범위와 실행 단계

| 단계 | 판단 기준 | 실행 |
|---|---|---|
| 직접 | 결과가 뻔하고, 보고서만으로는 판정하기 어려워 어차피 코드를 봐야 하는 작은 수정 | 조정자가 직접 수정하고 영향 시험 실행 |
| 병렬 | 파일 소유권을 나눌 수 있는 독립 단위가 2개 이상 | task를 worker 서브에이전트에 맡김 |
| 체인 | 여러 세션 분량, 설계 판단이 큼, 또는 사용자가 명시 요청 | 계획 세션 → 마일스톤 세션들 |

- 직접과 병렬 중 무엇을 고를지는 조정자가 판단한다. 파일 수 같은 숫자 기준은 두지 않는다. 애매하면 가벼운 쪽을 고른다.
- 체인 적용 중에는 전역 CLAUDE.md의 "서브에이전트·병렬 wave는 Orca+codex 기본", "Opus 초안 → codex 리뷰", "완료 시 codex 크로스체크", 인계 프로토콜 규칙 4·8의 Codex 크로스체크 대신 **이 스킬의 worker 배정과 Sol 게이트**를 따른다.

## 2. 역할과 모델

| 역할 | 에이전트 | 모델·effort | 쓰는 경우 |
|---|---|---|---|
| 계획 | `chain-planner` | Opus high | 기본 |
| 계획(깊이) | `chain-planner-deep` | Opus xhigh | 스키마, 외부 계약, 동시성, 보안처럼 되돌리기 어려운 설계 |
| 구현 | `chain-worker` | Sonnet high | 명세가 있는 task (기본) |
| 구현(판단) | `chain-worker-deep` | Opus high | 상태·동시성·권한 경계나 원인 조사가 핵심일 때, `chain-worker` 실패 후 재시도 |
| 검토 | OpenCode `review-sol` (Orca 탭) | GPT-6.1 Sol high | 계획 검토, 웨이브 고위험 검토, 마일스톤 최종 검토 |
| 조정 | 메인 세션 | 세션 모델 | 마일스톤 조정, 기록, 통합 검증 |

- 모델과 effort는 에이전트 frontmatter에 고정돼 있다. `Agent` 호출 때 `model`을 넘겨 덮어쓰지 않는다. 호출할 때는 `subagent_type`에 플러그인 접두사가 붙은 이름(`claude-autonomous-chain:chain-worker` 등)을 쓴다.
- worker 등급은 planner가 task마다 표시한 대로 따른다. "중요해 보인다"는 이유로 올리지 않는다.
- worker는 서브에이전트를 다시 만들지 않는다(정의에서 `Agent` 도구가 빠져 있다).
- 실제로 적용된 모델·effort를 확인하지 못하면 상태 파일에 `unverified`로 두고 통과로 추론하지 않는다.

## 3. 계획 세션

1. 목표·기존 상태 확인. 프로파일(`.claude/autonomous-chain.md`)을 읽는다(형식: `references/profile.md`).
2. **권한 확인 1회**: 로컬 커밋, push, 외부 시스템 쓰기, 새 비용(유료 API·인프라). 프로파일에 상시 정책(`commit`·`push`)이 있으면 그 값을 쓰고 다시 묻지 않는다. 결과를 상태 파일 `authority`에 기록한다. 이 스킬의 기본값, 리뷰 SHIP, 추천안 선택은 승인을 새로 만들지 않는다.
3. planner 호출: 설계가 되돌리기 어려우면 `chain-planner-deep`, 아니면 `chain-planner`. 지시서에는 `references/planning.md` 절대 경로, 목표, `authority`, 기존 상태 경로, 프로파일 경로, 계획 문서 경로(기본 `docs/chain/<chain-id>/plan.md`)만 넣는다.
4. 계획 `review: required`면 Sol 계획 검토(§6). BLOCK은 같은 planner에 delta만 넘겨 고친다(`SendMessage`로 이어가거나, 새 호출이면 BLOCK 결과 경로와 고칠 절만 넘긴다).
5. 상태 파일과 질문 대기열을 만들고(§8), 인계 문서를 쓴 뒤 M1 세션을 Orca 탭으로 연다(§9).

## 4. 마일스톤 세션 (조정자)

```text
착수: 인계·상태 확인 → [on-milestone-start]
wave N:
  task 병렬 기동 (상한 parallel-max, 소유 파일 겹치면 순차)
  task 완료 → 보고서 확인 → (authority에 커밋이 있으면) 조정자가 task 파일만 경로 지정 커밋
           → 상태 갱신 → [on-task-done]
웨이브 통합: verify.full 1회 → 고위험 task 묶음 Sol 검토(가벼운 게이트) → BLOCK 수정
           → [on-wave-integrated] → push (authority에 있을 때)
마감 (마지막 웨이브 통합과 합침):
     종료 조건 확인 → verify.full → Sol 최종 검토(무거운 게이트) → BLOCK 수정
     → [on-milestone-close] → wrap-up·인계 → 다음 마일스톤 탭 기동
```

- 대괄호는 프로파일 훅 절이다. 비어 있으면 공통 동작만 한다.
- 마지막 웨이브의 통합은 마일스톤 마감과 합쳐 검증·일지·push·wrap-up을 한 번만 한다.
- 새 마일스톤 세션은 상태를 승계하고 다음 미완료 작업부터 진행한다. **계획과 계획 검토를 다시 하지 않는다.**

### worker 기동

- `Agent`(`subagent_type: claude-autonomous-chain:<worker 등급>`)로 띄운다. 같은 웨이브의 독립 task는 한 메시지에서 여러 개를 동시에 띄운다(`run_in_background: true`도 가능).
- 지시서에는 다음만 넣는다. 계획 전문을 붙이지 않는다.
  - 공통 지시서 `references/task-brief.md` 절대 경로 (+ 프로파일 `task-brief`가 있으면 그 경로)
  - 리포 절대 경로, 계획 문서 경로와 task 절 위치(`M1-W1-T03`)
  - 관련 결정 번호·절, 고위험 여부
  - 보고서 경로: `docs/chain/<chain-id>/reports/<task-id>.md`
- 반환값은 `<보고서 경로> — <결과> <요약>` 한 줄이다. 그 이상이 돌아와도 diff는 읽지 않는다.
- 보고서 파일은 조정자의 `Read`·`git commit -- <경로>` 입력이다. 반환된 경로에 파일이 없으면 worker 실패로 보고 §7 실패 처리를 따른다(최종 메시지 내용으로 커밋 목록을 대신하지 않는다).

## 5. 조정자 규율

- **worker의 코드를 읽지 않고, worker가 통과시킨 시험을 다시 돌리지 않는다.** 보고서(변경 파일 목록·실행한 시험), 조정자 커밋 결과, 웨이브 통합 검증으로 확인한다.
- 계획 문서는 해당 task의 인수 기준과 위험 행만 읽는다.
- 공용 등록 파일(계획의 `조정자 소유` 목록)과 상태 파일·질문 대기열은 조정자만 고친다. worker 보고서의 "조정자 등록 요청"을 반영한다.
- **git index에 쓰는 작업은 조정자만 한다.** 경로 지정 커밋도 index 전체를 잠그므로 worker 여럿이 커밋하면 `index.lock`이 충돌한다. 조정자는 보고서의 변경 파일 목록으로 `git commit -m "<type>(<영역>): <요약> (<task-id>)" -- <경로들>`을 **한 번에 하나씩** 실행한다. 새 파일은 먼저 그 경로만 `git add -- <경로들>`. diff는 읽지 않는다.
- `authority`에 로컬 커밋이 없으면 커밋하지 않는다. 보고서와 상태 갱신만으로 통합 검증까지 진행하고, 커밋할 경로 목록을 상태 파일에 누적한다. 이때 Sol 검토 요청과 검증 기록의 snapshot에는 HEAD와 함께 **작업 트리 식별자**(`references/sol-review.md` §2)를 쓴다.
- 보고서의 변경 파일 목록과 `GIT_OPTIONAL_LOCKS=0 git status --short`의 이름 목록이 다르면(목록 밖 변경) 그 파일은 커밋하지 않고 해당 worker 보고서에 질의하거나 질문 대기열에 남긴다. 내용은 읽지 않는다.

## 6. 검증 예산과 Sol 게이트

### 검증 예산

| 시점 | 실행 | 하지 않음 |
|---|---|---|
| task 완료 | worker가 영향 시험 | 조정자의 재실행 |
| 웨이브 통합 | `verify.static`(있으면) → `verify.full` 1회. 실패하면 원인 task에 수정 worker 1회, 실패 항목과 영향 시험만 다시 | 통과한 항목 재실행 |
| 마일스톤 마감 | `verify.full` 1회. 같은 snapshot에서 웨이브 통합 결과가 유효하면 재사용 | 증거 시험 처음부터 재실행 |

- 수집 0건, skip, 미실행은 통과가 아니다. 총계를 함께 기록한다.
- 원인을 확인하지 않고 같은 시험을 반복하지 않는다. flaky 의심은 1회만 재시도한다.
- 마감 중에 진행 도구 결함이 드러나도 그 자리에서 도구를 새로 만들지 않는다. 후속 task로 남긴다. 제품 결함은 고친다.

### Sol 게이트

실행 절차·요청 형식·결과 추출·장애 처리는 `references/sol-review.md`를 따른다.

| 게이트 | 대상 | 조건 | 무게 | 회차 |
|---|---|---|---|---|
| 계획 | 전체 계획 | `review: required` | 마일스톤 2개 이상이면 무거움, 1개면 가벼움 | 3회 / 1회 |
| 웨이브 통합 | 해당 웨이브의 고위험 task 변경 묶음 | 고위험 task가 있을 때 push 전 | 가벼움 | 1회 |
| 마일스톤 마감 | 마일스톤 전체 변경, 종료 조건, 실행 증거 | 항상 | 무거움 | 3회 |

- **무거운 게이트**: 재검토 요청에 회차(`round 2/3`)를 적는다. 같은 finding이 두 번 연속 나오면 근거를 붙여 1회 반박할 수 있다(회차에 포함). 3회 뒤에도 BLOCK이면 통과로 처리하지 않고 멈춤 조건 6으로 보고한다.
- **가벼운 게이트**: 리뷰 1회 → BLOCK 수정 → 영향 시험으로 조정자가 확인 → 재검토 없이 진행. 수정 항목은 마일스톤 최종 검토 범위에 넣는다. 동의하지 않는 BLOCK은 반박 근거와 함께 질문 대기열에 남기고 진행한다.
- BLOCK은 구체적 오동작, 요구 누락, 중대한 회귀, 권한·데이터 오류, 핵심 검증 누락으로 한정한다. 취향·문서 형식은 완료를 막지 않는다.
- 리뷰가 진행되는 동안 대상 문서·코드를 고치지 않는다.
- 판정은 출력의 **마지막** `# 판정:` 블록과 그 안의 snapshot이 요청 snapshot과 같은지로 한다. `REVIEW-DONE`만으로는 통과가 아니다.
- 검토 증거(snapshot, 리뷰 세션 ID, 회차, 판정)를 상태 파일에 기록한다. 검토 뒤에 대상이 바뀌면 바뀐 범위만 delta 검토한다.
- Sol 장애(1회 재시도 후): 웨이브 고위험 검토는 Opus 보조 검토로 진행하고 `sol-pending`을 남겨 최종 검토에 넣는다. 계획 검토·마일스톤 최종 검토는 대체하지 않고 `unverified` + 멈춤 조건 5.

## 7. 결정, 질문, 멈춤

- 확인할 수 있는 사실은 직접 확인한다.
- 기술·설계 선택은 추천안으로 정해 진행하고 이유를 기록한다. 결과가 크게 갈리는 선택도 권한 안이면 추천안으로 진행하고 질문 대기열에 남긴다.
- 정책 충돌, 새 비용, `authority` 밖 작업은 추천안을 대기열에 적고 **그 작업만** 실행하지 않는다. 의존하지 않는 허용 작업은 계속한다.
- 질문 대기열 `questions.md`(상태 파일 옆) 항목: 질문, 추천안, 실제 택한 선택(또는 "대기"), 되돌리는 비용.
- 마일스톤 보고 때 확인받지 않은 항목만 요약한다. 마감 후 사용자 지시가 없으면 다음 마일스톤 세션을 자동으로 연다.

**멈추는 경우** (이때만 멈추고 보고한다)

1. 남은 작업이 모두 권한 대기나 사용자 결정 대기에 걸려 진행할 독립 작업이 없음
2. 같은 task가 재시도와 조정자의 직접 마무리 뒤에도 실패
3. 다음 마일스톤의 목표를 계획과 상태에서 찾을 수 없음
4. 프로파일 `stop-conditions`에 해당
5. 필수 Sol 게이트(계획 검토, 마일스톤 최종 검토)를 재시도 뒤에도 실행할 수 없음
6. 무거운 Sol 게이트가 3회 뒤에도 BLOCK

시간 경과, 침묵, timeout만으로는 멈추지 않는다. timeout이나 빈 응답은 성공으로도 실패로도 세지 않고 `unverified`로 기록한다.

### 실패 처리

- worker 실패: 1회 재시도. `chain-worker`가 실패했으면 재시도는 `chain-worker-deep`(이전 보고서 경로를 지시서에 넣는다). 그래도 실패하면 조정자가 직접 마무리한다(이때는 코드를 읽어도 된다).
- 같은 task에서 지시·보고 왕복이 2회를 넘으면 그 task만 조정자가 직접 마무리한다. 두 task 연속이면 질문 대기열에 방식 전환을 제안한다.
- 조정자 커밋 중 `index.lock` 경합(IDE, hook 등)은 구현 실패가 아니다. 잠시 기다려 다시 커밋하고 실패 횟수에 넣지 않는다.
- 반복 실패에 새 가설이 없으면 그 task를 `blocked`로 기록하고, 의존하지 않는 task는 계속한다.

## 8. 상태 파일

프로파일 `state`, 없으면 `docs/chain/<chain-id>/state.md`. 도구 호출 로그는 두지 않는다.

```markdown
---
chain-id: <id>
workflow: claude-autonomous-chain-1
plan: docs/chain/<id>/plan.md
current: M<n> / W<n>
authority: { local-commit: yes|no, push: none|wave|milestone, external-write: …, new-cost: … }
verify-full: "<명령>"
questions: docs/chain/<id>/questions.md
---

## 진행
| task | worker | 결과 | 보고서 | 커밋 | 비고(sol-pending 등) |

## 검증
| 시점 | snapshot(HEAD) | 명령 | 결과(수집·skip) |

## Sol 검토
| 게이트 | 회차 | snapshot | 세션 ID | 판정 | 결과 파일 |

## 결정
## 미해결
## 모델 적용 확인        # 실제 적용 모델·effort 또는 unverified
```

## 9. 인계

- 마일스톤 인계와 다음 세션 기동은 전역 CLAUDE.md의 「Orca 탭 방식 후속 세션 인계 프로토콜」을 그대로 따른다(이 스킬에 다시 쓰지 않는다). 단 그 프로토콜 규칙 4·8의 Codex 크로스체크는 이 스킬의 Sol 게이트로 대체한다.
- 인계 프롬프트 예: `<상태 파일 절대 경로>와 <인계 문서 절대 경로>를 읽고 claude-autonomous-chain 스킬로 M<n+1>을 진행해.`
- 일지는 프로파일 `daily-log` 시점에 쓴다. 매 마일스톤 daily-log+handoff를 이중으로 만들지 않고 상태 파일을 재사용하며, 인계 문서에는 상태 파일에 없는 실행 맥락만 보탠다.
- 맥락이 부족해지면 마일스톤 도중이라도 안전한 지점에서 인계하고 같은 마일스톤을 새 세션이 이어받는다. 진행 중인 worker·리뷰가 있으면 결과 회수 책임을 인계 문서에 적는다.
