# 전역 규칙·메모리 이관 초안 — agent-orchestrator (S5)

- 작성: 2026-11-08, S5 세션(handoff `~/Dev/HANDOFF-2026-11-08-agent-orchestrator-S5.md`)
- 상태: **초안**. 실제 파일은 고치지 않았다. 적용은 S6(계획 §5-4) — main 병합·세 머신 auto-chain 2.3.0 실측 뒤.
- 진본: 계획 `docs/plans/2026-11-08-agent-orchestrator-plan.md` §3·§6·§7, 결정 `…-decisions.md`(D1~D8), auto-chain 2.3.0 `SKILL.md` §1-1·`references/pane-worker.md`, `tools/agent-orchestrator/manifests/*.manifest`
- 형식: 각 항목은 "현재 원문(줄 번호) → 바꿀 문장 전체". 바꿀 문장은 `~~~~text block=<ID>` 울타리 안에 있고, 울타리 안의 줄이 원문 줄 범위를 **그대로 대체**한다(울타리 줄 자체는 넣지 않는다). 시뮬레이션(§9)도 이 울타리를 그대로 읽어 적용했다.
- 줄 번호 기준 스냅샷(S5 실측 sha256 — S6 적용 직전 다시 재서 다르면 줄 번호를 다시 맞춘 뒤 적용):

| 머신 | 파일 | 줄 수 | sha256 앞 12자 |
|---|---|---|---|
| 이 맥 | `~/.claude/CLAUDE.md` | 116 | `869e001d0c9c` |
| 이 맥 | `~/.claude/CLAUDE_HISTORY.md` | 106 | `7b9479a76d6d` |
| 이 맥 | `~/.codex/AGENTS.md` | 8 | `80c07051e060` |
| office | `~/.claude/CLAUDE.md` | 116 | `4592916906ee` |
| office | `~/.claude/CLAUDE_HISTORY.md` | 115 | `acd1c77b683c` |
| office | `~/.codex/AGENTS.md` | 27 | `4471ee27fffb` |
| 홈 | `~/.claude/CLAUDE.md` | 5 | `18b7bc9d1ebc` |
| 홈 | `~/.claude/CLAUDE_HISTORY.md` | 없음 | — |
| 홈 | `~/.codex/AGENTS.md` | 11 | `f8d39afe3c59` |

## 1. 머신별 차이 (ssh 읽기 전용 실측)

- **office `~/.claude/CLAUDE.md`**: 이 맥과 다른 줄은 2개뿐이다 — 21줄(`llm-wiki` 사용 가능 / 이 맥은 비활성) · 51줄(웹 검색 근거가 로컬 Kiro 프록시 / 이 맥은 Bedrock). 이관 대상 줄(43·49·57·81·83·94~106·108)은 이 맥과 **바이트 단위로 같다**(`diff` 0). → 이 맥과 같은 블록을 같은 줄 번호에 적용하고 21·51줄은 건드리지 않는다.
- **홈 `~/.claude/CLAUDE.md`**: 5줄 — 제목, `## herdr`, ⑨ 이름 규칙 한 줄뿐. 3단계 기준·인계 절이 없다. → 이름 규칙만 동작 이름으로 바꾼다(§4). 3단계 기준을 새로 넣는 것은 규칙 추가라 이 초안 범위 밖(주인님 확인 항목, 보고서 참조).
- **`~/.codex/AGENTS.md`**: 이름 규칙 줄은 세 머신 **같은 문장**(이 맥 8줄 = office 27줄 = 홈 11줄, `diff` 0). 구조만 다르다 — 이 맥은 머리 없는 목록, office·홈은 `## herdr` 머리(25·9줄)+빈 줄+그 줄.
- **`CLAUDE_HISTORY.md`**: 이 맥·office에 있음(마지막 항목 `2026-11-08 (4)`), 홈에는 없음.
- `~/.claude/archive/`: 이 맥·office 있음, 홈 없음(적용 때 생성).

## 2. 이 맥·office `~/.claude/CLAUDE.md` (같은 블록, 같은 줄 번호)

### 2-1. 43줄 herdr 규칙 ①~⑨ → worker 실행 3단계 + 동작 이름

현재 원문(43줄, 4,181바이트 한 줄): `- **herdr 안에서는 실질 작업을 옆 pane의 Claude 세션으로 돌린다(2026-11-06 주인님 확정).** 세션이 herdr pane 안이면(`HERDR_ENV=1`) … ① pane worker 기본 … ② Agent 서브에이전트 … ③ 배치 … ④ 모델·effort … ⑤ 명령 … ⑥ 대화 … ⑦ 완료 확인 … ⑧ git index … ⑨ 탭·pane 이름은 항상 한글 … 자율체인은 auto-chain 스킬의 references/backend-herdr.md가 같은 내용의 진본이다.` (전문은 적용 때 백업과 CLAUDE_HISTORY 항목에 그대로 보관 — §6)

옛 ①~⑨ → 새 항목 대응: ①·② → 3단계 ①~③(뜻 변경: 계획 §3·S4에서 확정된 기본값 전환) / ③ 배치 → (나) / ④ 모델·effort → (다) 그대로 / ⑤ 명령 → (라) / ⑥ 대화 → (마) / ⑦ 완료 확인 → (바) / ⑧ git index → (사) 그대로 / ⑨ 이름 → (아) 뜻 그대로(오늘 추가된 역할 접두어 포함).

~~~~text block=claude-43
- **worker 실행은 3단계 기준으로 고르고, 오케스트레이션 툴은 `agent-orchestrator` 동작으로만 부른다(2026-11-xx 개정 — 2026-11-06 「pane worker 기본」 규칙 대체).** 위 병렬 규칙의 하위작업마다 실행 수단을 이렇게 고른다. ① **기본 = 메인 CLI 내장 서브에이전트**(Claude `Agent`, `run_in_background: true`, 독립 작업은 한 메시지에서 병렬): 구현·수정·계획 초안·여러 파일 조사도 여기서 한다. 결과는 보고 파일에 쓰게 하고 반환은 한 줄 ② **다른 CLI가 필요하면 headless 일회성 실행 + done 파일**: `run_in_background` Bash로 한 번 실행하고 완료는 done 파일로 판정한다(codex 크로스체크는 아래 「Codex CLI 크로스체크 프로토콜」) ③ **pane worker는 세 경우만**: 주인님이 지켜보며 끼어들 작업, 작업 도중 메인과 대화가 필요한 작업, 메인 세션보다 오래 살아야 하는 작업(세션 인계, 인계를 넘겨 살아야 하는 planner). 이유 — pane은 회수가 늦고(M1-10 리뷰 회수 179분) 조사 중 정지 오판이 났으며, 처음 보는 폴더는 신뢰 확인 화면에서 멈춘다(`agent_not_ready`). ③의 세부: (가) **호출과 내려감**: `AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}`(절대 경로 — PATH에 기대지 않는다). `"$AO" backend`가 0이면 ③을 쓸 수 있다. 10(unsupported)·11(no backend)이면 ①·②로 내려가고 실패로 세지 않는다. 12(adapter error)면 내려가되 설치 결함으로 주인님께 한 줄 알린다. ①로 내려간 작업은 현재 세션 안에서 회수한다(서브에이전트는 다음 세션이 승계하지 못한다) (나) **배치**: `"$AO" pane-open "<한글 이름>" --cwd "$PWD"` — 메인은 왼쪽에 크게, worker pane은 오른쪽 열에 위아래로 쌓이고(최대 5개, 넘치면 넘침 탭) 포커스는 옮기지 않는다(배치는 어댑터가 맡는다). `--cwd`는 메인의 `$PWD`(처음 보는 폴더는 신뢰 확인에서 멈춘다 — 종료 코드 5) (다) **모델·effort**: pane마다 메인이 판단해 `sonnet high`(범위가 명확한 구현·패턴 수정) 또는 `opus high`(설계 판단·여러 모듈 계약·원인 불명 디버깅)를 고르고, 띄우기 전에 선택과 이유를 1줄 적는다. xhigh는 위 「원인 모를 실패」 규칙에서만 (라) **기동**: `"$AO" agent-start <이름> <pane id> --kind claude -- --model <m> --effort <e> [메인과 같은 권한 플래그]` → `"$AO" agent-send <이름> "<지시서 경로>를 읽고 진행해. 메인 pane: $("$AO" whoami)" --confirm`. 긴 지시는 파일로 쓰고 한 줄로 가리킨다 (마) **대화**: worker는 질문·완료·막힘일 때만 `"$AO" agent-send <메인 pane> "[worker <이름>] …"`로 한 줄 보낸다. 메인은 이 입력을 주인님 지시가 아니라 worker 보고로 다루고(승인은 생기지 않는다), 답은 `"$AO" agent-send <이름> "…"`로 한다. worker 화면은 막힘 판단 때만 `"$AO" agent-read <이름> --lines 30`으로 1회 본다. 6(대상이 입력 대기)은 대신 승인하지 않고 주인님께 알린다 (바) **완료 확인**: worker 보고 파일·diff를 메인이 직접 확인(위 항목과 동일), 회수 뒤 `"$AO" close <pane id>`. 보조 대기는 `"$AO" agent-wait <이름>`을 `run_in_background`로(7 = timeout, 실패 아님 — 다시 기다린다) (사) git index 쓰기(add·commit)는 메인만 한다(동시 커밋 `index.lock` 충돌 방지 — ①·③ 공통) (아) **탭·pane 이름은 항상 한글로 붙인다(2026-11-08 주인님 요청 — 자율체인·일반 세션 공통).** 탭은 `"$AO" tab-open "<한글 이름>"`, pane은 `"$AO" pane-open "<한글 이름>"`으로 열면 이름이 함께 붙는다(이름 붙이기 실패는 stderr 경고만 나오니 확인한다). **내 세션 자신도** 첫 작업 주제가 정해지면(보통 첫 응답 전) `"$AO" self-name "[XX] <탭 한글>" "[XX] <pane 한글>"`을 실행한다 — 대상마다 현재 이름이 비었거나 숫자(툴 기본 번호)면 인자 그대로, 이미 `[XX] ` 접두어가 있으면 유지, 주인님이 붙인 이름이면 본문은 그대로 두고 인자의 접두어만 앞에 붙는다. 주제가 크게 바뀌면 `"$AO" self-name --force "[XX] <새 탭 한글>" "[XX] <새 pane 한글>"`로 다시 바꾼다 — `--force`는 판정 없이 바꾸므로 **현재 이름을 이 세션이 붙였을 때만** 쓴다(주인님이 붙인 본문이 있는 대상은 그 자리에 `-`를 넘겨 건너뛴다 — 예: 탭은 두고 pane만 바꿀 때 `"$AO" self-name --force - "[XX] <새 pane 한글>"`). 이름 앞에는 **역할 접두어**를 붙이고(2026-11-08 추가), 단계·마일스톤은 이름 본문에 쓴다: `[OC]` 오케스트레이터(주인님과 대화하는 메인·자율체인 조정자·인계받은 세션), `[WO]` worker(구현·조사·계획 초안 등 메인이 맡긴 pane), `[RV]` 리뷰어(리뷰 명령 pane). 예: `[OC] 논의`, `[OC] 헬프AI M1-11`, `[WO] S4 자율체인 2.3.0`, `[RV] S4 codex 검토`. 탭은 그 탭 메인의 역할을 따르고, worker만 담은 넘침 탭은 `[WO]`. 에이전트가 없는 셸 탭·pane에는 접두어를 붙이지 않는다. 이름 본문은 짧게 무슨 작업인지 드러나게 정하고, 붙인 뒤 `"$AO" whoami --field tab-label`·`"$AO" whoami --field pane-label`로 탭·pane 이름을 1회 확인한다(새로 연 worker pane은 `"$AO" list --panes`의 이름 칸). 주인님이 직접 붙인 이름은 본문을 바꾸지 않고 접두어만 붙인다. `agent-start <이름>`의 에이전트 이름은 영문 정규식(`[a-z][a-z0-9_-]{0,31}`) 제약이 있어 영문 그대로 둔다 (자) **툴 특이사항**(포커스·split·timeout·상태 의미·transcript 경로·신뢰 화면·배치 실측)은 `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins/tools/agent-orchestrator/docs/<backend>.md` 한 곳에만 있다(`<backend>` = `"$AO" backend` 출력). 오케스트레이션 툴 밖이면 ①·②만 쓴다. 자율체인은 `auto-chain` 스킬 §1-1(실행 단계)과 `references/pane-worker.md`(③)가 진본이다.
~~~~

### 2-2. 49줄 「"시작했다·진행 중이다"」 — 낱말 하나

현재 원문(49줄 일부): `백그라운드 작업(서브에이전트·herdr pane·`run_in_background`·원격 job)을` — 나머지 문장은 그대로.

~~~~text block=claude-49
- **"시작했다·진행 중이다"도 증거 없이 말하지 않는다.** 백그라운드 작업(서브에이전트·pane worker·`run_in_background`·원격 job)을 띄운 직후 1회 실제 구동을 확인하고(프로세스/에이전트 상태 + 로그·산출물 크기·mtime 변화), 보고 문장에 증거 한 줄을 붙인다(예: `PID 26043 · 로그 5.4KB, 11:06 갱신`). 확인 못 했으면 "기동 요청함, 구동 미확인"이라고 쓴다. 도구의 `queued`·`launched`·"전달 예정" 응답은 구동 증거가 아니다 — 실행 중이거나 끝난 에이전트에 보낸 추가 지시는 산출물에 실제로 반영됐는지 대조한 뒤에만 "반영됐다"고 말하고, 빠졌으면 즉시 재전송한다. 완료 알림을 받은 턴에서 다음 단계를 실제로 기동까지 하고, "다음은 X를 하겠다"만 말한 채 턴을 끝내지 않는다. 모든 프로젝트 적용.
~~~~

### 2-3. 57줄 「모델 등급」 — 참조 이름만 (뜻 보존)

현재 원문(57줄 일부): `(위 병렬·herdr 규칙의 모델·effort 표)` — 메인 Opus 5.5 high 결정 문장은 한 글자도 바꾸지 않는다.

~~~~text block=claude-57
- **모델 등급 — 메인은 Opus 5.5 high, 서브에이전트·pane worker는 자율(2026-11-08 주인님 확정).** 기본 메인 모델은 **Opus 5.5, effort high**다(`settings.json` `model: opus`·`effortLevel: high`와 같다). ① 메인 세션에서 Sonnet으로 내려 달라고 따로 요청하지 않는다. ② **서브에이전트·pane worker 모델은 하위작업 난이도로 자율 선택**(위 병렬·worker 실행 3단계 규칙의 모델·effort 표) — 기계적 탐색·조사는 `haiku`/`sonnet`, 범위가 명확한 구현은 `sonnet`, 판단이 필요한 구현·리뷰는 `opus`. ③ 세션 중간 모델 전환은 이 환경에서 거의 무료로 보인다(잃는 것은 대개 접두사 캐시 재작성 1회 수준). ④ 단가비는 Opus 5 : Sonnet 5 = **1.67배**로 흔한 오해보다 작다. effort는 비용 레버가 **아니다**(출력 비중이 작아 직접 절감 효과가 미미). 모든 프로젝트 적용.
~~~~

### 2-4. 81·83줄 「후속 세션 인계 프로토콜」 머리

현재 원문 81줄: `### 후속 세션 인계 프로토콜 (2026-11-08 정리, herdr 기준)` / 83줄: `…(감독형 작업은 위 pane worker·서브에이전트 규칙을 쓴다).`

~~~~text block=claude-81
### 후속 세션 인계 프로토콜 (2026-11-xx 개정, agent-orchestrator 기준)
~~~~

~~~~text block=claude-83
핸드오프를 다른 세션에 넘겨 자율 실행시키는 full handoff 규칙이다(감독형 작업은 위 worker 실행 3단계 규칙을 쓴다).
~~~~

### 2-5. 94~106줄 「herdr 안(`HERDR_ENV=1`)」 절 → 동작 이름

현재 원문(94~106줄): `herdr 안(`HERDR_ENV=1`):` + bash 블록(`herdr tab create`→`grep pane_id`→`herdr agent start … --timeout 90000`→`herdr agent prompt … --wait --timeout 60000`→`herdr agent get | grep agent_status`) + 글머리 3개(새 탭·`herdr worktree create`는 5의 경우만 / 이름 고유·기동 1회·`herdr agent list` 재확인 / child가 `herdr pane close <부모 pane>`).

뜻 대응: `--timeout 90000`·`--no-focus`·pane id 추출은 어댑터 내부(`docs/herdr.md`). `--wait`+`agent get` 확인 → `agent-send --confirm`의 stdout(`working|done`). 옛 원문은 프롬프트를 작은따옴표로 감싸 `$HERDR_PANE_ID`가 펼쳐지지 않았다 → 큰따옴표+`$("$AO" whoami)`로 고침(뜻은 같고 원래 의도대로 동작).

~~~~text block=claude-94
오케스트레이션 툴 안(`"$AO" backend`가 0):

```bash
AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}
ROOT=$("$AO" tab-open "<[OC] 짧은 한글 이름>" --cwd "$PWD")
"$AO" agent-start <이름> "$ROOT" --kind <현재 세션과 같은 에이전트> -- <현재 세션과 같은 플래그 — ps -o args= -p $PPID>
"$AO" agent-send <이름> "<handoff 절대경로>를 읽고 그대로 진행해. 부모 pane: $("$AO" whoami)" --confirm   # 출력 working|done = 인계 증거
```

- 인계 세션은 **새 탭**에 연다(오른쪽 pane이 아니라 — 이어받는 세션이 메인이 되어 크게 보여야 한다). `--cwd`는 현재 신뢰된 폴더. 에이전트는 주인님이 따로 명시하지 않으면 현재 세션과 같은 것을 다시 연다. 새 worktree는 위 5의 경우에만 만든다(만든 뒤 `tab-open --cwd <worktree>`).
- 에이전트 이름(`[a-z][a-z0-9_-]{0,31}`)이 살아 있는 agent 사이에서 고유하다는 점이 재시도 기준이다(중복이면 `agent-start`가 3). **기동은 인계 시도당 1회**. 응답을 잃었으면 `"$AO" list --agents`에서 이름을 찾아 있으면 `agent-send`만 다시 보내고, 없을 때만 1회 더 기동한다. 5(준비 안 됨)·6(입력 대기)·그 밖의 실패가 반복되면 blocker 보고.
- **부모 정리는 child가 한다**(부모 자기 close는 실행 중 명령 절단 위험): 수신 직후 첫 착수 전에 `"$AO" close <부모 pane>`(부모 탭에 다른 pane이 남아 있으면 탭은 닫지 않는다). 실패는 무시하고 진행. 프롬프트가 "부모 pane을 닫지 말 것"이라고 하면 그 지시가 우선한다.
~~~~

### 2-6. 108줄 「herdr 밖」

~~~~text block=claude-108
오케스트레이션 툴 밖(`"$AO" backend`가 10·11·12 — 일반 터미널·ssh 포함): 다음 세션을 자동 기동하지 않는다. handoff 문서를 쓰고 다음 세션 시작 프롬프트(위 2의 한 줄)를 주인님께 드린다. 12면 설치 결함도 함께 알린다.
~~~~

바꾸지 않는 줄: 1~42, 44~48, 50~56, 58~80, 82, 84~93, 107, 109~116(office 21·51줄 머신별 줄 포함).

## 3. 세 머신 `~/.codex/AGENTS.md`

codex에서는 ① = codex 내장 서브에이전트(병렬 에이전트 도구), Claude worker가 필요하면 ②(headless 일회성 + done 파일), ③은 같은 동작 이름.

~~~~text block=codex-bullets
- worker 실행은 3단계로 고른다(2026-11-xx). ① **기본 = Codex 내장 서브에이전트**(병렬 에이전트 도구). 결과는 보고 파일, 반환은 한 줄 ② **Claude 등 다른 CLI worker가 필요하면 headless 일회성 실행 + done 파일**: 백그라운드로 한 번 실행하고(예: `claude -p … > <결과 파일> 2>&1; echo "exit=$?" > <done 파일>`) 완료는 done 파일로 판정한다 ③ **pane worker는 사용자가 지켜보며 끼어들 작업·작업 도중 대화가 필요한 작업·메인 세션보다 오래 살아야 하는 작업(세션 인계)만** `AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}`의 동작으로 연다(`"$AO" pane-open "<한글 이름>" --cwd "$PWD"` → `"$AO" agent-start <영문 이름> <pane id> --kind claude|codex -- <CLI 인자>` → `"$AO" agent-send <이름> "<한 줄 — 긴 지시는 파일 경로>" --confirm` → 회수 뒤 `"$AO" close <pane id>`). `"$AO" backend`가 10·11이면 ①·②로 내려가고, 12면 내려가되 설치 결함을 사용자에게 한 줄 알린다. ①로 내려간 작업은 현재 세션 안에서 끝나야 한다(인계 전 완료·회수 필수 — 내장 서브에이전트는 다음 세션이 승계하지 못한다. 인계를 넘겨 살아야 하는 planner가 ①로 내려가면 인계 전에 완료를 기다린다). 툴 특이사항은 `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins/tools/agent-orchestrator/docs/<backend>.md`.
- 탭·pane 이름은 항상 한글로 붙인다(2026-11-08). 오케스트레이션 툴 안(`"$AO" backend`가 0)이면 첫 작업 주제가 정해졌을 때 `"$AO" self-name "[XX] <짧은 한글 탭 이름>" "[XX] <짧은 한글 pane 이름>"`을 실행한다(대상마다 현재 이름이 비었거나 숫자면 인자 그대로, 이미 `[XX] ` 접두어면 유지, 사용자가 붙인 이름이면 본문은 두고 접두어만 붙는다). 주제가 크게 바뀌면 `"$AO" self-name --force "[XX] <새 탭>" "[XX] <새 pane>"`로 다시 바꾼다(`--force`는 현재 이름을 이 세션이 붙였을 때만). 붙인 뒤 `"$AO" whoami --field tab-label`·`"$AO" whoami --field pane-label`로 1회 확인한다. 새 탭은 `"$AO" tab-open "<한글>"`, 새 pane은 `"$AO" pane-open "<한글>"`(이름이 함께 붙는다). 이름 앞에는 **역할 접두어**를 붙이고(2026-11-08 추가), 단계·마일스톤은 이름 본문에 쓴다: `[OC]` 오케스트레이터(사용자와 대화하는 메인·자율체인 조정자·인계받은 세션), `[WO]` worker(구현·조사·계획 초안 등 메인이 맡긴 pane), `[RV]` 리뷰어(리뷰 명령 pane). 예: `[OC] 논의`, `[OC] 헬프AI M1-11`, `[WO] S4 자율체인 2.3.0`, `[RV] S4 codex 검토`. 탭은 그 탭 메인의 역할을 따르고, worker만 담은 넘침 탭은 `[WO]`. 에이전트가 없는 셸 탭·pane에는 접두어를 붙이지 않는다. 사용자가 붙인 이름은 본문을 바꾸지 않고 접두어만 붙인다. `agent-start`의 에이전트 이름은 영문(`[a-z][a-z0-9_-]`) 그대로 둔다.
~~~~

머신별 적용:

| 머신 | 현재 | 적용 |
|---|---|---|
| 이 맥 | 8줄(머리 없는 목록의 한 줄) | 8줄 → `codex-bullets` 두 줄 |
| office | 25줄 `## herdr`, 26줄 빈 줄, 27줄 이름 규칙 | 25~27줄 → 아래 `codex-office-home` |
| 홈 | 9줄 `## herdr`, 10줄 빈 줄, 11줄 이름 규칙 | 9~11줄 → 아래 `codex-office-home` |

`codex-office-home` = 머리 줄 `## 오케스트레이션 툴 (agent-orchestrator)` + 빈 줄 + `codex-bullets` 두 줄.

~~~~text block=codex-office-home-head
## 오케스트레이션 툴 (agent-orchestrator)

~~~~

## 4. 홈 `~/.claude/CLAUDE.md` (3~5줄)

현재 원문: 3줄 `## herdr`, 4줄 빈 줄, 5줄 ⑨ 이름 규칙(`HERDR_ENV=1`·`herdr tab rename`·`herdr pane rename`·`herdr tab create … --label`·`herdr pane split` 직후 rename·`herdr agent start`). 홈은 이름 규칙만 있으므로 이름 규칙만 바꾼다(뜻 그대로).

~~~~text block=home-claude-3
## 탭·pane 이름 (agent-orchestrator)

- **탭·pane 이름은 항상 한글로 붙인다(2026-11-08 주인님 요청 — 자율체인·일반 세션 공통).** `AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}`(절대 경로). 세션이 오케스트레이션 툴 안이면(`"$AO" backend`가 0) 첫 작업 주제가 정해졌을 때 `"$AO" self-name "[XX] <짧은 한글 탭 이름>" "[XX] <짧은 한글 pane 이름>"`을 실행한다(대상마다 현재 이름이 비었거나 숫자면 인자 그대로, 이미 `[XX] ` 접두어면 유지, 주인님이 붙인 이름이면 본문은 두고 접두어만 붙는다). 주제가 크게 바뀌면 `"$AO" self-name --force "[XX] <새 탭 한글>" "[XX] <새 pane 한글>"`로 다시 바꾼다(`--force`는 판정 없이 바꾸므로 현재 이름을 이 세션이 붙였을 때만 쓴다). 새 탭은 `"$AO" tab-open "<한글>"`, 새 pane은 `"$AO" pane-open "<한글>"`(이름이 함께 붙는다). 이름 앞에는 **역할 접두어**를 붙이고(2026-11-08 추가), 단계·마일스톤은 이름 본문에 쓴다: `[OC]` 오케스트레이터(주인님과 대화하는 메인·자율체인 조정자·인계받은 세션), `[WO]` worker(구현·조사·계획 초안 등 메인이 맡긴 pane), `[RV]` 리뷰어(리뷰 명령 pane). 예: `[OC] 논의`, `[OC] 헬프AI M1-11`, `[WO] S4 자율체인 2.3.0`, `[RV] S4 codex 검토`. 탭은 그 탭 메인의 역할을 따르고, worker만 담은 넘침 탭은 `[WO]`. 에이전트가 없는 셸 탭·pane에는 접두어를 붙이지 않는다. 이름 본문은 짧게 무슨 작업인지 드러나게 정하고, 붙인 뒤 `"$AO" whoami --field tab-label`·`"$AO" whoami --field pane-label`로 탭·pane 이름을 1회 확인한다. 주인님이 직접 붙인 이름은 본문을 바꾸지 않고 접두어만 붙인다. `agent-start`의 에이전트 이름은 영문(`[a-z][a-z0-9_-]`) 그대로 둔다.
~~~~

## 5. 이름 규칙 뜻 보존 대조 (⑨·역할 접두어·메인 모델)

| 옛 문장 | 새 문장 | 차이 |
|---|---|---|
| 탭 `herdr tab create … --label` | `tab-open "<한글>"`(어댑터가 `--label`) | 없음 |
| pane split 직후 `pane rename` | `pane-open "<한글>"`(어댑터가 rename, 실패는 경고) | 없음 |
| 자기 탭: label이 번호·영문 기본값이면 rename / 자기 pane: label이 **없으면** rename | `self-name` — 대상마다 빈 값·숫자만이면 인자 그대로, `[XX] ` 접두어가 있으면 유지, 그 밖(사용자 이름)은 본문 두고 접두어만(1회차 크로스체크 반영, ASCII 기본값 판정 폐지) | 옛 "영문 기본값"은 숫자 번호만 기본값으로 좁혔다 — 영문 사용자 이름(`Peter review`)도 본문이 보존된다(시험 `self-name-user-en`·가드 `neg-self-name-user-guard`) |
| 주제가 크게 바뀌면 다시 바꾼다 | `self-name --force` (현재 이름을 이 세션이 붙였을 때만) | 없음 |
| 붙인 뒤 `tab get`/`pane get`의 `label`로 1회 확인 | `whoami --field tab-label`·`--field pane-label` | 없음 |
| `[OC]`/`[WO]`/`[RV]`, 단계는 본문, 넘침 탭 `[WO]`, 셸에는 접두어 없음, 주인님 이름은 접두어만 | 그대로 | 없음 |
| 에이전트 이름 영문 정규식 | 그대로 | 없음 |
| 메인 Opus 5.5 high(57줄) | 참조 낱말 하나만(`herdr 규칙` → `worker 실행 3단계 규칙`) | 없음 |

## 6. `CLAUDE_HISTORY.md` 항목 문안 (이 맥·office — 홈은 파일 없음, 이 맥 항목에 홈 포함 기재)

파일 끝(현재 마지막 항목 `2026-11-08 (4)` 다음)에 빈 줄 하나 + 아래 블록을 덧붙인다. `<ts>`·`<날짜>`는 적용 때 실제 값으로, `<details>` 안은 적용 직전 백업에서 `sed -n '43p;81,108p' ~/.claude/archive/claude-md-<ts>.md`로 뽑은 원문을 그대로 넣는다(이 맥·office 원문이 같으므로 같은 내용).

~~~~text block=history-entry
- <날짜>: herdr 직접 명령 규칙을 `agent-orchestrator` 동작 이름 + **worker 실행 3단계 기준**으로 이관(이 맥·office CLAUDE.md는 전체, 홈 CLAUDE.md는 이름 규칙만, AGENTS.md는 세 머신. office gira 메모리 `herdr-parallel-agents.md`의 반대 지침은 **주인님 결정 대기**로 남김. 계획 `waymakerlabs-claude-plugins/docs/plans/2026-11-08-agent-orchestrator-plan.md` S6 · 초안 `…-rules-draft.md`). ① 2026-11-06 「herdr 안에서는 실질 작업을 옆 pane의 Claude 세션으로」(pane worker 기본)를 「① 메인 CLI 내장 서브에이전트 기본 ② 다른 CLI는 headless 일회성 + done 파일 ③ pane worker는 주인님이 지켜볼 작업·작업 도중 대화·메인보다 오래 사는 작업만」으로 바꿨다. 근거: M1-10 리뷰 pane 회수 179분, 조사 중 worker 정지 오판, 처음 보는 폴더의 `agent_not_ready`. auto-chain 2.3.0 §1-1과 같은 기준이다. ② 명령은 `~/.local/bin/agent-orchestrator <동작>` 절대 경로(D3 — PATH 추가 없음), 종료 코드 10·11은 ①·②로 내려감, 12는 내려가되 설치 결함 알림. 툴 특이사항은 `tools/agent-orchestrator/docs/<backend>.md` 한 곳. ③ 2026-11-08 ⑨ 탭·pane 한글 이름·역할 접두어와 메인 Opus 5.5 high는 뜻을 바꾸지 않고 동작 이름으로 옮겼다. ④ 「후속 세션 인계 프로토콜」 herdr 절을 `tab-open`→`agent-start`→`agent-send --confirm`으로 바꿨다. ⑤ `~/.codex/AGENTS.md` 세 머신: 이름 규칙을 동작 이름으로, codex는 ① 내장 서브에이전트·② Claude headless. ⑥ 홈 CLAUDE.md는 이름 규칙만 바꿨다(3단계 기준 미기재 — 홈 일반 Claude 세션에는 새 선택 기준이 없다). ⑦ 이름 계약: `self-name`은 사용자 이름 본문을 보존하고 접두어만 붙이며, 주제 변경은 `self-name --force`, 확인은 `whoami --field tab-label|pane-label`. 백업: 이 맥·office `~/.claude/archive/claude-md-<ts>.md`·`claude-history-<ts>.md`·`codex-agents-md-<ts>.md`, 홈 `~/.claude/archive/claude-md-<ts>.md`·`codex-agents-md-<ts>.md`. 이관 뒤 `install.sh --check herdr` 전역 규칙 잔존 0 확인(값: <이 맥 n · office n · 홈 n>). 이 파일의 이전 herdr 항목(2026-11-06~11-08)은 역사 기록이라 고치지 않는다.

  <details><summary>이관 전 원문 (CLAUDE.md 43줄 · 81~108줄, 이 맥·office 동일)</summary>

  ````markdown
  <적용 직전 백업에서 sed -n '43p;81,108p'로 뽑은 원문>
  ````

  </details>
~~~~

## 7. 메모리 변경안 (이 맥만 — helpai 2파일+색인, gchat-g-on 1파일. herdr-ios 3파일 제외)

### 7-1. helpai `codex-review-partner.md` (`~/.claude/projects/-Users-peter-Dev-helpai/memory/`)

뜻 보존: helpai 리뷰는 **pane 유지**(D1 — helpai 프로파일 `review_view: pane`, S6에서 helpai가 재판단). 바꾸는 것은 명령 예시뿐이다.

- 3줄 description `…을 herdr 오른쪽 pane에서 실행 — …` →
~~~~text block=mem-helpai-crp-3
description: "helpai 검토는 codex CLI 직접 호출(`command codex exec`, Sol high, read-only)을 오른쪽 열 pane(`agent-orchestrator pane-open`·`pane-run`)에서 실행 — 플러그인·Orca·opencode 미사용. 마일스톤 단위만"
~~~~
- 15줄 `**herdr 안에서는 codex 실행을 오른쪽 열 pane에서 한다**` →
~~~~text block=mem-helpai-crp-15
2026-11-07 22:4x +0900 주인님 확정: **오케스트레이션 툴 안에서는 codex 실행을 오른쪽 열 pane에서 한다**(M1-08 milestone-review r1만 Bash 백그라운드로 두고, 그다음 회차부터 적용). 2026-11-xx부터 명령은 `agent-orchestrator` 동작이다(auto-chain 2.3.0 — 프로파일 `review_view: pane`).
~~~~
- 21줄(2단계) →
~~~~text block=mem-helpai-crp-21
2. 오른쪽 열에 pane을 연다(아래 3·5단계까지 같은 셸에서): `AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}; PANE=$("$AO" pane-open "[RV] <마일스톤> codex 검토" --cwd <리포>)` — 배치(오른쪽 열이 비면 오른쪽, 있으면 가장 높은 pane을 아래로 반분)와 포커스 유지는 어댑터가 한다. 10·11·12면 pane을 쓰지 않고 `review-run.sh`를 `run_in_background` Bash로 돌린다(12는 주인님께 한 줄 알림).
~~~~
- 22줄(3단계) 앞머리 `그 pane에서 실행한다: `herdr pane run <id> "…"`` → `그 pane에서 실행한다: `"$AO" pane-run "$PANE" "…"`` (따옴표 안 명령 문자열과 나머지 문장 그대로). 적용은 문자열 치환 1회: `herdr pane run <id> ` → `"$AO" pane-run "$PANE" `.
- 26줄 `5. 회수 뒤 `herdr pane close`.` →
~~~~text block=mem-helpai-crp-26
5. 회수 뒤 `"$AO" close "$PANE"`.
~~~~
- 23~25줄(2026-11-08 실측·주인님 발언·2.2.0 대체)은 역사 기록이라 그대로 둔다.

### 7-2. helpai `MEMORY.md` 8줄 (색인 — description과 맞춤)

~~~~text block=mem-helpai-index-8
- [Codex review partner](codex-review-partner.md) — helpai reviews call codex CLI directly (`command codex exec`, Sol high, read-only) in a right-column pane via `agent-orchestrator pane-open`/`pane-run` (from after M1-08 r1); never the plugin; per milestone only
~~~~

### 7-3. helpai `m1-autonomous-run.md` 11줄 — 괄호 안 한 구절

`(2026-11-06 14:54부터 herdr 새 탭 — Orca는 2026-11-08 두 머신에서 삭제)` → `(2026-11-06 14:54부터 새 탭 인계 — 지금은 `agent-orchestrator tab-open`, Orca는 2026-11-08 두 머신에서 삭제)`. 문장의 나머지는 그대로.

### 7-4. gchat-g-on `office-macmini-session-contact.md` — 명령 유지(D7), 한 줄 추가

`herdr --machine …` 명령 3개는 D7(원격 조작 범위 밖)로 **그대로 둔다**(manifest `allow`). 11줄 끝 `… — use herdr):` 다음에 근거 한 줄만 덧붙인다(12줄 빈 줄 앞).

~~~~text block=mem-gchat-11a
(2026-11-xx: `agent-orchestrator`는 원격 조작 `--machine`을 지원하지 않는다(D7). 그래서 아래만 herdr를 직접 부르는 알려진 예외로 남긴다 — `tools/agent-orchestrator/docs/herdr.md` 「알려진 예외」.)
~~~~

`MEMORY.md` 1줄은 그대로(같은 예외).

### 7-5. 범위 밖으로 확인한 메모리 (변경안 없음 — 주인님 확인 항목)

office에 herdr 언급 메모리 9파일이 있다(이 맥 계획 §0 집계 밖). 그중 **`-Users-peter-Dev-gira/memory/herdr-parallel-agents.md`는 새 3단계 기준과 뜻이 정면으로 어긋난다**("구현이 필요한 작업은 `Agent` 대신 herdr 패널", 2026-11-06). 나머지 8개(gira `MEMORY.md`·`gira-weekly-report.md`·`verify-started-claims.md`, legacy-lens 5개)는 역사 서술·인계 명령 예시다. 홈은 0개.

## 8. S6 전에 브랜치에 넣을 manifest 변경안 (`tools/**` — S5는 수정 금지라 문안만)

전역 규칙 잔존을 0으로 만들어도 `plugins/auto-chain/skills/autonomous-chain` rule이 **2.3.0 브랜치 기준 28건**을 남긴다(지금 마켓플레이스 2.2.2 사본은 120건). 28건 = 시험 하니스 20 + 래퍼·포인터·호환 주석 8 — 계획 §3·S4 보고서의 허용 목록과 같은 종류인데 `herdr.manifest`에는 아직 `allow`가 없다. 계획 S6 종료 조건("`--check herdr` 잔존 0(allow 외)")을 맞추려면 아래 줄을 `manifests/herdr.manifest` 끝에 더한다(탭 구분 5칸).

~~~~text block=manifest-allow
allow	-	plugins/auto-chain/skills/autonomous-chain/scripts/test/run-tests.sh	grep:herdr	가짜 바이너리 이름(시험 하니스)
allow	-	plugins/auto-chain/skills/autonomous-chain/scripts/herdr-spawn-worker.sh	grep:herdr	2.3.x 호환 래퍼
allow	-	plugins/auto-chain/skills/autonomous-chain/scripts/herdr-stall-watch.sh	grep:herdr	2.3.x 호환 래퍼
allow	-	plugins/auto-chain/skills/autonomous-chain/references/backend-herdr.md	grep:herdr	2.3.x 옛 경로 포인터
allow	-	plugins/auto-chain/skills/autonomous-chain/references/pane-worker.md	grep:backend-herdr.md	옛 문서 이름 안내
allow	-	plugins/auto-chain/skills/autonomous-chain/SKILL.md	grep:herdr-spawn-worker.sh	옛 스크립트 이름 호환 안내
allow	-	plugins/auto-chain/skills/autonomous-chain/scripts/spawn-pane-worker.sh	grep:herdr-spawn-worker.sh	옛 이름 주석
allow	-	plugins/auto-chain/skills/autonomous-chain/scripts/agent-stall-watch.sh	grep:herdr-stall-watch.sh	옛 이름 주석
~~~~

## 9. 적용 절차 (S6)

전제: 계획 §5-3 전환 조건 충족 → main 병합·push → 세 머신 marketplace 갱신·auto-chain 2.3.0 설치 실측 → (§8 allow를 병합 전에 넣었다면) 마켓플레이스 사본의 manifest에 allow 8줄이 있는지 확인.

1. **스냅샷 대조**: 머신마다 대상 파일 sha256을 머리 표와 비교. 다르면 그 파일만 `diff`로 바뀐 줄을 보고 줄 번호를 다시 맞춘다(블록 문장은 그대로).
2. **백업**(머신마다, 같은 `<ts>`):
   - 이 맥·office: `cp -p ~/.claude/CLAUDE.md ~/.claude/archive/claude-md-<ts>.md`, `cp -p ~/.claude/CLAUDE_HISTORY.md ~/.claude/archive/claude-history-<ts>.md`, `cp -p ~/.codex/AGENTS.md ~/.claude/archive/codex-agents-md-<ts>.md`
   - 홈: `mkdir -p ~/.claude/archive` 뒤 CLAUDE.md·AGENTS.md 두 개
   - 메모리(이 맥): `cp -p <파일> ~/.claude/archive/memory-<프로젝트>-<파일명>-<ts>.md` 4개(helpai 3·gchat 1)
3. **적용 순서**: 이 맥 → `--check` → office → `--check` → 홈 → `--check` → 메모리. 머신마다 CLAUDE.md(§2 또는 §4) → AGENTS.md(§3) → CLAUDE_HISTORY(§6, 홈 제외). 적용 방법은 이 초안의 블록을 줄 범위에 대체하는 스크립트(§10의 시뮬레이션 스크립트와 같은 규칙) — 손 편집이면 블록을 복사해 붙인다.
4. **확인**(머신마다): `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins/tools/agent-orchestrator/install.sh --check herdr`에서 `~/.claude/CLAUDE.md`·`~/.codex/AGENTS.md` rule이 `잔존 0건`, 마지막 줄 `rule 잔존 0건(allow 제외)`(§8 allow 포함 시). 보조로 `grep -n -i herdr ~/.claude/CLAUDE.md ~/.codex/AGENTS.md` 결과 0줄. 줄 수(§10 시뮬레이션 실측 — 울타리 내용을 그대로 보존해 대체, `codex-office-home-head`의 빈 줄 포함): `CLAUDE.md` 이 맥·office 116 → 115(94~106 13줄 → 12줄), 홈 5 유지 / `AGENTS.md` 이 맥 8 → 9, office 27 → 28, 홈 11 → 12(3줄 → 제목+빈 줄+두 bullet 4줄).
5. **되돌리기**: 백업을 원래 경로로 `cp -p`. 메모리도 같음.

## 10. 적용 시뮬레이션 (S5 실측)

방법: 세 머신 원본 사본(`/tmp/s5/*.md`, ssh 읽기만)에 이 초안 블록을 위 줄 범위대로 대체해 가짜 HOME(`/tmp/s5/sim-<머신>/`)을 만들고, 개발 리포의 `lib/manifest.py check`를 `HOME=<가짜>`·`AO_REPO=<개발 리포, 2.3.0 브랜치>`로 실행. §8 allow는 manifest 사본(`/tmp/s5/herdr-allow.manifest`)에 더해 따로 실행. 결과는 보고서 `2026-11-08-agent-orchestrator-S5-report.md` §3.
