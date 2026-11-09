# 프로젝트 설정 (`.claude/review-chain.md`)

프로젝트 루트의 `.claude/review-chain.md`. 없으면 기본값. frontmatter는 값, 본문 절은 절차(OC가 그 시점에 읽고 따른다). auto-chain 프로파일(`.claude/autonomous-chain.md`)과 따로 둔다 — 공용 파일 목록이 같으면 본문에서 그 파일을 가리켜도 된다.

## 형식

```markdown
---
review-chain-profile: 1
max-workers: 4                 # 동시 worker 상한(논의형·잡수정 합계, 최대 5)
merge: ff-only                 # ff-only | squash
push: ask                      # none | ask | per-merge   (사용자가 둔 상시 정책. push는 언제나 OC만)
version: per-merge             # none | per-merge | batch
shared-files:                  # OC 전용. worker 수정 금지
  - VERSION
  - CHANGELOG.md
  - docs/progress/**
verify:
  worker: "<영향 시험 추천 명령>"   # worker 지시서에 넣는다
  merge: "<병합 뒤 main 검증 명령>"  # OC가 병합마다 1회
worktree-setup: "<worktree에서 1회 — 의존 설치·데이터 사본>"   # 선택
worktree-cleanup: "<git worktree remove 전 1회 — 데이터 사본 보관·정리>"   # 선택. 남은 ignored 파일은 OC가 archive로 옮긴다
external: none                 # none | jira | <이름> — 절차는 본문 ## external
---

## on-merge
(판올림·릴리즈 노트·진행 원장 갱신 절차. 예: VERSION 패치 +1 → CHANGELOG "## 미출시"에 노트 초안 다듬어 추가 → docs/progress/dashboard.md 표 갱신)

## external
(외부 반영 절차. 예: 대기열 항목에 JIRA 키가 있으면 병합 뒤 그 이슈에 커밋 해시 댓글. authority.external 허용일 때만)

## on-chain-end
(체인 종료 때 1회. 예: 릴리즈 노트 묶음 정리, 사용자 QC 재요청 문구)
```

## 기본값

| 키 | 기본값 | 비고 |
|---|---|---|
| `max-workers` | 4 | 논의형·잡수정을 합친 수. 종류별 상한은 두지 않는다. 5를 넘기면 OC가 무시하고 5 |
| `merge` | `ff-only` | worker가 main 위로 rebase해 둔다 |
| `push` | `ask` | OC는 병합·공용 파일 커밋까지만 하고, 사용자가 "push"라고 할 때 OC가 모아서 push한다. worker는 push하지 않는다 |
| `version` | `none` | 판올림 방식을 모르는 프로젝트에서 VERSION을 지어내지 않는다 |
| `shared-files` | `[]` | 비면 OC가 착수 때 VERSION·CHANGELOG·RELEASE_NOTES류를 찾아 사용자에게 1회 확인 |
| `verify.merge` | 없음 | 없으면 병합 뒤 검증 생략을 `state.md` 병합 표 `검증` 칸에 `none`으로 적는다(통과로 쓰지 않는다) |

- 설정의 push·external 값은 사용자가 둔 상시 정책이다. 이 스킬의 기본값은 승인을 만들지 않는다.
