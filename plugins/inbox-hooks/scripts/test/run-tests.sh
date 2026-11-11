#!/usr/bin/env bash
# inbox-hooks 래퍼 자동 시험(계획 2026-11-11-inbox-simplify §5). 가짜 AGENT_ORCHESTRATOR만 쓴다.
#   bash plugins/inbox-hooks/scripts/test/run-tests.sh   → 마지막 줄 "collected=N passed=N failed=N skipped=N"
# 실제 ~/.local/state/agent-orchestrator 와 ~/.local/bin 은 건드리지 않는다(AO_STATE_ROOT=임시 폴더).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PLUG=$(cd "$HERE/../.." && pwd)
HOOK="$PLUG/scripts/inbox-hook.sh"
EXPECT=9
T=$(mktemp -d /tmp/inbox-hooks-unit.XXXXXX)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0; skip=0; names=""

ok()   { pass=$((pass + 1)); names="$names $1"; echo "PASS $1"; }
bad()  { fail=$((fail + 1)); names="$names $1"; echo "FAIL $1: $2"; }
skp()  { skip=$((skip + 1)); names="$names $1"; echo "SKIP $1: $2"; }

# 가짜 AO: FAKE_MODE=new|old. 호출마다 $T/calls 에 인자, $T/stdin.<n> 에 stdin 기록
mkfake() {
  cat > "$T/fake-ao" <<'EOF'
#!/usr/bin/env bash
n=$(( $(wc -l < "$FAKE_DIR/calls" 2>/dev/null || echo 0) + 1 ))
echo "$*" >> "$FAKE_DIR/calls"
if [ "$1 ${2:-}" = "inbox-wait --status" ]; then
  [ "$FAKE_MODE" = old ] && { echo "알 수 없는 명령" >&2; exit 2; }
  [ "$FAKE_MODE" = v3 ] && { echo "inbox-wait 3"; exit 0; }
  echo "inbox-wait 2"; exit 0
fi
cat > "$FAKE_DIR/stdin.$n"
exit "${FAKE_EXIT:-0}"
EOF
  chmod +x "$T/fake-ao"
}
reset() { rm -f "$T"/calls "$T"/stdin.* "$T"/out "$T"/err; rm -rf "$T/state"; mkdir -p "$T/state/inbox"; }
run() { # run <모드> <stdin> [env…]
  local m=$1 in=$2; shift 2
  printf '%s' "$in" | env AO_STATE_ROOT="$T/state" FAKE_DIR="$T" "$@" bash "$HOOK" "$m" >"$T/out" 2>"$T/err"
  echo $?
}
mkfake
J='{"session_id":"0a1b2c3d-1111-2222-3333-444455556666","hook_event_name":"Stop","transcript_path":"/tmp/x.jsonl"}'

# hook-ao-missing
reset; rc=$(run wait "$J" AGENT_ORCHESTRATOR="$T/nope")
if [ "$rc" = 0 ] && [ ! -s "$T/out" ] && [ ! -s "$T/err" ]; then ok hook-ao-missing; else bad hook-ao-missing "rc=$rc"; fi

# hook-ao-old
reset; rc=$(run wait "$J" AGENT_ORCHESTRATOR="$T/fake-ao" FAKE_MODE=old)
calls=$(grep -vc -- '--status' "$T/calls" 2>/dev/null); calls=${calls:-0}
if [ "$rc" = 0 ] && [ ! -s "$T/out" ] && [ ! -s "$T/err" ] && [ "$calls" = 0 ]; then ok hook-ao-old; else bad hook-ao-old "rc=$rc calls=$calls"; fi

# hook-off-marker
reset; : > "$T/state/inbox/hooks.off"; rc=$(run wait "$J" AGENT_ORCHESTRATOR="$T/fake-ao" FAKE_MODE=new)
if [ "$rc" = 0 ] && [ ! -s "$T/out" ] && [ ! -e "$T/calls" ]; then ok hook-off-marker; else bad hook-off-marker "rc=$rc calls=$(cat "$T/calls" 2>/dev/null)"; fi

# hook-stop-exec: 인자·stdin 그대로, 종료 코드 2(깨움)와 stderr도 그대로
reset; rc=$(run wait "$J" AGENT_ORCHESTRATOR="$T/fake-ao" FAKE_MODE=new FAKE_EXIT=2)
last=$(tail -1 "$T/calls" 2>/dev/null); got=$(cat "$T"/stdin.* 2>/dev/null)
if [ "$rc" = 2 ] && [ "$last" = "inbox-wait" ] && [ "$got" = "$J" ]; then ok hook-stop-exec; else bad hook-stop-exec "rc=$rc last=$last"; fi

# hook-start-quiet: 옛 session-start 모드(0.1.0 hooks.json 이 남은 세션) → 0·출력 0·AO 호출 0
reset; rc=$(run session-start "${J/Stop/SessionStart}" AGENT_ORCHESTRATOR="$T/fake-ao" FAKE_MODE=new)
if [ "$rc" = 0 ] && [ ! -s "$T/out" ] && [ ! -s "$T/err" ] && [ ! -e "$T/calls" ]; then ok hook-start-quiet; else bad hook-start-quiet "rc=$rc calls=$(cat "$T/calls" 2>/dev/null)"; fi

# hook-ao-other-version: --status 가 inbox-wait 2 가 아니면(예: 3) 무동작
reset; rc=$(run wait "$J" AGENT_ORCHESTRATOR="$T/fake-ao" FAKE_MODE=v3)
calls=$(grep -vc -- '--status' "$T/calls" 2>/dev/null); calls=${calls:-0}
if [ "$rc" = 0 ] && [ ! -s "$T/out" ] && [ "$calls" = 0 ]; then ok hook-ao-other-version; else bad hook-ao-other-version "rc=$rc calls=$calls"; fi

# hook-bad-mode: 알 수 없는 모드 → 0, AO 호출 0
reset; rc=$(run bogus "$J" AGENT_ORCHESTRATOR="$T/fake-ao" FAKE_MODE=new)
if [ "$rc" = 0 ] && [ ! -s "$T/out" ] && [ ! -e "$T/calls" ]; then ok hook-bad-mode; else bad hook-bad-mode "rc=$rc"; fi

# hook-json-shape: hooks.json 구조(이벤트 4개, 모두 wait 하나·asyncRewake+7200, 동기 훅 없음)
if python3 - "$PLUG/hooks/hooks.json" "$PLUG/.claude-plugin/plugin.json" <<'EOF'
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]; p = json.load(open(sys.argv[2]))
assert p["name"] == "inbox-hooks" and p["defaultEnabled"] is False and p["version"] == "0.2.0"
assert set(h) == {"Stop", "StopFailure", "UserPromptSubmit", "SessionStart"}
for ev, groups in h.items():
    hs = [x for g in groups for x in g["hooks"]]
    assert len(hs) == 1, ev
    x = hs[0]
    assert x["command"] == '"${CLAUDE_PLUGIN_ROOT}"/scripts/inbox-hook.sh wait'
    assert x.get("asyncRewake") is True and x["timeout"] == 7200
EOF
then ok hook-json-shape; else bad hook-json-shape "hooks.json 구조"; fi

# hook-validate
if command -v claude >/dev/null 2>&1; then
  if out=$(claude plugin validate "$PLUG" 2>&1) && printf '%s' "$out" | grep -q 'Validation passed'; then ok hook-validate
  else bad hook-validate "$(printf '%s' "$out" | tail -5)"; fi
else skp hook-validate "claude CLI 없음"; fi

collected=$((pass + fail + skip))
[ "$collected" = "$EXPECT" ] || { echo "FAIL collected=$collected != EXPECT=$EXPECT"; fail=$((fail + 1)); }
echo "collected=$collected passed=$pass failed=$fail skipped=$skip"
[ "$fail" = 0 ]
