# 상태 파일 형식

`$RC` = `<리포>/.review-chain/<chain-id>/`. 모두 OC가 만든다. 사람이 읽는 markdown 표로 두고(OC·worker 모두 Read로 읽는다), 기계가 읽는 것은 `current-oc` 한 줄뿐이다.

```
.review-chain/
├── launch-<YYYYMMDD-HHMM>.md # 시작 메모(launcher가 씀, launch.md §3)
├── <chain-id>/
│   ├── current-oc            # pane id 한 줄
│   ├── state.md
│   ├── queue.md
│   ├── merge.lock            # 병합 중일 때만(단계 진행 기록)
│   └── workers/<name>/{brief.md, report.md, plan-draft.md}
├── wt/<name>/                # git worktree
└── archive/<name>/           # 정리 때 옮긴 데이터 사본
```

## current-oc

```
w2:p4
```

- 줄바꿈 하나로 끝나는 pane id 한 줄. 교체 때 OC가 임시 파일에 쓰고 `mv`로 바꾼다(읽는 쪽이 반쯤 쓴 파일을 보지 않게).
- 같은 폴더의 `current-oc.log`에 `<시각> <pane id> <사유>`를 한 줄씩 덧붙인다(교체 이력).

## state.md

```markdown
---
chain-id: rc-20261109-gira
repo: /Users/peter/Dev/gira
main-base: 7d77c00            # 체인 시작 때 main
backend: herdr w2:p4
authority: {push: ask, external: none, version: per-merge, worker-commit: yes}   # 기본 yes(전역 예외 승인 2026-11-09, SKILL §15 D5). push는 OC만
oc-status: 활성               # 활성 | 교체중(옛 OC 동결 — 새 결정·병합·답 없음)
config: .claude/review-chain.md   # 없으면 default
---

## worker
| 이름 | pane | 탭 | 머신 | worktree | 브랜치 | 항목 | 파일 범위 | 상태 | 마지막 보고 | 비고 |
|---|---|---|---|---|---|---|---|---|---|---|
| rail | w2:p9 | w2:tC | macbook | .review-chain/wt/rail | rc/rc-20261109-gira/rail | Q3 | src/issue/Rail*.tsx, src/issue/rail.css | 진행 | 14:20 [범위] 레일 컴포넌트 분리 | opus high — 논의형 |
| fix1 | w2:p6 | w2:tA | macbook | .review-chain/wt/fix1 | rc/rc-20261109-gira/fix1 | Q1,Q2,Q5 | src/list/Row.tsx, src/i18n/ko.json | 완료보고 | 14:31 [완료] 3건 | sonnet high — 잡수정 |

## 병합
| 순번 | worker | 커밋 | 항목 | 판 | 검증 | push | 시각 |
|---|---|---|---|---|---|---|---|
| 1 | fix1 | a1b2c3d | Q1,Q2,Q5 | 1.4.3 | pass | 대기(ask) | 14:40 |

## 결정
- 14:22 Q3·Q7 범위 겹침(src/issue/Rail.tsx) — rail 우선, create 보류.

## 미처리
(oc-status: 교체중 동안 옛 OC가 받은 메시지 원문을 받은 순서대로 한 줄씩. 새 OC가 처리한 줄 끝에 ` → 처리 <시각>`)
- 15:02 [rc rc-20261109-gira] [WO rail] [범위변경] /…/workers/rail/report.md 레일 아이콘 파일 추가

## 종료
(체인 끝날 때만)
```

- `oc-status: 교체중`인 동안 옛 OC는 새 OC 기동 전 마무리 기록(`oc-handover.md` §1-3·4)과 "## 미처리" 덧붙이기 말고는 상태 파일을 고치지 않는다(새 OC와 동시 편집 방지). `활성`으로 되돌리는 것은 새 OC다.

## merge.lock

병합 하나의 진행 기록. OC가 단계를 끝낼 때마다 그 칸을 채운다. 교체된 OC는 **비어 있는 첫 칸부터만** 이어 한다(판올림·외부 반영 중복 방지). 칸 값 `skip`은 해당 없음(설정 `none`·권한 없음).

```
worker: fix1
started: 14:38
sha: a1b2c3d4e5f6...          # [완료] 보고 SHA(= 검토·병합 대상)
merged: 9f8e7d6...            # 병합 뒤 main 머리. 비어 있으면 병합 전
verified: pass                # pass | fail | none
version-bumped: 1.4.3         # 새 판 | skip
shared-committed: 0a1b2c3     # 공용 파일 커밋 SHA | skip
pushed: origin/main 0a1b2c3   # | skip | 대기(ask)
external-done: GIRA-12 댓글   # | skip
```

- 병합 전 거절(`[확인]`·`[main갱신]`·`[완료] 다시`)이면 lock을 지운다. `verified: fail`이면 지우지 않고 사용자 결정을 기다린다(SKILL §7-1).
- 칸 하나를 채우는 것은 그 단계의 결과를 확인한 뒤다(예: `pushed`는 `git ls-remote` 또는 push 출력으로 확인한 SHA).

- 표 한 줄 = worker 하나. 교체된 worker는 줄을 지우지 않고 상태 `교체됨`.
- `마지막 보고` = `<시각> <종류> <한 줄>`. OC가 메시지를 받을 때마다 고친다.
- 파일 범위는 리포 루트 기준 경로·glob, 쉼표 구분.

## queue.md

```markdown
| 번호 | 내용(사용자 원문 요지) | 분류 | 상태 | 담당 | 의존 | 결과 |
|---|---|---|---|---|---|---|
| Q1 | 목록 행 간격 좁음 | 잡수정 | 병합됨 | fix1 | - | a1b2c3d |
| Q3 | 이슈 상세 진행 레일 | 논의 | 진행 | rail | - | - |
| Q7 | 이슈 만들기 단추 | 논의 | 대기 | - | Q3(Rail.tsx) | - |
| Q9 | 권한 모델 재설계 | 승격 | auto-chain으로 넘김 | rail2 | - | plan-draft: workers/rail2/plan-draft.md |
```

- 상태: `대기` `배정` `진행` `병합됨` `보류` `auto-chain으로 넘김` `취소`(사용자가 철회).
- 번호는 다시 쓰지 않는다. 사용자가 말한 순서대로 붙인다.
- 외부 반영(JIRA 등)을 했으면 `결과`에 이슈 키를 덧붙인다.

## report.md (worker가 쓴다)

틀은 `worker-brief.md` §5. 절: `- 진행:` 한 줄 / `## 범위` / `## 완료` / `## 노트 초안` / `## 인계`(교체 때만).
