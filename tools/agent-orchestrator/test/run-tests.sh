#!/usr/bin/env bash
# run-tests.sh — agent-orchestrator S1·S2 계약 시험 (가짜 herdr, PATH 격리)
#
# 사용: tools/agent-orchestrator/test/run-tests.sh
# 실제 herdr를 부르지 않는다. 모든 호출은 env -i PATH="$FAKE:/usr/bin:/bin" HOME="$T/home" 로 격리하고,
# 첫 케이스에서 격리 PATH의 herdr가 가짜인지 확인한다(실제 /opt/homebrew/bin/herdr가 잡히면 전부 무효).
# 결과: 케이스마다 "PASS|FAIL <이름> — …" 한 줄, 끝에 집계. 실행된 케이스 수가 EXPECT와 다르면 실패.
# bash 3.2 호환.
# shellcheck disable=SC2015
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
AO=$(cd "$HERE/.." && pwd)
BIN="$AO/bin/agent-orchestrator"
T=$(mktemp -d "${TMPDIR:-/tmp}/ao-test.XXXXXX")
T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
FAKE="$T/bin"; NOHERDR="$T/bin-noherdr"; FD="$T/fake"
mkdir -p "$FAKE" "$NOHERDR" "$FD" "$T/home"
cp "$HERE/fake-herdr.py" "$FAKE/herdr"; chmod +x "$FAKE/herdr"
EXPECT=134

PASS=0; FAIL=0
# 여러 줄 값은 ⏎로 이어 한 줄 한 케이스를 지킨다
ok()  { PASS=$((PASS + 1)); echo "PASS $1 — $(printf '%s' "$2" | tr '\n' '⏎')"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1 — 기대 $(printf '%s' "$2" | tr '\n' '⏎') / 실제 $(printf '%s' "$3" | tr '\n' '⏎')"; }

reset_state() {
  : > "$FD/calls.log"
  rm -f "$FD"/fail-* "$FD/notready" "$FD/server-down"
  cat > "$FD/state.json" <<'JSON'
{"tabs":[{"tab_id":"w1:t1","label":"1","workspace_id":"w1"}],
 "panes":[{"pane_id":"w1:p1","tab_id":"w1:t1","rect":{"x":0,"y":0,"height":50},"cwd":"/tmp/x","label":"","agent":"claude"}],
 "agents":[]}
JSON
}
# 상태 조작: setst <이름> <agent_status> [prompt 뒤 상태]
setst() {
  FD="$FD" /usr/bin/python3 - "$@" <<'PY'
import json, os, sys
p = os.path.join(os.environ["FD"], "state.json"); s = json.load(open(p))
for a in s["agents"]:
    if a["name"] == sys.argv[1]:
        a["agent_status"] = sys.argv[2]
        if len(sys.argv) > 3: a["after_prompt"] = sys.argv[3]
json.dump(s, open(p, "w"))
PY
}

# 격리 실행: run [VAR=값 …] -- <명령…>  → OUT, ERR, RC
BASE=(PATH="$FAKE:/usr/bin:/bin" HOME="$T/home" FAKE_DIR="$FD" HERDR_ENV=1
      HERDR_PANE_ID=w1:p1 HERDR_TAB_ID=w1:t1 HERDR_WORKSPACE_ID=w1)
run() {
  local e=()
  while [ "$1" != -- ]; do e+=("$1"); shift; done
  shift
  OUT=$(cd "$T" && env -i "${BASE[@]}" ${e[@]+"${e[@]}"} "$@" 2>"$T/err"); RC=$?
  ERR=$(cat "$T/err")
}
ao() { run -- bash "$BIN" "$@"; }
# chk <이름> <기대 rc> [<기대 stdout>]
chk() {
  local name=$1 want=$2
  if [ $# -ge 3 ]; then
    if [ "$RC" = "$want" ] && [ "$OUT" = "$3" ]; then ok "$name" "rc=$want out=$3"
    else bad "$name" "rc=$want out=$3" "rc=$RC out=$OUT err=$ERR"; fi
  else
    if [ "$RC" = "$want" ]; then ok "$name" "rc=$want"
    else bad "$name" "rc=$want" "rc=$RC out=$OUT err=$ERR"; fi
  fi
}
called() { grep -qF -- "$1" "$FD/calls.log"; }

reset_state
echo "== PATH 격리"
run -- /bin/sh -c 'command -v herdr'
[ "$OUT" = "$FAKE/herdr" ] && ok iso-fake-herdr "격리 PATH의 herdr = 가짜" || bad iso-fake-herdr "$FAKE/herdr" "${OUT:-없음}"
run PATH="$NOHERDR:/usr/bin:/bin" -- /bin/sh -c 'command -v herdr || echo none'
[ "$OUT" = none ] && ok iso-no-herdr "가짜 제거 PATH엔 herdr 없음" || bad iso-no-herdr none "$OUT"

echo "== 백엔드 결정·음성 대조(11·12·10)"
ao backend; chk backend 0 herdr
run AGENT_ORCHESTRATOR_BACKEND=none -- bash "$BIN" backend; chk neg-backend-none 11
run HERDR_ENV= -- bash "$BIN" backend; chk neg-no-herdr-env 11
run HERDR_ENV= -- bash "$BIN" agent-status ao-x; chk neg-no-herdr-env-op 11
mkdir -p "$T/home/.config/agent-orchestrator"
echo "backend=herdr" > "$T/home/.config/agent-orchestrator/config"
run HERDR_ENV= -- bash "$BIN" backend; chk neg-config-outside 11
echo "backend=nosuch" > "$T/home/.config/agent-orchestrator/config"
ao backend; chk neg-config-unknown-adapter 12
rm -f "$T/home/.config/agent-orchestrator/config"
# 어댑터 파일 제거 → 12 (사본 디렉터리 + AGENT_ORCHESTRATOR_HOME)
cp -R "$AO" "$T/ao-noadapter"; rm -f "$T/ao-noadapter/adapters/herdr.sh"
run AGENT_ORCHESTRATOR_HOME="$T/ao-noadapter" -- bash "$BIN" backend; chk neg-adapter-missing 12
# 로딩 실패(끝 표시 없음) → 12
cp -R "$AO" "$T/ao-broken"; grep -v '^AO_ADAPTER_OK=1' "$AO/adapters/herdr.sh" > "$T/ao-broken/adapters/herdr.sh"
run AGENT_ORCHESTRATOR_HOME="$T/ao-broken" -- bash "$BIN" backend; chk neg-adapter-broken 12
# lib 없음 → 12
cp -R "$AO" "$T/ao-nolib"; rm -f "$T/ao-nolib/lib/common.sh"
run AGENT_ORCHESTRATOR_HOME="$T/ao-nolib" -- bash "$BIN" backend; chk neg-lib-missing 12
# 가짜 herdr 제거(격리 PATH) → 12
run PATH="$NOHERDR:/usr/bin:/bin" -- bash "$BIN" backend; chk neg-herdr-binary-missing 12
run PATH="$NOHERDR:/usr/bin:/bin" -- bash "$BIN" whoami; chk neg-herdr-binary-missing-op 12
# 서버 정지 → 4
touch "$FD/server-down"; ao backend; chk server-down 4; rm -f "$FD/server-down"
# 어댑터에 없는 동작 → 10
cp -R "$AO" "$T/ao-nopanerun"; echo 'unset -f op_pane_run' >> "$T/ao-nopanerun/adapters/herdr.sh"
run AGENT_ORCHESTRATOR_HOME="$T/ao-nopanerun" -- bash "$BIN" pane-run w1:p1 "echo hi"; chk neg-unsupported-op 10
called "pane run" && bad neg-unsupported-no-call "pane run 호출 없음" "호출됨" || ok neg-unsupported-no-call "10이면 백엔드 호출 없음"

echo "== 인자 오류 2 (백엔드보다 먼저)"
ao; chk arg-no-op 2
ao bogus; chk arg-unknown-op 2
run AGENT_ORCHESTRATOR_BACKEND=none -- bash "$BIN" agent-send ao-x "$(printf 'a\nb')"; chk arg-newline-before-backend 2
ao agent-send ao-x "$(printf 'a\nb')"; chk arg-newline-prompt 2
ao agent-start BadName w1:p1 --kind claude; chk arg-bad-name 2
ao agent-start "$(printf 'ok\nbad')" w1:p1 --kind claude; chk arg-name-multiline 2
ao agent-start ao-x w1:p1 --kind gemini; chk arg-bad-kind 2
ao agent-start ao-x w1:p1; chk arg-no-kind 2
ao whoami --field host; chk arg-bad-field 2
ao agent-wait ao-x --timeout 0; chk arg-bad-timeout 2
ao tab-open; chk arg-tab-no-name 2
ao pane-open "작업" --cwd "$T/nope"; chk arg-bad-cwd 2
ao pane-open "작업" --parent "bad id"; chk arg-bad-parent 2
ao list; chk arg-list-no-kind 2
ao close; chk arg-close-no-pane 2

echo "== whoami"
ao whoami; chk whoami-pane 0 w1:p1
ao whoami --field tab; chk whoami-tab 0 w1:t1
ao whoami --field workspace; chk whoami-ws 0 w1
run HERDR_PANE_ID= -- bash "$BIN" whoami; chk whoami-missing 3

echo "== tab-open·pane-open (배치)"
reset_state
ao tab-open "인계 탭" --cwd "$T"; chk tab-open 0 w1:p2
called "tab create --workspace w1 --cwd $T --label 인계 탭 --no-focus" && ok tab-open-args "--label·--cwd·--no-focus" || bad tab-open-args "tab create … --no-focus" "$(grep 'tab create' "$FD/calls.log")"
reset_state
ao pane-open "작업자 1" --cwd "$T"; chk pane-open-right 0 w1:p2
called "pane split w1:p1 --direction right --cwd $T --no-focus" && ok pane-open-right-args "right·--no-focus" || bad pane-open-right-args "split right" "$(grep 'pane split' "$FD/calls.log")"
called "pane rename w1:p2 작업자 1" && ok pane-open-label "split 직후 한글 이름" || bad pane-open-label "pane rename w1:p2 작업자 1" "$(grep 'rename' "$FD/calls.log")"
ao pane-open "작업자 2" --cwd "$T"; chk pane-open-down 0 w1:p3
called "pane split w1:p2 --direction down --ratio 0.5" && ok pane-open-down-args "가장 높은 오른쪽 pane을 down 0.5" || bad pane-open-down-args "split w1:p2 down" "$(grep 'pane split' "$FD/calls.log" | tail -1)"
# --parent: HERDR_PANE_ID 없이 기준 pane 지정(기존 spawn 5번째 인자 호환)
run HERDR_PANE_ID= -- bash "$BIN" pane-open "작업자 3" --parent w1:p1 --cwd "$T"; chk pane-open-parent 0 w1:p4
ao pane-open "작업자 4" --cwd "$T"; ao pane-open "작업자 5" --cwd "$T"; chk pane-open-fifth 0 w1:p6
ao pane-open "작업자 6" --cwd "$T"; chk pane-open-overflow-tab 0 w1:p7
called "tab create --workspace w1 --cwd $T --label [WO] 작업 넘침 --no-focus" && ok pane-open-overflow-label "넘침 탭 '[WO] 작업 넘침'" || bad pane-open-overflow-label "tab create [WO] 작업 넘침" "$(grep 'tab create' "$FD/calls.log")"
# 넘침 탭이 이미 있고 첫 pane이 비어 있으면 그대로 쓴다
ao pane-open "작업자 7" --cwd "$T"; chk pane-open-overflow-reuse 0 w1:p7
ao pane-open "작업자 8" --parent w1:p99 --cwd "$T"; chk pane-open-missing-parent 3
reset_state; echo internal > "$FD/fail-pane-rename"
ao pane-open "작업자 9" --cwd "$T"
[ "$RC" = 0 ] && [ "$OUT" = w1:p2 ] && echo "$ERR" | grep -q '이름 붙이기 실패' && ok pane-open-rename-fail-warn "이름 실패는 경고만 rc=0" || bad pane-open-rename-fail-warn "rc=0 + 경고" "rc=$RC out=$OUT err=$ERR"

echo "== self-name (S5 1회차 계약: 빈 값·숫자 → 인자 / 접두어 있음 → 유지 / 사용자 이름 → 접두어만)"
# 현재 label 조작: setlabel <tab|pane> <id> <label>
setlabel() {
  FD="$FD" /usr/bin/python3 - "$@" <<'PY'
import json, os, sys
p = os.path.join(os.environ["FD"], "state.json"); s = json.load(open(p))
for x in s[sys.argv[1] + "s"]:
    if x[sys.argv[1] + "_id"] == sys.argv[2]:
        x["label"] = sys.argv[3]
json.dump(s, open(p, "w"))
PY
}
reset_state
# 탭 "1"(herdr 기본 번호)·pane 빈 값 → 인자 그대로
ao self-name "[OC] 오케스트레이터" "[OC] S1 구현"; chk self-name 0 ""
called "tab rename w1:t1 [OC] 오케스트레이터" && called "pane rename w1:p1 [OC] S1 구현" && ok self-name-calls "빈 값·숫자면 인자 그대로" || bad self-name-calls "tab·pane rename" "$(grep rename "$FD/calls.log")"
: > "$FD/calls.log"
ao self-name "[WO] 다른 이름" "[WO] 다른 pane"
[ "$RC" = 0 ] && ! called "rename" && echo "$ERR" | grep -q '이름 유지' && ok self-name-keep "이미 [XX] 접두어면 유지(경고)" || bad self-name-keep "rename 없음 + 유지 경고" "rc=$RC $(grep rename "$FD/calls.log") err=$ERR"
reset_state; setlabel pane w1:p1 3
ao self-name "[OC] 탭" "[OC] 숫자 pane"
[ "$RC" = 0 ] && called "pane rename w1:p1 [OC] 숫자 pane" && ok self-name-numeric "pane 숫자 이름 = 기본값" || bad self-name-numeric "pane rename" "rc=$RC $(grep rename "$FD/calls.log")"
reset_state; setlabel tab w1:t1 "Peter review"; setlabel pane w1:p1 "Peter review"
ao self-name "[OC] 새 작업" "[RV] 새 작업"
[ "$RC" = 0 ] && called "tab rename w1:t1 [OC] Peter review" && called "pane rename w1:p1 [RV] Peter review" && ok self-name-user-en "사용자 영문 이름 본문 보존·접두어만" || bad self-name-user-en "[OC]/[RV] Peter review" "rc=$RC $(grep rename "$FD/calls.log")"
reset_state; setlabel tab w1:t1 "헬프AI"
ao self-name "[OC] 무시될 본문"
[ "$RC" = 0 ] && called "tab rename w1:t1 [OC] 헬프AI" && ok self-name-user-ko "사용자 한글 이름 본문 보존·접두어만" || bad self-name-user-ko "[OC] 헬프AI" "rc=$RC $(grep rename "$FD/calls.log")"
reset_state; setlabel tab w1:t1 "Peter review"
ao self-name "새 작업"
[ "$RC" = 0 ] && ! called "rename" && ok self-name-noprefix-arg "인자에 접두어 없으면 사용자 이름 유지" || bad self-name-noprefix-arg "rename 없음" "rc=$RC $(grep rename "$FD/calls.log")"
reset_state; setlabel tab w1:t1 "[OC] 논의"; setlabel pane w1:p1 "[OC] 논의"
ao self-name --force "[OC] 새 주제" "[OC] 새 주제 pane"
[ "$RC" = 0 ] && called "tab rename w1:t1 [OC] 새 주제" && called "pane rename w1:p1 [OC] 새 주제 pane" && ! called "tab get" && ok self-name-force "--force는 판정 없이 바꿈" || bad self-name-force "tab·pane rename, get 없음" "rc=$RC $(cat "$FD/calls.log")"
ao self-name --force; chk arg-self-name-force-only 2
ao self-name --bogus "[OC] 탭"; chk arg-self-name-bad-opt 2
ao whoami --field tab-label; chk whoami-tab-label 0 "[OC] 새 주제"
reset_state
ao whoami --field pane-label; chk whoami-pane-label-empty 0 ""
run HERDR_TAB_ID= -- bash "$BIN" whoami --field tab-label; chk whoami-tab-label-missing 3
# 가드 제거 시 실패 증명: 사용자 이름 보존 줄(GUARD:user-name)을 지운 사본은 본문을 갈아 끼운다
cp -R "$AO" "$T/ao-nouserguard"
grep -v 'GUARD:user-name' "$AO/adapters/herdr.sh" > "$T/ao-nouserguard/adapters/herdr.sh"
if grep -q 'GUARD:user-name' "$T/ao-nouserguard/adapters/herdr.sh"; then bad neg-self-name-user-guard "가드 제거" "남음"; else
  reset_state; setlabel tab w1:t1 "Peter review"
  run AGENT_ORCHESTRATOR_HOME="$T/ao-nouserguard" -- bash "$BIN" self-name "[OC] 새 작업"
  called "tab rename w1:t1 [OC] 새 작업" && ! called "tab rename w1:t1 [OC] Peter review" \
    && ok neg-self-name-user-guard "가드 없으면 Peter review 본문이 바뀐다(Peter review 케이스가 FAIL할 조건)" || bad neg-self-name-user-guard "본문 교체" "rc=$RC $(grep rename "$FD/calls.log")"
fi

echo "== agent-start"
reset_state
ao agent-start ao-a w1:p1 --kind claude -- --model sonnet --effort high; chk agent-start 0 ""
called "agent start ao-a --kind claude --pane w1:p1 --timeout 90000 -- --model sonnet --effort high" && ok agent-start-args "--timeout 90000 -- CLI 인자" || bad agent-start-args "agent start …" "$(grep 'agent start' "$FD/calls.log")"
ao agent-start ao-a w1:p1 --kind claude; chk agent-start-dup 3
ao agent-start ao-b w1:p99 --kind claude; chk agent-start-no-pane 3
touch "$FD/notready"; ao agent-start ao-c w1:p1 --kind claude; chk agent-start-not-ready 5; rm -f "$FD/notready"
ao agent-start ao-cx w1:p1 --kind codex; chk agent-start-codex 0 ""

echo "== agent-send"
setst ao-a idle working
ao agent-send ao-a "지시서를 읽고 진행해" --confirm; chk send-confirm 0 working
called "agent prompt ao-a 지시서를 읽고 진행해 --wait --until working --until done --timeout 60000" && ok send-confirm-args "--wait --until working --until done --timeout" || bad send-confirm-args "prompt --until done" "$(grep 'agent prompt' "$FD/calls.log")"
setst ao-a idle "done"
ao agent-send ao-a "짧은 일" --confirm; chk send-fast-done 0 "done"
setst ao-a idle
ao agent-send ao-a "답장"; chk send-plain 0 idle
called "agent prompt ao-a 답장" && ! grep -q 'agent prompt ao-a 답장 --' "$FD/calls.log" && ok send-plain-args "--confirm 없으면 --wait·--timeout 없음" || bad send-plain-args "prompt 단독" "$(grep 'agent prompt ao-a 답장' "$FD/calls.log")"
setst ao-a blocked
ao agent-send ao-a "답장" --confirm; chk send-blocked 6
ao agent-send ao-zz "답장"; chk send-missing 3
setst ao-a idle
ao agent-send w1:p1 "pane id로 보냄"; chk send-by-pane 0 idle
called "agent prompt w1:p1 pane id로 보냄" && ok send-by-pane-args "pane id 대상 그대로 전달" || bad send-by-pane-args "agent prompt w1:p1" "$(grep 'agent prompt w1' "$FD/calls.log")"
# 음성 대조: 어댑터 사본에서 --until done 을 빼면 빠른 완료가 timeout(7)이 된다
cp -R "$AO" "$T/ao-nodone"
sed 's/ --until working --until "done" / --until working /' "$AO/adapters/herdr.sh" > "$T/ao-nodone/adapters/herdr.sh"
if grep -q -- '--until working --until "done"' "$T/ao-nodone/adapters/herdr.sh"; then bad neg-send-until-done "sed 적용" "남음"; else
  setst ao-a idle "done"
  run AGENT_ORCHESTRATOR_HOME="$T/ao-nodone" -- bash "$BIN" agent-send ao-a "짧은 일" --confirm; chk neg-send-until-done 7
fi

echo "== agent-wait·agent-status·session-id·transcript"
setst ao-a "done"
ao agent-wait ao-a --timeout 5; chk wait-done 0 "done"
called "agent wait ao-a --until done --until idle --timeout 5000" && ok wait-args "--until done --until idle, 초→ms" || bad wait-args "agent wait … 5000" "$(grep 'agent wait' "$FD/calls.log")"
setst ao-a working
ao agent-wait ao-a --timeout 1; chk wait-timeout 7
ao agent-wait ao-zz; chk wait-missing 3
ao agent-status ao-a; chk status-working 0 working
setst ao-a weird; ao agent-status ao-a; chk status-unknown 0 unknown
ao agent-status ao-zz; chk status-missing 3
ao agent-session-id ao-a; chk session-id 0 uuid-ao-a
J="$T/home/.claude/projects/-tmp-x/uuid-ao-a.jsonl"
ao agent-transcript ao-a; chk transcript-no-file 3
mkdir -p "$(dirname "$J")"; : > "$J"
ao agent-transcript ao-a; chk transcript-claude 0 "$J"
# 음성 대조(2회차 NOTE 1): codex kind로 등록된 agent 이름 → 10
ao agent-transcript ao-cx; chk neg-transcript-codex 10

echo "== agent-read·agent-keys·pane-run·close·list"
ao agent-read ao-a --lines 5; chk read-agent 0 "$(printf 'screen ao-a line1\nscreen ao-a line2')"
called "agent read ao-a --source visible --lines 5" && ok read-agent-args "--source visible --lines" || bad read-agent-args "agent read …" "$(grep 'agent read' "$FD/calls.log")"
ao agent-read w1:p1; chk read-pane 0 "$(printf 'pane w1:p1 line1\npane w1:p1 line2')"
called "pane read w1:p1 --lines 30" && ok read-pane-default "pane id면 pane read, 기본 30줄" || bad read-pane-default "pane read w1:p1 --lines 30" "$(grep 'pane read' "$FD/calls.log")"
ao agent-keys ao-a Escape; chk keys 0 ""
ao pane-run w1:p1 "echo 'hi there'"; chk pane-run 0 ""
called "pane run w1:p1 echo 'hi there'" && ok pane-run-args "셸 문자열 한 인자" || bad pane-run-args "pane run …" "$(grep 'pane run' "$FD/calls.log")"
ao list --agents; chk list-agents 0 "$(printf 'w1:p1\tao-a\tunknown\nw1:p1\tao-cx\tidle')"
ao list --panes; chk list-panes 0 "$(printf 'w1:p1\t-\t-')"
setst ao-a working
echo garbage > "$FD/fail-agent-get"; ao agent-status ao-a; chk backend-garbage 4; rm -f "$FD/fail-agent-get"
echo internal_error > "$FD/fail-pane-close"; ao close w1:p1; chk backend-error 4; rm -f "$FD/fail-pane-close"
ao close w1:p1; chk close 0 ""
ao close w1:p1; chk close-missing 3

echo "== S2: install.sh·uninstall-backend.sh (사본 리포 + 가짜 HOME)"
# 사본 리포: install.sh가 REPO=tools/../.. 로 리포 상대 경로를 푼다 → 실제 리포의 auto-chain을 읽지 않게
R="$T/repo"; mkdir -p "$R/tools" "$R/plugins/auto-chain/skills/autonomous-chain/archive"
cp -R "$AO" "$R/tools/agent-orchestrator"
I="$R/tools/agent-orchestrator/install.sh"; U="$R/tools/agent-orchestrator/uninstall-backend.sh"
printf 'herdr pane 규칙\n일반 줄\n' > "$R/plugins/auto-chain/skills/autonomous-chain/SKILL.md"
printf 'herdr 옛 기록\n' > "$R/plugins/auto-chain/skills/autonomous-chain/archive/old.md"   # 제외 대상
printf 'herdr 버전 이력\n' > "$R/plugins/auto-chain/skills/autonomous-chain/CHANGELOG.md"   # 제외 대상
H="$T/h2"
mkdir -p "$H/.claude/hooks" "$H/.codex" "$H/.claude/projects/-Users-peter-Dev-herdr-ios/memory" "$H/.claude/projects/-Users-peter-Dev-gchat-g-on/memory"
echo '#!/bin/sh' > "$H/.claude/hooks/herdr-agent-state.sh"; echo '#!/bin/sh' > "$H/.codex/herdr-agent-state.sh"
for f in "$H/.claude/settings.json" "$H/.codex/hooks.json"; do cat > "$f" <<'JSON'
{"model":"opus","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/bin/sh -c 'rex __internal session-start'"}]},
 {"matcher":"^(startup|resume)$","hooks":[{"type":"command","command":"bash '/x/herdr-agent-state.sh' session"}]}],
 "PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"python3 guard.py"}]}]}}
JSON
done
printf '[projects."/Users/peter/Dev/herdr-ios"]\ntrust_level = "trusted"\n' > "$H/.codex/config.toml"
echo 'm' > "$H/.claude/projects/-Users-peter-Dev-herdr-ios/memory/a.md"
printf '# 규칙\nherdr 안에서는 pane\n그 밖\nHERDR_ENV=1 이면\n' > "$H/.claude/CLAUDE.md"
printf 'herdr 탭 이름은 한글\n' > "$H/.codex/AGENTS.md"
printf 'herdr --machine office-macmini agent list\n' > "$H/.claude/projects/-Users-peter-Dev-gchat-g-on/memory/office-macmini-session-contact.md"
# 트리 전체 지문(경로·종류·링크 대상·내용)
# 제외 없는 전체 지문. install.sh·uninstall-backend.sh가 PYTHONDONTWRITEBYTECODE=1로 python 캐시 쓰기를 막으므로
# HOME/Library/Caches 가 생기면 실제 쓰기로 본다
snap() { (cd "$1" && find . -print | sort | while IFS= read -r f; do
  if [ -L "$f" ]; then echo "L $f $(readlink "$f")"; elif [ -f "$f" ]; then echo "F $f $(shasum < "$f")"; else echo "D $f"; fi
  done) | shasum; }
ih() { run HOME="$H" AGENT_ORCHESTRATOR_LINK_TARGET="$R/tools/agent-orchestrator/bin/agent-orchestrator" -- bash "$@"; }

S0=$(snap "$H")
ih "$I" --check herdr; chk check-core-missing 1
S1=$(snap "$H")
[ "$S0" = "$S1" ] && ok check-readonly "--check 전후 HOME 지문 같음" || bad check-readonly "지문 같음" "다름"
echo "$OUT" | grep -q '^== core: 필수 0/2 있음' && ok check-core-count "core 0/2" || bad check-core-count "core 0/2" "$(echo "$OUT" | grep '^==')"
echo "$OUT" | grep -q '^== herdr: 필수 6/6 있음, rule 잔존 4건' && ok check-herdr-count "herdr 6/6, 잔존 4(CLAUDE.md 2·AGENTS 1·SKILL 1, archive·CHANGELOG 제외)" || bad check-herdr-count "6/6 잔존 4" "$(echo "$OUT" | grep '^==')"
printf '%s\n' "$OUT" | grep -q "^허용 1건	allow" && ok check-allow "allow 1건 따로 셈" || bad check-allow "허용 1건" "$(echo "$OUT" | grep allow)"
printf '%s\n' "$OUT" | grep -q "^정보	existing	rex	~/.claude/settings.json	보존 대상 있음" && ok check-existing-info "existing은 정보 행" || bad check-existing-info "정보 existing rex" "$(echo "$OUT" | grep existing)"
ih "$I" --check nosuch; chk check-unknown-backend 12
ih "$I" --check; chk check-no-backend 2
ih "$I" --check "../x"; chk check-bad-name 2

ih "$I" herdr; chk install-first 0
[ "$(readlink "$H/.local/bin/agent-orchestrator")" = "$R/tools/agent-orchestrator/bin/agent-orchestrator" ] && [ "$(cat "$H/.config/agent-orchestrator/config")" = backend=herdr ] \
  && ok install-made "링크·config 생성" || bad install-made "링크·backend=herdr" "$(ls -l "$H/.local/bin" 2>&1) $(cat "$H/.config/agent-orchestrator/config" 2>&1)"
S2=$(snap "$H"); ih "$I" herdr; S3=$(snap "$H")
[ "$RC" = 0 ] && [ "$S2" = "$S3" ] && [ "$(echo "$OUT" | grep -c '^유지')" = 2 ] && ok install-idempotent "두 번째 실행 = 유지 2, 지문 같음" || bad install-idempotent "유지 2·지문 같음" "rc=$RC $OUT"
ih "$I" --check herdr; chk check-after-install 0
run HOME="$H" -- "$H/.local/bin/agent-orchestrator" backend; chk link-runs 0 herdr
printf 'other=1\nbackend=rex\n' > "$H/.config/agent-orchestrator/config"
ih "$I" herdr; [ "$RC" = 0 ] && [ "$(cat "$H/.config/agent-orchestrator/config")" = "$(printf 'other=1\nbackend=herdr')" ] && ok install-config-value "값만 바꾸고 다른 줄 보존" || bad install-config-value "other=1⏎backend=herdr" "$(cat "$H/.config/agent-orchestrator/config")"
H3="$T/h3"; mkdir -p "$H3/.local/bin"; echo keep > "$H3/.local/bin/agent-orchestrator"
run HOME="$H3" AGENT_ORCHESTRATOR_LINK_TARGET="$R/tools/agent-orchestrator/bin/agent-orchestrator" -- bash "$I" herdr; chk install-conflict 3
[ "$(cat "$H3/.local/bin/agent-orchestrator")" = keep ] && ok install-conflict-keep "일반 파일 덮어쓰지 않음" || bad install-conflict-keep keep "$(cat "$H3/.local/bin/agent-orchestrator")"
run HOME="$H3" AGENT_ORCHESTRATOR_LINK_TARGET="$T/nope" -- bash "$I" herdr; chk install-no-target 12

echo "== S2: uninstall dry-run·apply"
S4=$(snap "$H")
ih "$U" herdr; chk uninstall-dry 0
S5=$(snap "$H")
[ "$S4" = "$S5" ] && [ ! -e "$H/.claude/archive" ] && ok uninstall-dry-nochange "dry-run 전후 지문 같음·archive 없음" || bad uninstall-dry-nochange "변경 0" "다름"
n=$(printf '%s\n' "$OUT" | grep -c '^보존	\(existing\|link	ours-core\|config	ours-core\)')
[ "$n" = 6 ] && ok uninstall-dry-preserve "existing 4·ours-core 2 = 보존" || bad uninstall-dry-preserve "보존 6" "$n: $(printf '%s\n' "$OUT" | grep '^보존')"
printf '%s\n' "$OUT" | grep -q '^위치만 출력 2건	rule	ours-backend	~/.claude/CLAUDE.md' && ok uninstall-dry-rule "rule = 위치만" || bad uninstall-dry-rule "위치만 2건" "$(echo "$OUT" | grep rule)"
printf '%s\n' "$OUT" | grep -q '^== dry-run: 실행할 동작 4개' && ok uninstall-dry-count "실행 예정 4(훅 2·설정 2)" || bad uninstall-dry-count "4개" "$(echo "$OUT" | grep '^==')"
ih "$U" core; chk uninstall-core 2
ih "$U" herdr --force; chk uninstall-bad-opt 2
ih "$U" nosuch; chk uninstall-unknown 12
# 가드 제거 시 실패 증명: 보존 줄을 지운 사본은 existing rex 설정을 제거 계획에 넣는다
cp -R "$R" "$T/repo-noguard"
grep -v 'GUARD:preserve' "$R/tools/agent-orchestrator/lib/manifest.py" > "$T/repo-noguard/tools/agent-orchestrator/lib/manifest.py"
if grep -q 'GUARD:preserve' "$T/repo-noguard/tools/agent-orchestrator/lib/manifest.py"; then bad neg-preserve-guard "가드 제거" "남음"; else
  ih "$T/repo-noguard/tools/agent-orchestrator/uninstall-backend.sh" herdr
  ! printf '%s\n' "$OUT" | grep -q '^보존	existing	rex' && ! printf '%s\n' "$OUT" | grep -q '^보존	link	ours-core' \
    && ok neg-preserve-guard "가드 없으면 existing·ours-core가 보존으로 처리되지 않음(rc=$RC)" || bad neg-preserve-guard "보존 줄 없음" "rc=$RC $(printf '%s\n' "$OUT" | grep '^보존')"
fi
C0=$(shasum < "$H/.claude/CLAUDE.md"); T0=$(shasum < "$H/.codex/config.toml")
ih "$U" herdr --apply; chk uninstall-apply 0
A=$(find "$H/.claude/archive/agent-orchestrator" -mindepth 1 -maxdepth 1 -name 'herdr-*' 2>/dev/null | head -1)
[ -n "$A" ] && [ -f "$A/.claude/hooks/herdr-agent-state.sh" ] && [ ! -e "$H/.claude/hooks/herdr-agent-state.sh" ] && [ -f "$A/.codex/herdr-agent-state.sh" ] \
  && ok apply-hook-archived "훅 2개 archive로 이동" || bad apply-hook-archived "archive 이동" "$(find "$H/.claude/archive" 2>&1 | head -5)"
/usr/bin/python3 - "$H/.claude/settings.json" "$A/.claude/settings.json" <<'PY' && ok apply-setting "herdr 항목만 제거·rex·PreToolUse·model 유지·원본 백업" || bad apply-setting "herdr만 제거" "$(cat "$H/.claude/settings.json")"
import json, sys
d = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
cmds = [h["command"] for g in d["hooks"]["SessionStart"] for h in g["hooks"]]
assert not any("herdr-agent-state" in c for c in cmds), cmds
assert any("rex __internal" in c for c in cmds) and d["hooks"]["PreToolUse"] and d["model"] == "opus"
assert any("herdr-agent-state" in h["command"] for g in b["hooks"]["SessionStart"] for h in g["hooks"])
PY
[ "$(shasum < "$H/.claude/CLAUDE.md")" = "$C0" ] && [ "$(shasum < "$H/.codex/config.toml")" = "$T0" ] && [ -L "$H/.local/bin/agent-orchestrator" ] && [ -f "$H/.claude/projects/-Users-peter-Dev-herdr-ios/memory/a.md" ] \
  && ok apply-preserve "rule·existing·ours-core 그대로" || bad apply-preserve "변경 없음" "바뀜"

TOTAL=$((PASS + FAIL))
echo "== 집계: PASS $PASS / FAIL $FAIL / 총 $TOTAL (기대 $EXPECT)"
[ "$TOTAL" = "$EXPECT" ] || { echo "FAIL 케이스 총계 불일치: $TOTAL ≠ $EXPECT"; exit 1; }
[ "$FAIL" = 0 ]
