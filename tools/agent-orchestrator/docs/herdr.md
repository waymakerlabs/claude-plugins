# herdr 특이사항 (agent-orchestrator 어댑터 `adapters/herdr.sh`)

herdr 관련 툴 특이사항은 이 문서 한 곳에만 둔다. 규칙 문서(전역 CLAUDE.md·AGENTS.md·auto-chain SKILL.md)는 동작 이름만 쓰고 "툴 특이사항: `tools/agent-orchestrator/docs/herdr.md`" 한 줄로 이 문서를 가리킨다. 실측 기준은 herdr 0.9.5(`/opt/homebrew/bin/herdr`, 세 머신 같음)다.

## 전제·판정

- herdr pane 안이면 `HERDR_ENV=1`과 `HERDR_PANE_ID`·`HERDR_TAB_ID`·`HERDR_WORKSPACE_ID`가 설정된다. `HERDR_ENV≠1`이면 어댑터는 11(no backend)을 돌려준다. 설정 파일이 `backend=herdr`여도 마찬가지다.
- `herdr status server` 출력에 `status: running`이 없으면 4.
- 하위 명령에 `--help`를 붙여도 최상위 사용법만 나온다(`herdr pane split --help` 무효). 옵션의 진본은 이 문서와 어댑터 코드다. 맨 `herdr`는 TUI를 띄우므로 스크립트에서 실행하지 않는다.

## 응답 형식 (실측)

- 응답은 공백 없는 압축 JSON 한 줄. 성공 `{"id":"cli:<그룹>:<동작>","result":{…}}`.
- 오류는 stderr에 `{"error":{"code":…}}` + exit 1. 어댑터 변환: `*_not_found`→3, `agent_not_ready`→5, `agent_blocked`→6, `timeout`→7, 그 밖·해석 실패→4.
- `pane split` → `result.pane.pane_id`(`type: pane_info`).
- `tab create` → `result.root_pane.pane_id` + `result.tab`(`type: tab_created`). 실측 예(S2):
  `{"result":{"root_pane":{…,"pane_id":"w2:p19","tab_id":"w2:tB",…},"tab":{"label":"시험 탭","pane_count":1,"tab_id":"w2:tB",…},"type":"tab_created"}}`
  어댑터는 `root_pane.pane_id`를 먼저 읽고, 없으면 응답의 첫 `pane_id`로 내려간다(옛 인계 명령의 `grep … | head -1`과 같은 결과).
- `pane close` → `{"result":{"type":"ok"}}`.
- `pane layout --pane <id>` → `result.layout.panes[].rect{x,y,width,height}`. 오른쪽 열 판정은 기준 pane보다 `x`가 큰 pane.
- `agent list`에는 이름 없는 agent(herdr가 감지만 한 codex 등)가 섞인다 → `list --agents`의 이름 칸 `-`.

## 동작별 주의

- **포커스**: `tab create`·`pane split`에 항상 `--no-focus`. 사용자가 보던 pane을 빼앗지 않는다.
- **이름**: `pane split`에는 이름 옵션이 없다 → split 직후 `pane rename <id> "<한글>"`. 이름 붙이기 실패는 경고만 하고 계속한다. 탭은 `tab create --label`. 탭·pane 이름은 역할 접두어(`[OC]`/`[WO]`/`[RV]`) + 한글, 에이전트 이름은 `[a-z][a-z0-9_-]{0,31}`(herdr 정규식).
  - **자기 이름 `self-name [--force] <탭|-> [<pane|->]`**(`-` = 그 대상 건너뜀): 대상마다 `tab get`/`pane get`의 현재 `label`로 판정한다. 빈 값·숫자만(herdr 기본 번호) → 인자 그대로 `tab rename`/`pane rename`. 이미 `[XX] `(대문자 2자) 접두어 → 유지(stderr "이름 유지"). 그 밖(사용자가 붙인 이름 — 영문·한글 무관) → 본문은 두고 인자의 접두어만 앞에 붙인다(`Peter review` → `[OC] Peter review`, 인자에 접두어가 없으면 유지). `--force`는 판정·조회 없이 바로 rename — 주제가 바뀌었고 **현재 이름을 이 세션이 붙였을 때만** 쓴다.
  - **탭 가드**: 탭 자리가 `-`이고 pane 인자가 `[OC] `로 시작하면(대기 표시 `self-name --force - "[OC] … · 대기 …"` 등) 탭을 한 번 판정 없이 확인한다. 이미 `[XX] `면 그대로, 사용자 이름이면 `[OC] <이름>`, 빈 값·숫자면 `[OC] <pane 본문의 첫 " · " 앞>`. 바꾸면 stderr `탭 접두어 보정: 옛 → 새`, 실패는 경고만(pane 종료 코드 그대로). `[WO]`/`[RV]` pane이면 탭은 건드리지 않는다.
  - **시작 묶음 `session-init <OC|WO|RV> <이름> [--tab <탭>] [--inbox <경로|pane>]...`**: self-name(OC = 탭+pane, WO/RV = pane만) + `--inbox`마다 폴더 생성·`inbox-subscribe`를 한 번에 하고 `session-init role=… tab=… pane=… subs=N` 한 줄을 낸다. herdr 밖이면 이름만 건너뛴다(구독은 함, 0).
  - **이름 읽기**: `whoami --field tab-label` / `--field pane-label` = `tab get`/`pane get`의 `label` 한 줄(없으면 빈 출력). 붙인 뒤 확인은 이것으로 한다(`list --panes`는 pane label만 보인다).
- **배치**: 오른쪽 영역(탭 맨 왼쪽 열보다 `x`가 큰 pane 전부)이 비면 기준 pane을 `--direction right`, 있으면 오른쪽 영역에서 가장 높은 pane을 `--direction down --ratio 0.5`(2개 반반, 4개 4등분). 기준 pane이 오른쪽 영역 안에 있어도(자식 조정자가 worker를 띄울 때) 새 열을 만들지 않고 오른쪽에서 아래로 쌓는다(2026-11-14). (2026-11-13) 기본은 개수 제한이 없다(`AGENT_ORCHESTRATOR_MAX_RIGHT` 기본 999 — 탭 하나 = 체인 하나, 부모 왼쪽·자식 오른쪽). 이 값을 작게 주면 그 수를 넘칠 때 넘침 탭(기본 `[WO] 작업 넘침` — 역할 접두어, `AGENT_ORCHESTRATOR_OVERFLOW_TAB`)을 재사용하거나 만든다. 넘침 탭 첫 pane이 빈 셸이면 그대로 쓴다.
- **자리 바꾸기 `pane-swap <a> <b>`**: `pane swap --source-pane <a> --target-pane <b>`. 인계에서 새 조정자가 옛 조정자(왼쪽)를 닫기 직전에 자기와 자리를 바꾼다.
- **cwd**: `--cwd`는 호출자의 신뢰된 폴더. 처음 보는 폴더는 Claude Code 폴더 신뢰 화면에서 멈춰 `agent start`가 `agent_not_ready`(→5)가 된다. 신뢰를 대신 승인하지 않는다 — `agent-read`로 화면 확인 → `agent-keys <이름> Escape` → 신뢰된 cwd로 다시 연다.
- **agent start**: `--timeout 90000`. 이름 중복은 herdr가 막지 않을 수 있어 어댑터가 `agent list`로 먼저 검사한다(중복 3).
- **agent prompt**: `--timeout`은 `--wait`와 함께만 유효하다. `--confirm` = `--wait --until working --until done --timeout 60000`. 빠른 완료(prompt 직후 바로 done)는 `--until done`이 없으면 대기가 성공하지 않는다 — 계약의 일부(음성 대조 `neg-send-until-done`). 프롬프트는 한 줄(개행은 Enter로 해석돼 중간 제출).
- **agent wait**: `--until done --until idle --timeout <ms>`. timeout 오류 코드는 `timeout`(→7, 실패 아님).
- **agent_status 의미**: `working`(일하는 중) / `done`(턴 끝, 확인 전) / `idle`(입력 대기) / `blocked`(권한·질문 대화상자 — prompt가 `agent_blocked`로 거절됨, 대신 승인하지 않는다) / 그 밖 → `unknown`.
- **transcript**: kind claude만. `agent get`의 `agent_session.value`(UUID)와 `cwd` → `~/.claude/projects/<cwd의 영숫자 아닌 문자를 -로>/<UUID>.jsonl`. codex 등은 10.
- **화면**: agent는 `agent read <이름> --source visible --lines N`, pane id는 `pane read <id> --lines N`.

## 설치물 (`manifests/herdr.manifest`)

- herdr가 스스로 설치(편집 금지, 제거 때 보관만): `~/.claude/hooks/herdr-agent-state.sh`·`~/.codex/herdr-agent-state.sh`("managed by herdr", `HERDR_INTEGRATION_VERSION=11`)와 `~/.claude/settings.json`·`~/.codex/hooks.json`의 SessionStart 등록.
- 건드리지 않음(`existing`): `~/.codex/config.toml`의 `projects."/Users/peter/Dev/herdr-ios"`(herdr 자체 개발 프로젝트 신뢰 항목), 그 프로젝트 메모리, Rex SessionStart 훅.
- 점검: `install.sh --check herdr`(읽기 전용). 제거: `uninstall-backend.sh herdr`(기본 dry-run).

## 알려진 예외

- **`--machine`(원격 조작)은 범위 밖(D7).** gchat-g-on 메모리 `office-macmini-session-contact.md`의 `herdr --machine office-macmini agent prompt …`는 그대로 둔다(manifest `allow` — 잔존 검사에서 뺀다).
- 홈 맥미니 `known_marketplaces.json`에 autoUpdate 키가 없다(기본값 동작 UNVERIFIED).
