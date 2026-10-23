---
title: claude-autonomous-chain 설계
status: reviewed   # Sol 2차 SHIP (§19)
revision: 3   # 2차 NOTE 2건 + 리뷰 회차 2단계 반영
date: 2026-10-23
review: required   # Sol 검토 대상 (스킬 규약·전역 지침 변경 포함)
---

# claude-autonomous-chain 설계

Claude Code에서 큰 작업을 milestone → wave → task 단위로 나누고, 마일스톤 하나를 세션 하나가 조정하며, task는 병렬 서브에이전트가 구현하는 자율 진행 스킬이다. 모든 프로젝트에 공통인 절차는 스킬이 갖고, 각 시점에 추가로 할 일은 프로젝트 프로파일이 정한다.

## 1. 목표와 비목표

**목표**
- 조정자(오케스트레이터) 세션의 컨텍스트를 최소화한다. 조정자는 worker의 코드를 읽지 않는다.
- 작업 크기에 맞게 실행 방식을 고른다. 작은 수정은 직접, 독립 단위가 여럿이면 병렬 worker로 맡긴다.
- 마일스톤마다 새 Claude Code 세션을 Orca 탭으로 열어, 질문이 생겨도 멈추지 않고 다음 마일스톤까지 이어간다.
- 계획은 Opus가 세우고 검토는 다른 계열 모델(GPT-6.1 Sol)이 맡는다.
- task/wave/milestone이 끝난 뒤 할 일은 프로젝트마다 다르게 설정할 수 있게 한다.

**비목표**
- 프로젝트별 진행 도구(원장, 회사 시스템 동기화 등)를 이 스킬이 구현하지 않는다. 프로파일은 그런 도구를 가리키기만 한다.
- GPT·GLM으로 구현을 재시도하는 사다리는 두지 않는다. 구현은 Claude만 한다.
- 작은 수정이나 질문에는 이 스킬을 적용하지 않는다.

## 2. 출처

- OpenCode `~/.config/opencode/skills/autonomous-chain` (v2, 2026-10-02): 질문 3분류, 검증 예산, BLOCK 범위 한정, 재개 시 재계획 금지, 실패를 성공으로 추론하지 않기.
- GIRA Kiro 실행 방식 (`~/Dev/gira/.kiro/steering/gira-kiro-execution.md`, `giki-kiro-execution.md`, `.claude/skills/gira-progress`, `docs/plans/gira-kiro-task-brief.md`): 마일스톤 세션과 task 서브에이전트(1단), 조정자는 코드를 읽지 않음(DEC-105), task·웨이브·마감 기록 시점(DEC-100), 보고서 형식, 실패 처리, 멈춤 조건.

## 3. 적용 범위와 실행 단계

| 단계 | 판단 기준 | 실행 |
|---|---|---|
| 직접 | 결과가 뻔하고, 보고서만으로는 판정하기 어려워 어차피 코드를 봐야 하는 작은 수정 | 조정자가 직접 수정하고 영향 시험 실행 |
| 병렬 | 파일 소유권을 나눌 수 있는 독립 단위가 2개 이상 | task를 worker 서브에이전트에 맡김 |
| 체인 | 여러 세션 분량, 설계 판단이 큼, 또는 사용자가 명시 요청 | 계획 세션 → 마일스톤 세션들 |

직접과 병렬 중 무엇을 고를지는 조정자가 판단한다. 파일 수 같은 숫자 기준은 두지 않는다. 판단이 애매하면 가벼운 쪽을 고른다.

## 4. 단위

- **milestone**: 결과가 관찰 가능한 통합 지점이다. 종료 조건(exit criteria)을 갖고, 세션 하나가 처음부터 마감까지 조정한다.
- **wave**: 동시에 진행할 수 있는 task 묶음이다. 웨이브가 끝나면 전체 검증을 1회 하고, 권한이 있으면 push한다.
- **task**: worker 하나가 맡는 구현 단위다. 인수 기준(AC), 소유 파일, 검증 명령, worker 등급, 고위험 여부를 갖는다.

분해는 planner가 한다. 분해 기준은 `references/planning.md`에 둔다.
- task는 worker 한 세션 안에 끝나는 크기로 나눈다. 인수 기준은 관찰 가능한 결과로 쓴다.
- 같은 웨이브의 task끼리는 소유 파일이 겹치지 않게 한다. 공용 등록 파일(카탈로그, 라우트 표, 생성 계약 등)은 계획에 명시하고 조정자가 맡는다.
- 계획은 방향, 비싼 설계 결정, 완료와 검증 판정 기준이 정해지면 반환한다. 함수나 파일 배치를 전부 미리 정하지 않는다.

## 5. 역할과 모델

| 역할 | 에이전트 정의 | 모델·effort | 쓰는 경우 |
|---|---|---|---|
| 계획 | `chain-planner` | Opus 5.5 high | 기본 |
| 계획(깊이) | `chain-planner-deep` | Opus 5.5 xhigh | 스키마, 외부 계약, 동시성, 보안처럼 되돌리기 어려운 설계 |
| 구현 | `chain-worker` | Sonnet 5.5 high | 명세가 있는 task (기본) |
| 구현(판단) | `chain-worker-deep` | Opus 5.5 high | 상태·동시성·권한 경계나 원인 조사가 task의 핵심일 때, `chain-worker` 실패 후 재시도 |
| 검토 | OpenCode `review-sol` (Orca 경유) | GPT-6.1 Sol high | plan 검토, 웨이브 고위험 검토, 마일스톤 최종 검토 |
| 조정 | 메인 세션 | 세션 모델 | 마일스톤 조정, 기록, 통합 검증 |

- 모델과 effort는 에이전트 정의 frontmatter에 고정한다. 호출할 때 덮어쓰지 않는다.
- worker 등급은 planner가 task마다 표시하고 조정자는 그 표시를 따른다. "중요해 보인다"는 이유로 등급을 올리지 않는다.
- worker는 서브에이전트를 다시 만들지 않는다(1단 구조).

## 6. 흐름

```text
[계획 세션]
  목표·권한·기존 상태 확인
  → chain-planner(-deep): milestone → wave → task 분해, task별 등급·고위험 표시
  → review: required 이면 Sol 검토 → BLOCK 수정(같은 planner에 delta만) → SHIP
  → 상태 파일·인계 작성 → Orca 탭으로 M1 세션 기동

[마일스톤 세션]  조정자
  착수: 인계·상태 확인 → [on-milestone-start]
  wave N:
    task 병렬 기동 (상한 parallel-max)
    task 완료 → 보고서 확인 → (권한이 있으면) 조정자가 task 파일만 경로 지정 커밋 → 상태 갱신
             → [on-task-done] → 다음 task
  웨이브 통합: 전체 검증 1회 → 고위험 task 묶음 Sol 검토 → BLOCK 수정
             → [on-wave-integrated] → push (권한이 있을 때)
  마감 (마지막 웨이브 통합과 합침):
       종료 조건 확인 → 전체 검증 → Sol 최종 검토 → BLOCK 수정
       → [on-milestone-close] → wrap-up·인계 → 다음 마일스톤 탭 기동
```

대괄호 단계는 프로파일이 채운다. 마지막 웨이브의 통합은 웨이브 수와 관계없이 마일스톤 마감과 합쳐서, 검증·일지·push·wrap-up을 한 번만 한다(GIRA `milestone-lifecycle.md` §3).

## 7. 조정자 규율

- worker의 코드를 읽지 않고 worker가 통과시킨 시험을 다시 돌리지 않는다. 보고서(변경 파일 목록·실행한 시험), 조정자 커밋 결과, 웨이브 통합 검증으로 확인한다.
- worker 지시서에는 공통 지시서 경로, task 절 위치, 관련 결정, 고위험 여부, 보고서 경로만 넣는다. 계획 전문을 붙이지 않는다.
- 공용 등록 파일과 상태 파일은 조정자만 고친다.
- git index에 쓰는 작업(stage, commit)은 조정자만 한다. 경로 지정 커밋(`git commit -- <경로>`)도 index 전체를 잠그므로, worker 여럿이 동시에 커밋하면 `index.lock` 충돌이 난다(git `builtin/commit.c` partial commit 처리, Sol 1차 B2). 조정자는 task 보고서의 변경 파일 목록으로 `git commit -m … -- <경로들>`을 한 번에 하나씩 실행하고, diff는 읽지 않는다.
- 계획 문서는 해당 task의 인수 기준과 위험 행만 읽는다.

## 8. worker 계약

`references/task-brief.md`에 공통 지시서를 둔다. 프로파일이 `task-brief`를 지정하면 그 파일을 추가로 읽게 한다.

- 맡은 task 하나만 구현하고 영향 시험을 통과시킨다. stage·commit·push는 하지 않는다. 변경한 파일 경로를 보고서에 빠짐없이 적는다(조정자가 이 목록으로 커밋한다).
- index나 작업 트리를 바꾸는 git 명령(add, commit, stash, reset, checkout, restore)은 쓰지 않는다. 같은 트리에서 다른 worker가 일한다. git을 읽을 때는 `GIT_OPTIONAL_LOCKS=0`을 붙여 `status`가 index 갱신 잠금을 잡지 않게 한다.
- 전체 시험은 돌리지 않는다. 바꾼 모듈과 바로 인접한 시험만 돌린다.
- 결정이 필요하면 추천안으로 정하고 보고서에 적는다. 검사를 완화하거나 추가하는 결정은 적용하지 않고 제안만 한다.
- 보고서는 작업 시작 직후 뼈대를 만들고 진행하면서 갱신한다. 60줄 이내로 쓴다.

```text
# <task-id> 보고
- 결과: DONE | PARTIAL | BLOCKED
- 변경 파일: <경로 목록> (N개)
- 인수 기준: AC별 충족/미충족 한 줄씩
- 실행한 시험: `<정확한 명령>` → <결과>
- 결정 제안: 없음 | 추천안과 이유
- 후속·주의: 다음 task가 알아야 할 것, 남긴 미완료
```

worker의 최종 반환값은 보고서 경로와 결과 한 줄뿐이다. 조정자에게 diff를 돌려주지 않는다.

## 9. 검증 예산

| 시점 | 실행 | 하지 않음 |
|---|---|---|
| task 완료 | worker가 영향 시험 | 조정자의 재실행 |
| 웨이브 통합 | `verify.full` 1회. 실패하면 원인 task에 수정 worker 1회, 실패 항목과 영향 시험만 다시 | 통과한 항목 재실행 |
| 마일스톤 마감 | `verify.full` 1회. 같은 snapshot에서 웨이브 통합 결과가 유효하면 재사용 | 증거 시험 처음부터 재실행 |

- 수집 0건, skip, 미실행은 통과가 아니다.
- 원인을 확인하지 않고 같은 시험을 반복하지 않는다. flaky가 의심되면 1회만 재시도한다.
- 마감 중에 진행 도구 결함이 드러나도 그 자리에서 도구를 새로 만들지 않는다. 후속 task로 남긴다. 제품 결함은 고친다.

## 10. Sol 검토

| 시점 | 대상 | 조건 |
|---|---|---|
| 계획 | 전체 계획 | 계획 frontmatter가 `review: required`일 때. 스키마·외부 계약·보안·비가역 변경을 포함하거나 마일스톤이 2개 이상이면 planner가 required로 표시 |
| 웨이브 통합 | 해당 웨이브의 고위험 task 변경 묶음 | 고위험 task가 있을 때 push 전에 |
| 마일스톤 마감 | 마일스톤 전체 변경, 종료 조건, 실행 증거 | 항상 |

- 실행: Orca 탭에서 `opencode run --agent review-sol -m 'ai-gateway-openai/gpt-6.1-sol#high'`을 띄운다. 검토 지시는 요청 파일로 넘긴다. 결과는 파일이 아니라 **터미널 출력**으로 받는다. 출력을 `tee`로 로그에 남기고, 조정자가 `# 판정:`부터 `REVIEW-DONE`까지 잘라 결과 파일로 저장한다. `review-sol` 정의가 읽기 전용이라 결과 파일을 쓰라는 지시를 따르지 않기 때문이다(1차 실측). 상세 절차는 `references/sol-review.md`에 둔다.
- 탭은 Orca에 등록된 worktree에 열고, 명령 안에서 대상 리포로 `cd`한다. 등록되지 않은 리포에서는 `--worktree active`가 `selector_not_found`로 실패한다(1차 실측).
- 끝났는지는 두 신호로 판단한다: 프로세스 종료 표시와 출력의 `REVIEW-DONE`. 종료됐는데 `REVIEW-DONE`이 없으면 검토 실패로 본다.
- 리뷰어가 공개 자료(공식 문서, 업스트림 소스)를 읽기 목적으로 조회하는 것은 허용한다. 조회했다면 이유와 출처를 결과에 적게 한다. 파일 수정과 git 상태 변경은 금지한다.
- BLOCK은 구체적 오동작, 요구 누락, 중대한 회귀, 권한·데이터 오류, 핵심 검증 누락으로 한정한다. 취향이나 문서 형식은 완료를 막지 않는다.
- 재검토: 같은 리뷰 세션을 재개할 수 있으면 재개한다(`opencode run -s <세션>`). 재검토는 기존 BLOCK이 해소됐는지와 그 수정의 영향을 중심으로 본다. 다만 새 근거로 확인한 요청 범위 안의 중대한 결함은 이번 수정이 만든 것이 아니어도 보고하게 한다. 새 근거가 없으면 이미 확인한 영역을 다시 훑지 않는다(Sol 1차 B4).
- **재검토 회차** (2026-10-23 사용자 확정): 게이트 무게로 정한다.

  | 게이트 | 무게 | 회차 | BLOCK 처리 |
  |---|---|---|---|
  | 계획 검토 — 마일스톤 2개 이상인 큰 설계 | 무거움 | 최대 3회 | 아래 무거운 게이트 규칙 |
  | 마일스톤 최종 검토 | 무거움 | 최대 3회 | 아래 무거운 게이트 규칙 |
  | 계획 검토 — 마일스톤 1개 | 가벼움 | 1회 | 수정 후 재검토 없이 진행 |
  | 웨이브 고위험 검토 | 가벼움 | 1회 | 수정 후 재검토 없이 진행 |

  - 무거운 게이트: 재검토 요청에 회차(`round 2/3`)를 적는다. 같은 finding이 두 번 연속 나오면 조정자가 근거를 붙여 1회 반박할 수 있다(회차에 포함). 3회 뒤에도 BLOCK이면 통과로 처리하지 않고 남은 finding을 정리해 §11 멈춤 조건 6으로 보고한다.
  - 가벼운 게이트: 리뷰 1회 → BLOCK 수정 → 영향 시험으로 조정자가 확인 → 재검토 없이 진행한다. 수정한 항목은 마일스톤 최종 검토 범위에 넣는다. 조정자가 동의하지 않는 BLOCK은 반박 근거와 함께 질문 대기열에 남기고 진행한다.
- 리뷰가 진행되는 동안에는 대상 문서·코드를 고치지 않는다.
- 결과 판정: 종료 표시와 `REVIEW-DONE`이 있어도 그것만으로는 통과가 아니다. 출력에서 **마지막** `# 판정:` 블록을 잘라 내고, 그 안의 snapshot(SHA·HEAD)이 요청한 snapshot과 같은지 확인한다. 빈 결과, 잘린 결과, 이전 회차 판정의 인용은 통과로 인정하지 않는다(Sol 2차 N4).
- 검토 증거: 대상 snapshot(HEAD, 대상 파일 SHA), 리뷰 세션 ID, 회차, 판정을 상태 파일에 기록한다. 검토 뒤에 대상이 바뀌면 바뀐 범위만 delta 검토한다.
- Sol 장애: 1회 재시도한다. 그래도 안 되면 게이트별로 처리한다(Sol 1차 B3).
  - 웨이브 고위험 검토: Claude Opus 리뷰 서브에이전트가 보조 검토하고, 그 결과로 push까지 진행할 수 있다. 해당 task는 상태 파일에 `sol-pending`으로 표시하고 마일스톤 최종 Sol 검토 범위에 반드시 넣는다.
  - 계획 검토와 마일스톤 최종 검토: 다른 리뷰어로 대체하지 않는다. 게이트를 `unverified`로 두고 §11 멈춤 조건 5로 보고한다. Opus 보조 검토를 미리 해 두는 것은 허용하지만 통과 근거로 쓰지 않는다.

## 11. 권한, 자율 진행과 질문

**권한 상한** (Sol 1차 B1)
- 실행할 수 있는 작업의 상한은 사용자의 기존 승인과 프로젝트 정책이다. 이 스킬의 기본값, 리뷰 SHIP, 추천안 선택은 승인을 새로 만들지 않는다.
- 계획 세션에서 체인 권한을 한 번에 확인해 상태 파일의 `authority`에 기록한다. 확인 항목은 로컬 커밋, push, 외부 시스템 쓰기, 새 비용(유료 API·인프라)이다. 프로파일에 프로젝트 상시 정책이 이미 있으면 그 값을 기록하고 다시 묻지 않는다.
- `authority`에 없는 작업은 실행하지 않는다. 그 작업만 질문 대기열에 올려 대기시키고, 의존하지 않는 허용 작업은 계속한다.

**결정과 질문**
- 확인할 수 있는 사실은 직접 확인한다.
- 기술·설계 선택(구현 방식, 라이브러리, 파일 구성, 합리적 기본값)은 추천안으로 정해 진행하고 이유를 기록한다. 결과가 크게 갈리는 선택도 권한 안이면 추천안으로 진행하고 질문 대기열에 남긴다.
- 정책 충돌, 새 비용, 권한 밖 작업이 필요한 질문은 추천안을 대기열에 적되 해당 작업은 실행하지 않는다.
- 질문 대기열 `questions.md`(상태 파일 옆) 항목: 질문, 추천안, 실제 택한 선택(또는 "대기"), 되돌리는 비용.
- 마일스톤 보고 때 확인받지 않은 항목만 요약한다.
- 마일스톤 마감 후 사용자 지시가 없으면 다음 마일스톤 세션을 자동으로 연다.

**멈추는 경우** (이때만 멈추고 보고한다)
1. 남은 작업이 모두 권한 대기나 사용자 결정 대기에 걸려 진행할 독립 작업이 없음
2. 같은 task가 재시도와 조정자의 직접 마무리 뒤에도 실패
3. 다음 마일스톤의 목표를 계획과 상태에서 찾을 수 없음
4. 프로파일 `stop-conditions`에 해당
5. 필수 Sol 게이트(계획 검토, 마일스톤 최종 검토)를 재시도 뒤에도 실행할 수 없음
6. 무거운 Sol 게이트(큰 계획 검토, 마일스톤 최종 검토)가 3회 뒤에도 BLOCK

시간 경과, 침묵, timeout만으로는 멈추지 않는다. 리뷰 횟수는 §10 재검토 회차 규칙으로만 다룬다. timeout이나 빈 응답은 성공으로도 실패로도 세지 않고 `unverified`로 기록한다.

## 12. 실패 처리

- worker 실패: 같은 지시로 1회 재시도한다. `chain-worker`가 실패했다면 재시도는 `chain-worker-deep`으로 한다. 그래도 실패하면 조정자가 직접 마무리한다.
- 같은 task에서 지시와 보고 왕복이 2회를 넘으면 그 task만 조정자가 직접 마무리한다. 두 task 연속으로 그러면 질문 대기열에 방식 전환을 제안한다.
- 조정자 커밋 중 `index.lock` 경합(IDE, hook 등 외부 프로세스)은 구현 실패가 아니다. 잠시 기다려 다시 커밋하고 worker 실패 횟수에 넣지 않는다.
- 반복 실패에 새 가설이 없으면 그 task를 `blocked`로 기록하고, 의존하지 않는 task는 계속한다.

## 13. 상태와 인계

- 진행 상태는 파일 하나에 둔다. 프로파일 `state`가 있으면 그 파일(예: 프로젝트 원장)을 쓰고, 없으면 `docs/chain/<chain-id>/state.md`를 쓴다.
- 상태에는 현재 마일스톤·웨이브·task 상태, 중요한 결정, 검증 포인터, 미해결, 질문 대기열 경로를 둔다. 도구 호출 로그는 두지 않는다.
- 마일스톤 인계와 다음 세션 기동은 전역 CLAUDE.md의 「Orca 탭 방식 후속 세션 인계 프로토콜」을 그대로 따른다. 이 스킬에 같은 절차를 다시 쓰지 않는다.
- 새 마일스톤 세션은 상태를 승계하고 다음 미완료 작업부터 진행한다. 계획과 계획 검토를 다시 하지 않는다.
- 맥락이 부족해지면 마일스톤 도중이라도 안전한 지점에서 인계하고 같은 마일스톤을 새 세션이 이어받는다.

## 14. 프로젝트 프로파일

위치: 프로젝트 루트의 `.claude/autonomous-chain.md`. 없으면 기본값으로 동작한다.

```markdown
---
chain-profile: 1
state: <진행 상태 파일 경로>                # 기본 docs/chain/<chain-id>/state.md
verify:
  full: "<전체 검증 명령>"                   # 웨이브·마감 때 1회
  static: "<빠른 사전 점검 명령>"            # 선택
parallel-max: 3                             # 동시 worker 상한
commit: task                                # none | task  (사용자가 둔 상시 정책)
push: wave                                  # none | wave | milestone  (사용자가 둔 상시 정책)
daily-log: wave                             # none | wave | milestone
task-brief: <프로젝트 추가 지시서 경로>      # 선택
---

## on-milestone-start
## on-task-done
## on-wave-integrated
## on-milestone-close
## high-risk
## stop-conditions
```

- frontmatter는 값, 본문 절은 절차다. 절차는 프로젝트 스킬이나 문서를 가리키는 포인터로 써도 된다(예: "`gira-progress` 스킬의 '세부 task 검증 완료'를 수행한다").
- 기본값: `parallel-max: 3`, `daily-log: milestone`. `commit`·`push`에는 스킬 기본값이 없다. 프로파일에 값이 있으면 사용자가 둔 프로젝트 상시 정책으로 보고, 없으면 계획 세션의 권한 확인 결과(§11)를 따른다. 훅 절이 비어 있으면 공통 동작만 한다. `verify.full`이 없으면 프로젝트 설정 파일(package.json, Makefile 등)에서 찾고, 찾은 명령을 상태 파일에 기록한다.
- `high-risk` 절은 고위험 판정 기준을 프로젝트 기준으로 덧붙인다. 기본 기준은 인증·권한, 데이터 원자성, 외부 시스템 쓰기, 스키마·외부 계약이다.
- 병렬 상한은 파일이 겹치지 않는다는 조건에서만 쓴다. 겹치면 순차로 돌린다.

## 15. 플러그인 구성

```text
plugins/claude-autonomous-chain/
├── .claude-plugin/plugin.json
├── README.md
├── skills/autonomous-chain/
│   ├── SKILL.md
│   └── references/
│       ├── planning.md
│       ├── task-brief.md
│       ├── sol-review.md
│       └── profile.md
└── agents/
    ├── chain-planner.md
    ├── chain-planner-deep.md
    ├── chain-worker.md
    └── chain-worker-deep.md
```

`marketplace.json`에 등록한다. 의존: Orca 데스크톱 앱(런타임 ready), OpenCode CLI와 `review-sol` 에이전트 정의.

## 16. 전역 지침 변경 (구현 때 함께 반영)

`~/.claude/CLAUDE.md`:
1. "서브에이전트 위임은 Orca+codex가 예외 없는 기본값" → 자율체인 적용 중에는 이 스킬의 worker 배정(Claude Agent)을 따른다는 예외 추가.
2. "독립 하위작업은 Orca codex 병렬 wave가 기본" → 같은 예외 추가.
3. "비trivial 구현 계획은 Opus 초안 → codex 리뷰 1회" → 자율체인에서는 Opus plan → Sol 검토로 대체.
4. 작업 완료 시 codex 크로스체크 의무 → 자율체인에서는 마일스톤 Sol 최종 검토로 대체.
5. 「Orca 탭 방식 후속 세션 인계 프로토콜」 규칙 4(종료 순서의 Codex 크로스체크)·규칙 8(새 세션의 Codex 크로스체크) → 자율체인 세션에서는 이 스킬의 Sol 게이트로 대체. 남겨 두면 후속 세션에 게이트가 중복된다(Sol 1차 N1).

legacy-lens memory:
6. wrap-up 의무 규칙(`feedback_wrap_up_daily_log_handoff_obligation.md`) → 자율체인에서는 프로파일의 `daily-log` 시점과 마일스톤 인계를 따른다.

변경 전 각 파일을 백업하고 `CLAUDE_HISTORY.md`에 경위를 남긴다.

## 17. 구현 전 확인할 전제

| 전제 | 현재 상태 | 확인 방법 |
|---|---|---|
| 프록시가 Opus 5.5 `effort: xhigh`를 받음 | HTTP 200 확인. 실제 적용 여부는 UNVERIFIED | 구현 시 사용량·응답으로 확인 |
| Claude Code 에이전트 frontmatter가 `effort: xhigh`를 받음 | **요청까지 확인·모델 적용 UNVERIFIED** (2026-10-23, Claude Code 2.1.309, `claude -p --plugin-dir`). 4개 정의가 경고 없이 로드됨. 음성 시험(`effort: bogus-level`)에서 `invalid effort … Valid options: low, medium, high, xhigh, max or an integer` 경고. 서브에이전트 기록(`~/.claude/projects/<probe>/…/subagents/*.jsonl`)의 API 요청에 `output_config.effort`가 worker `high`, planner-deep `xhigh`로 실림(구현 Sol 1차 N1이 지적, debug 로그만 보고 미확인이라 쓴 것을 정정). 프록시·모델이 그 effort를 실제 적용했는지는 미확인 | 첫 실사용에서 사용량·응답으로 확인 |
| 서브에이전트가 보고서 파일을 쓰고 경로만 반환 | 하니스가 서브에이전트마다 "report .md를 쓰지 말고 최종 메시지로 반환, 단 다른 도구의 입력 파일은 괜찮다" 지시를 붙임(구현 Sol 1차 B4). 보고서를 조정자 `Read`·`git commit` 입력으로 명시(`task-brief.md` §6). **실측 확인** (2026-10-23, 임시 git 리포 task 1개를 `chain-worker`로 실행): 보고서 파일 작성(8항목), 반환값은 `<경로> — DONE <요약>` 한 줄, HEAD 불변·staged 0·변경은 `calc.py`와 보고서뿐, 영향 시험 통과 | 병렬 worker 여럿의 무커밋 동작은 첫 실사용에서 확인 |
| 플러그인 에이전트 frontmatter의 `model`이 적용됨 | **확인** (같은 실측). `chain-worker`(model: sonnet) 호출이 `dispatching to firstParty model=claude-sonnet-5-5`, `modelUsage`에 `claude-sonnet-5-5` 별도 집계. `chain-planner-deep`은 `claude-opus-5-5` | — |
| Orca 탭의 `opencode run --agent review-sol`이 사람 입력 없이 끝남 | 1차 검토로 확인: 약 7분 만에 무인 완료, `REVIEW-DONE` 출력. 결과 파일은 쓰지 않음(읽기 전용 정의 우선) → 출력 캡처로 변경(§10) | 2차 검토에서 재확인 |
| 같은 작업 트리에서 worker 여럿이 동시에 경로 지정 커밋 | Sol 1차가 git 소스로 반증: 경로 지정 커밋도 index를 잠금 → 커밋은 조정자만(§7) | 구현 후 소규모 시험 체인에서 worker 무커밋 동작 확인 |
| 요청한 모델·effort가 실제로 적용됨 | 미확인 | 첫 실사용에서 실제 적용된 모델·effort를 상태 파일에 기록. 확인하지 못하면 `unverified`로 두고 통과로 추론하지 않음(Sol 1차 N3) |

## 18. 미결 사항

- 웨이브 고위험 검토를 묶어서 하면 결함 발견이 웨이브 끝까지 늦어진다. 검토 없이 push하지는 않는다. 다만 Sol 장애로 Opus 보조 검토만 거친 변경은 Sol 검토가 마일스톤 최종 검토까지 미뤄진 채 push될 수 있다(Sol 2차 N5). 비용과 속도를 고려해 이 방식을 기본으로 한다.
- 질문 대기열 항목 중 되돌리는 비용이 큰 것이 쌓였을 때 자동으로 멈출지는 정하지 않았다. 첫 실사용 후 판단한다.
- B3 처리는 사용자 표현을 구분해 정한 추천안이다. 고위험 task 리뷰는 "가능하면 Sol"이라 Opus 보조 검토를 허용했고, 마일스톤 최종 검토는 "Sol이 하는 게 좋겠다"여서 대체를 허용하지 않았다. 사용자 확인 대상이다.
- B1 처리로 계획 세션에 권한 확인 질문이 1회 생긴다. 사용자가 계획 세션에 있을 때 한 번만 묻고 이후 세션은 묻지 않는다.

## 19. 검토 기록

| 차수 | 판정 | finding | 반영 위치 |
|---|---|---|---|
| 1차 (Sol, 2026-10-23, 설계 SHA `d240b66e…`) | BLOCK | B1 권한 경계 누락 | §11 권한 상한, §14 commit·push 기본값 제거 |
| | | B2 경로 지정 커밋의 index 잠금 | §7 조정자 단독 커밋, §8 worker 무커밋, §12 잠금 경합 처리 |
| | | B3 Sol 장애 시 필수 게이트 대체 | §10 게이트별 장애 처리, §11 멈춤 조건 5 |
| | | B4 재검토 범위 과소 | §10 재검토 |
| | | N1 인계 프로토콜 Codex 의무 | §16 항목 5 |
| | | N2 마지막 웨이브와 마감 병합 | §6 |
| | | N3 모델·effort 미적용 처리 | §17 |

| 2차 (Sol, 같은 세션 재개, 설계 SHA `4ace35f1…`, round 2/3) | SHIP | B1~B4 해소 확인, 새 BLOCK 없음 | — |
| | | N4 출력 캡처 시 현재 판정 식별 | §10 결과 판정 |
| | | N5 Opus 보조 경로의 push 설명 | §18 |
| 2차 이후 (사용자 결정) | — | 리뷰 회차 2단계(무거운 게이트 3회 / 가벼운 게이트 1회) | §10 재검토 회차, §11 멈춤 조건 6 |

원문: `docs/design/reviews/claude-autonomous-chain-review-1-result.md`, `…-review-2-result.md`

2차 SHIP 이후 반영한 변경(리뷰 회차 2단계, N4, N5)은 리뷰 지적을 받아들이거나 사용자가 결정한 사항이고 새 설계 판단이 아니어서 재검토하지 않는다. 구현 단계의 Sol 검토에서 함께 본다.
