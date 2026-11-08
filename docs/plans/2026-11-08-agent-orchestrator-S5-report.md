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

## 6. 1회차 크로스체크 반영

- 리뷰어 codex Sol high, 판정 **BLOCK** — BLOCK 3 · NOTE 4(`/tmp/xc-result-20261108-182002.md`). 지시서 `docs/plans/2026-11-08-agent-orchestrator-S5-fix-brief.md`대로 모두 반영했다.
- **BLOCK 1·2 + NOTE 1 (이름 계약)** — `tools/**` 변경(문서 변경과 독립):
  - `adapters/herdr.sh`: ASCII 기본값 판정(`AO_ASCII_RE`)을 없앴다. `self-name`은 대상마다 현재 label로 판정한다 — 빈 값·숫자만이면 인자 그대로, 이미 `[XX] ` 접두어면 유지(stderr 경고), 그 밖(사용자 이름, 영문·한글 무관)은 본문을 두고 인자의 접두어만 앞에 붙인다(인자에 접두어가 없으면 유지). `--force`는 판정 없이 바꾼다. `whoami --field tab-label|pane-label`은 현재 label을 한 줄로 읽는다(없으면 빈 출력).
  - `bin/agent-orchestrator`: `self-name [--force]`와 `--field tab-label|pane-label`의 인자 검사, 머리 주석을 고쳤다. 종료 코드는 기존 0·2·3·4 안에서 쓴다.
  - `docs/herdr.md` 「이름」, `adapters/README.md`를 새 계약으로 고쳤다.
  - 시험: `self-name`·`self-name-calls`·`self-name-keep`의 이름은 그대로 두고 기대값만 바꿨다. 새 케이스는 `self-name-numeric`·`-user-en`(`Peter review`)·`-user-ko`(`헬프AI`)·`-noprefix-arg`·`-force`, `arg-self-name-force-only`·`-bad-opt`, `whoami-tab-label`·`-pane-label-empty`·`-tab-label-missing`이다. 가드 제거 시 실패 증명 `neg-self-name-user-guard`: `GUARD:user-name` 줄을 지운 사본은 `Peter review` → `[OC] 새 작업`으로 본문을 바꾼다. 이 조건이면 `self-name-user-en`이 FAIL한다. `EXPECT` 123 → 134, 결과는 134/134 PASS다.
  - `manifests/herdr.manifest`: §4-4의 allow 8줄을 반영했다(`/tmp/s5/herdr-allow.manifest`와 `diff` 0).
- **초안 반영**:
  - BLOCK 1·2: `claude-43` (아), `codex-bullets`, `home-claude-3`의 이름 문안을 새 `self-name`·`--force`(현재 이름을 이 세션이 붙였을 때만)·`whoami --field tab-label|pane-label` 계약으로 바꿨다. "사용자 이름은 본문 두고 접두어만" 문장은 그대로 두었다. §5 대조표의 차이 칸도 새 계약에 맞췄다.
  - NOTE 1: 이름 확인을 탭·pane 둘 다 `whoami --field tab-label`/`pane-label`로 한다.
  - BLOCK 3: `mem-helpai-crp-21`의 첫 단계에서 같은 셸에 `AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}`를 정의하고, 이후 3·5단계는 `"$AO"`를 쓴다. 전수 확인 결과 `"$AO"`를 쓰는 블록은 모두 같은 블록(또는 같은 파일의 바로 앞 bullet) 안에 `AO=` 정의가 있다. 대상은 `claude-43`·`claude-94`·`codex-bullets`·`home-claude-3`·`mem-helpai-crp-21`/`-26`이고, 7-1의 22줄 치환은 21줄 정의 다음에 온다.
  - NOTE 2: `codex-bullets`에 ③→① 폴백 시 "인계 전 완료·회수"를 넣었다(SKILL.md §1-1과 같다).
  - NOTE 3: HISTORY 문안의 "세 머신 같게"를 실제 범위로 고쳤다(이 맥·office는 전체, 홈 CLAUDE.md는 이름 규칙만, AGENTS.md는 세 머신, office gira 메모리는 **주인님 결정 대기**).
  - NOTE 4: `/tmp/s5/sim.py`를 고쳤다. 울타리 내용을 그대로 보존하고 마지막 개행 하나만 떼어, `codex-office-home-head`의 빈 줄을 유지한다. 다시 돌린 실측 줄 수는 CLAUDE.md 이 맥·office 115, 홈 5 / AGENTS.md 이 맥 9, office **28**, 홈 **12**다. §9의 줄 수를 이 값으로 바꿨으므로, 이 보고 §3의 "office 27, 홈 11"은 이 값으로 대체한다.
- 시뮬레이션 재실행: 6파일의 herdr 문자열은 모두 0이다(새 문안의 "herdr 기본 번호"는 "툴 기본 번호"로 고쳤다). 리포의 manifest(allow 8줄 포함)로 `lib/manifest.py check`를 돌리면 세 머신 모두 `rule 잔존 0건(allow 제외)`이다.
- 실제 herdr 읽기 확인: 아래 「실측」 줄에 적는다.
- 실측(이 herdr pane, 읽기만 — rename·pane 생성 없음): `whoami --field tab-label` → `[OC] 논의`, `--field pane-label` → `[OC] 논의 메인`(둘 다 rc 0).
- 확인: `tools/agent-orchestrator/test/run-tests.sh` 134/134 PASS(총계 = EXPECT), auto-chain `scripts/test/run-tests.sh` 90/90 PASS. auto-chain 스크립트는 `self-name`을 부르지 않는다(scripts grep 0건). shellcheck 0건.
- 남은 문제: auto-chain `references/pane-worker.md:46`의 `self-name` 설명이 옛 계약("번호·영문 기본값일 때만")으로 남아 있다. `plugins/**`는 이번 수정 범위 밖이라 고치지 않았다.

## 7. 2·3회차 크로스체크 (메인 기록)

- 리뷰어 codex Sol high. 무거운 게이트(최대 3회).
- 2회차 `BLOCK`: 1회차 7건 중 6건 해소, BLOCK 2는 부분 해소 — 사용자 탭은 두고 pane만 `--force` 할 계약이 없었다. NOTE 1건(pane-worker.md "herdr 기본 이름" 잔존).
- 반영: `self-name` 대상 자리에 `-`를 넘기면 그 대상을 건너뛴다(둘 다 `-`면 2). tools `2b84fed`(main `c0ff883`, 세 머신 배포 확인), 문서 `25d5973`. 시험 tools 137/137(건너뛰기 가드를 지우면 `self-name-skip-tab` FAIL 확인), auto-chain 90/90.
- 3회차 **`SHIP`**: 2회차 BLOCK·NOTE 모두 해소, 새 finding 0.
- 남은 결정: office gira 메모리 `herdr-parallel-agents.md`("구현은 pane", 2026-11-06) 처리 — 주인님 결정 대기. S6 적용 전에 확정한다.
