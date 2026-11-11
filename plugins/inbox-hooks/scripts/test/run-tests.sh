#!/usr/bin/env bash
# inbox-hooks 래퍼 자동 시험(계획 2026-11-11 rev 5 §3 S2). 가짜 AGENT_ORCHESTRATOR만 쓴다.
#   bash plugins/inbox-hooks/scripts/test/run-tests.sh   → 마지막 줄 "collected=N passed=N failed=N skipped=N"
# 실제 ~/.local/state/agent-orchestrator 와 ~/.local/bin 은 건드리지 않는다(AO_STATE_ROOT=임시 폴더).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PLUG=$(cd "$HERE/../.." && pwd)
HOOK="$PLUG/scripts/inbox-hook.sh"
EXPECT=8
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
  echo "inbox-wait 2"; exit 0
fi
cat > "$FAKE_DIR/stdin.$n"
if [ "${2:-}" = --session-start ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"[받은편지함] 미처리 1줄"}}\n'
fi
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

# hook-start-json
reset; rc=$(run session-start "${J/Stop/SessionStart}" AGENT_ORCHESTRATOR="$T/fake-ao" FAKE_MODE=new)
last=$(tail -1 "$T/calls" 2>/dev/null)
if [ "$rc" = 0 ] && [ "$last" = "inbox-wait --session-start" ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["hookSpecificOutput"]["additionalContext"]' "$T/out" 2>/dev/null
then ok hook-start-json; else bad hook-start-json "rc=$rc last=$last out=$(cat "$T/out")"; fi

# hook-bad-mode: 알 수 없는 모드 → 0, AO 호출 0
reset; rc=$(run bogus "$J" AGENT_ORCHESTRATOR="$T/fake-ao" FAKE_MODE=new)
if [ "$rc" = 0 ] && [ ! -s "$T/out" ] && [ ! -e "$T/calls" ]; then ok hook-bad-mode; else bad hook-bad-mode "rc=$rc"; fi

# hook-json-shape: hooks.json 구조(이벤트 4개, wait는 asyncRewake+7200, session-start는 동기 10)
if python3 - "$PLUG/hooks/hooks.json" "$PLUG/.claude-plugin/plugin.json" <<'EOF'
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]; p = json.load(open(sys.argv[2]))
assert p["name"] == "inbox-hooks" and p["defaultEnabled"] is False
assert set(h) == {"Stop", "StopFailure", "UserPromptSubmit", "SessionStart"}
for ev, groups in h.items():
    hs = [x for g in groups for x in g["hooks"]]
    for x in hs:
        m = x["command"].split()[-1]
        assert x["command"].startswith('"${CLAUDE_PLUGIN_ROOT}"/scripts/inbox-hook.sh ')
        if m == "wait": assert x.get("asyncRewake") is True and x["timeout"] == 7200
        else: assert m == "session-start" and ev == "SessionStart" and "asyncRewake" not in x and x["timeout"] == 10
    assert [x["command"].split()[-1] for x in hs] == (["session-start", "wait"] if ev == "SessionStart" else ["wait"])
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
