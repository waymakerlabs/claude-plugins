# 어댑터 작성 계약

`bin/agent-orchestrator`는 인자를 검사한 다음 백엔드를 고르고 `adapters/<백엔드>.sh`를 source해서 `op_<동작>` 함수를 부릅니다(동작 이름의 `-`는 `_`로 바꿉니다). 동작 계약(인자·stdout·종료 코드)의 원본은 `docs/plans/2026-11-08-agent-orchestrator-plan.md` §1입니다.

## 반드시 지킬 것

| 항목 | 규칙 |
|---|---|
| 로딩 완료 표시 | 파일 마지막 줄에 `AO_ADAPTER_OK=1`. 이 값이 없으면 진입점이 12(adapter error)로 끝냅니다 |
| 전제 검사 | `ao_adapter_check` 함수(선택). 툴 밖이면 11, 필수 바이너리가 없으면 12, 서버 장애면 4로 끝냅니다. `backend` 동작 전에도 실행됩니다 |
| 지원하지 않는 동작 | 함수를 정의하지 않습니다. 진입점이 10(unsupported)을 반환합니다. 일부 경우만 지원하지 않는다면(예: kind별) 함수 안에서 `ao_die 10 …` |
| 인자 | 진입점이 검사를 마친 위치 인자로 받습니다(아래 표). 어댑터에서 다시 검사하지 않습니다 |
| 출력 | stdout은 값 한 줄. `agent-read`와 `list`만 여러 줄을 냅니다. 사유와 경고는 `ao_warn`/`ao_die`로 stderr에 씁니다 |
| 종료 코드 | 2 인자 · 3 대상 없음/충돌 · 4 백엔드 실패/해석 실패 · 5 준비 안 됨 · 6 blocked · 7 timeout · 10 · 11 · 12. 툴의 오류 코드를 이 값으로 옮기는 일은 어댑터가 합니다 |
| 서브셸 | `$(…)` 안에서 `ao_die`를 부르면 서브셸만 끝납니다. 값을 받는 줄에는 `|| exit $?`를 붙입니다 |
| JSON | `lib/common.sh`의 `ao_json`(식)이나 `ao_jsonx`(문장, 결과는 `R`)를 씁니다. 외부 값은 환경 변수로 넘깁니다(`AO_X=… ao_json "E['AO_X']"`) |
| 이름 | `tab-open`·`pane-open`은 호출자가 넘긴 이름을 그대로 씁니다. `self-name`은 대상 자리에 `-`를 받으면 그 대상을 건너뛰고(어댑터의 `op_self_name`이 처리), 나머지 대상은 현재 label로 판정합니다 — 빈 값·숫자만이면 인자 그대로, 이미 `[XX] ` 접두어면 유지(경고), 그 밖(사용자 이름)은 본문을 두고 인자의 접두어만 앞에 붙입니다(인자에 접두어가 없으면 유지). force가 1이면 판정 없이 바꿉니다. 에이전트 이름은 `[a-z][a-z0-9_-]{0,31}` |
| 포커스 | 탭이나 pane을 열어도 사용자 포커스를 옮기지 않습니다 |

## 함수 인자(진입점이 넘기는 순서)

| 함수 | 인자 |
|---|---|
| `op_whoami` | `pane\|tab\|workspace\|tab-label\|pane-label` (`*-label` = 현재 이름, 없으면 빈 출력) |
| `op_tab_open` | `<이름> <절대 cwd>` |
| `op_pane_open` | `<이름> <parent 또는 빈 값> <절대 cwd>` |
| `op_self_name` | `<force 0\|1> <탭 이름> [<pane 이름>]` |
| `op_agent_start` | `<에이전트 이름> <pane id> <kind> [CLI 인자…]` |
| `op_agent_send` | `<대상> <한 줄> <confirm 0\|1>` |
| `op_agent_wait` | `<대상> <초>` |
| `op_agent_status` · `op_agent_session_id` · `op_agent_transcript` | `<대상>` |
| `op_agent_read` | `<대상> <줄 수>` |
| `op_agent_keys` | `<대상> <키>` |
| `op_pane_run` | `<pane id> <셸 문자열>` |
| `op_close` | `<pane id>` |
| `op_list` | `agents\|panes` |

`<대상>`은 에이전트 이름이나 pane id(`<workspace>:<pane>`)입니다. 둘을 구분하려면 `ao_is_pane`을 씁니다.

## 새 백엔드 추가(예: Rex)

1. `adapters/rex.sh`: 위 함수 중 지원하는 것만 작성하고 마지막 줄에 `AO_ADAPTER_OK=1`.
2. `bin/agent-orchestrator`의 자동 판단 자리(주석 `(예약) Rex`)에 판정 줄 하나.
3. `manifests/rex.manifest`: 그 툴의 설치물 목록(S2 형식).
4. `test/run-tests.sh`에 가짜 바이너리 시험 묶음. PATH를 격리하고 음성 대조(10·11·12)를 포함합니다.
5. 툴 특이사항은 `docs/rex.md` 한 곳에만 적습니다.
