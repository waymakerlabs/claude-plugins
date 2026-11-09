# review-chain

개발이 끝난 뒤 사용자가 시각검증(QC)을 하며 쏟아내는 수정사항을 병렬로 처리하는 skill입니다. 중심 세션 **OC** 하나가 수정사항을 대기열로 받고, 논의가 필요한 feature는 전용 worker(**WO**)에, 범위가 안 겹치는 사소한 수정은 묶음 worker 하나에 맡깁니다. 사용자는 worker 탭·pane에서 직접 논의하고, OC는 결과만 받아 병합·판올림·릴리즈 노트·외부 반영을 맡습니다.

## 구성

| 구성 | 설명 |
|------|------|
| skill `review-chain` | 시작·재개, 분류, worker 기동, 범위 충돌 판정, 병합, 공용 파일, OC·worker 교체, auto-chain 승격, 정리 |
| `references/state-files.md` | 상태 파일(`current-oc`·`state.md`·`queue.md`) 형식 |
| `references/messages.md` | worker↔OC 한 줄 메시지 형식(`[rc <chain-id>] …`) |
| `references/worker-brief.md` | worker 지시서·보고 파일 틀 |
| `references/launch.md` | 기본 시작 경로 — 부른 세션이 시작 메모를 쓰고 새 탭에 깨끗한 OC를 연다 |
| `references/oc-handover.md` | OC 교체·worker 교체 절차 |
| `references/project-config.md` | 프로젝트 설정 `.claude/review-chain.md` |
| `scripts/rc-send.sh` | `current-oc`를 읽어 worker 보고 한 줄 전송 |

## 핵심 규칙

- 진본은 리포 안 `.review-chain/<chain-id>/`의 상태 파일입니다(`.git/info/exclude`로 추적 제외). OC는 판단만 합니다.
- worker는 OC pane id를 외우지 않고 보고 때마다 `current-oc` 파일을 읽습니다. OC 교체 = 파일 갱신.
- 충돌은 착수 전에: worker가 파일 범위를 먼저 제출하고, 겹치면 OC가 보류·순서를 정합니다. 병합은 OC만, 한 번에 하나.
- VERSION·릴리즈 노트·진행 원장·외부 반영은 OC 전용입니다.
- 메시지는 worker→OC, OC→worker 한 줄만. worker끼리 대화하지 않습니다.
- worker 안에서 auto-chain을 돌리지 않습니다. 큰 항목은 auto-chain으로 승격하고, 첫 판에서는 승격이 생기면 진행 중 worker만 마무리하고 멈춥니다.
- 오케스트레이션 툴(`tools/agent-orchestrator`, `backend`가 0) 안에서만 동작합니다.
