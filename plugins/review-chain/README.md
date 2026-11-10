# review-chain

개발이 끝난 뒤 사용자가 시각검증(QC)을 하며 쏟아내는 수정사항을 병렬로 처리하는 skill입니다. 중심 세션 **OC** 하나가 수정사항을 대기열로 받고, 논의가 필요한 feature는 전용 worker(**WO**)에, 범위가 안 겹치는 사소한 수정은 묶음 worker 하나에 맡깁니다. 사용자는 worker 탭·pane에서 직접 논의하고, OC는 결과만 받아 병합·판올림·릴리즈 노트·외부 반영을 맡습니다.

## 구성

| 구성 | 설명 |
|------|------|
| skill `review-chain` | 시작·재개, 분류, worker 기동, 범위 충돌 판정, 병합, 공용 파일, OC·worker 교체, auto-chain 승격, 정리 |
| `references/state-files.md` | 상태 파일(`state.md`·`queue.md`·받은편지함·`claims.tsv`·`shared-files`·`current-oc`) 형식 |
| `references/messages.md` | worker↔OC 한 줄 메시지 형식(`<시각> [rc <chain-id>] …`)과 Monitor 수신 방법 |
| `references/worker-brief.md` | worker 지시서·보고 파일 틀 |
| `references/launch.md` | 기본 시작 경로 — 부른 세션이 시작 메모를 쓰고 새 탭에 깨끗한 OC를 연다 |
| `references/oc-handover.md` | OC 교체·worker 교체 절차 |
| `references/project-config.md` | 프로젝트 설정 `.claude/review-chain.md` |
| `scripts/rc-send.sh` | 메시지 한 줄을 받은편지함 파일에 덧붙임(worker→OC `inbox.log`, `--to`로 OC→worker `workers/<name>/inbox.log`). 입력창에 쳐 넣지 않음 |
| `scripts/rc-watch.sh` | 받은편지함을 처리 위치부터 지켜봄(Claude Code `Monitor` 명령). `--ack`로 처리 위치 기록, `--pending`으로 미처리 줄 확인 |
| `scripts/rc-claim.sh` | worker 파일 범위 선점·충돌 판정(`claims.tsv`). 선점되면 OC 승인 없이 착수, 충돌이면 OC가 순서 결정. `--release`·`--list` |

## 핵심 규칙

- (0.1.4) 받은편지함 기록·감시를 `agent-orchestrator inbox-send --raw`·`inbox-watch` 공용 동작으로 옮겼습니다(`rc-send.sh`·`rc-claim.sh`가 같은 잠금으로 기록, 형식은 그대로). Monitor를 못 쓸 때 상대가 유휴면 `agent-send`로 알리던 예외를 없앴습니다. `rc-send.sh` 기록 실패는 종료 4.
- 진본은 리포 안 `.review-chain/<chain-id>/`의 상태 파일입니다(`.git/info/exclude`로 추적 제외). OC는 판단만 합니다.
- 메시지는 받은편지함 파일(`inbox.log`)에 덧붙이고, 받는 쪽이 `Monitor`로 지켜봅니다. 상대 pane 입력창에 쳐 넣지 않아 사용자가 치던 프롬프트와 섞이지 않습니다. 경로가 고정이라 OC가 교체돼도 worker는 바꿀 것이 없고, 처리 위치(`.cursor`) 뒤의 줄이 새 OC에 이어집니다.
- 충돌은 착수 전에: worker가 `rc-claim.sh`로 파일 범위를 스스로 선점하고(겹침 없으면 OC 승인 없이 착수), 겹칠 때만 OC가 보류·순서를 정합니다. 병합은 OC만, 한 번에 하나.
- VERSION·릴리즈 노트·진행 원장·외부 반영은 OC 전용입니다.
- 메시지는 worker→OC, OC→worker 한 줄만. worker끼리 대화하지 않습니다.
- worker 안에서 auto-chain을 돌리지 않습니다. 큰 항목은 auto-chain으로 승격하고, 첫 판에서는 승격이 생기면 진행 중 worker만 마무리하고 멈춥니다.
- 오케스트레이션 툴(`tools/agent-orchestrator`, `backend`가 0) 안에서만 동작합니다.
