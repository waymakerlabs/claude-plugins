# 계획 지침 (chain-planner / chain-planner-deep)

계획 세션의 조정자가 planner에게 이 파일의 절대 경로를 넘긴다. planner는 끝까지 읽고 따른다. `chain-planner`와 `chain-planner-deep` 모두 이 파일이 공통 계약이다(에이전트 정의끼리는 서로 상속되지 않는다).

## 0. 하지 말 것 (공통)

- 제품 코드·설정 수정. 쓰기는 지시서가 정한 계획 문서 경로(와 지시서가 명시한 보조 문서)에만 한다.
- index·작업 트리를 바꾸는 git 명령(`add`, `commit`, `stash`, `reset`, `checkout`, `restore`, `clean`, `push` 등). git을 읽을 때는 `GIT_OPTIONAL_LOCKS=0`을 붙인다. index 쓰기는 조정자만 한다.
- 서브에이전트 생성, 외부 시스템 쓰기, 새 비용 발생.
- probe가 필요하면 `/tmp` 아래 임시 사본이나 읽기 전용 명령으로 한다. 리포를 바꾸는 probe는 첫 웨이브 task로 넘긴다.

## 1. 입력

지시서에 다음이 있다. 없는 항목은 계획 문서의 `blocking`이 아니라 `가정` 절에 추천안으로 적는다.

- 목표와 사용자 요구(원문 인용 또는 경로)
- `authority`: 로컬 커밋, push, 외부 시스템 쓰기, 새 비용 각각의 허용 여부
- 기존 상태(관련 문서·이전 계획·진행 원장 경로)
- 프로젝트 프로파일 경로(`.claude/autonomous-chain.md`, 없으면 "없음")
- 결함 계열 원장 경로(이전 체인의 것이 있으면). 있으면 끝까지 읽는다
- 계획 문서를 쓸 경로(기본 `docs/chain/<chain-id>/plan.md`)

## 2. 분해 기준

- **milestone**: 결과가 관찰 가능한 통합 지점. 종료 조건(exit criteria)을 관찰 가능한 문장으로 쓴다. 세션 하나가 처음부터 마감까지 조정할 수 있는 크기로 나눈다.
- **wave**: 동시에 진행할 수 있는 task 묶음. 같은 웨이브의 task끼리는 **소유 파일이 겹치지 않게** 한다. 겹치면 다른 웨이브로 나눈다.
- **task**: worker 한 세션 안에 끝나는 크기. 인수 기준(AC)은 관찰 가능한 결과로 쓴다("함수 X를 만든다"가 아니라 "명령 Y가 Z를 출력한다").
- 공용 등록 파일(카탈로그, 라우트 표, 생성 계약, 버전 파일, marketplace 목록 등)은 task 소유에서 빼고 `조정자 소유` 목록에 적는다. 해당 task의 AC에는 "조정자가 등록할 항목"을 보고서에 적는 것을 넣는다.
- 첫 웨이브에는 위험이 큰 기술 전제를 확인하는 작은 probe task를 우선 둔다.

## 3. task별 표시

| 항목 | 값 |
|---|---|
| `id` | `M<n>-W<n>-T<nn>` |
| `worker` | `chain-worker`(기본) / `chain-worker-deep`(상태·동시성·권한 경계나 원인 조사가 task의 핵심일 때만) |
| `high-risk` | `yes` / `no`. 기본 기준: 인증·권한, 데이터 원자성, 외부 시스템 쓰기, 스키마·외부 계약. 프로파일 `high-risk` 절이 있으면 덧붙인다 |
| `owns` | 이 task만 수정하는 파일·디렉터리 |
| `ac` | 인수 기준 목록 |
| `verify` | worker가 돌릴 영향 시험 명령(정확한 명령) |
| `deps` | 선행 task id |
| `decisions` | 참고할 결정 번호·절(있으면) |
| `defect-classes` | 이 task가 만들 수 있는 알려진 결함 계열 id(원장이 있을 때). 해당 계열의 "올바른 모양"을 AC 하나로 넣는다 |

- 원장의 계열이 여러 task에 걸치면, 그 계열의 공통 규칙을 한 곳에 모으는 task(헬퍼·래퍼·정적 검사)를 첫 웨이브에 두는 방안을 먼저 검토한다. 위치마다 따로 지키게 하면 호출자가 늘 때마다 다시 깨지기 때문이다.

"중요해 보인다"는 이유로 `chain-worker-deep`이나 `high-risk: yes`를 고르지 않는다. 판단 근거를 한 줄로 적는다.

## 4. review 판정

계획 frontmatter `review`를 다음으로 정한다.

- `required`: 스키마·외부 계약·보안·비가역 변경을 포함하거나 마일스톤이 2개 이상
- `optional`: 그 밖

## 5. 계획 종료 기준

다음이 정해지면 반환한다. 더 확장하지 않는다.

- 목표·범위·비목표
- 비싼 설계 결정과 그 이유
- 마일스톤 종료 조건, task AC, 검증 명령
- 권한과 결정적 전제(확인했으면 근거, 못 했으면 `unverified`)

함수·파일 배치를 전부 정하거나, worker 수·분할을 최적화하거나, 전체 시험 목록을 닫으려고 늘리지 않는다. 국소 미정은 담당 task와 확인 시점을 적어 넘긴다.

## 6. 계획 문서 형식

```markdown
---
chain-id: <id>
review: required | optional
status: draft
authority:
  local-commit: yes | no
  push: none | wave | milestone
  external-write: no | <허용 범위>
  new-cost: no | <허용 범위>
verify-full: "<명령>"          # 프로파일 값 또는 찾은 명령, 못 찾으면 unverified
---

# <체인 제목>

## 목표·범위·비목표
## 가정
## 핵심 결정          # 결정, 대안, 고른 이유, 되돌리는 비용
## 조정자 소유 파일
## blocking           # 없으면 "없음"

## M1 <이름>
- mode: build          # 기본. harden 은 사용자가 출시 검토를 요청했을 때만(SKILL.md §6-0)
- 종료 조건: ...       # build 모드: 기능이 동작하는 관찰 가능한 문장. 경계 조건 전수·여러 폭 계측을 종료 조건에 넣지 않는다
### W1
#### M1-W1-T01 <제목>
- worker: chain-worker — <근거>
- high-risk: no — <근거>
- owns: ...
- deps: 없음
- defect-classes: 없음 | C<n>
- ac:
  - ...
- verify: `<명령>`
```

## 7. 수정 요청(delta)

Sol BLOCK을 받아 조정자가 delta 수정을 요청하면, 지적된 절만 고치고 나머지는 건드리지 않는다. 바꾼 절 목록을 반환한다.
