# 계획 초안 — agent-orchestrator (오케스트레이션 툴 추상화)

- 작성: 2026-11-08, 지시서 `docs/plans/2026-11-08-agent-orchestrator-brief.md` 기준
- 상태: **확정** — codex Sol high 1회차 BLOCK(5·NOTE 4) 반영 → 2회차 SHIP(NOTE 3 반영, §10). 사용자 결정 D1~D8 반영(`docs/plans/2026-11-08-agent-orchestrator-decisions.md`). 구현은 새 세션에서 S1부터.
- 저장소: `/Users/peter/Dev/waymakerlabs-claude-plugins` HEAD `b5691fb`(auto-chain 2.2.2)

## 0. 조사로 확인한 사실 (실측)

| 항목 | 값 |
|---|---|
| herdr | 0.9.5, 세 머신 모두 `/opt/homebrew/bin/herdr`. 그룹 `pane`·`tab`·`agent`·`workspace`·`worktree`. 하위 명령에 `--help`를 붙이면 최상위 사용법만 나온다(`herdr pane split --help` 무효) → 하위 명령 옵션은 `backend-herdr.md` 실측값과 기존 스크립트를 진본으로 쓴다 |
| `pane split` | 이름 옵션 없음 → split 직후 `pane rename` (2.2.2 스크립트가 이미 함) |
| 기존 시험 | `scripts/test/run-tests.sh` PASS 56 / FAIL 0 (가짜 codex·opencode·herdr·git). 음성 대조 `sp-neg-until`(375줄)은 `herdr-spawn-worker.sh` 사본에서 `--until "done"`을 sed로 지워 rc=6을 확인한다 |
| herdr 사용처(auto-chain) | `backend-herdr.md`(216줄), `SKILL.md`(7·17·21~30·38·53·62~63·89~90·107·121~122·411~417·476~486줄), `herdr-spawn-worker.sh`(239줄, 5번째 인자 `main-pane`을 배치 기준으로 씀 — 45·159줄), `herdr-stall-watch.sh`(192줄), `run-tests.sh`, `README.md`(30~32·34·60줄), `references/task-brief.md`(17줄 — **worker가 직접 `herdr agent prompt` 실행**), `references/sol-review.md`(121줄 — herdr·`backend-orca.md` 분기 참조) |
| herdr 사용처(전역) | `~/.claude/CLAUDE.md` 13곳, `CLAUDE_HISTORY.md` 13곳(역사 기록), `~/.codex/AGENTS.md` 1절(한글 이름 규칙). office·홈에도 같은 절 |
| 메모리 | herdr 언급 8파일: helpai `codex-review-partner.md`·`m1-autonomous-run.md`·`MEMORY.md`, gchat-g-on `office-macmini-session-contact.md`·`MEMORY.md`(`herdr --machine` 원격 prompt), herdr-ios 3파일(herdr 자체 개발 — 이관 대상 아님) |
| herdr 설치물 | `~/.claude/hooks/herdr-agent-state.sh`, `~/.codex/herdr-agent-state.sh`("managed by herdr", `HERDR_INTEGRATION_VERSION=11`). 등록: `~/.claude/settings.json` 43줄 부근, `~/.codex/hooks.json` 16줄. office·홈에도 훅 파일 있음 |
| herdr-ios | `/Users/peter/Dev/herdr-ios`는 자체 `CLAUDE.md`가 있는 **개발 프로젝트**. `~/.codex/config.toml:327` 신뢰 항목은 그 프로젝트의 것이지 herdr 설치물이 아니다 |
| Rex | `rex __internal session-start` — `~/.claude/settings.json` 33줄, `~/.codex/hooks.json` 7줄. 건드리지 않음 |
| Orca 잔재 | `references/backend-orca.md`(36줄), `SKILL.md` §1-1 3번·§9 인계·7·17줄, `sol-review.md:121`, `README.md` 30줄, 마켓플레이스 `orca-codex-delegate` 1.0.3. auto-chain 원본 태그 `auto-chain-v1.7.1-orca`. `installed_plugins.json` 확인 결과 세 머신 모두 `orca-codex-delegate` 미설치 |
| 마켓플레이스 | 세 머신 모두 `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins`(GitHub `waymakerlabs/claude-plugins` clone). **autoUpdate**: 이 맥 `known_marketplaces.json`·`settings.json` 모두 `true`, office `true`, 홈 `known_marketplaces.json`에 키 없음(기본값 동작 UNVERIFIED). 따라서 **main push = 세 머신 게시**로 본다 |
| 플러그인 캐시 | `~/.claude/plugins/cache/waymakerlabs-claude-plugins/auto-chain/<버전>/` — 버전마다 폴더(1.1.0~2.2.2 12개). 폴더 공존이 실행 중 세션의 버전 고정을 증명하지는 않는다 |
| PATH | office: 비로그인 ssh에 `~/.local/bin` 없음, 로그인 셸에 있음. 홈: 비로그인·로그인 모두 없음. 이 맥 `~/.local/bin`에 claude·codex 링크 |
| auto-chain 사용 체인 | helpai(이 맥): M1-11 planned(planner 작성 중). `chain-guide.md`·여러 handoff가 `herdr-spawn-worker.sh`·`backend-herdr.md`를 직접 가리킴. **office gira**: `docs/chain/*/state.md` 3개(gira-shared-editor 등, 최근 11-08 10:06 갱신)가 같은 스크립트를 가리킴 — 두 번째 소비자 |

## 1. 동작 계약

명령: `agent-orchestrator <동작> [인자…]`. 표준 출력은 **필요한 값 한 줄**(없으면 빈 출력), 사유·경고는 stderr. JSON 출력 없음. 여러 줄 출력 예외는 `agent-read`·`list`와 받은편지함의 `inbox-watch`·`inbox-watch --pending`(§1-4)뿐이다.

### 1-1. 종료 코드 (모든 동작 공통)

| 코드 | 뜻 | 호출자 행동 |
|---|---|---|
| 0 | 성공 | 출력 값 사용 |
| 2 | 인자 오류(이름 규칙 위반·필수 인자 없음·줄바꿈 포함 프롬프트) | 호출자 버그. 고치고 재호출 |
| 3 | 대상 없음/충돌(이름 중복, 없는 pane·agent) | 동작별 처리 |
| 4 | 백엔드 실행 실패(명령 비0, 응답 해석 실패) | 1회 재시도 후 아래 단계로. **`agent-send`는 예외** — 재전송하지 않는다(입력창에 지시가 남아 있을 수 있음). `agent-status`·transcript로 착수를 1회 확인하고, 안 됐으면 pane을 닫고 사라진 것을 확인한 뒤에만 새 pane·새 이름으로 다시 띄운다(받은편지함 계획 §0) |
| 5 | 에이전트 준비 안 됨(`agent_not_ready`, 신뢰 확인 화면) | 화면 1회 확인 → 아래 단계로 |
| 6 | 대상이 사용자 입력 대기(`blocked`) | 사용자에게 알림, 대신 승인 안 함 |
| 7 | timeout(대기 동작) | 실패 아님. 같은 명령 재대기. **`agent-send --confirm`은 예외** — 같은 프롬프트를 다시 보내지 않고 코드 4의 `agent-send` 행동을 따른다 |
| 10 | **unsupported** — 백엔드(또는 해당 `--kind`)에 이 동작이 없음 | 3단계 규칙의 아래 단계로 |
| 11 | **no backend** — 설정·환경상 지금 쓸 백엔드가 없음(정상 부재) | 단계 ①·②로 |
| 12 | **adapter error** — 백엔드는 정해졌는데 어댑터 파일 없음·로딩 실패·필수 바이너리 없음 | 설치 결함. 아래 단계로 가되 사용자에게 한 줄 알림(11과 구분 — NOTE 3) |

10·11은 정상적인 내려감 신호라 실패 횟수에 넣지 않는다. 12는 내려가되 결함으로 보고한다.

받은편지함 동작(§1-4)은 백엔드를 쓰지 않으므로 0·2·4만 낸다. 4는 받은편지함 파일의 기록·잠금·ack 실패다.

### 1-2. 동작 목록

사용처 근거: `herdr-spawn-worker.sh`, `herdr-stall-watch.sh`, `backend-herdr.md` §4~§8, `task-brief.md:17`(worker → 조정자 메시지), 전역 인계 프로토콜, helpai `chain-guide.md:47`·`m1-plan.md:102`(UUID).

| 동작 | 인자 | stdout | 비고 |
|---|---|---|---|
| `backend` | — | 백엔드 이름 | 없으면 11, 결함 12 |
| `whoami` | `[--field pane\|tab\|workspace]` | 자기 pane id(기본) | |
| `tab-open` | `<한글 이름> [--cwd 경로]` | 새 탭 루트 pane id | 포커스 이동 없음 |
| `pane-open` | `<한글 이름> [--parent <pane id>] [--cwd 경로]` | 새 pane id | `--parent` = 배치 기준 조정자 pane(기본 `whoami`). 기존 spawn 5번째 인자 `main-pane`을 이것으로 전달(NOTE 1). 오른쪽 열 최대 5, 넘치면 새 탭 — 어댑터 내부. 이름 붙이기 실패는 경고만 |
| `self-name` | `<탭 한글> [<pane 한글>]` | — | 번호·영문 기본값일 때만 바꿈 |
| `agent-start` | `<에이전트 이름> <pane id> --kind claude\|codex -- <CLI 인자…>` | — | 이름 `[a-z][a-z0-9_-]{0,31}`, 중복 3, 준비 안 됨 5 |
| `agent-send` | `<에이전트 이름\|pane id> <한 줄> [--confirm]` | 상태(`working\|done\|idle`) | `--confirm` = working 또는 done 관측까지(빠른 완료 허용 — `--until done` 포함이 계약). blocked 6 |
| `agent-wait` | `<이름> [--timeout 초]` | 최종 상태 | done·idle까지. timeout 7 |
| `agent-status` | `<이름>` | `working\|done\|idle\|blocked\|unknown` | |
| `agent-session-id` | `<이름>` | 세션 UUID | helpai 대리 보고 `session:<UUID>`·`external_session_id` 용(BLOCK 1) |
| `agent-transcript` | `<이름>` | transcript 파일 절대 경로 | 정지 감시 용. **`--kind claude`만** — codex 등 경로 규칙을 모르는 kind는 10(BLOCK 1) |
| `agent-read` | `<이름\|pane id> [--lines N]` | 화면 텍스트(여러 줄 — 유일한 예외) | 기본 30 |
| `agent-keys` | `<이름> <키>` | — | Escape 등 |
| `pane-run` | `<pane id> <셸 문자열>` | — | `review_view: pane`용 |
| `close` | `<pane id>` | — | 없는 pane 3 |
| `list` | `--agents\|--panes` | 줄마다 `<id>\t<이름>\t<상태>` | 이름 중복 검사·인계 재시도 판단 |

`--machine`(원격 조작)은 이번 범위에서 제외(D7). gchat-g-on 메모리의 원격 prompt는 `docs/herdr.md`의 알려진 예외로 기재.

### 1-3. herdr 어댑터 매핑

| 동작 | herdr 0.9.5 |
|---|---|
| 전제 | 11: `HERDR_ENV≠1`. 12: `adapters/herdr.sh` 없음·source 실패·`herdr` 바이너리 없음. 4: `herdr status server`가 running 아님 |
| whoami | `$HERDR_PANE_ID` / `$HERDR_TAB_ID` / `$HERDR_WORKSPACE_ID` |
| tab-open | `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd <cwd> --label <이름> --no-focus` → 첫 `pane_id` |
| pane-open | `pane layout --pane <parent>`로 오른쪽 열 판정 → 비었으면 `pane split <parent> --direction right`, 아니면 가장 높은 pane을 `--direction down --ratio 0.5`, 5개 넘으면 넘침 탭 재사용·생성. 항상 `--cwd --no-focus`, 직후 `pane rename <id> <이름>` (현 `herdr-spawn-worker.sh` 131~195줄 로직 이전) |
| self-name | `tab rename`/`pane rename` (현재 label 조회 후 조건부) |
| agent-start | 사전 `agent list` 중복 검사 → `herdr agent start <이름> --kind <k> --pane <id> --timeout 90000 -- …`; `agent_not_ready` → 5 |
| agent-send | `herdr agent prompt <이름> "<줄>"` (`--confirm`이면 `--wait --until working --until done --timeout 60000`); `agent_blocked` → 6 |
| agent-wait | `herdr agent wait <이름> --until done --until idle --timeout <ms>` 후 `agent get` |
| agent-status | `herdr agent get`의 `agent_status` |
| agent-session-id | `herdr agent get`의 `agent_session.value` (없으면 3) |
| agent-transcript | kind=claude일 때만: `agent_session.value`+`cwd` → `~/.claude/projects/<cwd 비영숫자→->/<UUID>.jsonl`, 파일 존재 확인(없으면 3). 그 밖 kind → 10 |
| agent-read | `herdr agent read <이름> --source visible --lines N` / pane이면 `herdr pane read <id> --lines N` |
| agent-keys | `herdr agent send-keys <이름> <키>` |
| pane-run | `herdr pane run <id> "<문자열>"` |
| close | `herdr pane close <id>` |
| list | `herdr agent list` / `herdr pane list --workspace …` 필드 추출 |

JSON 파싱은 `lib/common.sh`의 `python3 -c` 헬퍼 한 곳으로 모은다.

### 1-4. 받은편지함 동작 (세션 간 메시지 — 2026-11-10)

이미 첫 지시를 받은 세션의 입력창에는 아무것도 쳐 넣지 않는다. 세션 간 메시지는 받은편지함 파일에 덧붙이고, 받는 쪽은 `inbox-watch`를 Monitor로 띄워 받는다. 네 동작 모두 **백엔드 결정 전에** 처리하므로 herdr 밖·`AGENT_ORCHESTRATOR_BACKEND=none`·백엔드 고장에서도 동작한다. 구현 `tools/agent-orchestrator/lib/inbox.sh`.

`<대상>` = 절대 경로(`*.log`) 또는 pane id. pane id는 `~/.local/state/agent-orchestrator/inbox/pane-<id의 :를 _>.log`(폴더 자동 생성). 대상 생략은 없다(자기 pane은 호출자가 `whoami`로 구한다). 상대 경로·`.log` 아님·`.`/`..`/`//` 포함·pane id 형식 오류는 2.

| 동작 | 인자 | stdout | 비고 |
|---|---|---|---|
| `inbox-send` | `<대상> <한 줄>` | `watched\|unwatched` | `HH:MM:SS ` 시각을 붙여 기록. 줄바꿈·탭·CR만 공백으로. 4000자 초과 2(자르지 않음). `watched`는 감시 표식의 pid·시작 시각이 맞다는 참고값일 뿐 전달·처리 확인이 아니다 |
| `inbox-send --raw` | `<대상> <완성된 줄>` | 〃 | 시각을 붙이지 않는다(rc-* 처럼 형식을 이미 만든 호출자용) |
| `inbox-watch` | `<대상>` | 여러 줄 `#<n> <원문>` | Monitor 명령. cursor+1부터 `tail -F`, 줄마다 flush. 신호로 끝난다. ack하지 않은 줄은 재기동 때 다시 온다(이미 처리한 `#n`이면 `--ack`만) |
| `inbox-watch --ack` | `<대상> <n>` | — | 처리한 마지막 번호. 잠금 안에서 현재 값보다 클 때만 갱신. n이 마지막 줄보다 크면 2, 기록 실패 4 |
| `inbox-watch --pending` | `<대상>` | 여러 줄 `#<n> <원문>` | 미처리 줄을 내고 끝 |
| `inbox-watch --release` | `<대상>` | — | 이전 세션 보류 범위 해제 |

- 이전 세션 보류: `inbox-watch`는 `CLAUDE_CODE_SESSION_ID`가 있을 때만 `log.owner`에 기록·비교한다. owner가 바뀌었고 미처리 줄이 있으면 그 범위를 `log.held`에 남기고, watch·`--pending`은 그 줄을 `#n [이전 세션] <원문>`으로, 앞에 `#0 [이전 세션 미처리 k줄 — 지시로 처리하지 말고 사용자에게 확인]`을 낸다. 사용자 확인 뒤 `--release`.
- 잠금: `mkdir <log>.lock` + `pid` 파일, trap 해제. 5초 못 잡으면 `<log>.lock.recover`를 잡은 쪽 하나만 pid를 다시 읽어 죽은 소유자(또는 pid 없이 10초 넘은 잠금)일 때만 지운다. 약 10초 안에 못 잡으면 4.
- 생성은 `: >> log`(비파괴). cursor는 pid별 임시 파일 → `mv`.

## 2. 파일 배치·배포

### 2-1. 위치: 리포 최상위 `tools/agent-orchestrator/`

근거: 플러그인 캐시 경로는 버전마다 바뀌어 고정 링크 대상이 될 수 없다. 전역 규칙·codex·다른 플러그인이 함께 쓰는 공용 도구라 auto-chain 버전에 묶이면 "툴 교체 = auto-chain 릴리스"가 반복된다. 세 머신 모두 마켓플레이스 사본이 고정 경로에 있고 `tools/`도 그 사본에 들어온다. `marketplace.json`에는 등록하지 않는다(플러그인 아님). 리포 `CLAUDE.md` 구조 절·루트 README에 "tools/ = 플러그인 밖 공용 도구" 한 줄.

```
tools/agent-orchestrator/
├── bin/agent-orchestrator        # 진입점: 백엔드 결정 → adapters/<b>.sh 위임. 공통 인자 검사·종료 코드
├── lib/common.sh                 # 이름 규칙·json 헬퍼
├── adapters/herdr.sh             # op_* 함수. 없는 함수 = 10
├── adapters/README.md            # 어댑터 작성 계약(Rex 자리: adapters/rex.sh + manifests/rex.manifest)
├── manifests/core.manifest       # 오케스트레이터 자체 설치물(NOTE 2)
├── manifests/herdr.manifest      # herdr 관련 설치물
├── docs/herdr.md                 # 툴별 특이사항 단일 문서
├── install.sh                    # 링크·설정 생성(멱등). --check 는 읽기 전용 점검
├── uninstall-backend.sh          # manifest 기반 보관(archive-first), 기본 --dry-run
└── test/run-tests.sh             # 가짜 herdr 계약 시험
```

시험 가능성을 위해 진입점은 `AGENT_ORCHESTRATOR_HOME`(기본: 진입점 실제 경로의 상위)으로 adapters·lib 위치를 정한다. 사본 디렉터리에서 변형 어댑터를 돌리는 음성 대조가 이 변수로 가능해진다(BLOCK 3).

### 2-2. 백엔드 결정 순서

1. `AGENT_ORCHESTRATOR_BACKEND`(일회성 덮어쓰기, 시험용. `none` = 11)
2. `~/.config/agent-orchestrator/config` 한 줄 `backend=herdr` (머신별)
3. 자동 판단: `HERDR_ENV=1` → herdr. (Rex 판정 줄 자리를 주석으로 예약)
4. 없음 → 11

설정이 herdr라도 `HERDR_ENV≠1`(그 툴 밖)이면 11.

### 2-3. 링크·PATH (D3·D6 결정 반영)

- `install.sh`가 `~/.local/bin/agent-orchestrator` → `~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins/tools/agent-orchestrator/bin/agent-orchestrator` 링크(세 머신 동일, D6). 개발 중 시험은 개발 리포 경로를 직접 부른다.
- PATH에 기대지 않는다(D3, 셸 설정 추가 없음): 규칙·스크립트는 `${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}` 절대 경로로 부른다.
- 링크가 없으면 auto-chain 래퍼 함수가 `-x` 검사 후 12를 반환한다(설치 결함 — 11과 구분).

### 2-4. 설치 목록 형식

탭 구분 한 줄 한 항목. `owner`: `herdr`(툴이 스스로 설치 — 편집 금지, 제거 때 보관만) / `ours-backend`(이 어댑터를 위해 우리가 만든 것 — 백엔드 제거 때 보관) / `ours-core`(오케스트레이터 자체 — 백엔드 교체 때 **보존**) / `existing`(설치 주체·제거 근거가 이 백엔드가 아닌 것 — 목록에만 기재, 어떤 경우에도 건드리지 않음).

`manifests/core.manifest`:
```
# kind	owner	path	selector	note
link	ours-core	~/.local/bin/agent-orchestrator	-	백엔드 교체 시 보존. 오케스트레이터 자체 제거 때만 보관
config	ours-core	~/.config/agent-orchestrator/config	backend=	교체 시 값만 바꿈(보존)
```

`manifests/herdr.manifest`:
```
# kind	owner	path	selector	note
hook	herdr	~/.claude/hooks/herdr-agent-state.sh	-	managed by herdr, 편집 금지
setting	herdr	~/.claude/settings.json	hooks.*[command~=herdr-agent-state.sh]	-
hook	herdr	~/.codex/herdr-agent-state.sh	-	managed by herdr
setting	herdr	~/.codex/hooks.json	hooks.*[command~=herdr-agent-state.sh]	-
adapter	ours-backend	tools/agent-orchestrator/adapters/herdr.sh	-	리포 파일(git으로 관리, 보관은 git 이력)
doc	ours-backend	tools/agent-orchestrator/docs/herdr.md	-	-
rule	ours-backend	~/.claude/CLAUDE.md	grep:herdr	잔존 검사 대상(자동 수정 안 함)
rule	ours-backend	~/.codex/AGENTS.md	grep:herdr	-
rule	ours-backend	plugins/auto-chain/skills/autonomous-chain	grep:herdr	활성 문서 전체(archive·CHANGELOG 제외)
existing	-	~/.codex/config.toml	projects."/Users/peter/Dev/herdr-ios"	개발 프로젝트 신뢰 항목 — 보존(BLOCK 5)
existing	-	~/.claude/projects/-Users-peter-Dev-herdr-ios/memory/	-	개발 프로젝트 메모리 — 보존
existing	rex	~/.claude/settings.json	hooks.SessionStart[command~=rex __internal]	건드리지 않음
existing	rex	~/.codex/hooks.json	hooks.SessionStart[command~=rex __internal]	건드리지 않음
allow	-	~/.claude/projects/-Users-peter-Dev-gchat-g-on/memory/office-macmini-session-contact.md	grep:herdr --machine	D7 알려진 예외(잔존 허용)
```

- `install.sh --check <backend>`: 항목 존재 여부, `rule` 항목의 잔존 수(`allow` 제외)를 읽기 전용으로 보고 — 툴 교체 때 "잔재 0" 기준.
- `uninstall-backend.sh <backend>`: 기본 `--dry-run`. 실행 시 `herdr`·`ours-backend` 파일은 `~/.claude/archive/agent-orchestrator/<backend>-<ts>/`로 이동, JSON·TOML은 원본 백업 후 해당 항목만 제거, `rule`은 위치만 출력(자동 수정 안 함), `existing`·`ours-core`는 출력에도 "보존"으로만 표시. 이번 범위는 작성·dry-run 시험까지.

### 2-5. 게시 모델 — push = 세 머신 배포

autoUpdate가 켜져 있어 main에 push하면 세 머신이 마켓플레이스 사본과 버전이 바뀐 플러그인을 받을 수 있다. 그래서 순서를 "어디에 커밋하는가"로 나눈다.

| 변경 | main에 바로 가도 되는가 | 근거 |
|---|---|---|
| `tools/agent-orchestrator/` 추가(S1~S2) | **예** | 새 폴더 추가뿐이고 어떤 플러그인 버전도 바뀌지 않는다. 자동 갱신은 사본에 파일을 놓을 뿐 `install.sh`는 실행하지 않으며, 기존 규칙·스크립트 어디에서도 부르지 않는다. 기존 동작 변경 0. 확인: push 전 `git diff --stat main..`이 `tools/`·`docs/plans/`·리포 `CLAUDE.md`/README 한 줄 밖을 건드리지 않는지 |
| `install.sh` 실행(S3) | 별개(머신별 수동, 승인) | 링크·config는 아무도 부르지 않는 동안 무해 |
| `orca-codex-delegate` 폴더·marketplace.json 항목 삭제(D5) | **예**(S2, 태그 먼저) | 세 머신 미설치 확인. 태그 `orca-codex-delegate-v1.0.3` push 후 삭제 |
| auto-chain 2.3.0(S4) | **아니오** — 브랜치 `feat/agent-orchestrator-2.3.0`에만 push | 버전 변경 → 자동 갱신으로 진행 중 체인(helpai M1-11, office gira)이 다음 세션부터 새 정책을 읽음 |
| 전역 규칙 이관(S5) | 리포 밖 파일이라 push와 무관하지만 **적용은 S6** | 2.2.2 정책(pane 기본)과 맞물려 있어 따로 바꾸면 규칙과 스킬이 어긋남. S5는 초안 파일을 브랜치에 두고 크로스체크만 |
| main 병합 + 전역 규칙 적용(S6) | 전환 시점 | 아래 5절 조건 충족 뒤 |

## 3. 문서 이관 방식

- **규칙 문서**(`~/.claude/CLAUDE.md`·`~/.codex/AGENTS.md`·auto-chain `SKILL.md`·helpai `chain-guide.md`)에는 동작 이름과 worker 실행 3단계 기준만:
  ① 기본 = 메인 CLI 내장 서브에이전트(Claude `Agent`), 결과는 파일, 반환 한 줄
  ② 다른 CLI가 필요하면 headless 일회성 실행 + done 파일(`review-run.sh`/`review-wait.sh`, `headless-run.sh`)
  ③ pane worker(`pane-open`·`agent-start`·`agent-send`)는 사용자가 지켜보며 끼어들 작업·작업 도중 메인과 대화가 필요한 작업·**메인 세션보다 오래 살아야 하는 작업**(세션 인계, 인계를 넘겨 살아야 하는 planner)만. 근거 한 줄(M1-10 회수 179분, 정지 오판, `agent_not_ready`).
  ③에서 10·11·12를 받으면 ①·②로 내려간다. ①로 내려간 작업은 현재 세션 안에서 끝나야 한다(인계 전 회수 필수 — BLOCK 2).
- 탭·pane 한글 이름 규칙은 동작 수준으로 유지: "`tab-open`·`pane-open`·`self-name`의 이름은 항상 한글, 에이전트 이름은 영문 정규식".
- **툴별 특이사항**(`--no-focus`, split 이름 없음→rename, `--timeout`은 `--wait`와만, `agent_status` 의미, jsonl 경로 규칙, 신뢰 확인 화면, 오른쪽 열 배치 실측, `--machine` 예외)은 `tools/agent-orchestrator/docs/herdr.md` 한 곳에만. 규칙 문서는 "툴 특이사항: `docs/<backend>.md`" 한 줄로 가리킨다.
- **auto-chain 활성 문서 전체가 이관 대상**(BLOCK 4): `SKILL.md`, `README.md`, `references/backend-herdr.md`, `references/task-brief.md`(17줄 worker 메시지 → `agent-orchestrator agent-send <조정자 pane> "[worker …] …"`, 실패 10·11·12면 보고서 `- 진행:` 줄만), `references/sol-review.md`(121줄 실행 분기 → `review_view` 기준 headless/`pane-run`, orca 분기 삭제), `references/planning.md`·`profile.md`(현재 herdr 0건이지만 검사 범위에 포함), 스크립트·시험. 종료 검사는 `grep -rn -i 'herdr\|orca' plugins/auto-chain`에서 허용 목록(`CHANGELOG`·README 버전 이력 줄·`docs/herdr.md` 포인터·래퍼 파일의 호환 주석) 외 0건.
- 전역 CLAUDE.md 43번째 줄 herdr 규칙 ①~⑨와 「후속 세션 인계 프로토콜」 herdr 절 → 동작 이름 버전으로 다시 쓰고, 원문과 이관 경위는 `CLAUDE_HISTORY.md`에 날짜 항목으로(기존 herdr 13곳은 역사 기록이라 수정 안 함).
- 메모리: helpai 2파일·gchat-g-on 1파일의 명령 예시를 동작 이름으로. herdr-ios 3파일 제외. gchat-g-on 원격 prompt는 D7 예외로 그대로 두고 manifest `allow`.
- **Orca 잔재 삭제(D5)**: auto-chain `references/backend-orca.md`·SKILL.md orca 분기·sol-review.md orca 분기·README orca 서술 제거(S4 브랜치, 복원은 기존 태그 `auto-chain-v1.7.1-orca`). `plugins/orca-codex-delegate/`와 marketplace.json 항목 제거(S2, 먼저 태그 `orca-codex-delegate-v1.0.3`). 세 머신 미설치 확인됨 — S2 착수 때 `installed_plugins.json`을 다시 확인하고 설치돼 있으면 uninstall.

## 4. auto-chain 2.3.0 (브랜치 `feat/agent-orchestrator-2.3.0`)

| 항목 | 변경 |
|---|---|
| 백엔드 선택 §1-1 | `backend: herdr\|orca\|agent` → 실행 단계 선택. 웨이브 worker 기본 = ① `Agent`(`auto-chain:<역할>`, `run_in_background`, 같은 웨이브 한 메시지 병렬). `agent-orchestrator backend`는 ③이 필요할 때만 조회 |
| 웨이브 구현·BLOCK 수정 | ① `Agent`. 모델·effort는 `Agent`의 `model`·`effort`로 지정(sonnet medium 허용 유지) |
| 롤링 분해·다음 마일스톤 planner(BLOCK 2) | 현 SKILL.md:90은 "마감 때 planner가 안 끝났으면 남긴 채 인계, child가 회수"를 허용하고, `backend-herdr.md` §8은 child가 부모 pane을 닫는다. `Agent` 서브에이전트는 부모 세션에 속해 child가 승계할 수 없다. 그래서: **③ 백엔드가 있으면 planner는 ③ pane 유지**(인계를 넘겨 사는 작업). ③을 쓸 수 없으면(10·11·12) ① `Agent`로 돌리되 **인계 전 planner 완료·회수가 필수 조건**이 된다 — 마감 뒤 planner를 기다리고, 그 대기를 상태 파일 `## 시간`에 기록. SKILL.md:90의 예외 문장을 "③ planner에만 적용"으로 고친다 |
| `chain-planner-deep`(최초 계획) | ③ pane 유지(D2). 10·11·12면 ① |
| Sol 검토·원인 조사 | ② headless 기본(D1: `review_view: headless` — `run_in_background` + `review-wait.sh`). `review_view: pane`이면 `pane-open` + `pane-run`. helpai는 프로파일에서 `pane` 유지(S6에서 helpai가 재판단) |
| `worker:opencode` 비리뷰 실행 | ② 확장: `scripts/headless-run.sh <cli> <지시서> <done>` 추가(같은 done 형식, verdict 없이 exit·snapshot) |
| 마일스톤 인계 | ③ `tab-open` + `agent-start` + `agent-send --confirm` |
| worker → 조정자 메시지 | `task-brief.md` 17줄을 `agent-orchestrator agent-send`로. ① Agent worker는 메시지 없이 반환 한 줄(완료 알림이 옴) |
| `herdr-stall-watch.sh` | `agent-stall-watch.sh`로, `agent-status`·`agent-transcript`만 사용(transcript 10이면 상태만으로 감시하고 `감시 불가 · transcript unsupported` 줄). **pane worker가 있는 웨이브에만** Monitor 기동. 옛 이름은 2.3.x 동안 래퍼 |
| `herdr-spawn-worker.sh` | 배치·split·rename·중복 검사는 어댑터 `pane-open --parent`·`agent-start`로 올린다. 스킬에는 `spawn-pane-worker.sh`(ROLE 해석·PERM_FLAGS argv 판정·첫 지시·성공 줄 형식 — auto-chain 고유 정책)만. 5번째 인자 `main-pane`은 `--parent`로 전달(NOTE 1). 출력 `OK name=… pane=… jsonl=…`(jsonl은 `agent-transcript`, 10이면 `jsonl=unsupported`)·종료 코드 2~6 유지. 어댑터의 10·11·12는 **변환하지 않고 같은 코드로 그대로 전달**한다(호출자가 내려감·알림을 고를 수 있게 — 2회차 NOTE 2). 옛 이름은 래퍼 |
| `backend-herdr.md` | `references/pane-worker.md`(동작 이름, ③ 전용)로 축소. 실측 특이사항은 `tools/agent-orchestrator/docs/herdr.md`로. 옛 경로에는 포인터 한 줄 파일을 2.3.x 동안 남김(진행 중 handoff·가이드가 가리킴) |
| 시험(BLOCK 3) | 기존 56건의 **검증 목적**을 유지한다. 그대로 두면 깨지는 케이스: `sp-neg-until`(sed 대상이 래퍼가 됨). 변경: 변형 대상을 실제 구현 위치인 `tools/agent-orchestrator/adapters/herdr.sh`로 옮긴다 — `tools/agent-orchestrator`를 `$T/ao`로 복사, 사본 어댑터에서 `--until done` 제거(제거됐는지 grep으로 먼저 확인), `AGENT_ORCHESTRATOR_HOME=$T/ao`로 spawn 실행 → rc=6. sp 계열은 래퍼·신규 경로 양쪽으로 돌린다. 신규: 가짜 `agent-orchestrator`로 spawn 계약(10·11·12 각각 **같은 코드 그대로** rc=10·11·12와 stderr 사유), `--parent` 전달 호환(`HERDR_PANE_ID` 없이 5번째 인자로 배치 — 기존 시험과 같은 조건). 집계는 케이스 이름 목록 diff로 "기존 56개 이름이 모두 있음"을 확인 |
| 버전 | plugin.json·marketplace.json 2.3.0 동기화, README(orca 서술 제거)·CHANGELOG |

## 5. 진행 중인 체인과의 전환 순서

소비자 두 곳: helpai(이 맥, M1-11 planned), office gira(`docs/chain/*/state.md`가 `herdr-spawn-worker.sh`를 가리킴).

1. S1~S3(`tools/` 추가·배포·Orca 플러그인 삭제)는 auto-chain 버전을 바꾸지 않아 두 체인과 무관하게 main에 간다(2-5 표).
2. S4·S5는 브랜치에만. main은 2.2.2 그대로라 자동 갱신이 일어나도 두 체인은 2.2.2를 계속 받는다.
3. **S6 전환 조건**(모두 충족, D4):
   - helpai M1-11 마감(`chain-state.md`에 done) 그리고 다음 마일스톤 조정자 미기동, 또는 사용자가 지정한 경계.
   - office gira: 진행 중인 체인이 있으면 마일스톤 경계까지 대기, 사용자 확인(그 체인 상태 파일 확인 — 읽기만).
   - 전환 직전 세 머신에서 실제 선택된 auto-chain 캐시 경로와 `installed_plugins.json`의 auto-chain 버전을 기록(NOTE 4 — 폴더 공존이 고정을 증명하지 않으므로 전후 실측).
4. S6 순서: 브랜치 main 병합·push → 세 머신 marketplace 갱신 확인(자동 또는 수동 `/plugin marketplace update`) → 설치 버전 2.3.0 실측 → 전역 규칙 초안 적용(세 머신, 백업 후) → helpai `chain-guide.md` 반영(helpai 소유 — helpai 조정자 또는 승인 세션):
   - 39~51줄 실행 수단 표 → 3단계 기준. `herdr-spawn-worker.sh` → `spawn-pane-worker.sh`(③일 때만).
   - 47줄 대리 보고 ID: pane worker는 `agent-orchestrator agent-session-id`(UUID, 기존 Q24 `session:<UUID>`와 같은 값), Agent worker 값은 helpai가 결정(D8 제안 `agent:<agentId>`).
   - 88줄 "Orca로 대신 열지 않는다"는 Orca 삭제로 의미가 없어지므로 "③ 불가 시 인계 문서만 남김"으로.
   - 160~166줄 인계 명령 → 동작 이름.
   - 프로파일 `review_view: pane`(D1).
5. SKILL.md "프로젝트 가이드 충돌 검사"(30줄)는 2.3.0에서 "3단계 기준 우선, 가이드가 명시적으로 pane을 요구하면 ③ 허용"으로. helpai 가이드 반영 전에도 충돌이 상태 파일 `## 결정`에 기록되고 진행된다. 옛 스크립트 이름 래퍼·`backend-herdr.md` 포인터 덕에 가이드가 옛 경로를 가리켜도 깨지지 않는다.
6. gira 쪽 상태 파일의 옛 경로는 래퍼로 계속 동작. 정리는 gira 다음 체인 착수 때(범위 밖, backlog).

## 6. 세션 단계

각 단계 종료: 게이트(시험) → 진행 기록 → commit(사용자 정책) → handoff → 다음 세션.

| 세션 | 내용 | 종료 조건·검증 | 다음 첫 착수 |
|---|---|---|---|
| **S1** 핵심·어댑터 (main) | `tools/agent-orchestrator/` bin·lib·adapters/herdr.sh·adapters/README.md·test. 16개 동작 | `test/run-tests.sh` 전부 PASS: 동작별 정상·종료 코드 2~7. **PATH 격리**(NOTE 3): 시험은 `env -i PATH="$FAKE:/usr/bin:/bin" HOME="$T/home"`로 돌려 실제 `/opt/homebrew/bin/herdr`가 잡히지 않게 하고, 첫 케이스로 `command -v herdr`가 가짜인지 확인. 음성 대조: `AGENT_ORCHESTRATOR_BACKEND=none`→11, `HERDR_ENV` 없음→11, 어댑터 없는 동작→10, 어댑터 파일 제거→12, 가짜 herdr 제거(격리 PATH)→12, 가짜 herdr에 `--kind codex`로 등록된 agent 이름을 넘긴 `agent-transcript <이름>`→10(2회차 NOTE 1 — 계약 인자 형식 그대로). 실제 herdr pane에서 읽기 동작(`backend`·`whoami`·`list`·`agent-status`) 1회 | S2 |
| **S2** 설치 목록·배포 준비·Orca 플러그인 삭제 (main) | core/herdr manifest, install.sh(`--check`), uninstall-backend.sh(dry-run), docs/herdr.md, 리포 CLAUDE.md·README 한 줄. 태그 `orca-codex-delegate-v1.0.3` 생성 후 `plugins/orca-codex-delegate/`·marketplace.json 항목 삭제(D5), 루트 `README.md`(·`README.ko.md`)의 이 플러그인 소개·설치 명령·Skill 호출 안내 절 삭제(2회차 NOTE 3) | `install.sh --check herdr` 이 맥 전부 존재. uninstall dry-run이 `existing`(herdr-ios 신뢰·Rex)과 `ours-core`를 "보존"으로 표시하고 파일 변경 0(전후 `shasum`). 실제 herdr pane에서 `pane-open "시험 pane"`→`close` 1회. push 전 `git diff --stat`이 `tools/`·`plugins/orca-codex-delegate/`·marketplace.json·리포 CLAUDE.md·루트 README(.ko).md 밖 0, `grep -n orca-codex-delegate README.md README.ko.md .claude-plugin/marketplace.json` 결과 0 | 사용자 승인 → 태그·main push |
| **S3** 세 머신 배포 | 자동 갱신 또는 수동 update 확인 → 세 머신 `install.sh` → `--check herdr` | 각 머신 **유효한 herdr pane 안에서** `~/.local/bin/agent-orchestrator backend` → `herdr`(양성, NOTE 3). 비로그인 ssh에서는 11(12가 아님)인지 확인 — 11과 12를 구분해 기록. 세 머신 `installed_plugins.json`에 orca-codex-delegate 없음 | S4(브랜치 생성) |
| **S4** auto-chain 2.3.0 (브랜치) | spawn-pane-worker.sh·agent-stall-watch.sh·headless-run.sh·래퍼·포인터 파일, SKILL.md·README·task-brief.md·sol-review.md·pane-worker.md, backend-orca.md 삭제, 버전 동기화 | `run-tests.sh` 기존 56 이름 전부 존재·PASS + 신규 PASS(`collected` 총계 대조). 3절 grep 종료 검사 허용 목록 외 0. **codex 크로스체크(무거운 게이트)**. 브랜치에만 push | S5 |
| **S5** 전역 규칙·메모리 초안 (브랜치) | 이 맥·office·홈 `~/.claude/CLAUDE.md`·`~/.codex/AGENTS.md` 이관안과 CLAUDE_HISTORY 항목, 메모리 3파일 변경안을 브랜치 `docs/plans/2026-11-xx-agent-orchestrator-rules-draft.md`에 작성(실제 파일은 안 고침) | 초안 적용 시 잔존 수(`--check` 시뮬레이션)가 `allow` 외 0. **codex 크로스체크(무거운 게이트)** — 전역 규칙 | 5절 전환 조건 확인 → S6 |
| **S6** 전환 | 5절 3·4 순서: 병합·push, 버전 실측, 전역 규칙 적용(세 머신, 백업), 메모리, helpai chain-guide | 세 머신 설치 버전 2.3.0 실측, `--check herdr` 잔존 0(allow 외), 다음 helpai 웨이브에서 ① Agent worker 기동·회수 1회와 인계 ③ 1회 성공 증거(상태 파일) | 종료. 회고 → backlog(gira 경로 정리) |

## 7. 되돌리기·고위험 지점

| 지점 | 위험 | 되돌리기 | 크로스체크 |
|---|---|---|---|
| `tools/` main push(S1~S2) | 낮음 — 기존 동작 변경 0 | `git revert` + push(자동 갱신으로 세 머신에 반영) | — |
| Orca 플러그인 삭제(S2) | 낮음 — 미설치 | 태그 `orca-codex-delegate-v1.0.3`에서 폴더·항목 복원 | — |
| `~/.local/bin` 링크·config(S3) | 낮음 | 링크·config 보관 | — |
| auto-chain 2.3.0 main 병합(S6) | **높음** — 자동 갱신으로 세 머신의 진행 중 체인에 즉시 반영 | 병합 커밋 `git revert` + push → 자동 갱신으로 2.2.2 내용 복귀(버전 번호는 2.3.1 등으로 다시 올려야 갱신이 일어날 수 있음 — S6 전에 실측 방법 확정). "프로파일 버전 고정"은 현재 기능이 없어 되돌리기 수단으로 쓰지 않는다(NOTE 4). 전환 직전 기록한 캐시 경로·버전이 복귀 확인 기준 | **필수(S4)** |
| 전역 `~/.claude/CLAUDE.md`·`~/.codex/AGENTS.md`(세 머신, S6) | **높음** — 모든 세션 동작 | 편집 전 `~/.claude/archive/claude-md-<ts>.md` 등 백업, 복원 | **필수(S5)** |
| `settings.json`·`hooks.json`·`config.toml` | **높음** — 이번 범위에서 수정 없음(manifest 기재만). herdr-ios 신뢰 항목은 `existing`으로 영구 보존 | — | 실행 시 필수 |
| helpai chain-guide | 중간 — 다른 체인 소유 | helpai 리포 `git revert` | helpai 게이트 범위 |
| 메모리 파일 | 낮음 | 편집 전 사본 보관 | — |

## 8. 사용자 결정 (결정됨)

| 항목 | 결정 |
|---|---|
| D1 리뷰 실행 화면 | **결정됨** — headless 기본(`review_view: headless`, `run_in_background` + `review-wait.sh`). `pane`은 선택지. helpai는 프로파일에서 `pane` 유지, S6에서 helpai가 재판단 |
| D2 `chain-planner-deep` | **결정됨** — pane ③ 유지, 10·11(·12)이면 ① Agent |
| D3 홈 PATH | **결정됨** — 추가하지 않음. `~/.local/bin/agent-orchestrator` 절대 경로 호출. 재측정: 홈 로그인 셸에도 없음, office는 로그인 셸에만 |
| D4 2.3.0 반영 시점 | **결정됨** — helpai M1-11 마감 뒤. autoUpdate 때문에 "반영 보류" = "main 병합 보류"로 구현(2-5·5절) |
| D5 Orca 잔재 | **결정됨** — 삭제. `orca-codex-delegate` 폴더·marketplace.json 항목(태그 `orca-codex-delegate-v1.0.3` 먼저), auto-chain `backend-orca.md`·orca 분기(기존 태그 `auto-chain-v1.7.1-orca`). 세 머신 설치 시 uninstall(현재 미설치) |
| D6 링크 대상 | **결정됨** — 세 머신 모두 마켓플레이스 사본. 개발 중 시험은 개발 리포 경로 직접 호출 |
| D7 `--machine` | **결정됨** — 이번 범위 제외. gchat-g-on 원격 prompt는 `docs/herdr.md` 알려진 예외 + manifest `allow` |
| D8 helpai 대리 보고 ID | **결정됨** — helpai 쪽이 S6에서 결정. 제안: Agent worker `agent:<agentId>`, pane worker 기존 `session:<UUID>`(`agent-session-id`) |

남은 확인(새 결정 아님, S6 전 실측): 홈 맥미니 autoUpdate 기본값 동작, revert 뒤 자동 갱신이 버전 번호 변경 없이 일어나는지.

## 9. 1회차 크로스체크 반영

리뷰어 codex Sol high, 판정 BLOCK(BLOCK 5·NOTE 4). 메인이 BLOCK 1~5를 원본 줄에서 확인함.

| finding | 반영 위치 / 어떻게 |
|---|---|
| BLOCK 1 `agent-session` 반환값 불일치·codex 경로 | §1-2·§1-3·§4·§5-4 / `agent-session-id`(UUID)와 `agent-transcript`(경로, claude만, 그 밖 kind는 10)로 분리. helpai 47줄은 `agent-session-id`로 교체, stall-watch는 `agent-transcript` |
| BLOCK 2 Agent planner의 인계 생존 | §3 ③ 정의·§4 planner 행 / 인계를 넘겨 사는 planner는 ③ 유지, ③ 불가로 ①에 내려가면 인계 전 완료·회수를 필수로. SKILL.md:90 예외를 ③ planner로 한정 |
| BLOCK 3 음성 대조가 래퍼에서 무효 | §2-1(`AGENT_ORCHESTRATOR_HOME`)·§4 시험 행·S4 / 변형 대상을 사본 `adapters/herdr.sh`로 옮기고 사본 위치를 환경 변수로 지정, 케이스 이름 목록으로 기존 56개 존재 확인 |
| BLOCK 4 task-brief.md·sol-review.md 누락 | §0·§3·§4·S4 / 두 파일과 README를 수정 대상에 추가, 활성 문서 전체 grep 종료 검사(허용 목록 외 0) |
| BLOCK 5 herdr-ios 신뢰 항목을 제거 대상으로 잡음 | §0·§2-4·§7 / `existing`(보존)으로 변경, 메모리 폴더도 `existing`. `existing`은 uninstall이 건드리지 않음을 계약에 명시 |
| NOTE 1 `main-pane` 인자 | §1-2 `pane-open --parent`·§4 spawn 행·시험 / 반영 — 5번째 인자를 `--parent`로 전달, `HERDR_PANE_ID` 없는 호환 시험 |
| NOTE 2 manifest에 링크·config 없음 | §2-4 / 반영 — `core.manifest`에 `ours-core`로 추가, 백엔드 교체 때 보존 규칙 명시 |
| NOTE 3 PATH 격리·11 허용 게이트 | §1-1(코드 12 신설)·S1·S3 / 반영 — 시험 `env -i` PATH 격리와 가짜 바이너리 확인, 어댑터 결함 12를 11과 분리, S3에 머신별 pane 안 양성 검증 |
| NOTE 4 캐시 공존≠버전 고정·autoUpdate·프로파일 고정 없음 | §0·§2-5·§5-3·§7 / 반영 — push=게시 모델로 S4·S5를 브랜치에 두고 S6에 병합, 전환 직전 캐시 경로·버전 실측 기록, 되돌리기 수단에서 프로파일 고정 삭제 |
| 메인 추가 사실: autoUpdate true | §0·§2-5·§5·§7 / "커밋만, update 보류" 삭제. tools/ 추가는 플러그인 버전 불변·아무도 부르지 않아 main에 가도 무해, auto-chain 정책 변경은 브랜치 → S6 병합 |
| 추가 발견(이번 반영 중 조사): office gira 체인도 auto-chain 소비자 | §0·§5 / S6 전환 조건에 gira 진행 체인 경계 확인 추가, 옛 경로는 래퍼로 유지 |

## 10. 2회차 크로스체크 반영

리뷰어 codex Sol high, 판정 **SHIP**(1회차 9건 모두 해소, 새 BLOCK 0, NOTE 3). 가벼운 NOTE라 메인이 직접 반영하고 재검토 없이 확정한다.

| finding | 반영 위치 / 어떻게 |
|---|---|
| NOTE 1 시험의 `agent-transcript --kind codex`가 계약 인자와 다름 | S1 / 가짜 herdr에 codex kind로 등록된 agent 이름을 넘기는 형식으로 수정 |
| NOTE 2 spawn이 10·11·12를 어떻게 전달하는지 미정 | §4 spawn 행·시험 행 / 변환 없이 같은 코드로 전달, 시험도 정확한 코드로 기대 |
| NOTE 3 [backlog] 루트 README의 orca-codex-delegate 안내 누락 | S2 / README(.ko) 해당 절 삭제를 범위에 추가, diff 허용 목록과 grep 0 검사 추가 |
