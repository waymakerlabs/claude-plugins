# S5 보고 — 전역 규칙·메모리 이관 초안 (2026-11-08)

- 브랜치 `feat/agent-orchestrator-2.3.0`, 시작 HEAD `3e9b5e5`. 로컬 커밋만, push 안 함.
- 초안: `docs/plans/2026-11-08-agent-orchestrator-rules-draft.md`
- 실제 전역 파일·메모리·HISTORY·훅·settings·`tools/**`·`plugins/**`는 고치지 않았다(세 머신은 ssh로 읽기만, `install.sh --check`만 실행).

## 1. 초안 구성

| 절 | 대상 | 내용 |
|---|---|---|
| §2 | 이 맥·office `~/.claude/CLAUDE.md` 43·49·57·81·83·94~106·108줄 | 43줄 ①~⑨ → 3단계 기준 + (가)~(자) 동작 이름. 이름 규칙·역할 접두어·모델·effort·git index 보존. 인계 절 → `tab-open`·`agent-start`·`agent-send --confirm`·`close` |
| §3 | 세 머신 `~/.codex/AGENTS.md` | codex ① 내장 서브에이전트 · ② Claude headless + done · ③ 동작 이름, 이름 규칙 |
| §4 | 홈 `~/.claude/CLAUDE.md` 3~5줄 | 이름 규칙만 |
| §5 | 뜻 보존 대조표 | ⑨·접두어·Opus 5.5 high |
| §6 | `CLAUDE_HISTORY.md` 항목 문안 | 이관 경위·백업 경로·원문 `<details>` 자리 |
| §7 | 메모리 | helpai `codex-review-partner.md`·`MEMORY.md`·`m1-autonomous-run.md`, gchat-g-on 예외 한 줄 |
| §8 | `herdr.manifest` allow 8줄 문안 | `tools/**` 수정 금지라 문안만 |
| §9·§10 | 적용 절차·시뮬레이션 | 백업 경로, 순서, 확인 방법 |

## 2. 머신별 차이 (실측)

- office CLAUDE.md: 이 맥과 다른 줄은 21(llm-wiki)·51(웹 검색 근거) 2개. 이관 대상 줄은 이 맥과 `diff` 0이라 같은 블록을 같은 줄 번호에 적용한다.
- 홈 CLAUDE.md: 5줄(이름 규칙 한 절뿐). CLAUDE_HISTORY·`~/.claude/archive` 없음.
- AGENTS.md 이름 규칙 줄은 세 머신이 같은 문장이다. 다른 점은 `## herdr` 머리 줄의 유무뿐이다(이 맥 없음, office 25줄, 홈 9줄).

## 3. 잔존 수 (`install.sh --check herdr`)

| 머신 | 지금(마켓플레이스 2.2.2 사본 기준) | 시뮬레이션: 초안 적용 + 2.3.0 브랜치 | + §8 allow 8줄 |
|---|---|---|---|
| 이 맥 | 134 (CLAUDE 13 · AGENTS 1 · auto-chain 120) | **28** (CLAUDE 0 · AGENTS 0 · auto-chain 28) | **0** |
| office | 135 (13 · 2 · 120) | **28** (0 · 0 · 28) | **0** |
| 홈 | 124 (2 · 2 · 120) | **28** (0 · 0 · 28) | **0** |

- 시뮬레이션 방법: ssh로 읽은 원본 사본(`/tmp/s5/`)에 초안 울타리 블록을 그대로 대체해 가짜 HOME을 만들고, 개발 리포 `lib/manifest.py check`를 `HOME=가짜`·`AO_REPO=개발 리포`로 실행했다. 가짜 HOME이라 hook·setting 항목은 "필수 2/6"으로 나오는데, 이건 잔존 계산과 상관없다. 적용 뒤 파일의 herdr 문자열은 6파일 모두 0이다.
- 남는 28건은 auto-chain 2.3.0의 시험 하니스 20건과 래퍼·포인터·호환 주석 8건이다. 계획 §3·S4 보고서 허용 목록과 같은 종류인데, manifest에 `allow`가 없어서 S6 종료 조건("allow 외 0")을 채우려면 §8 allow를 브랜치에 넣어야 한다.
- 메모리 변경안(§7-1~7-3)도 같은 방식으로 적용해 보았다. helpai 3파일의 herdr 문자열은 0이 된다. 치환 대상 원문(`herdr pane run <id> `, m1 괄호 구절)은 각각 1회만 나와 유일하다.
- 줄 수: CLAUDE.md 이 맥·office 116 → 115, 홈 5 / AGENTS.md 이 맥 8 → 9, office 27, 홈 11.

## 4. 확인이 필요한 지점 (뜻이 달라질 수 있는 곳 — 결론 없이 나열)

1. 이름 규칙 동작 공백: `self-name`은 "비었거나 ASCII만"일 때만 이름을 바꾼다(`adapters/herdr.sh:192`). 그래서 ⓐ 옛 규칙의 "pane label이 **없으면**"보다 범위가 넓고 ⓑ "주제가 크게 바뀌면 다시 바꾼다"에 해당하는 강제 rename 동작이 없으며 ⓒ 탭 label 조회 동작도 없다. 초안은 `docs/<backend>.md` 「이름」 항목을 가리키게 했지만, 지금 그 문서에는 자기 탭 rename 명령이 없다.
2. 홈 CLAUDE.md에는 3단계 기준을 넣지 않았다. 원래 없던 규칙을 새로 넣는 일이라서다.
3. office gira 메모리 `herdr-parallel-agents.md`("구현 작업은 `Agent` 대신 herdr 패널", 2026-11-06)는 새 3단계 기준과 정면으로 어긋난다. 계획 §0·§3 범위 밖이라 변경안은 쓰지 않았다. office legacy-lens 5파일·gira 3파일에도 herdr 서술이 있다.
4. `herdr.manifest` allow 8줄(§8)은 `tools/**`에 속해 S5에서 수정할 수 없다.
5. 루트 `README.md:466`·`docs/auto-chain-guide.html`의 herdr 서술(S4에서 넘겨받은 것)은 manifest 검사 범위 밖이다.

## 5. codex 크로스체크 때 볼 위험 지점 (위치만)

- 초안 §2-1 `claude-43` 블록 전체: 옛 ①~⑨와 새 (가)~(자)의 대응, auto-chain `SKILL.md` §1-1(22~33줄)·`references/pane-worker.md` §0~§1과의 일치
- §2-1 (아)·§3·§4 이름 규칙과 `adapters/herdr.sh:192~216`(`self-name`) 실제 동작
- §2-5 `claude-94` 인계 블록과 계획 §1-2 `agent-send --confirm`·`tab-open`·`list` 계약, 그리고 「후속 세션 인계 프로토콜」 공통 규칙 1~6
- §2-5 옛 작은따옴표 `$HERDR_PANE_ID` 서술을 고친 부분
- §3 codex ② 예시 명령(`claude -p … ; echo exit=… > done`)과 auto-chain `headless-run.sh` done 형식
- §6 HISTORY 항목의 백업 경로가 §9 절차와 일치하는지
- §8 allow 8줄의 selector 범위(`grep:herdr` 파일 전체 허용 vs 문자열 한정)
- §9 적용 순서, 그리고 스냅샷 sha256 대조로 줄 번호가 밀린 것을 잡아내는 방법
- §7-1 helpai 메모리: D1(`review_view: pane` 유지)과 auto-chain 2.3.0 `sol-review.md` pane 경로

## 6. 커밋

- 로컬 커밋 1개(이 보고와 초안). 해시는 `git log -1 -- docs/plans/2026-11-08-agent-orchestrator-S5-report.md`로 확인하고 부모 보고에도 적는다. push 안 함.
- 원본 무변경 확인: 이 맥 대상 6파일의 sha256이 착수 때와 같다(커밋 직전 재측정).
