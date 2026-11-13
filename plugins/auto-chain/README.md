# auto-chain

큰 작업을 **milestone → wave → task**로 나누고, 마일스톤 하나를 Claude Code 세션 하나가 조정하며, task는 병렬 서브에이전트가 구현하는 자율 진행 skill입니다. 계획은 Opus, 검토는 다른 계열 모델(GPT-6.1 Sol high — Codex CLI 하나)이 맡습니다. 프로젝트마다 다른 절차는 프로파일 파일로 정합니다.

## 구성

| 구성 | 설명 |
|------|------|
| skill `autonomous-chain` | 계획 세션·마일스톤 세션 절차, 조정자 규율, 검증 예산, Sol 게이트, 멈춤 조건 |
| agent `chain-planner` | 최초 계획 뒤의 delta 수정·출시 검토 삽입(Opus, high) |
| agent `chain-planner-deep` | 체인의 최초 계획(항상), 이후 되돌리기 어려운 설계 계획(Opus, xhigh) |
| agent `chain-worker` | 명세가 있는 task 구현(Sonnet, high) |
| agent `chain-worker-deep` | 상태·동시성·권한 경계 task, 실패 재시도(Opus, high) |
| agent `chain-worker-xhigh` | deep으로도 실패한 task·결함 계열 재수정(Opus, xhigh). 처음부터 배정하지 않음 |
| `references/` | 계획 지침, worker 공통 지시서, Sol 검토 절차, 프로파일 형식 |

## 핵심 규칙

- (2.14.0) 새 세션은 기본이 같은 탭의 pane: 부모 세션이 여는 새 체인 조정자도 `pane-open --parent`로 같은 탭에 엽니다. 탭의 맨 왼쪽 pane이 맨 위 부모입니다. 새 탭은 사용자가 명시할 때만 쓰고 이름은 `[OC] <부모 탭 본문> › <체인 한글>`입니다. 계기: 한 부모 세션의 자식이 여러 탭으로 나뉘면 사용자가 답할 맨 위 부모 탭을 찾기 어려웠습니다.
- (2.13.0) 착수 체크를 SKILL.md 맨 위로: 계획·마일스톤·이어받은 세션 모두 첫 응답 전에 `agent-orchestrator session-init OC "<한글>" --inbox <받은편지함>` 한 번으로 탭·pane 이름(사용자 이름은 접두어만)과 구독을 함께 하고 증거 줄을 확인합니다. `inbox-send`는 받는 쪽이 구독하지 않았으면 stderr에 `미감시:`를 내고, 보낸 쪽은 `notify`로 사람에게 올립니다. 대기 표시(`self-name --force - "[OC] …"`)는 탭에 접두어가 없으면 한 번 보정합니다. 계기: 2026-11-13 조정자가 착수 이름을 빠뜨려 탭이 끝까지 `[OC]` 없이 남았고(이름 규칙이 ③ 전용 참조에만 있었음), 메인 고정 받은편지함이 구독되지 않아 보고 한 줄이 읽히지 않았습니다.
- (2.12.0) 메인 고정 받은편지함: 자식을 띄우는 메인은 pane id 대신 `inbox/main-<주제>.log`를 구독하고 그 경로를 자식에게 줍니다. 인계로 메인 pane이 바뀌어도 주소가 같습니다. `inbox-send <pane id>`는 그 pane이 없으면 3으로 끝나고(줄은 기록), 받는 쪽은 `agent-orchestrator notify`로 사람에게 올립니다. 화면에서 사용자에게 묻는 질문도 부모 받은편지함과 알림으로 같이 보냅니다. 계기: CSR worker가 닫힌 pane(wA:p1)으로 보고를 계속 보내려 했고, 부모는 worker의 질문을 몰랐습니다.
- (2.11.0) 대기 보고에 이유·병목·다음 확인을 붙입니다. 대기 목록 항목마다 `이유 · 병목 · 다음 확인 <HH:MM>` 줄을 두고, 체인을 띄운 부모 세션에는 대기 진입·해제를 한 줄씩 받은편지함으로 알립니다. 부모는 끝난 것·무엇을·왜·병목 실측·다음 확인 시각 다섯 가지로 사용자에게 보고하고, pane 상태만 보고 "멈췄다"고 말하지 않습니다(2026-11-13 정상 대기가 사용자에게 쉬는 탭으로만 보인 사례).
- (2.10.1) 웨이브 통합 끝과 마감 직전에 「pane 정리 확인」: `list --panes`로 그 웨이브·마일스톤의 ③ pane을 보고, 회수가 끝난 것은 조정자가 닫은 뒤 목록에서 사라진 것을 확인합니다. 사용자에게 닫기를 넘기지 않습니다(①·③ 혼합 웨이브에서 ③ pane을 놓친 사례).
- (2.10.0) ① 창 배치: 처음 시작하는 체인 세션만 새 탭이고, worker·RV와 마일스톤 인계로 뜨는 다음 조정자는 같은 탭의 pane입니다(`pane-open --parent`, 새 조정자가 착수 때 `pane-swap`으로 왼쪽 자리를 이어받은 뒤 옛 조정자를 닫음). pane 개수 제한이 없어 넘침 탭은 기본으로 생기지 않고, 탭 하나가 체인 하나입니다. ② 「대기 목록과 끝맺음」: 무언가 기다리며 턴을 끝낼 때 항목마다 실제 상태를 확인한 `대기 목록 (N):`을 답 끝에 두고, 훅 대기자가 10분 뒤 한 번·그 뒤 30분마다 "대기 점검"으로 깨웁니다(2026-11-12 editor-parity에서 planner 완료 알림을 받고도 "아직 돌고 있다"고 끝낸 사례). ③ `chain-planner`·`chain-planner-deep`도 반환 직전 `[planner <이름>] done <산출 파일> <한 줄>`을 조정자 받은편지함에 보내고, 조정자는 planner 지시서에 그 경로를 넣습니다.
- (2.9.0) 받은편지함 훅 대기자를 단순화(재통지·전달 확인·세대·sweep 삭제). 중복 깨움은 --ack 만으로 견딘다. 인계 순서는 ① 처리한 마지막 번호까지 `--ack` ② `inbox-subscribe --unsubscribe`(Monitor면 TaskStop) ③ 인계 문서에 받은편지함 경로·마지막 처리 번호 ④ 새 조정자가 `inbox-subscribe` 뒤 `--pending`의 4단계입니다.
- (2.8.1) 완료 알림 유실 대비: ① `Agent` worker도 반환 직전 조정자 받은편지함에 `[worker <task-id>] done|failed <보고서>` 한 줄을 보내고, 조정자는 완료 알림·받은편지함 줄·진행 감시 `완료` 중 먼저 온 것으로 회수합니다. 진행 감시 스크립트는 고쳐 쓰지 않고, 다시 띄운 직후 각 보고서 `- 진행:` 줄을 직접 읽어 이미 끝난 task를 회수합니다(2026-11-11 회수 지연 4시간·1시간 20분 사례).
- (2.8.0) 받은편지함 감시를 Monitor에서 `inbox-hooks` 구독으로 바꿨습니다. 받는 쪽은 받은편지함이 정해진 직후 `agent-orchestrator inbox-subscribe <받은편지함>`을 한 번 하고(조정자는 상태 파일을 만든 직후), 새 줄이 오면 쉬는 세션이 훅으로 깨어납니다. `inbox-hooks`는 dependency라 auto-chain과 함께 자동 설치·켜집니다. 인계 순서는 2.9.0 항목의 4단계이고, `inbox-send`가 `unwatched`를 내면 보고서·상태 파일에 `미감시 전송` 한 줄을 남깁니다. `spawn-pane-worker.sh`는 부모 pane에 감시가 없으면 경고와 `parent_watch=none`을 냅니다(기동은 계속). Codex·OpenCode·kiro-cli처럼 훅이 없는 도구는 Monitor `inbox-watch`를 그대로 씁니다.
- (2.7.0) 짧은 탐색·조사 서브에이전트는 Haiku: 읽기 전용 위치 탐색·grep·목록화·사실 확인은 `Agent`에 `model: haiku`로 돌리고, 결과는 조정자가 근거 파일로 대조합니다. 구현·리뷰·판단 단계와 pane worker는 그대로(sonnet/opus)입니다. 계기: Haiku 5.5 사용 가능, 전역 CLAUDE.md의 "haiku: 위치 탐색·grep·목록화" 기준과 맞춤.
- (2.6.0) 세션 간 메시지는 받은편지함으로: 이미 첫 지시를 받은 세션의 입력창에는 아무것도 쳐 넣지 않습니다. worker↔조정자·조정자↔부모 세션 메시지는 `agent-orchestrator inbox-send`로 파일에 덧붙이고 받는 쪽이 `inbox-watch` Monitor로 읽습니다(조정자 받은편지함은 체인 고정 경로라 인계로 pane이 바뀌어도 같음). `agent-send`는 새 세션 첫 지시 시도 1회뿐이고, 실패·불명확해도 재전송하지 않습니다(pane close 확인 뒤 새 pane으로). 인계 때 옛 조정자는 받은편지함을 동결(Monitor 중지·ack·인계 문서 기록)한 뒤 다음 조정자를 엽니다. 계기: office gira에서 마일스톤 조정자가 부모 세션 입력창에 답을 넣었습니다.
- (2.5.0) 큰 파일은 한 번에 쓰지 않습니다. 한 번의 Write·Edit 출력은 약 150줄·8KB 이하로 하고, 그보다 큰 파일(계획·수정 계획·delta·보고서·handoff·리뷰 요청·문서·코드)은 절 제목과 요지만 담은 뼈대를 먼저 Write한 뒤 절마다 Edit로 채웁니다. 기존 큰 파일을 대부분 고칠 때도 통째로 다시 쓰지 않고 절 단위 Edit로 나눕니다. 조정자와 planner·worker·breaker 지시서 모두에 적용합니다. 근거: 2026-11-09 helpai M1-12 planner가 조사를 끝낸 뒤 245줄·59KB plan을 한 번에 Write하려다 응답 생성이 약 6분 간격 재시도 9회(약 50분) 반복되며 파일이 0이었고, 뼈대 49줄 Write + 절별 Edit로 바꾸자 7분에 끝났습니다. 출력 생성 중 시간 초과라 PreToolUse 훅으로는 막을 수 없어 생성 전에 읽히는 지시로 둡니다(훅 없음).
- 조정자는 worker의 반환 본문을 근거로 쓰지 않습니다. 보고서와 실제 diff(위험 지점), 웨이브 통합 검증으로 확인합니다.
- worker는 stage·commit·push를 하지 않습니다. 커밋은 조정자가 보고서의 변경 파일 목록으로 하나씩 합니다(index 잠금 충돌 방지).
- 전체 검증은 웨이브 통합과 마일스톤 마감 때 1회씩만 합니다.
- 질문이 생겨도 멈추지 않고 추천안으로 진행하며, 권한 밖 작업만 대기열에 올립니다.
- 이 skill의 기본값이나 리뷰 SHIP은 push·외부 쓰기 승인을 만들지 않습니다.
- (1.6.0) 마일스톤은 기본 **구현 모드**: 주 흐름·회귀·데이터/권한/보안·크래시·비가역 대상·사용자 시각검증 지적만 BLOCK이고, 나머지 경계 조건은 백로그(`backlog.md`)에 쌓습니다. 전수 점검은 하지 않습니다. 사용자가 "출시 검토"·"전체 테스트"를 요청한 시점에만 `HARDEN` 마일스톤을 넣어 백로그·계열을 한 번에 정리합니다. 외부 '완료' 반영은 구현 완료 시점입니다.
- (1.6.1) Sol 무응답 대비: 재검토(delta)는 이전 세션을 재개하지 않고 새 세션으로 엽니다(맥락 누적 방지). 증거 이미지는 첨부 대신 경로만. 로그가 15분 정체하면 `SOL-STALL`로 보고, 같은 요청을 다시 보내지 않고 맥락을 줄여(r1은 영역 2개로 나눠 동시에) 1회 재시도합니다.
- (1.6.2) 실패 사다리를 등급 상향에서 시각 전환으로: 원인 모를 실패 1번 → Sol 원인 조사(읽기 전용, `references/sol-review.md` §7) → Sol 안대로 고쳤는데도 실패 → `chain-worker-xhigh`(반박된 가설 전부 첨부) → 그래도 실패 → task blocked·질문 대기열. 오타·flaky·환경 문제와 Sol 안 구현 실수는 세지 않습니다.
- (1.6.3) 수정 작업은 처음부터 `chain-worker-xhigh`: 원인 위치가 특정된 간단한 수정은 조정자 국소 경로, 그 밖의 BLOCK·회귀·원인 조사 수정은 Sonnet·deep 단계 없이 xhigh로 시작합니다. 신규 구현 task 등급은 그대로(planner 표시). 실패 사다리 = xhigh → Sol 원인 조사 → 새 xhigh(반박된 가설 첨부) → blocked.
- (1.6.5) 체인의 최초 계획은 위험도와 무관하게 항상 `chain-planner-deep`(Opus xhigh). delta 수정·출시 검토 삽입 같은 이후 planner 호출은 기존 기준(되돌리기 어려우면 deep, 아니면 `chain-planner`).
- (1.7.0) 속도 우선(giki-editor-v2 회고): 화면 마일스톤은 Sol 최종 검토 없이 build·스모크로 마감, 데이터 마일스톤은 Sol 가벼운 게이트 1회(무거운 게이트는 계획이 `gate: heavy`로 표시한 마일스톤만). breaker 기본 끔(프로파일 `breaker: on`). 일반 문제는 30분 상한 → 백로그 `[30분]`, 간헐 실패는 `[quarantine]`, 데이터·권한 문제만 그 자리에서 해결. 시각 확인 `visual-check: request`(기다리지 않는 요청, 반응 없으면 넘김) 또는 `end`. 최초 계획은 두 층(골격·가로지르는 결정·첫 두 마일스톤 task)이고 이후는 마일스톤 마감마다 `chain-planner`가 M+2를 롤링 분해(Sol 검토 없음). worker 보고서 30줄.
- (2.0.0) 실행 백엔드 분리: herdr pane 안이면 herdr(구현·계획 worker를 오른쪽 열 pane의 Claude 세션으로 띄우고, 조정자가 pane마다 sonnet high / opus high를 고름, worker와 조정자가 `herdr agent prompt`로 작업 중 대화), Orca 안이면 기존 Orca 방식. 짧은 탐색·조사만 서브에이전트. 판정 규칙(보고서·nonce·snapshot·게이트)은 그대로.
- (2.1.0) 2체인 운영 분석(office·helpai) 반영: pane worker 정지는 transcript(jsonl) mtime과 `agent_status`로만 판정(10분 후보 → 화면 1회 → Escape 재지시, 재기동은 20분 무변화 2회), 조사 단계 진행 줄 10분 갱신, 조정자 맥락 150K 기준(예시)과 체인마다 새 조정자 세션, 프로젝트 가이드의 실행 수단 충돌 검사, 롤링 분해를 마지막 웨이브 기동 직후 병렬로, Sol 명령 사전 점검(쓰기 가능 우회 시 전후 git 대조), 검증 snapshot 격리, 확인 범위 = 보고서 + 위험 지점 diff, 시각 확인 `막힘` 상태, SHA 12자리, worker 메시지 `[worker <이름>] <done|failed|question|blocked>`, pane 기동 스크립트 `scripts/herdr-spawn-worker.sh`, 마감 체크(미해결 정리·`updated:` 갱신).
- (2.4.0) 리뷰어를 codex CLI(`review-run.sh codex-cli`, `codex exec -m gpt-6.1-sol -c model_reasoning_effort="high" -s read-only --ephemeral`) 하나로 정리하고 opencode 리뷰어(`opencode-sol`·`opencode-build`)를 제거했습니다. 프로파일 `reviewer` 키는 하위 호환으로 남기되 값은 `codex-cli`만이며, 실행기는 opencode 값을 exit 2로 거부합니다. 이어받은 체인의 상태 파일이 `reviewer: opencode-*`이면 첫 리뷰 전에 codex 드라이런을 통과시키고 `codex-cli`로 이관합니다. 착수 드라이런이 실패하면 대체 리뷰어 없이 원인을 기록하고 멈춰 보고합니다. `worker:opencode-<agent>`(BLOCK 수정 구현 칸, `headless-run.sh`)는 리뷰가 아니라 그대로 둡니다. 근거: 2026-11-08 이 맥·office 맥미니 둘 다 codex 0.167.0로 read-only 실리뷰를 확인했고, opencode 경로는 인자 순서·래퍼·게이트웨이 키·에이전트 거부(office 7회·약 10분) 문제가 반복됐습니다.
- (2.3.0) 오케스트레이션 툴 추상화: 실행 단계를 3단계로(① `Agent` 기본 — 웨이브 구현·BLOCK 수정 ② headless 일회성 실행 — Sol 검토 기본 `review_view: headless`, 비리뷰 다른 CLI는 `scripts/headless-run.sh` ③ pane — 최초 계획·인계를 넘기는 planner·마일스톤 인계·사용자가 지켜볼 작업만). 툴 명령은 `agent-orchestrator <동작>`으로만 부르고 10·11·12(unsupported·no backend·adapter error)면 ①·②로 내려감(①로 내려간 planner는 인계 전 회수 필수). `scripts/spawn-pane-worker.sh`(정책만 — 배치·이름·중복 검사는 어댑터, 10·11·12는 같은 코드로 전달)·`scripts/agent-stall-watch.sh`(`agent-status`·`agent-transcript`만, transcript 10이면 상태만), `references/pane-worker.md`. 옛 이름 스크립트는 2.3.x 동안 래퍼, 옛 `references/backend-herdr.md`는 포인터. Orca 경로 삭제(`references/backend-orca.md` — 복원은 태그 `auto-chain-v1.7.1-orca`). 탭·pane 이름 역할 접두어 `[OC]` 조정자·`[WO]` worker·`[RV]` 리뷰어(기본 `[WO] <name>`, 넘침 탭 `[WO] 자율체인 작업`). 프로파일 키 `review_view`. 시험 90건(기존 56건 이름 유지)
- (2.2.2) herdr 탭·pane 이름을 항상 한글로: `herdr-spawn-worker.sh`가 split 직후 `pane rename`으로 `PANE_LABEL`(기본 `작업자 <name>`)을 붙이고(split에는 이름 옵션이 없다), 넘침 탭 기본 이름은 `자율체인 작업`. 조정자는 착수 때 자기 탭·pane이 번호·영문 기본값이면 한글로 바꾼다. 시험 56건
- (2.2.1) 실기 확인(이 맥·office 맥미니) 반영: `review-run.sh` opencode 경로에서 메시지를 `-f`보다 앞에 둔다(`-f`가 배열이라 메시지를 파일로 읽어 `File not found`), 셸 래퍼 대신 실제 바이너리 `~/.opencode/bin/opencode`를 우선(`REVIEW_OPENCODE_BIN`) — 래퍼는 비대화형 실행에서 provider 초기화 실패. codex-cli·opencode-build 실제 리뷰 둘 다 done 파일로 회수 확인
- (2.2.0) 시간 분석(helpai 43.6h: 사람 대기 ≈1,250분 > FIX ≈775 > 계획 > 죽은 시간 > 리뷰 실행 ≈240) 반영: **게이트 수렴 규칙**(재검토 = 직전 finding 해소 + 이번 수정의 회귀, 범위 밖 새 finding은 `NOTE [backlog]` — 재현된 데이터 손실·권한 우회·비가역 위험만 예외, `부분 해소` 2회·같은 계열 2회째면 계열 공통 원인 수정으로 전환, FIX 반복 중엔 영향 시험만·전체 시험은 게이트 닫기 전 1회). **리뷰어 중립화**: 공통 실행기 `scripts/review-run.sh`(`opencode-sol`·`opencode-build`·`codex-cli`)와 `review-wait.sh`, done 파일이 유일한 완료 근거(실제 종료 코드·RUN_ID·전후 snapshot). 프로파일 키 `reviewer`·`block-on`·`light-gate-rereview`·`root-cause`. 실패 사다리를 전역 규칙에 맞춤(원인 모를 실패 1번 → 바로 xhigh가 조사+수정, Sol 원인 조사는 `root-cause: sol`일 때만). 착수 때 사람 필요 항목 일괄 알림 1회·의존 task 뒤로 배치·대기 시각 기록. 마감마다 상태 파일 `## 시간` 한 줄과 `skill:` 버전. 정지 감시를 `scripts/herdr-stall-watch.sh`(transcript 내용으로 진척·API 재시도·blocked 구분)로. `sonnet medium`(명세가 명확한 작은 구현).
- (1.7.1) 계획 시간 상한 제거. 대신 planner가 (최초 계획이면) 코드 조사 전에 계획 뼈대를 먼저 파일로 쓰고 frontmatter 바로 다음 `진행:` 줄을 절마다 갱신하며, 조사 명령을 한 호출에 묶는다(실측: 시간 대부분이 "생각 2~4분 → grep 1개" 반복, 그동안 산출물 0).
- (1.2.0) 진행 보드와 한 줄 중간 보고를 정해진 시점에 냅니다. worker 보고서의 `- 진행:` 줄과 Sol 로그는 `Monitor`로 감시합니다.
- (1.2.0) BLOCK을 결함 계열 원장(`defect-classes.md`)에 쌓습니다. 같은 계열이 2회 나오면 위치별 수정을 멈추고 전수 점검 task로 바꿉니다.
- (1.3.0) 원인 위치가 특정된 BLOCK은 worker 없이 조정자가 직접 고치고(재현 회귀 + 영향 시험만), 재검토는 delta 검토(직전 BLOCK 해소 + 그 diff의 직접 회귀)로 받습니다. delta 밖 새 발견은 NOTE → 후속 task.
- (1.3.0) worker BLOCK 수정 지시서는 수정·재현 시험·영향 시험만 담습니다. 전수 점검·하니스 확장은 별도 task.
- (1.3.1) 국소 수정은 "코드를 읽지 않는다" 규칙의 예외로 명시. 같은 계열 2회째도 원인이 특정되면 국소 수정 먼저, 전수 점검은 마감을 막지 않는 후속 task. Sol 로그는 검토 중 `/tmp`에. 진행 보드는 웨이브·게이트·멈춤 때만, task 완료는 한 줄.
- (1.2.0) 무거운 게이트가 3회 뒤에도 BLOCK이면 계획 때 승인받은 `escalation` 사다리를 따라 진행합니다. 멈출 때는 푸시 알림을 보냅니다.
- (1.4.0) 기본 사다리 `[extra-rounds:1, carry-reversible, stop]`. 추천 수정 + delta 1회 뒤에도 BLOCK이면, 되돌릴 수 있는 제품 결함은 SHIP 없이 `carried`로 다음 웨이브에 넘기고 **조건부 마감** 절로 보고합니다. 되돌리기 어려운 대상이 걸린 BLOCK만 멈춥니다.
- (1.5.0, 1.7.0부터 프로파일 `breaker: on`일 때만) 파괴 검토 동시 실행. 같은 계열 2회째 BLOCK, 직전 수정이 만든 회귀, 공유 선택자·상태를 바꾼 수정이면 BLOCK 수정 커밋 뒤 Sol delta와 `chain-breaker`(Opus, 리포 쓰기 금지)를 같은 snapshot으로 동시에 띄우고, 둘의 결과를 한 번에 고칩니다. breaker 결함은 회차를 쓰지 않고, 판정은 여전히 Sol만 합니다.

## 프로젝트 프로파일

프로젝트 루트 `.claude/autonomous-chain.md`에 검증 명령, 병렬 상한, 커밋·push 정책, 시점별 추가 절차(`on-task-done` 등)를 둡니다. 없으면 기본값으로 동작합니다. 형식은 `skills/autonomous-chain/references/profile.md`를 보세요.

## 설치

```bash
/plugin install auto-chain@waymakerlabs-claude-plugins
```

1.0.x(`claude-autonomous-chain`)에서 옮길 때는 옛 플러그인을 지우고(`/plugin uninstall claude-autonomous-chain@waymakerlabs-claude-plugins`) 새 이름으로 설치합니다. 호출 이름이 `auto-chain:autonomous-chain`, 에이전트 접두사가 `auto-chain:`으로 바뀝니다. 이름을 바꾼 이유는 `claude-`로 시작하는 이름을 `claude plugin validate`가 예약어로 거부하기 때문입니다.

## 요구사항

- (2.3.0) 실행 단계는 3단계: ① Claude `Agent` 서브에이전트(기본, 추가 요구 없음) ② 다른 CLI의 headless 일회성 실행 ③ pane worker. ③은 이 리포의 `tools/agent-orchestrator`(설치 `tools/agent-orchestrator/install.sh` → `~/.local/bin/agent-orchestrator`)와 그것이 지원하는 오케스트레이션 툴 안에서만 쓰고, 없으면 ①·②로 내려갑니다. 툴 특이사항은 `tools/agent-orchestrator/docs/<backend>.md`
- 리뷰어 하나(2.4.0): Codex CLI(`codex exec -m gpt-6.1-sol`, 읽기 전용 샌드박스). 프로파일 `reviewer` 키는 하위 호환으로 남기되 값은 `codex-cli`만 받습니다.

## 설계

`docs/design/claude-autonomous-chain.md` (Sol 검토 기록: `docs/design/reviews/`)
