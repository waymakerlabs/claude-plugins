# 인계 — 자율체인·리뷰체인 발표자료 재작성

- 작성: 2026-11-10, 부모 세션 pane `w8:p1`(탭 `w8:t1`) — **부모 pane을 닫지 말 것**(주인님과 대화 중)
- 저장소: `/Users/peter/Dev/waymakerlabs-claude-plugins`, branch `main`, HEAD `950f04d`, origin/main과 같음(push 완료). `git status`에는 이 인계 문서 하나만 untracked로 있다 — 이 세션 커밋에 함께 넣는다
- 배포: 세 머신(이 맥·office·홈) 마켓플레이스 HEAD `950f04d`, 플러그인 auto-chain 2.6.0·review-chain 0.1.4, 전역 스킬 `pane-worker`·`session-handoff` md5 동일

## 목표

`docs/` 아래 발표자료를 **현재 구조 그대로** 보여주게 만든다. 주인님 결정: 옛 운영 가이드는 보관하고 새로 쓴다. 기존 자료(그림·표·용어집)는 최대한 다시 쓴다.

1. `docs/auto-chain-guide.html`(auto-chain 1.1.0 기준, Orca 서술 약 20곳) → `git mv`로 `docs/archive/auto-chain-guide-1.1.0.html`. 보관본 상단에 "옛 버전, 최신은 <새 파일>" 한 줄만 추가.
2. 같은 경로 `docs/auto-chain-guide.html`에 **발표자료**를 새로 쓴다. 담을 것:
   - 전체 그림: 자율체인(큰 작업, 마일스톤→웨이브→task)과 리뷰체인(QC 수정 병렬, OC 1 + worker 최대 4)의 역할과 관계(승격)
   - 자율체인 2.6.0: 구조·한 마일스톤 흐름·모델/effort 배정 표·Sol 게이트(codex CLI)·실패 사다리·인계
   - 리뷰체인 0.1.4: launch(새 탭 OC)·범위 자동 선점(`rc-claim.sh`)·worktree 커밋과 OC 병합·받은편지함 메시지·모델 배정
   - agent-orchestrator 계층: 동작 목록(받은편지함 `inbox-send`/`inbox-watch` 포함), 종료 코드, herdr 어댑터
   - 세션 간 메시지 원칙(2.6.0): 이미 첫 지시를 받은 세션 입력창에는 아무것도 쳐 넣지 않는다. 계기(office gira에서 마일스톤 조정자가 부모 세션 입력창에 답을 넣음)와 해결(받은편지함 + Monitor, 체인 고정 조정자 주소, 인계 동결, flock 잠금)
3. `docs/autonomous-chain-overview.html`: 바뀐 부분만 고친다 — 기준 버전 2.6.0, agent-orchestrator 동작 목록에 inbox 동작, 메시지 절(현재 `agent-send`로 보고한다고 적힌 곳), 리뷰체인·새 발표자료 링크.

## 진본 (사실은 여기서만 가져온다)

- auto-chain: `plugins/auto-chain/skills/autonomous-chain/SKILL.md`(모델 표 54~66줄 부근, 「세션 간 메시지」절), `references/pane-worker.md`, `references/task-brief.md`, `agents/*.md` frontmatter
- review-chain: `plugins/review-chain/skills/review-chain/SKILL.md`, `references/*.md`(messages·launch·oc-handover·worker-brief·state-files)
- agent-orchestrator: `tools/agent-orchestrator/bin/agent-orchestrator` 머리 주석, `docs/plans/2026-11-08-agent-orchestrator-plan.md` §1(계약), `tools/agent-orchestrator/docs/herdr.md`
- 이번 변경 경위: `~/.claude/plans/2026-11-10-inbox-messaging.md`, `git log c7b0939..950f04d`
- 문서에 버전·모델·명령·수치를 적을 때마다 위 파일에서 대조한다. 기억으로 쓰지 않는다.

## 작업 방식

- 발표자료다: 그림(mermaid 등 기존 HTML이 쓰는 방식)·표 위주, 한 화면에 한 주제. 기존 두 HTML의 CSS·라이트/다크 토큰을 그대로 쓴다. 외부 스크립트는 기존 파일이 쓰는 것과 같은 CDN·버전만.
- **큰 파일은 한 번에 쓰지 않는다.** 한 번의 Write·Edit는 약 150줄·8KB 이하. 뼈대(절 제목·CSS)를 먼저 Write하고 절마다 Edit로 채운다. 서브에이전트에 맡기면 지시서에도 이 줄을 넣는다.
- 회사·개인 식별 정보(gira 내부 호스트·경로·티켓 키)는 overview처럼 일반화한다.
- 렌더 확인: `ego-browser` 스킬로 두 파일을 열어 라이트·다크, 좁은 폭(390px)에서 깨짐이 없는지 본다(스크린샷 근거를 보고에 붙인다).

## 수정 가능 파일 · 권한

- 수정: `docs/auto-chain-guide.html`(새로 씀), `docs/archive/auto-chain-guide-1.1.0.html`(옮긴 보관본, 상단 한 줄만), `docs/autonomous-chain-overview.html`. 그 밖은 건드리지 않는다.
- 커밋: 이 세션이 경로를 지정해 커밋해도 된다(`git add -A`·`.` 금지). **push는 하지 않는다** — 끝나면 주인님께 push 여부를 묻는다.
- 크로스체크: 문서 작업이라 의무 없음. 대신 사실 대조 결과(버전·모델 표·명령 이름)를 보고에 표로 붙인다.

## 멈춤 예외

진본 문서끼리 서로 다르면(예: 모델 표가 SKILL.md와 agents frontmatter에서 다름) 추측으로 맞추지 말고 주인님께 묻는다.

## 끝나면

1. 이 탭에서 주인님께 보고한다(바뀐 파일, 커밋 해시, 렌더 확인 근거, push 대기).
2. 부모에게 한 줄: `~/.local/bin/agent-orchestrator inbox-send w8:p1 "[발표자료] 완료 <커밋 해시> — push 대기"`. 부모 입력창에 `agent-send`로 쓰지 않는다.
