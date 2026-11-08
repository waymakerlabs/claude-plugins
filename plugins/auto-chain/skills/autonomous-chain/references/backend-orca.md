# 실행 백엔드 — Orca (1.7.1까지의 방식)

Orca 데스크톱 앱 안에서 체인을 돌릴 때 쓴다. SKILL.md §1-1 백엔드 선택이 진본이다. 1.7.1 원본은 git 태그 `auto-chain-v1.7.1-orca`에 그대로 남아 있다.

## 0. 전제

- `orca status`가 runtime ready.
- 상태 파일 frontmatter `backend: orca`.

## 1. 무엇을 무엇으로

| 작업 | 실행 |
|---|---|
| 구현 task·BLOCK 수정·planner | `Agent` 서브에이전트(`subagent_type: auto-chain:<역할>`, SKILL.md §4 "worker 기동") — 모델·effort는 frontmatter 고정값, `model`을 넘겨 덮어쓰지 않는다 |
| Sol 검토·원인 조사·`worker:opencode-<agent>` | Orca 터미널 탭(§2) |
| 마일스톤 인계 | Orca 탭(§3) |

## 2. Sol 검토 탭 (sol-review.md §3~§5에서 호출)

Orca에 **등록된** worktree에 탭을 연다. 대상 리포가 등록되지 않았으면 `--worktree active`가 `selector_not_found`로 실패하므로, 등록된 worktree(`path:<등록 경로>`)에 열고 명령 안에서 `cd`한다.

```bash
orca terminal create --worktree <active|path:등록경로> --title "$TITLE" --command "$CMD" --json
```

- `CMD`는 sol-review.md §3에서 인자마다 `printf '%q '`로 만든 실행기 호출(`scripts/review-run.sh …`)을 그대로 쓴다 — 경로를 따옴표로 감싸 문자열에 끼우지 않는다. (2.2.0) RUN 기록은 실행기가 직접 쓰는 `<done>.run` 한 줄(`RUN <RUN_ID> pid=<pid> start=<시작 시각>`)뿐이고, 완료는 done 파일 하나로만 판단한다(sol-review.md §4 `review-wait.sh`).
- `create`는 시도당 1회. 응답 전체에서 handle을 즉시 추출한다(잘라서 잃으면 `orca terminal list`로 title 기반 재확보, 재create 금지).
- Orca 터미널 status는 완료 신호로 쓰지 않는다(명령이 끝나도 셸이 남아 `running`으로 보인다).
- 무응답(`review-wait.sh` 종료 4가 거듭될 때) 화면 확인: `orca terminal read --terminal <handle> --screen --json`.
- 정리: `orca terminal close --terminal <handle> --tab --json`.

## 3. 마일스톤 인계

- 전역 CLAUDE.md의 「Orca 탭 방식 후속 세션 인계 프로토콜」을 따른다. 단 그 프로토콜 규칙 4·8의 Codex 크로스체크는 이 스킬의 Sol 게이트로 대체한다.
- 인계 탭도 Sol 탭과 같이 등록된 worktree(`path:<등록 경로>`)에 열고, 인계 문서에 "실행 위치"와 "git은 `git -C <리포>`"를 적는다.
- 부모 탭 정리(child 쪽): `orca terminal close --tab` 응답의 `ok`와 `ptyKilled`를 상태 파일에 기록한다. `ok: true`인데 `ptyKilled: false`이면 `orca terminal list`에서 부모 handle이 사라졌는지 확인하고 결과를 남긴다. 부모 프로세스를 강제로 끝내지는 않는다. 목록에 남아 있으면 같은 worktree에 편집 소유자가 둘일 수 있으니 질문 대기열에 올리고, 부모가 고치던 파일은 건드리지 않는다.
