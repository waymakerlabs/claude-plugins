# 프로젝트 프로파일 (`.claude/autonomous-chain.md`)

프로젝트 루트의 `.claude/autonomous-chain.md`. 없으면 기본값으로 동작한다. frontmatter는 값, 본문 절은 절차다.

## 형식

```markdown
---
chain-profile: 1
state: docs/chain/<chain-id>/state.md      # 진행 상태 파일. 프로젝트 원장을 써도 된다
verify:
  full: "<전체 검증 명령>"                  # 웨이브 통합·마감 때 1회
  static: "<빠른 사전 점검 명령>"           # 선택. 전체 검증 전에 먼저
parallel-max: 3                            # 동시 worker 상한
commit: task                               # none | task   (사용자가 둔 상시 정책)
push: wave                                 # none | wave | milestone   (사용자가 둔 상시 정책)
daily-log: milestone                       # none | wave | milestone
task-brief: docs/plans/<추가 지시서>.md     # 선택. 공통 지시서에 덧붙일 프로젝트 지시서
defect-classes: docs/chain/defect-classes.md # 선택. 체인끼리 공유할 결함 계열 원장
escalation: [extra-rounds:2, worker:chain-worker-xhigh, stop]   # 선택. 무거운 게이트 상한 초과 사다리(사용자가 둔 상시 정책)
---

## on-milestone-start
## on-task-done
## on-wave-integrated
## on-milestone-close
## high-risk
## stop-conditions
```

## 값

| 키 | 기본값 | 의미 |
|---|---|---|
| `state` | `docs/chain/<chain-id>/state.md` | 진행 상태 파일 하나. 질문 대기열 `questions.md`는 그 옆에 둔다 |
| `verify.full` | 없음 → 프로젝트 설정(package.json scripts, Makefile, pyproject 등)에서 찾고 상태 파일에 기록 | 못 찾으면 `unverified`로 두고 질문 대기열에 올린다 |
| `verify.static` | 없음 | 있으면 `verify.full` 전에 먼저 돌려 고칠 것을 찾는다 |
| `parallel-max` | 3 | 소유 파일이 겹치지 않는다는 조건에서만 쓴다. 겹치면 순차 |
| `commit` | **기본값 없음** | 있으면 사용자가 둔 프로젝트 상시 정책. 없으면 계획 세션의 `authority.local-commit` |
| `push` | **기본값 없음** | 있으면 상시 정책. 없으면 `authority.push` |
| `daily-log` | `milestone` | 일지 갱신 시점. `none`이면 마감 인계만 |
| `task-brief` | 없음 | worker 지시서에 경로를 추가한다 |
| `defect-classes` | `docs/chain/<chain-id>/defect-classes.md` | 결함 계열 원장(SKILL.md §6-1). 프로젝트 공용 경로로 두면 다음 체인이 이전 체인의 계열을 이어받는다 |
| `escalation` | **기본값 없음**(계획 세션에서 묻고, 답이 없으면 `[stop]`) | 무거운 게이트 3회 뒤 BLOCK일 때 자동으로 밟을 칸 목록(SKILL.md §6). 마지막 칸은 `stop` |

`commit`·`push`·`escalation`에 스킬 기본값을 두지 않는 이유: 이 스킬의 기본값이 사용자 승인을 새로 만들면 안 되기 때문이다. 프로파일 값은 사용자가 그 프로젝트에 미리 둔 정책으로 보고, 계획 세션에서 다시 묻지 않는다.

## 훅 절

- 해당 시점에 공통 동작 **다음에** 추가로 할 일을 쓴다. 비어 있으면 공통 동작만 한다.
- 프로젝트 스킬이나 문서를 가리키는 포인터로 써도 된다. 예: "`gira-progress` 스킬의 '세부 task 검증 완료'를 수행한다."
- 훅 절차가 `authority`에 없는 작업(외부 쓰기 등)을 요구하면 실행하지 않고 질문 대기열에 올린다.

| 절 | 시점 |
|---|---|
| `on-milestone-start` | 마일스톤 세션 착수, 인계·상태 확인 직후 |
| `on-task-done` | task 보고서 확인·조정자 커밋·상태 갱신 직후 |
| `on-wave-integrated` | 웨이브 통합 검증·고위험 검토 통과 후, push 전 |
| `on-milestone-close` | 마감 검증·최종 Sol 검토 통과 후, wrap-up·인계 전 |
| `high-risk` | 고위험 판정 기준 추가(기본: 인증·권한, 데이터 원자성, 외부 시스템 쓰기, 스키마·외부 계약) |
| `stop-conditions` | 공통 멈춤 조건에 더할 프로젝트 조건 |

## 예시 (최소)

```markdown
---
chain-profile: 1
verify:
  full: "npm test && npm run typecheck"
commit: task
push: none
---

## high-risk
- `migrations/**` 변경
```
