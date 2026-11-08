# agent-orchestrator S3 보고 — 세 머신 배포 (2026-11-08)

- 실행: 논의 세션(메인, pane `w2:p14`)이 직접 수행. 별도 worker 없음
- 배포 커밋: `9047985`(main = origin/main), 태그 `orca-codex-delegate-v1.0.3` → `b5691fb` origin push 확인(`git ls-remote`)

## 머신별 결과

| 항목 | 이 맥 | office | 홈 |
|---|---|---|---|
| 사본 도착 방법 | 수동 `claude plugin marketplace update` (push 직후 자동 갱신 안 됨: HEAD `b5691fb`) | 수동 update (자동 안 됨: `b5691fb`) | 수동 update (자동 안 됨: `cd7fcec`) |
| 갱신 뒤 사본 HEAD·`tools/` | `9047985` · 있음 | `9047985` · 있음 | `9047985` · 있음 |
| `install.sh herdr` 1회차 | 생성 link · 생성 config | 생성 · 생성 | 생성 · 생성 |
| 2회차(멱등) | 유지 · 유지 | 유지 · 유지 | 유지 · 유지 |
| `--check herdr` core / herdr | 2/2 · 6/6 | 2/2 · 6/6 | 2/2 · 6/6 |
| rule 잔존(allow 제외) | 134 | 135 | 124 |
| `backend` herdr pane 안 | `herdr` rc=0 (실제 pane `w2:p14`) | `herdr` rc=0 — **대리 확인**(ssh에 `HERDR_ENV=1`을 넣어 실행, 서버 `status: running`). 실제 pane 안 확인은 UNVERIFIED | 같음(대리 확인, UNVERIFIED) |
| `backend` herdr 밖 | rc=11 (`HERDR_ENV` 제거) | rc=11 (비로그인 ssh) | rc=11 (비로그인 ssh) |
| `installed_plugins.json` orca-codex-delegate | 0 | 0 | 0 |

## 실측으로 알게 된 것

- **autoUpdate는 push 직후 사본을 갱신하지 않았다**(세 머신 모두). 자동 갱신은 Claude Code 시작 시점 등 별도 시점에 일어나는 것으로 보인다(UNVERIFIED). 그래도 계획의 "main push = 게시" 전제는 유지한다 — 다음 세션 시작 때 갱신될 수 있으므로 S4·S5 브랜치 분리는 그대로 필요하다.
- 원격 실행은 `ssh <h> "bash -c \"…\""`처럼 따옴표를 겹치면 `$HOME`·`$I`가 이 맥에서 먼저 풀려 실패했다. 스크립트 파일을 `scp`로 보내 실행하는 방식이 안전했다.
- rule 잔존 수는 S5에서 0(allow 제외)으로 줄일 대상이다.

## 남은 것

- office·홈의 실제 herdr pane 안 양성 확인: 그 머신에서 herdr 세션을 열 때 `~/.local/bin/agent-orchestrator backend` 1회(pending).
- S4: auto-chain 2.3.0 — 브랜치 `feat/agent-orchestrator-2.3.0`.
