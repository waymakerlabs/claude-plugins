#!/usr/bin/env bash
# herdr-stall-watch.sh — pane worker 정지 감시 (2.2.0)
#
# 사용: herdr-stall-watch.sh <tsv-file>
#   tsv 줄: <task>\t<agent 이름>\t<jsonl 경로>   (빈 줄·#로 시작하는 줄은 건너뜀)
#   Monitor로 실행한다(stdout 한 줄 = 알림 하나). 매 회차 tsv를 다시 읽으므로 worker를
#   추가·제거할 때는 tsv만 고친다.
# 환경 변수(선택):
#   STALL_INTERVAL   확인 간격 초(기본 60)
#   STALL_ONCE=1     한 회차만 돌고 끝낸다(시험용)
#   STALL_STATE_DIR  중복 억제 상태 폴더(기본 mktemp -d)
#   STALL_TAIL       jsonl 끝에서 볼 줄 수(기본 400)
#
# 판정 (references/backend-herdr.md §6-1, interface §3):
#   마지막 진척 = type=assistant 이고 content에 비어 있지 않은 text 또는 tool_use가 있는 항목,
#                또는 type=user 이고 tool_result가 있는 항목의 timestamp
#   API 재시도 = 마지막 진척 뒤의 type=api-request 항목 수
#   (실측 helpai f9b95a74: 재시도 루프에서 assistant 없이 api-request만 5~6분 간격으로 이어짐)
# 출력(상태별, 10분 단위로 한 번씩만):
#   <task> 정지 후보 · 마지막 진척 N분 전 · working (실측)              working, 진척 ≥10분
#   <task> API 재시도 반복 · 진척 뒤 api-request k건 · N분 (실측)        k≥3 그리고 진척 ≥5분 (정지 후보보다 우선)
#   <task> 권한·입력 대기 · status=blocked (실측)
#   <task> 끝남 · status=done|idle
#   <task> 감시 불가 · jsonl 읽기 실패 (UNVERIFIED)                     파일 없음·해석 실패 — mtime으로 추정하지 않는다
#     (해석 실패 = 마지막 진척보다 뒤에 JSON이 아닌 줄. 창 첫 줄(잘린 줄)은 무시)
# 중복 억제 상태 파일명 = "<task>\t<agent>\t<jsonl>"의 sha256 앞 16자 (재기동하면 새 키)
#   <task> 감시 불가 · agent 상태 읽기 실패 status=<값> (UNVERIFIED)      agent가 없거나 응답 해석 실패
# bash 3.2 호환. JSON 해석은 python3, 값은 argv·환경 변수로만 넘긴다.

set -u

[ $# -eq 1 ] || { echo "사용: $0 <tsv-file>" >&2; exit 2; }
TSV=$1
[ -f "$TSV" ] || { echo "herdr-stall-watch: tsv 없음: $TSV" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "herdr-stall-watch: python3 없음" >&2; exit 2; }
command -v herdr >/dev/null 2>&1 || { echo "herdr-stall-watch: herdr 없음" >&2; exit 2; }

INTERVAL=${STALL_INTERVAL:-60}
case "$INTERVAL" in ''|*[!0-9]*|0) INTERVAL=60 ;; esac
TAIL=${STALL_TAIL:-400}
case "$TAIL" in ''|*[!0-9]*|0) TAIL=400 ;; esac
STATE=${STALL_STATE_DIR:-}
if [ -z "$STATE" ]; then STATE=$(mktemp -d "${TMPDIR:-/tmp}/stall-watch.XXXXXX") || exit 2; fi
mkdir -p "$STATE" || exit 2

# jsonl 판정: 출력 "ok <진척 경과 분> <api-request 수>" 또는 "err <사유>"
# 진척이 창(끝 TAIL줄) 안에 없으면 창의 첫 timestamp를 진척 하한으로 쓴다(경과 분은 하한값)
analyze() {
  python3 - "$1" "$TAIL" <<'PY'
import json, sys, collections, datetime
path, tail = sys.argv[1], int(sys.argv[2])
UTC = datetime.timezone.utc
def ts(s):
    # Claude Code transcript는 UTC 'Z' 표기(예: 2026-11-07T16:52:24.609Z). 소수 초는 버린다
    try:
        d = datetime.datetime.strptime(s[:19], '%Y-%m-%dT%H:%M:%S')
    except Exception:
        return None
    rest = s[19:].split('.', 1)[-1] if s[19:20] == '.' else s[19:]
    rest = rest.lstrip('0123456789')
    if rest in ('', 'Z'):
        return d.replace(tzinfo=UTC)
    try:
        sign = 1 if rest[0] == '+' else -1
        hh, mm = int(rest[1:3]), int(rest[-2:])
        return (d - sign * datetime.timedelta(hours=hh, minutes=mm)).replace(tzinfo=UTC)
    except Exception:
        return None
try:
    with open(path, 'rb') as f:
        lines = collections.deque(f, tail)
except Exception as e:
    print('err open'); sys.exit()
items, pos, bad = [], [], []
last_n = len(lines) - 1
for n, raw in enumerate(lines):
    # deque는 완전한 줄 단위로 읽으므로 창 첫 줄도 온전한 줄이다.
    # 예외는 개행 없이 끝난 마지막 줄 하나 — 기록 중인 줄이라 다음 회차에 다시 본다.
    partial = (n == last_n and not raw.endswith(b'\n'))
    try:
        d = json.loads(raw)
    except Exception:
        if not partial:
            bad.append(n)
        continue
    if isinstance(d, dict):
        items.append(d); pos.append(n)
    elif not partial:
        bad.append(n)
if not items:
    print('err empty'); sys.exit()
def progress(d):
    t = d.get('type')
    m = d.get('message')
    c = m.get('content') if isinstance(m, dict) else None
    if t == 'assistant':
        if isinstance(c, str):
            return bool(c.strip())
        if isinstance(c, list):
            for x in c:
                if not isinstance(x, dict):
                    continue
                if x.get('type') == 'tool_use':
                    return True
                if x.get('type') == 'text' and str(x.get('text') or '').strip():
                    return True
        return False
    if t == 'user' and isinstance(c, list):
        return any(isinstance(x, dict) and x.get('type') == 'tool_result' for x in c)
    return False
last_i, first_ts = None, None
for i, d in enumerate(items):
    s = d.get('timestamp')
    if first_ts is None and isinstance(s, str) and ts(s):
        first_ts = ts(s)
    if progress(d) and isinstance(d.get('timestamp'), str) and ts(d['timestamp']):
        last_i = i
last_pos = pos[last_i] if last_i is not None else -1
if any(b > last_pos for b in bad):
    print('err parse'); sys.exit()
if last_i is None:
    if first_ts is None:
        print('err no-timestamp'); sys.exit()
    base, after = first_ts, items
else:
    base, after = ts(items[last_i]['timestamp']), items[last_i + 1:]
k = sum(1 for d in after if d.get('type') == 'api-request')
now = datetime.datetime.now(UTC)
age = int((now - base).total_seconds() // 60)
print('ok %d %d' % (max(age, 0), k))
PY
}

agent_status() {
  herdr agent get "$1" 2>/dev/null | python3 -c "import json,sys
try:
    print(json.load(sys.stdin)['result']['agent']['agent_status'] or 'unknown')
except Exception:
    print('unknown')"
}

sha16() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -c1-16; }

# 같은 (task, agent, jsonl)·같은 키면 한 번만 출력. 상태 파일 경로는 check_one이 KF에 둔다
KF=""
emit() {  # $1 key, $2 메시지
  if [ "$(cat "$KF" 2>/dev/null)" != "$1" ]; then
    printf '%s\n' "$2"
    printf '%s' "$1" > "$KF"
  fi
}
reset_key() {  # 정상으로 돌아오면 키를 지워 다음 정지를 다시 알린다
  printf 'ok' > "$KF"
}

check_one() {  # $1 task, $2 agent, $3 jsonl
  local task=$1 agent=$2 j=$3 st res age k
  KF="$STATE/$(printf '%s\t%s\t%s' "$task" "$agent" "$j" | sha16)"
  st=$(agent_status "$agent")
  case "$st" in
    blocked) emit blocked "$task 권한·입력 대기 · status=blocked (실측)" ;;
    done|idle) emit "end-$st" "$task 끝남 · status=$st" ;;
    working)
      res=$(analyze "$j" 2>/dev/null)
      # shellcheck disable=SC2086  # "ok <age> <k>"를 의도적으로 나눈다
      set -- $res
      if [ "${1:-err}" != ok ]; then
        emit err "$task 감시 불가 · jsonl 읽기 실패 (UNVERIFIED)"
        return
      fi
      age=$2; k=$3
      if [ "$k" -ge 3 ] && [ "$age" -ge 5 ]; then
        emit "api-$((age / 10))" "$task API 재시도 반복 · 진척 뒤 api-request ${k}건 · ${age}분 (실측)"
      elif [ "$age" -ge 10 ]; then
        emit "stall-$((age / 10))" "$task 정지 후보 · 마지막 진척 ${age}분 전 · working (실측)"
      else
        reset_key
      fi ;;
    *) emit "status-$st" "$task 감시 불가 · agent 상태 읽기 실패 status=$st (UNVERIFIED)" ;;
  esac
}

TAB=$(printf '\t')
while :; do
  while IFS="$TAB" read -r task agent j || [ -n "${task:-}" ]; do
    case "${task:-}" in ''|'#'*) continue ;; esac
    [ -n "${agent:-}" ] || continue
    check_one "$task" "$agent" "${j:-}"
  done < "$TSV"
  [ "${STALL_ONCE:-}" = 1 ] && exit 0
  sleep "$INTERVAL"
done
