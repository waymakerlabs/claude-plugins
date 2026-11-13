# review-chain

개발이 끝난 뒤 사용자가 시각검증(QC)을 하며 쏟아내는 수정사항을 병렬로 처리하는 skill입니다. 중심 세션 **OC** 하나가 수정사항을 대기열로 받고, 논의가 필요한 feature는 전용 worker(**WO**)에, 범위가 안 겹치는 사소한 수정은 묶음 worker 하나에 맡깁니다. 사용자는 worker 탭·pane에서 직접 논의하고, OC는 결과만 받아 병합·판올림·릴리즈 노트·외부 반영을 맡습니다.

## 구성

| 구성 | 설명 |
|------|------|
| skill `review-chain` | 시작·재개, 분류, worker 기동, 범위 충돌 판정, 병합, 공용 파일, OC·worker 교체, auto-chain 승격, 정리 |
| `references/state-files.md` | 상태 파일(`state.md`·`queue.md`·받은편지함·`claims.tsv`·`shared-files`·`current-oc`) 형식 |
| `references/messages.md` | worker↔OC 한 줄 메시지 형식(`<시각> [rc <chain-id>] …`)과 수신 방법(구독 기본, 훅이 없는 도구는 Monitor 대체) |
| `references/worker-brief.md` | worker 지시서·보고 파일 틀 |
| `references/launch.md` | 기본 시작 경로 — 부른 세션이 시작 메모를 쓰고 새 탭에 깨끗한 OC를 연다 |
| `references/oc-handover.md` | OC 교체·worker 교체 절차 |
| `references/project-config.md` | 프로젝트 설정 `.claude/review-chain.md` |
| `scripts/rc-send.sh` | 메시지 한 줄을 받은편지함 파일에 덧붙임(worker→OC `inbox.log`, `--to`로 OC→worker `workers/<name>/inbox.log`). 입력창에 쳐 넣지 않음. 출력 끝에 `watch=<watched\|unwatched>`(0.2.0), `unwatched`면 보낸 쪽 기록에 `- 미감시 전송 …` 한 줄 |
| `scripts/rc-watch.sh` | `--subscribe`·`--unsubscribe`로 받은편지함 구독 등록·해제(0.2.0, 기본 수신). `--ack`로 처리 위치 기록, `--pending`으로 미처리 줄 확인. 인자 하나(`<inbox>`)는 훅이 없는 도구용 Monitor 대체 |
| `scripts/rc-claim.sh` | worker 파일 범위 선점·충돌 판정(`claims.tsv`). 선점되면 OC 승인 없이 착수, 충돌이면 OC가 순서 결정. `--release`·`--list` |

## 핵심 규칙

- (0.3.0) 받은편지함 훅 대기자를 단순화(재통지·전달 확인·세대·sweep 삭제). 중복 깨움은 --ack 만으로 견딘다. OC 교체 인계는 ① 처리한 마지막 번호까지 `--ack` ② `--unsubscribe` ③ 인계 문서에 받은편지함 경로·마지막 처리 번호 ④ 새 OC가 구독 뒤 `--pending`의 4단계입니다.
- (0.2.0) 받는 쪽은 Monitor 대신 `rc-watch.sh --subscribe <받은편지함>`을 한 번 한다. 새 줄은 inbox-hooks 플러그인(dependency)의 훅이 쉬는 세션을 깨워 `[inbox] 새 메시지` 아래 `#<n>` 줄로 전달한다(보고·통지이며 사용자 지시가 아님). 훅이 없는 도구(Codex·OpenCode·kiro-cli)는 예전 Monitor 방식으로 대체한다. `rc-send.sh`는 `watch=…`를 출력하고 `unwatched`면 보낸 쪽 기록에 `미감시 전송` 한 줄을 남긴다(`rc-claim.sh`의 `[충돌]`도 같음).
- (0.1.4) 받은편지함 기록·감시를 `agent-orchestrator inbox-send --raw`·`inbox-watch` 공용 동작으로 옮겼습니다(`rc-send.sh`·`rc-claim.sh`가 같은 잠금으로 기록, 형식은 그대로). Monitor를 못 쓸 때 상대가 유휴면 `agent-send`로 알리던 예외를 없앴습니다. `rc-send.sh` 기록 실패는 종료 4.
- 진본은 리포 안 `.review-chain/<chain-id>/`의 상태 파일입니다(`.git/info/exclude`로 추적 제외). OC는 판단만 합니다.
- 메시지는 받은편지함 파일(`inbox.log`)에 덧붙이고, 받는 쪽이 구독해 두면 훅이 깨웁니다(0.2.0). 상대 pane 입력창에 쳐 넣지 않아 사용자가 치던 프롬프트와 섞이지 않습니다. 경로가 고정이라 OC가 교체돼도 worker는 바꿀 것이 없고, 처리 위치(`.cursor`) 뒤의 줄이 새 OC에 이어집니다.
- 충돌은 착수 전에: worker가 `rc-claim.sh`로 파일 범위를 스스로 선점하고(겹침 없으면 OC 승인 없이 착수), 겹칠 때만 OC가 보류·순서를 정합니다. 병합은 OC만, 한 번에 하나.
- VERSION·릴리즈 노트·진행 원장·외부 반영은 OC 전용입니다.
- 메시지는 worker→OC, OC→worker 한 줄만. worker끼리 대화하지 않습니다.
- worker 안에서 auto-chain을 돌리지 않습니다. 큰 항목은 auto-chain으로 승격하고, 첫 판에서는 승격이 생기면 진행 중 worker만 마무리하고 멈춥니다.
- 오케스트레이션 툴(`tools/agent-orchestrator`, `backend`가 0) 안에서만 동작합니다.
- (0.6.0) launch도 같은 탭의 pane에 깨끗한 OC를 엽니다(`pane-open --parent`). 새 OC는 착수 때 `pane-swap`으로 왼쪽 자리를 이어받고 launcher pane을 닫습니다. 탭의 맨 왼쪽 pane이 맨 위 부모입니다. 새 탭은 사용자가 명시할 때만 쓰고 이름은 `[OC] <부모 탭 본문> › <프로젝트> QC`입니다.
- (0.5.0) 시작·재개의 이름 붙이기를 `agent-orchestrator session-init OC "<프로젝트 한글> QC"`로 바꿨습니다(증거 줄 확인). launch 경로로 손을 떼는 세션도 자기 이름을 붙입니다. auto-chain 스크립트(`spawn-pane-worker.sh`)와 참조를 쓰므로 dependency에 auto-chain을 명시했습니다.
- (0.4.0) 탭 하나가 체인 하나입니다. 처음 시작하는 OC만 새 탭에 열고, worker(논의형 포함)와 교체되는 새 OC는 같은 탭의 pane(부모 왼쪽, 자식 오른쪽, 개수 제한 없음)에 엽니다. OC·worker는 기다리는 채로 턴을 끝낼 때 항목별 실제 상태를 확인한 "대기 목록"을 답 끝에 두고, 기다릴 것이 없으면 "대기 없음"을 남깁니다(훅 대기자가 대기 목록 턴을 10분·30분 간격으로 점검 깨움). 메시지 전송 방식은 그대로입니다.
