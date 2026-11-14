# adapters/herdr.sh — agent-orchestrator herdr 0.9.5 어댑터
#
# 진입점(bin/agent-orchestrator)이 인자 검사를 끝낸 뒤 source 하고 op_<동작> 함수를 부른다.
# 함수가 없는 동작 = 10(unsupported). 끝 줄 AO_ADAPTER_OK=1 이 없으면 진입점이 12로 본다.
# 툴 특이사항(실측): --no-focus, split에 이름 옵션 없음 → 직후 pane rename, agent prompt의
#   --timeout은 --wait와 함께만, 빠른 완료는 --until done 없이는 대기가 성공하지 않음,
#   오류는 {"error":{"code":…}} + 비0 종료, transcript = ~/.claude/projects/<cwd 비영숫자→->/<UUID>.jsonl
#
# 주의: $(…) 안에서 ao_die 하면 서브셸만 끝난다. 그래서 값을 받는 줄은 모두 `|| exit $?`로 코드를 올린다.
# shellcheck shell=bash

# (2026-11-13) 기본 제한 없음: 부모 탭 안 오른쪽 열에 계속 쌓는다(탭 하나 = 체인 하나). 숫자를 주면 넘침 탭 사용
AO_HERDR_MAX_RIGHT=${AGENT_ORCHESTRATOR_MAX_RIGHT:-999}
# 오른쪽 열이 찼을 때 쓰는 탭 이름(한글). 호출자(auto-chain 등)가 덮어쓸 수 있다
AO_HERDR_OVERFLOW_TAB=${AGENT_ORCHESTRATOR_OVERFLOW_TAB:-[WO] 작업 넘침}

# 전제: 11 = herdr 밖, 12 = 필수 바이너리 없음, 4 = 서버가 running 아님
ao_adapter_check() {
  [ "${HERDR_ENV:-}" = 1 ] || ao_die 11 "no backend: HERDR_ENV=1 아님 (herdr pane 밖)"
  command -v herdr >/dev/null 2>&1 || ao_die 12 "adapter error: herdr 바이너리 없음 (PATH=$PATH)"
  command -v python3 >/dev/null 2>&1 || ao_die 12 "adapter error: python3 없음"
  herdr status server 2>/dev/null | grep -q 'status: running' \
    || ao_die 4 "herdr 서버가 running 아님 (herdr status server)"
}

# hd <herdr 인자…>  — stdout은 HD_OUT, 실패 사유는 HD_ERR. 종료 코드를 계약 코드로 바꿔 돌려준다.
# herdr 오류 코드: *_not_found → 3, agent_not_ready → 5, agent_blocked → 6, timeout → 7, 그 밖 → 4
hd() {
  local errf rc code all
  errf=$(mktemp "${TMPDIR:-/tmp}/ao-herdr.XXXXXX") || { HD_ERR="mktemp 실패"; return 4; }
  HD_OUT=$(herdr "$@" 2>"$errf"); rc=$?
  all="$HD_OUT
$(cat "$errf")"
  rm -f "$errf"
  code=$(printf '%s' "$all" | ao_json "(d.get('error') or {}).get('code')" 2>/dev/null)
  if [ -z "$code" ] && [ "$rc" != 0 ]; then
    code=$(printf '%s' "$all" | grep -o 'agent_not_ready\|agent_blocked\|[a-z]*_not_found' | head -1)
  fi
  [ "$rc" = 0 ] && [ -z "$code" ] && return 0
  HD_ERR="herdr $1 ${2:-}: ${code:-exit $rc} — $(printf '%s' "$all" | tr '\n' ' ' | head -c 300)"
  case "$code" in
    *_not_found) return 3 ;;
    agent_not_ready) return 5 ;;
    agent_blocked) return 6 ;;
    timeout) return 7 ;;
    *) return 4 ;;
  esac
}

# hd_must <herdr 인자…>  — 실패면 계약 코드로 종료
hd_must() {
  hd "$@"; local c=$?
  [ "$c" = 0 ] || ao_die "$c" "$HD_ERR"
}

# hj <python 식>  — HD_OUT에 적용. 해석 실패 = 4
hj() {
  local v
  v=$(printf '%s' "$HD_OUT" | ao_json "$1") || ao_die 4 "herdr 응답 해석 실패: $(printf '%s' "$HD_OUT" | head -c 200)"
  printf '%s' "$v"
}
hjx() {
  local v
  v=$(printf '%s' "$HD_OUT" | ao_jsonx "$1") || ao_die 4 "herdr 응답 해석 실패: $(printf '%s' "$HD_OUT" | head -c 200)"
  printf '%s' "$v"
}

norm_status() {
  case "$1" in working|done|idle|blocked) echo "$1" ;; *) echo unknown ;; esac
}

# agent get → HD_OUT (없으면 3)
agent_get() { hd_must agent get "$1"; }
agent_field() {  # $1 대상, $2 python 식(a = agent 객체) → 값
  agent_get "$1"
  hj "(lambda a: $2)(d['result']['agent'])"
}

# ───────── whoami
op_whoami() {
  local v=""
  case "$1" in
    tab-label|pane-label)   # 현재 label 한 줄(없으면 빈 출력)
      local k=${1%-label} id
      if [ "$k" = tab ]; then id=${HERDR_TAB_ID:-}; else id=${HERDR_PANE_ID:-}; fi
      [ -n "$id" ] || ao_die 3 "자기 $k id 없음 (HERDR_$(echo "$k" | tr '[:lower:]' '[:upper:]')_ID)"
      hd_must "$k" get "$id"
      v=$(hj "d['result']['$k'].get('label')") || exit $?
      [ -z "$v" ] || printf '%s\n' "$v"
      return 0 ;;
    pane) v=${HERDR_PANE_ID:-} ;;
    tab) v=${HERDR_TAB_ID:-} ;;
    workspace) v=${HERDR_WORKSPACE_ID:-} ;;
  esac
  [ -n "$v" ] || ao_die 3 "자기 $1 id 없음 (HERDR_$(echo "$1" | tr '[:lower:]' '[:upper:]')_ID)"
  echo "$v"
}

need_ws() { [ -n "${HERDR_WORKSPACE_ID:-}" ] || ao_die 3 "HERDR_WORKSPACE_ID 없음"; }

# ───────── tab-open <이름> <cwd>
op_tab_open() {
  local p
  need_ws
  hd_must tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$2" --label "$1" --no-focus
  # 실측(S2, herdr 0.9.5): {"result":{"root_pane":{…,"pane_id":…},"tab":{…},"type":"tab_created"}}
  # root_pane.pane_id 를 먼저 쓰고, 없으면 응답의 첫 pane_id(문서 순서 깊이 우선 — 기존 인계 명령의
  # `grep … | head -1`과 같은 기준)로 내려간다
  p=$(hjx '
rp = (d.get("result") or {}).get("root_pane")
def walk(x):
    if isinstance(x, dict):
        for k, v in x.items():
            if k == "pane_id" and isinstance(v, str):
                return v
            r = walk(v)
            if r:
                return r
    elif isinstance(x, list):
        for v in x:
            r = walk(v)
            if r:
                return r
    return None
R = rp["pane_id"] if isinstance(rp, dict) and isinstance(rp.get("pane_id"), str) else walk(d.get("result"))
') || exit $?
  [ -n "$p" ] || ao_die 4 "tab create 응답에서 pane id를 찾지 못함: $(printf '%s' "$HD_OUT" | head -c 200)"
  echo "$p"
}

# 배치 결정 → "right <pane>" | "down <pane>" | "full" | "missing"   ($1 기준 pane, $2 상한)
pick_split() {
  hd_must pane layout --pane "$1"
  AO_BASE=$1 AO_LIMIT=$2 hjx '
ps = d["result"]["layout"]["panes"]
b = [p for p in ps if p["pane_id"] == E["AO_BASE"]]
if not b:
    R = "missing"
else:
    # 오른쪽 영역 = 탭 맨 왼쪽 열(부모)보다 x 가 큰 pane 전부. 기준 pane 이 오른쪽 영역 안에 있어도(자식 조정자가 또 띄울 때)
    # 새 열을 만들지 않고 오른쪽 영역 안에서 아래로 쌓는다 — 탭은 왼쪽 부모 열 + 오른쪽 세로 쌓기 한 열(2026-11-14 주인님 요청)
    left = min(p["rect"]["x"] for p in ps)
    right = [p for p in ps if p["rect"]["x"] > left]
    if not right:
        R = "right " + E["AO_BASE"]
    elif len(right) >= int(E["AO_LIMIT"]):
        R = "full"
    else:
        R = "down " + sorted(right, key=lambda p: (-p["rect"]["height"], p["rect"]["y"]))[0]["pane_id"]
'
}

split_pane() {  # $1 방향, $2 나눌 pane, $3 cwd → 새 pane id
  if [ "$1" = right ]; then
    hd_must pane split "$2" --direction right --cwd "$3" --no-focus
  else
    hd_must pane split "$2" --direction down --ratio 0.5 --cwd "$3" --no-focus
  fi
  hj "d['result']['pane']['pane_id']"
}

# ───────── pane-open <이름> <parent|""> <cwd>
op_pane_open() {
  local name=$1 parent=${2:-${HERDR_PANE_ID:-}} cwd=$3 plan dir target p="" tab first busy
  need_ws
  [ -n "$parent" ] || ao_die 3 "배치 기준 pane 없음 (--parent 또는 HERDR_PANE_ID)"
  plan=$(pick_split "$parent" "$AO_HERDR_MAX_RIGHT") || exit $?
  dir=${plan%% *}; target=${plan#* }
  case "$dir" in
    right|down) p=$(split_pane "$dir" "$target" "$cwd") || exit $? ;;
    full)
      hd_must tab list --workspace "$HERDR_WORKSPACE_ID"
      tab=$(AO_TAB_LABEL=$AO_HERDR_OVERFLOW_TAB hj "next((t['tab_id'] for t in d['result']['tabs'] if t.get('label')==E['AO_TAB_LABEL']),None)") || exit $?
      if [ -z "$tab" ]; then
        p=$(op_tab_open "$AO_HERDR_OVERFLOW_TAB" "$cwd") || exit $?
      else
        hd_must pane list --workspace "$HERDR_WORKSPACE_ID"
        first=$(AO_TAB=$tab hj "next((p['pane_id'] for p in d['result']['panes'] if p.get('tab_id')==E['AO_TAB']),None)") || exit $?
        [ -n "$first" ] || ao_die 4 "넘침 탭 $tab 의 pane을 찾지 못함"
        hd_must pane get "$first"
        busy=$(hj "d['result']['pane'].get('agent') or None") || exit $?
        if [ -z "$busy" ]; then
          p=$first   # 비어 있는 셸 pane은 그대로 쓴다
        else
          plan=$(pick_split "$first" "$AO_HERDR_MAX_RIGHT") || exit $?
          dir=${plan%% *}; target=${plan#* }
          case "$dir" in
            right|down) p=$(split_pane "$dir" "$target" "$cwd") || exit $? ;;
            full) ao_die 4 "오른쪽 열 ${AO_HERDR_MAX_RIGHT}개와 넘침 탭 '$AO_HERDR_OVERFLOW_TAB' 이 모두 참" ;;
            *) ao_die 4 "넘침 탭 배치 해석 실패: $plan" ;;
          esac
        fi
      fi ;;
    missing) ao_die 3 "기준 pane $parent 이 layout에 없음" ;;
    *) ao_die 4 "배치 해석 실패: $plan" ;;
  esac
  [ -n "$p" ] || ao_die 4 "pane 생성 실패"
  hd pane rename "$p" "$name" || ao_warn "pane 이름 붙이기 실패 pane=$p (계속): $HD_ERR"
  echo "$p"
}

# 이름 판정(S5 1회차 크로스체크 반영 — ASCII 기본값 판정 폐지)
#   herdr 기본 이름 = 빈 값 또는 숫자만. 역할 접두어 = 대문자 2자 `[XX] `
AO_NUM_RE='^[0-9]+$'
AO_PREFIX_RE='^(\[[A-Z][A-Z]\]) '

# label_plan <현재> <인자>  → stdout 새 label(빈 출력 = 유지)
#   빈 값·숫자만 → 인자 그대로 / 이미 접두어 있음 → 유지
#   그 밖(사용자 이름) → 본문은 두고 인자의 접두어만 앞에 붙임. 인자에 접두어가 없으면 유지
label_plan() {
  local cur=$1 arg=$2
  if [ -z "$cur" ] || [[ $cur =~ $AO_NUM_RE ]]; then echo "$arg"; return 0; fi
  [[ $cur =~ $AO_PREFIX_RE ]] && return 0
  # 아래 한 줄이 사용자 이름 보존 가드다(지우면 다음 줄로 내려가 본문을 갈아 끼운다 — 시험 neg-self-name-user-guard)
  { [[ $arg =~ $AO_PREFIX_RE ]] && echo "${BASH_REMATCH[1]} $cur"; return 0; }  # GUARD:user-name
  # shellcheck disable=SC2317  # 가드가 있으면 닿지 않는 줄(가드 제거 음성 대조용)
  echo "$arg"
}

# name_one <tab|pane> <id> <인자> <force 0|1>
name_one() {
  local kind=$1 id=$2 arg=$3 force=$4 cur new
  if [ "$force" = 1 ]; then
    hd_must "$kind" rename "$id" "$arg"
    return 0
  fi
  hd_must "$kind" get "$id"
  cur=$(hj "d['result']['$kind'].get('label')") || exit $?
  new=$(label_plan "$cur" "$arg")
  if [ -z "$new" ] || [ "$new" = "$cur" ]; then
    ao_warn "$kind 이름 유지: $cur"
  else
    hd_must "$kind" rename "$id" "$new"
  fi
}

# tab_guard <[OC] pane 인자> — 탭 이름에 역할 접두어가 없을 때만 보정(이미 [XX] 면 그대로, 조용히)
#   사용자 이름 → "[OC] <현재 이름>" / 빈 값·숫자 → "[OC] <pane 본문의 첫 ' · ' 앞, 앞뒤 공백 제거>"
tab_guard() {
  local body cur new
  [ -n "${HERDR_TAB_ID:-}" ] || return 3
  hd_must tab get "$HERDR_TAB_ID"
  cur=$(hj "d['result']['tab'].get('label')") || return 4
  [[ $cur =~ $AO_PREFIX_RE ]] && return 0
  if [ -z "$cur" ] || [[ $cur =~ $AO_NUM_RE ]]; then
    body=${1#\[OC\] }; body=${body%% · *}
    body=$(printf '%s' "$body" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$body" ] || return 0
    new="[OC] $body"
  else
    new="[OC] $cur"
  fi
  hd_must tab rename "$HERDR_TAB_ID" "$new"
  ao_warn "탭 접두어 보정: ${cur:-(빈 값)} → $new"
}

# ───────── self-name <force 0|1> <탭> [<pane>]
op_self_name() {
  local force=$1
  shift
  if [ "$1" != - ]; then   # "-" = 탭 건너뜀
    [ -n "${HERDR_TAB_ID:-}" ] || ao_die 3 "HERDR_TAB_ID 없음"
    name_one tab "$HERDR_TAB_ID" "$1" "$force"
  elif [ $# -ge 2 ] && [ "${2#\[OC\] }" != "$2" ]; then
    # 탭 가드(2026-11-13): 탭을 건너뛰어도 [OC] pane이면 탭을 한 번 판정 없이(force 0 규칙) 확인한다.
    #   하위 셸에서 돌려 실패는 경고만 — pane 이름 바꾸기의 종료 코드를 바꾸지 않는다
    ( tab_guard "$2" ) || ao_warn "탭 접두어 보정 실패(무시)"
  fi
  if [ $# -ge 2 ] && [ "$2" != - ]; then
    [ -n "${HERDR_PANE_ID:-}" ] || ao_die 3 "HERDR_PANE_ID 없음"
    name_one pane "$HERDR_PANE_ID" "$2" "$force"
  fi
}

# ───────── agent-start <이름> <pane> <kind> [CLI 인자…]
op_agent_start() {
  local name=$1 pane=$2 kind=$3 n c
  shift 3
  hd_must agent list
  n=$(AO_NAME=$name hj "sum(1 for a in d['result']['agents'] if a.get('name')==E['AO_NAME'])") || exit $?
  [ "$n" = 0 ] || ao_die 3 "이름 중복: $name 가 이미 살아 있음"
  if [ $# -gt 0 ]; then
    hd agent start "$name" --kind "$kind" --pane "$pane" --timeout 90000 -- "$@"
  else
    hd agent start "$name" --kind "$kind" --pane "$pane" --timeout 90000
  fi
  c=$?
  [ "$c" = 0 ] || ao_die "$c" "$HD_ERR — 화면 확인: agent-read $name"
  printf '%s' "$HD_OUT" | grep -q '"agent_status"' \
    || ao_die 4 "agent start 응답에 agent_status 없음: $(printf '%s' "$HD_OUT" | head -c 200)"
}

# ───────── agent-send <대상> <한 줄> <confirm 0|1>
op_agent_send() {
  local st
  if [ "$3" = 1 ]; then
    hd_must agent prompt "$1" "$2" --wait --until working --until "done" --timeout 60000
  else
    hd_must agent prompt "$1" "$2"
  fi
  st=$(agent_field "$1" "a.get('agent_status')") || exit $?
  st=$(norm_status "$st")
  case "$st" in
    blocked) ao_die 6 "대상 $1 이 사용자 입력 대기(blocked)" ;;
    unknown) [ "$3" = 1 ] && ao_die 4 "전송 뒤 상태 unknown: $1" ;;
  esac
  echo "$st"
}

# ───────── agent-wait <대상> <초>
op_agent_wait() {
  local st
  hd_must agent wait "$1" --until "done" --until idle --timeout "$(($2 * 1000))"
  st=$(agent_field "$1" "a.get('agent_status')") || exit $?
  st=$(norm_status "$st")
  [ "$st" = blocked ] && ao_die 6 "대상 $1 이 사용자 입력 대기(blocked)"
  echo "$st"
}

op_agent_status() {
  local st
  st=$(agent_field "$1" "a.get('agent_status')") || exit $?
  norm_status "$st"
}

op_agent_session_id() {
  local u
  u=$(agent_field "$1" "(a.get('agent_session') or {}).get('value')") || exit $?
  [ -n "$u" ] || ao_die 3 "세션 id 없음: $1"
  echo "$u"
}

# kind claude만 경로 규칙을 안다. 그 밖 kind = 10
op_agent_transcript() {
  local kind uuid cwd enc f
  agent_get "$1"
  kind=$(hj "d['result']['agent'].get('agent')") || exit $?
  [ "$kind" = claude ] || ao_die 10 "unsupported: kind ${kind:-?} 의 transcript 경로 규칙 없음 ($1)"
  uuid=$(hj "(d['result']['agent'].get('agent_session') or {}).get('value')") || exit $?
  cwd=$(hj "d['result']['agent'].get('cwd')") || exit $?
  { [ -n "$uuid" ] && [ -n "$cwd" ]; } || ao_die 3 "세션 id·cwd 없음: $1"
  enc=$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')
  f="$HOME/.claude/projects/$enc/$uuid.jsonl"
  [ -f "$f" ] || ao_die 3 "transcript 파일 없음: $f"
  echo "$f"
}

op_agent_read() {
  if ao_is_pane "$1"; then
    hd_must pane read "$1" --lines "$2"
  else
    hd_must agent read "$1" --source visible --lines "$2"
  fi
  printf '%s\n' "$HD_OUT"
}

op_agent_keys() { hd_must agent send-keys "$1" "$2"; }

op_pane_run() { hd_must pane run "$1" "$2"; }

op_close() { hd_must pane close "$1"; }

# pane-swap <a> <b> — 두 pane 자리 맞바꿈(인계: 새 조정자를 왼쪽 부모 자리로)
op_pane_swap() { hd_must pane swap --source-pane "$1" --target-pane "$2"; }

# ───────── list agents|panes → <id>\t<이름>\t<상태>  (빈 값은 '-')
AO_ROW_PY='def row(*xs):
    return "\t".join((" ".join(str(x).split()) if x not in (None, "") else "-") for x in xs)
def ns(s):
    return s if s in ("working", "done", "idle", "blocked") else ("unknown" if s else None)
'
op_list() {
  local v
  if [ "$1" = agents ]; then
    hd_must agent list
    v=$(hjx "${AO_ROW_PY}R = [row(a.get('pane_id'), a.get('name'), ns(a.get('agent_status')) or 'unknown') for a in d['result']['agents']]") || exit $?
  else
    need_ws
    hd_must pane list --workspace "$HERDR_WORKSPACE_ID"
    v=$(hjx "${AO_ROW_PY}R = [row(p.get('pane_id'), p.get('label'), ns(p.get('agent_status'))) for p in d['result']['panes']]") || exit $?
  fi
  [ -z "$v" ] || printf '%s\n' "$v"
}

# shellcheck disable=SC2034  # 진입점이 로딩 완료 표시로 읽는다
AO_ADAPTER_OK=1
