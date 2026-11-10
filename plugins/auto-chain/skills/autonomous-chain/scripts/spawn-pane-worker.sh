#!/usr/bin/env bash
# spawn-pane-worker.sh — auto-chain ③ pane worker 기동 (2.3.0, 옛 이름 herdr-spawn-worker.sh)
#
# 사용: spawn-pane-worker.sh <name> <model> <effort> <brief-path> [main-pane]
#   name       에이전트 이름 [a-z][a-z0-9_-]{0,31}, 살아 있는 에이전트 사이에서 고유
#   model      sonnet | opus
#   effort     low | medium | high | xhigh   (medium·low = 명세가 명확한 작은 구현.
#              xhigh = 수정 사다리·chain-planner-deep만 — SKILL.md §2)
#   brief-path 지시서 절대 경로
#   main-pane  조정자 pane id = 배치 기준(agent-orchestrator pane-open --parent). 없으면 `whoami`
#
# 이 스크립트는 auto-chain 고유 정책만 갖는다: ROLE 해석, 권한 플래그 판정, 첫 지시 문구, 성공 줄 형식.
# 배치·split·이름 붙이기·이름 중복 검사·툴 특이사항은 agent-orchestrator 어댑터가 맡는다
#   (동작 pane-open·agent-start·agent-send·agent-status·agent-transcript·list, 툴 특이사항은
#    tools/agent-orchestrator/docs/<backend>.md).
#
# 환경 변수(선택):
#   AGENT_ORCHESTRATOR  진입점 경로(기본 $HOME/.local/bin/agent-orchestrator). 실행할 수 없으면 12
#   ROLE        역할 에이전트(기본 chain-worker → --agent auto-chain:chain-worker).
#               ':' 포함이면 그대로, $PWD/.claude/agents/<ROLE>.md가 있으면 프로젝트
#               정의 이름 그대로, none이면 --agent 없음. 역할 적용 여부는 화면으로
#               입증되지 않으므로 지시서에도 역할 규칙을 함께 적는다
#   PERM_FLAGS  권한 플래그. 비우면 조정자 claude 프로세스의 실제 argv(원소 단위)에
#               --dangerously-skip-permissions가 있을 때만 그 플래그를 붙인다
#   TAB_LABEL   오른쪽 열이 찼을 때 쓰는 넘침 탭 이름(기본 "[WO] 자율체인 작업" — 역할 접두어 + 한글)
#               → AGENT_ORCHESTRATOR_OVERFLOW_TAB 으로 넘긴다
#   PANE_LABEL  새 pane에 붙일 이름(기본 "[WO] 작업자 <name>" — 역할 접두어 + 한글, [OC] 조정자·[WO] worker·[RV] 리뷰어). 이름 붙이기 실패는 경고만
#
# 순서: 인자 검사 → 이름 중복(list --agents) → pane-open --parent → agent-start → agent-send --confirm
#   → agent-status(working|done|idle) → 이름이 정확히 1개인지 재확인 → agent-transcript
# 첫 지시(agent-send --confirm)는 이 새 세션에 키보드로 넣는 **유일한 시도 1회**다(2.6.0).
#   실패·응답 유실·상태 불명확이어도 이 스크립트는 재전송하지 않고 호출자도 재전송하지 않는다
#   (입력창에 남은 지시가 나중에 제출돼 작업자가 둘이 된다). 호출자는 agent-status·transcript로 착수를
#   1회 확인하고, 안 됐으면 만든 pane을 close → list --panes에서 사라진 것을 확인한 뒤에만
#   새 pane·새 이름(또는 ①)으로 다시 띄운다. 이후 메시지는 inbox-send/inbox-watch(pane-worker.md §4).
# 출력: 성공하면 stdout 한 줄
#   OK name=<n> pane=<id> model=<m> effort=<요청값> status=<working|done|idle> jsonl=<경로|unsupported|unverified>
#   (jsonl = 정지 감시 입력. agent-transcript가 10이면 unsupported, 그 밖 실패면 unverified.
#    effort는 요청값 그대로 — 실제 적용은 조정자가 화면 표시로 1회 확인한다.
#    status=done|idle이면 빠른 완료 — 보고서를 바로 회수한다)
# 실패: 비0 종료, stderr에 사유.
#   2=인자·전제 3=이름 중복 4=배치(pane-open) 5=agent-start 6=첫 지시 실패·첫 지시 뒤 blocked/unknown·이중 기동
#   10·11·12 = agent-orchestrator의 unsupported·no backend·adapter error를 **같은 코드 그대로** 전달
#   (호출자가 ①·②로 내려갈지, 12면 설치 결함으로 알릴지를 고른다). 4 이후 실패면 만든 pane id를
#   함께 출력한다(닫지 않음 — 조정자가 화면 1회 확인 뒤 판단).
# bash 3.2 호환.

set -u

die() { code=$1; shift; echo "spawn-pane-worker: $*" >&2; exit "$code"; }

[ $# -ge 4 ] && [ $# -le 5 ] || die 2 "사용: $0 <name> <model> <effort> <brief-path> [main-pane]"
NAME=$1; MODEL=$2; EFFORT=$3; BRIEF=$4; MAIN=${5:-}
ROLE=${ROLE:-chain-worker}
TAB_LABEL=${TAB_LABEL:-[WO] 자율체인 작업}
PANE_LABEL=${PANE_LABEL:-[WO] 작업자 $NAME}
AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}

# [[ =~ ]]는 문자열 전체를 본다(grep은 줄 단위라 "ok\nBAD!"를 통과시킨다)
[[ $NAME =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die 2 "이름 형식 오류: $NAME"
case "$MODEL" in sonnet|opus) ;; *) die 2 "model은 sonnet|opus: $MODEL" ;; esac
case "$EFFORT" in low|medium|high|xhigh) ;; *) die 2 "effort는 low|medium|high|xhigh: $EFFORT" ;; esac
# ROLE은 pane을 만들기 전에 검사한다(잘못된 ROLE로 빈 pane이 남지 않게)
[[ $ROLE =~ ^[A-Za-z0-9_.:-]{1,64}$ ]] || die 2 "ROLE 형식 오류: $ROLE"
case "$BRIEF" in /*) ;; *) die 2 "지시서는 절대 경로: $BRIEF" ;; esac
[ -f "$BRIEF" ] || die 2 "지시서 없음: $BRIEF"
case "$PANE_LABEL$TAB_LABEL" in *$'\n'*|*$'\r'*) die 2 "PANE_LABEL·TAB_LABEL은 한 줄" ;; esac
[ -x "$AO" ] || die 12 "adapter error: agent-orchestrator 실행 파일 없음: $AO (설치 결함 — tools/agent-orchestrator/install.sh)"
command -v python3 >/dev/null 2>&1 || die 2 "python3 없음"
export AGENT_ORCHESTRATOR_OVERFLOW_TAB="$TAB_LABEL"

# ao_run <동작> <인자…> — stdout은 AO_OUT, stderr는 AO_ERR, 반환값은 agent-orchestrator 종료 코드
ao_run() {
  local errf rc
  errf=$(mktemp "${TMPDIR:-/tmp}/spawn-pane.XXXXXX") || { AO_OUT=""; AO_ERR="mktemp 실패"; return 4; }
  AO_OUT=$("$AO" "$@" 2>"$errf"); rc=$?
  AO_ERR=$(tr '\n' ' ' < "$errf" | head -c 300)
  rm -f "$errf"
  return "$rc"
}
# 10·11·12는 변환하지 않고 그대로 끝낸다. 그 밖은 $1(이 스크립트의 단계 코드)로 끝낸다
fail() {  # $1 단계 코드, $2 agent-orchestrator 코드, $3 사유
  case "$2" in 10|11|12) die "$2" "$3 — agent-orchestrator rc=$2: $AO_ERR" ;; esac
  die "$1" "$3 — agent-orchestrator rc=$2: $AO_ERR"
}

# 조정자 pane(배치 기준·첫 지시에 적을 값)
if [ -z "$MAIN" ]; then
  ao_run whoami; c=$?
  [ "$c" = 0 ] || fail 2 "$c" "조정자 pane id 없음(5번째 인자 또는 whoami)"
  MAIN=$AO_OUT
fi

name_count() {  # list --agents 의 둘째 칸이 $NAME 인 줄 수 → AO_N
  ao_run list --agents || return $?
  AO_N=$(printf '%s\n' "$AO_OUT" | awk -F '\t' -v n="$NAME" '$2==n{c++} END{print c+0}')
}

# 1. 이름 중복
name_count; c=$?
[ "$c" = 0 ] || fail 2 "$c" "에이전트 목록 조회 실패"
[ "$AO_N" = 0 ] || die 3 "이름 중복: $NAME 가 이미 살아 있음"

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
    *) PERM_FLAGS=""; echo "spawn-pane-worker: 조정자 claude argv를 읽지 못함 — 권한 플래그 없이 기동(필요하면 PERM_FLAGS로 지정)" >&2 ;;
  esac
fi

# 2. 배치 — pane-open (오른쪽 열·넘침 탭·이름 붙이기는 어댑터 내부)
ao_run pane-open "$PANE_LABEL" --parent "$MAIN" --cwd "$PWD"; c=$?
[ "$c" = 0 ] || fail 4 "$c" "pane-open 실패(기준 pane $MAIN)"
P=$AO_OUT
[ -n "$P" ] || die 4 "pane-open 응답에 pane id 없음"
[ -n "$AO_ERR" ] && echo "spawn-pane-worker: $AO_ERR" >&2   # 이름 붙이기 실패 등 경고는 그대로 보인다

# 3. agent-start
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
ao_run agent-start "$NAME" "$P" --kind claude -- "${EXTRA[@]}"; c=$?
case "$c" in
  0) ;;
  3) die 3 "이름 중복(agent-start) pane=$P — $AO_ERR" ;;
  *) fail 5 "$c" "agent-start 실패 pane=$P — 화면 1회 확인: agent-orchestrator agent-read $NAME --lines 30" ;;
esac

# 첫 지시: 지시서는 파일, 프롬프트는 포인터 한 줄.
# --confirm = working 또는 done 관측까지(빠른 완료 허용이 계약)
# 이 호출은 이 세션의 유일한 agent-send 시도다. 실패·불명확 시 같은 입력창에 다시 보내지 않는다(위 머리 주석).
ao_run agent-send "$NAME" "$BRIEF 를 읽고 그대로 진행해. 내 이름: $NAME. 조정자 pane: $MAIN" --confirm; c=$?
[ "$c" = 0 ] || fail 6 "$c" "첫 지시 실패 pane=$P — 재전송 금지: 착수를 agent-status·agent-transcript로 1회 확인하고, 안 됐으면 pane close 확인(list --panes에서 사라짐) 뒤 새 pane으로"

# 4. 상태 확인 + 중복 재확인
# working = 진행 중. done·idle = 첫 지시 뒤 이미 끝남(빠른 완료 — 실패가 아니다).
# blocked(권한·질문 대화상자)·그 밖·응답 없음만 실패 6
ao_run agent-status "$NAME"; c=$?
st=$AO_OUT
[ "$c" = 0 ] || fail 6 "$c" "첫 지시 뒤 상태 조회 실패 pane=$P"
case "$st" in
  working|done|idle) ;;
  *) die 6 "첫 지시 뒤 상태가 ${st:-없음} (working|done|idle 아님) pane=$P — 재전송 금지, 화면 1회 확인: agent-orchestrator agent-read $NAME --lines 30 — pane close 확인 뒤 새 pane으로" ;;
esac
name_count; c=$?
[ "$c" = 0 ] || fail 6 "$c" "기동 뒤 에이전트 목록 조회 실패 pane=$P"
[ "$AO_N" = 1 ] || die 6 "기동 뒤 이름 $NAME 가 ${AO_N:-?}개 — 이중 기동 의심 pane=$P"

ao_run agent-transcript "$NAME"; c=$?
case "$c" in
  0) J=$AO_OUT ;;
  10) J=unsupported ;;
  # worker는 이미 떠 있으므로 비0으로 끝내지 않는다. 대신 원래 코드를 stderr에 남겨
  # 11(백엔드 없음)·12(설치 결함) 진단이 사라지지 않게 한다(2.3.0 codex NOTE)
  *) J=unverified
     echo "spawn-pane-worker: agent-transcript rc=$c — jsonl=unverified (12면 agent-orchestrator 설치 점검: install.sh --check)" >&2 ;;
esac
[ -n "$J" ] || J=unverified

echo "OK name=$NAME pane=$P model=$MODEL effort=$EFFORT status=$st jsonl=$J"
