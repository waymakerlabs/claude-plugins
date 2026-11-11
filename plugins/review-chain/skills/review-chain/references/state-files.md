# 상태 파일 형식

`$RC` = `<리포>/.review-chain/<chain-id>/`. 모두 OC가 만든다. 사람이 읽는 markdown 표로 두고(OC·worker 모두 Read로 읽는다), 스크립트가 읽고 쓰는 것은 받은편지함(`inbox.log`·`.cursor`)·`claims.tsv`·`shared-files`다(`current-oc`는 기록·호환용이며 메시지 라우팅에는 쓰이지 않는다).

```
.review-chain/
├── launch-<YYYYMMDD-HHMM>.md # 시작 메모(launcher가 씀, launch.md §3)
├── <chain-id>/
│   ├── current-oc            # pane id 한 줄(기록·호환용 — 라우팅에 안 쓰임)
│   ├── inbox.log             # worker→OC 받은편지함(rc-send.sh·rc-claim.sh가 덧붙임)
│   ├── inbox.log.cursor      # OC가 처리한 줄 번호(rc-watch.sh --ack)
│   ├── claims.tsv            # 파일 범위 선점 진본(rc-claim.sh)
│   ├── claims.lock/          # 선점 중에만 있는 잠금 폴더
│   ├── shared-files          # 공용 파일 패턴 한 줄 한 패턴(OC가 체인 시작 때)
│   ├── state.md
│   ├── queue.md
│   ├── merge.lock            # 병합 중일 때만(단계 진행 기록)
│   └── workers/<name>/{brief.md, report.md, plan-draft.md, inbox.log, inbox.log.cursor}
│                              # inbox.log = OC→그 worker 받은편지함, cursor = worker가 처리한 줄 번호
├── wt/<name>/                # git worktree
└── archive/<name>/           # 정리 때 옮긴 데이터 사본
```

## current-oc

```
w2:p4
```

- 줄바꿈 하나로 끝나는 pane id 한 줄. 교체 때 OC가 임시 파일에 쓰고 `mv`로 바꾼다.
- **0.1.2부터 메시지 라우팅에 쓰이지 않는다**(받은편지함 경로가 고정). 현재 OC pane을 사람이 확인하거나 기존 도구와의 호환을 위해 기록으로 유지한다.
- 같은 폴더의 `current-oc.log`에 `<시각> <pane id> <사유>`를 한 줄씩 덧붙인다(교체 이력).

## 받은편지함 · claims.tsv · shared-files

- `inbox.log`(worker→OC), `workers/<name>/inbox.log`(OC→worker): 한 줄 = 메시지 하나(`<HH:MM:SS> [rc <chain-id>] …`, 형식은 `messages.md`). 줄은 덧붙이기만 하고 지우지 않는다. `<inbox>.cursor`는 처리한 마지막 줄 번호 한 줄이며 `rc-watch.sh --ack`만 올린다(되감지 않음). 처리 안 한 줄 = cursor 뒤 줄(`rc-watch.sh --pending <inbox>`). 받는 쪽은 `rc-watch.sh --subscribe <inbox>`로 구독한다(0.2.0, 훅이 없는 도구는 `messages.md` §1 대체 문단).
- **미감시 전송 기록(0.2.0)**: `rc-send.sh`·`rc-claim.sh`가 `inbox-send` stdout `unwatched`일 때 직접 남긴다. 형식은 `- 미감시 전송 <받은편지함 절대경로> <HH:MM>` 한 줄. worker→OC는 `workers/<name>/report.md`의 `- 진행:` 줄 아래(없으면 파일 끝), OC→worker는 `state.md`의 `## 미감시 전송` 절 끝(절이 없으면 파일 끝에 만든다). 재시도·알림은 없다.
- `claims.tsv`: `이름<TAB>패턴<TAB>active|released<TAB>시각` 한 줄씩. **파일 범위의 진본**이다. state.md worker 표 `파일 범위` 칸은 `[범위]`·`[범위변경]` 기록을 보고 OC가 옮겨 적는 거울이라, 어긋나면 `rc-claim.sh --list <$RC>`가 맞다. 해제(`--release`)는 줄을 지우지 않고 `released`로 바꾼다.
- `claims.lock/`: 선점 중 잠깐 있는 폴더. 오래 남아 있으면(스크립트 종료 6의 원인) OC가 선점 중인 프로세스가 없음을 확인한 뒤 지운다.
- `shared-files`: 설정 `shared-files`를 한 줄 한 패턴으로 옮긴 파일. 선점 패턴이 걸리면 `rc-claim.sh`가 종료 5로 거부한다. 없으면 공용 파일 검사를 하지 않는다.

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

## 종료
(체인 끝날 때만)
```

- 0.1.2부터 "## 미처리" 절은 쓰지 않는다. 처리하지 못한 메시지는 받은편지함의 처리 위치(`inbox.log.cursor`) 뒤에 그대로 남는다.
- `oc-status: 교체중`인 동안 옛 OC는 새 OC 기동 전 마무리 기록(`oc-handover.md` §1-3·4) 말고는 상태 파일을 고치지 않는다(새 OC와 동시 편집 방지). `활성`으로 되돌리는 것은 새 OC다.

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
- 파일 범위는 리포 루트 기준 경로·glob, 쉼표 구분. `claims.tsv`의 거울이다.

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

틀은 `worker-brief.md` §5. 절: `- 진행:` 한 줄(그 아래에 `- 미감시 전송 <받은편지함> <HH:MM>` 줄이 붙을 수 있다, 0.2.0) / `## 범위` / `## 완료` / `## 노트 초안` / `## 인계`(교체 때만).
