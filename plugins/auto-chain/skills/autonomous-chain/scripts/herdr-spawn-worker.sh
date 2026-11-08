#!/usr/bin/env bash
# herdr-spawn-worker.sh — auto-chain pane worker 기동 (2.1.0, 2.2.0 갱신)
#
# 사용: herdr-spawn-worker.sh <name> <model> <effort> <brief-path> [main-pane]
#   name       agent 이름 [a-z][a-z0-9_-]{0,31}, 살아 있는 agent 사이에서 고유
#   model      sonnet | opus
#   effort     low | medium | high | xhigh   (2.2.0 medium·low 허용 — 명세가 명확한 작은 구현은
#              sonnet medium. xhigh는 수정 사다리·chain-planner-deep만 — SKILL.md §2)
#   brief-path 지시서 절대 경로
#   main-pane  조정자 pane id (기본 $HERDR_PANE_ID)
# 환경 변수(선택):
#   ROLE        역할 에이전트(기본 chain-worker → --agent auto-chain:chain-worker).
#               ':' 포함이면 그대로, $PWD/.claude/agents/<ROLE>.md가 있으면 프로젝트
#               정의 이름 그대로, none이면 --agent 없음. 역할 적용 여부는 화면으로
#               입증되지 않으므로 지시서에도 역할 규칙을 함께 적는다
#   PERM_FLAGS  권한 플래그. 비우면 조정자 claude 프로세스의 실제 argv(원소 단위)에
#               --dangerously-skip-permissions가 있을 때만 그 플래그를 붙인다
#   TAB_LABEL   오른쪽 열이 찼을 때 쓰는 탭 이름(기본 "자율체인 작업" — 2.2.2 한글)
#   PANE_LABEL  새 pane에 붙일 한글 이름(기본 "작업자 <name>"). split에는 이름 옵션이
#               없어 split 직후 pane rename으로 붙인다(2.2.2). 실패해도 기동은 계속
#
# 하는 일 (references/backend-herdr.md §2~§3):
#   1. 전제·인자 검사, 이름 중복 검사(agent list)
#   2. 배치: 오른쪽 열이 비면 조정자 pane을 right로, 있으면 가장 높은 pane을
#      down 0.5로 나눈다. 오른쪽 열 5개면 TAB_LABEL 탭(없으면 만듦)에서 같은 규칙.
#      항상 --no-focus, --cwd "$PWD"(조정자의 신뢰된 폴더. 처음 보는 폴더면
#      Claude Code가 신뢰 확인 화면에서 멈춘다 — agent_not_ready 실측)
#   3. agent start → agent prompt(지시서 경로 포인터 한 줄, --wait --until working)
#   4. agent_status 확인: working → OK, done·idle → OK(빠른 완료 — 2.2.0), 그 밖(blocked·unknown) → 6.
#      같은 이름이 1개인지 재확인
# 출력: 성공하면 stdout 한 줄
#   OK name=<n> pane=<id> model=<m> effort=<요청값> status=<working|done|idle> jsonl=<transcript 경로>
#   (jsonl은 정지 감시 입력 — backend-herdr.md §6-1. effort는 요청값 그대로 — 실제 적용은
#    조정자가 화면 표시로 1회 확인한다. status=done|idle이면 보고서를 바로 회수한다)
# 실패: 비0 종료, stderr에 사유. 2=인자·전제 3=이름 중복 4=배치 5=agent start
#   6=첫 지시 실패·첫 지시 뒤 blocked/unknown·이중 기동. 4 이후 실패면 만든 pane id를 함께 출력한다(닫지 않음 —
#   조정자가 화면 1회 확인 뒤 판단).
# bash 3.2 호환. JSON 해석은 python3.

set -u

die() { code=$1; shift; echo "herdr-spawn-worker: $*" >&2; exit "$code"; }

[ $# -ge 4 ] && [ $# -le 5 ] || die 2 "사용: $0 <name> <model> <effort> <brief-path> [main-pane]"
NAME=$1; MODEL=$2; EFFORT=$3; BRIEF=$4; MAIN=${5:-${HERDR_PANE_ID:-}}
ROLE=${ROLE:-chain-worker}
TAB_LABEL=${TAB_LABEL:-자율체인 작업}
PANE_LABEL=${PANE_LABEL:-작업자 $NAME}
MAX_RIGHT=5

# [[ =~ ]]는 문자열 전체를 본다(grep은 줄 단위라 "ok\nBAD!"를 통과시킨다)
[[ $NAME =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die 2 "이름 형식 오류: $NAME"
# python 식에는 값을 문자열로 끼우지 않고 환경 변수로 넘긴다(따옴표·주입 방지)
export AC_NAME="$NAME" AC_TAB_LABEL="$TAB_LABEL"
case "$MODEL" in sonnet|opus) ;; *) die 2 "model은 sonnet|opus: $MODEL" ;; esac
case "$EFFORT" in low|medium|high|xhigh) ;; *) die 2 "effort는 low|medium|high|xhigh: $EFFORT" ;; esac
# ROLE은 pane을 만들기 전에 검사한다(잘못된 ROLE로 빈 pane이 남지 않게)
[[ $ROLE =~ ^[A-Za-z0-9_.:-]{1,64}$ ]] || die 2 "ROLE 형식 오류: $ROLE"
case "$BRIEF" in /*) ;; *) die 2 "지시서는 절대 경로: $BRIEF" ;; esac
[ -f "$BRIEF" ] || die 2 "지시서 없음: $BRIEF"
[ "${HERDR_ENV:-}" = 1 ] || die 2 "HERDR_ENV=1 아님 (herdr pane 밖)"
[ -n "$MAIN" ] || die 2 "조정자 pane id 없음"
[ -n "${HERDR_WORKSPACE_ID:-}" ] || die 2 "HERDR_WORKSPACE_ID 없음"
command -v python3 >/dev/null 2>&1 || die 2 "python3 없음"
herdr status server 2>/dev/null | grep -q 'status: running' || die 2 "herdr 서버가 running 아님"

# JSON 필드 뽑기: stdin JSON, $1 = python 식(변수 d, 외부 값은 os.environ['AC_…'])
jget() { python3 -c "import json,sys,os
try:
    d=json.load(sys.stdin)
    v=$1
    print('' if v is None else v)
except Exception:
    print('')"; }

name_count() {
  herdr agent list 2>/dev/null | jget "sum(1 for a in d['result']['agents'] if a.get('name')==os.environ['AC_NAME'])"
}

# 1. 이름 중복
n=$(name_count); [ -n "$n" ] || die 2 "agent list 응답 해석 실패"
[ "$n" = 0 ] || die 3 "이름 중복: $NAME 가 이미 살아 있음 (herdr agent list)"

# 권한 플래그: 조정자 claude 프로세스(조상 중 첫 claude)의 인자에서 판단
if [ -z "${PERM_FLAGS+x}" ] || [ -z "$PERM_FLAGS" ]; then
  # ps args는 argv 경계를 잃는다(공백이 든 인자 안의 문구를 플래그로 오인).
  # 실제 argv를 원소 단위로 읽는다: Linux /proc/<pid>/cmdline, macOS sysctl KERN_PROCARGS2.
  # 조상 중 argv[0] 이름이 정확히 claude인 첫 프로세스의 argv 원소에 플래그가 있을 때만 붙인다.
  perm=$(AC_START_PID=$$ python3 - <<'PY' 2>/dev/null
import os, struct, subprocess, ctypes, ctypes.util
def argv(pid):
    p = '/proc/%d/cmdline' % pid
    if os.path.exists(p):
        with open(p, 'rb') as f:
            return [a.decode('utf-8', 'replace') for a in f.read().split(b'\0')[:-1]]
    libc = ctypes.CDLL(ctypes.util.find_library('c'), use_errno=True)
    mib = (ctypes.c_int * 3)(1, 49, pid)  # CTL_KERN, KERN_PROCARGS2
    size = ctypes.c_size_t(0)
    if libc.sysctl(mib, 3, None, ctypes.byref(size), None, 0) != 0:
        return None
    buf = ctypes.create_string_buffer(size.value)
    if libc.sysctl(mib, 3, buf, ctypes.byref(size), None, 0) != 0:
        return None
    raw = buf.raw[:size.value]
    argc = struct.unpack('i', raw[:4])[0]
    rest = raw[4:]
    rest = rest[rest.index(b'\0'):].lstrip(b'\0')  # 실행 경로와 패딩을 건너뛴다
    return [a.decode('utf-8', 'replace') for a in rest.split(b'\0')[:argc]]
pid = int(os.environ['AC_START_PID'])
for _ in range(8):
    if pid <= 1:
        break
    a = argv(pid)
    if a and os.path.basename(a[0]) == 'claude':
        print('yes' if '--dangerously-skip-permissions' in a[1:] else 'no')
        break
    out = subprocess.run(['ps', '-o', 'ppid=', '-p', str(pid)], capture_output=True, text=True).stdout.strip()
    pid = int(out) if out.isdigit() else 0
PY
)
  case "$perm" in
    yes) PERM_FLAGS="--dangerously-skip-permissions" ;;
    no) PERM_FLAGS="" ;;
    *) PERM_FLAGS=""; echo "herdr-spawn-worker: 조정자 claude argv를 읽지 못함 — 권한 플래그 없이 기동(필요하면 PERM_FLAGS로 지정)" >&2 ;;
  esac
fi

# 2. 배치 — 분할 대상 결정
# 출력: "right <pane>" | "down <pane>" | "full"
pick_split() {  # $1 = 기준 pane, $2 = 상한
  herdr pane layout --pane "$1" 2>/dev/null | python3 -c "
import json,sys
base,limit=sys.argv[1],int(sys.argv[2])
try:
    ps=json.load(sys.stdin)['result']['layout']['panes']
except Exception:
    print('error'); sys.exit()
b=[p for p in ps if p['pane_id']==base]
if not b: print('error'); sys.exit()
bx=b[0]['rect']['x']
right=[p for p in ps if p['rect']['x']>bx]
if not right: print('right',base)
elif len(right)>=limit: print('full')
else:
    t=sorted(right,key=lambda p:(-p['rect']['height'],p['rect']['y']))[0]
    print('down',t['pane_id'])" "$1" "$2"
}

split_pane() {  # $1 = 방향, $2 = 나눌 pane → stdout 새 pane id
  if [ "$1" = right ]; then
    out=$(herdr pane split "$2" --direction right --cwd "$PWD" --no-focus 2>&1)
  else
    out=$(herdr pane split "$2" --direction down --ratio 0.5 --cwd "$PWD" --no-focus 2>&1)
  fi
  printf '%s' "$out" | jget "d['result']['pane']['pane_id']"
}

P=""
plan=$(pick_split "$MAIN" "$MAX_RIGHT")
# shellcheck disable=SC2086  # "<방향> <pane>"을 의도적으로 나눈다
set -- $plan
case "${1:-error}" in
  right|down) P=$(split_pane "$1" "$2") ;;
  full)
    # 넘침 탭: 같은 이름 탭이 있으면 그 안에서 2열 × 3행까지, 없으면 새로 만든다
    tab=$(herdr tab list --workspace "$HERDR_WORKSPACE_ID" 2>/dev/null \
      | jget "next((t['tab_id'] for t in d['result']['tabs'] if t.get('label')==os.environ['AC_TAB_LABEL']),'')")
    if [ -z "$tab" ]; then
      out=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label "$TAB_LABEL" --no-focus 2>&1)
      P=$(printf '%s' "$out" | grep -o '"pane_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    else
      export AC_TAB="$tab"
      first=$(herdr pane list --workspace "$HERDR_WORKSPACE_ID" 2>/dev/null \
        | jget "next((p['pane_id'] for p in d['result']['panes'] if p.get('tab_id')==os.environ['AC_TAB']),'')")
      [ -n "$first" ] || die 4 "넘침 탭 $tab 의 pane을 찾지 못함"
      # 탭 첫 pane이 비어 있는 셸이면(agent 없음) 그대로 쓴다
      busy=$(herdr pane get "$first" 2>/dev/null | jget "d['result']['pane'].get('agent') or ''")
      if [ -z "$busy" ]; then
        P=$first
      else
        plan2=$(pick_split "$first" "$MAX_RIGHT")   # pick_split은 오른쪽 pane만 센다: 첫 pane + 오른쪽 5 = 6
        # shellcheck disable=SC2086
        set -- $plan2
        case "${1:-error}" in
          right|down) P=$(split_pane "$1" "$2") ;;
          full) die 4 "오른쪽 열 ${MAX_RIGHT}개와 넘침 탭 $TAB_LABEL 이 모두 참 — TAB_LABEL을 바꿔 다시 실행" ;;
          *) die 4 "넘침 탭 배치 해석 실패" ;;
        esac
      fi
    fi ;;
  *) die 4 "pane layout 해석 실패 (기준 pane $MAIN)" ;;
esac
[ -n "$P" ] || die 4 "pane 생성 실패"
# 2.2.2: pane 이름(한글). split에는 이름 옵션이 없다. 실패는 경고만
herdr pane rename "$P" "$PANE_LABEL" >/dev/null 2>&1 \
  || echo "herdr-spawn-worker: pane 이름 붙이기 실패 pane=$P (기동은 계속)" >&2

# 3. agent start
# 역할 해석: ROLE=none → --agent 없음 / ':' 포함 → 그대로 / 프로젝트 정의
# (.claude/agents/<ROLE>.md)가 있으면 그 이름 / 그 밖 → auto-chain:<ROLE>
AGENT_ARGS=()
case "$ROLE" in
  none) ;;
  *:*) AGENT_ARGS=(--agent "$ROLE") ;;
  *) if [ -f "$PWD/.claude/agents/$ROLE.md" ]; then AGENT_ARGS=(--agent "$ROLE"); else AGENT_ARGS=(--agent "auto-chain:$ROLE"); fi ;;
esac
EXTRA=("${AGENT_ARGS[@]+"${AGENT_ARGS[@]}"}" --model "$MODEL" --effort "$EFFORT")
[ -n "$PERM_FLAGS" ] && EXTRA+=("$PERM_FLAGS")
out=$(herdr agent start "$NAME" --kind claude --pane "$P" --timeout 90000 -- "${EXTRA[@]}" 2>&1)
st=$(printf '%s' "$out" | grep -o '"agent_status":"[a-z]*"' | head -1 | cut -d'"' -f4)
if [ -z "$st" ]; then
  reason=$(printf '%s' "$out" | grep -o 'agent_not_ready\|"message":"[^"]*"' | head -1)
  die 5 "agent start 실패 pane=$P ${reason:-$(printf '%s' "$out" | head -c 200)} — herdr agent read $NAME --source visible --lines 30 로 1회 확인(backend-herdr.md §6)"
fi

# 첫 지시: 지시서는 파일, 프롬프트는 포인터 한 줄. --timeout은 --wait와 함께만 쓴다
out=$(herdr agent prompt "$NAME" "$BRIEF 를 읽고 그대로 진행해. 내 이름: $NAME. 조정자 pane: $MAIN" \
  --wait --until working --until "done" --timeout 60000 2>&1) \
  || die 6 "첫 지시 실패 pane=$P $(printf '%s' "$out" | head -c 200)"

# 4. 상태 확인 + 중복 재확인
# working = 진행 중. done·idle = 첫 지시 뒤 이미 끝남(빠른 완료 — 실패가 아니다, 2.2.0).
# blocked(권한·질문 대화상자)·그 밖·응답 없음만 실패 6
info=$(herdr agent get "$NAME" 2>/dev/null)
st=$(printf '%s' "$info" | grep -o '"agent_status":"[a-z]*"' | head -1 | cut -d'"' -f4)
case "$st" in
  working|done|idle) ;;
  *) die 6 "첫 지시 뒤 상태가 ${st:-없음} (working|done|idle 아님) pane=$P — herdr agent read $NAME --source visible --lines 30 로 1회 확인" ;;
esac
n=$(name_count)
[ "$n" = 1 ] || die 6 "기동 뒤 이름 $NAME 가 ${n:-?}개 — 이중 기동 의심 pane=$P"

uuid=$(printf '%s' "$info" | jget "d['result']['agent']['agent_session']['value']")
acwd=$(printf '%s' "$info" | jget "d['result']['agent']['cwd']")
enc=$(printf '%s' "${acwd:-$PWD}" | sed 's/[^A-Za-z0-9]/-/g')
J="$HOME/.claude/projects/$enc/$uuid.jsonl"
[ -n "$uuid" ] || J="unverified"

echo "OK name=$NAME pane=$P model=$MODEL effort=$EFFORT status=$st jsonl=$J"
