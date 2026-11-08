# lib/common.sh — agent-orchestrator 공통 헬퍼 (진입점과 어댑터가 source)
#
# 규칙: stdout은 값 한 줄, 사유·경고는 stderr. bash 3.2 호환. JSON 해석은 python3 한 곳(여기).
# shellcheck shell=bash

# 에이전트 이름: herdr 정규식과 같다. [[ =~ ]]는 문자열 전체를 본다(grep은 줄 단위라 "ok\nBAD!"를 통과시킨다)
AO_NAME_RE='^[a-z][a-z0-9_-]{0,31}$'
# pane id: <workspace>:<pane> (예 w2:p16)
AO_PANE_RE='^[A-Za-z0-9]+:[A-Za-z0-9]+$'

ao_warn() { echo "agent-orchestrator: $*" >&2; }
ao_die() { local code=$1; shift; ao_warn "$*"; exit "$code"; }

ao_is_name() { [[ $1 =~ $AO_NAME_RE ]]; }
ao_is_pane() { [[ $1 =~ $AO_PANE_RE ]]; }
ao_is_target() { ao_is_name "$1" || ao_is_pane "$1"; }

# 줄바꿈·CR 없는 비어 있지 않은 한 줄인지
ao_one_line() {
  [ -n "$1" ] || return 1
  case "$1" in *$'\n'* | *$'\r'*) return 1 ;; esac
  return 0
}

ao_is_uint() { [[ $1 =~ ^[1-9][0-9]{0,8}$ ]]; }

# JSON 해석의 공통 머리: stdin 전체를 JSON으로, 실패하면 '{'로 시작하는 줄을 차례로 시도한다
# (백엔드가 stderr 경고를 섞어 내는 경우 대비). 해석 실패 = exit 1.
# 외부 값은 문자열로 끼우지 않고 환경 변수(E['AO_…'])로 넘긴다(따옴표·주입 방지).
_AO_PY_HEAD='
import json, sys, os
raw = sys.stdin.read()
d = None
try:
    d = json.loads(raw)
except Exception:
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                d = json.loads(line)
                break
            except Exception:
                pass
if not isinstance(d, dict):
    sys.exit(1)
E = os.environ
def out(v):
    if v is None:
        return
    if isinstance(v, (list, tuple)):
        if v:
            sys.stdout.write("\n".join(str(x) for x in v) + "\n")
    else:
        sys.stdout.write(str(v) + "\n")
'

# ao_json <식>  — stdin JSON(변수 d)에 python 식을 적용해 출력. 목록은 줄마다. None은 빈 출력.
ao_json() {
  python3 -c "$_AO_PY_HEAD
try:
    v = eval(sys.argv[1])
except Exception:
    sys.exit(1)
out(v)" "$1"
}

# ao_jsonx <코드>  — 여러 문장이 필요할 때. 코드가 변수 R에 결과를 둔다.
ao_jsonx() {
  python3 -c "$_AO_PY_HEAD
R = None
try:
    exec(sys.argv[1])
except Exception:
    sys.exit(1)
out(R)" "$1"
}

# 출력 필드 정리: 탭·줄바꿈을 공백으로(list 출력이 한 줄 한 항목을 지키게)
ao_field() { printf '%s' "$1" | tr '\t\r\n' '   '; }
