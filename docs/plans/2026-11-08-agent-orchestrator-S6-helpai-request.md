# helpai `chain-guide.md` 반영 요청 — agent-orchestrator S6 (계획 §5-4)

- 요청: agent-orchestrator S6 세션(2026-11-08). 대상 소유자: helpai 조정자(M1-11 W2 재시작 세션) 또는 주인님이 승인한 세션.
- 전제: auto-chain **2.3.0**이 이 맥·office에 설치됨(`installed_plugins.json` 2.3.0, 캐시 `…/auto-chain/2.3.0`). 전역 `~/.claude/CLAUDE.md`는 「worker 실행 3단계」 규칙으로 바뀜(2026-11-08 (5) 이력 항목).
- 옛 경로(`scripts/herdr-spawn-worker.sh`·`herdr-stall-watch.sh`·`references/backend-herdr.md`)는 2.3.x 동안 래퍼·포인터로 남아 있어, 가이드를 고치기 전에도 깨지지 않는다. 다만 2.2.0 캐시 경로를 직접 가리키는 리뷰 스크립트 호출은 2.3.0 경로로 바꿔야 새 정책을 쓴다.

## 바꿀 곳 (`docs/milestones/M1-mvp/chain-guide.md`, 202줄 기준)

1. **39~45줄 실행 수단 표·기본 문장** → 3단계 기준. ① 구현·수정·계획 초안 worker = `Agent` 서브에이전트(`subagent_type: helpai-worker`, `run_in_background: true`) 기본 ② 다른 CLI는 headless 일회성 + done 파일 ③ pane worker는 주인님이 지켜볼 작업·도중 대화·메인보다 오래 사는 작업(인계를 넘겨 사는 planner 포함)만. 45줄의 "herdr 안 기본은 pane worker" 문장을 대체.
2. **46줄** `herdr-spawn-worker.sh` → `spawn-pane-worker.sh`(③일 때만). 인자 형식은 같다(auto-chain 2.3.0 `references/pane-worker.md`).
3. **47줄 대리 보고 ID**: pane worker는 `~/.local/bin/agent-orchestrator agent-session-id <이름>`(UUID — 기존 Q24 `session:<UUID>`와 같은 값). Agent worker 값은 helpai가 정한다(D8 제안 `agent:<agentId>`).
4. **51줄 정지 판정**: transcript 경로는 `agent-orchestrator agent-transcript <이름>`, 세부는 `tools/agent-orchestrator/docs/herdr.md`.
5. **70줄 codex 리뷰 pane**: `herdr pane split`/`pane run` → `agent-orchestrator pane-open "[RV] …" --cwd <리포>` / `pane-run`. 프로파일 `review_view: pane` 유지(D1 — helpai가 재판단). 리뷰 스크립트 경로는 2.3.0 캐시로.
6. **88줄** "Orca 탭으로 대신 열지 않는다" → "③을 쓸 수 없으면(`agent-orchestrator backend`가 10·11·12) 인계 문서만 남기고 주인님께 다음 세션 프롬프트를 드린다".
7. **158~166줄 인계 명령** → 동작 이름: `ROOT=$("$AO" tab-open "[OC] 헬프AI <마일스톤>" --cwd "$PWD")` → `"$AO" agent-start <이름> "$ROOT" --kind claude -- <같은 플래그>` → `"$AO" agent-send <이름> "<handoff>를 읽고 그대로 진행해. 부모 pane: $("$AO" whoami)" --confirm`(출력 working|done = 인계 증거) → child가 `"$AO" close <부모 pane>`. `AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}`.
8. 6줄 참고의 auto-chain 버전 표기 2.x → 2.3.0 확인.

## 반영 뒤 확인

- `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins/tools/agent-orchestrator/install.sh --check herdr`는 전역 파일만 보므로, 가이드는 `grep -n -i herdr docs/milestones/M1-mvp/chain-guide.md`로 남은 곳이 역사 서술뿐인지 본다.
- 다음 helpai 웨이브에서 ① Agent worker 기동·회수 1회, 인계 ③ 1회 성공 증거를 progress에 남긴다(계획 §5-4 6번 — agent-orchestrator 쪽 S6 종료 조건).
