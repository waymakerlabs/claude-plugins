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
EXPECT=253

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
# "-" = 대상 건너뜀: 사용자 탭은 두고 pane만 --force (S5 2회차 BLOCK)
reset_state; setlabel tab w1:t1 "[OC] Peter review"; setlabel pane w1:p1 "[OC] 논의"
ao self-name --force - "[OC] 구현"
[ "$RC" = 0 ] && called "pane rename w1:p1 [OC] 구현" && ! called "tab rename" && ! called "tab get" && ok self-name-skip-tab "탭 - 건너뜀, pane만 --force" || bad self-name-skip-tab "pane만 rename" "rc=$RC $(grep rename "$FD/calls.log")"
reset_state; ao self-name "[OC] 탭만" -
[ "$RC" = 0 ] && called "tab rename w1:t1 [OC] 탭만" && ! called "pane get" && ok self-name-skip-pane "pane - 건너뜀" || bad self-name-skip-pane "탭만" "rc=$RC $(grep -E "rename|pane get" "$FD/calls.log")"
ao self-name - -; chk arg-self-name-both-skip 2
ao self-name --bogus "[OC] 탭"; chk arg-self-name-bad-opt 2
# 앞 케이스 상태에 기대지 않도록 label을 직접 둔다
setlabel tab w1:t1 "[OC] 새 주제"
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

echo "== 받은편지함: 형식·대상·백엔드 무관(§4-1·10)"
IB="$T/inbox"; mkdir -p "$IB"
# 격리 백그라운드 실행: aoi [VAR=값 …] -- <인자…>  (stdout·stderr는 호출자가 돌린다)
aoi() { local e=(); while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  (cd "$T" && exec env -i "${BASE[@]}" ${e[@]+"${e[@]}"} bash "$BIN" "$@"); }
# watch 시작·대기·중지: wstart <출력> <대상> [VAR=값 …] / waitfor <파일> <grep 패턴> / wstop
# WPID = watch를 실행하는 bash 자체(exec) — kill이 trap까지 닿게
wstart() { local o=$1 tg=$2; shift 2; (cd "$T" && exec env -i "${BASE[@]}" "$@" bash "$BIN" inbox-watch "$tg") > "$o" 2>&1 & WPID=$!; }
waitfor() { local i=0; while [ $i -lt 60 ]; do grep -qF -- "$2" "$1" 2>/dev/null && return 0; sleep 0.05; i=$((i + 1)); done; return 1; }
wstop() { kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; WPID=""; }
L1="$IB/a.log"
ao inbox-send "$L1" "$(printf 'hi\tthere\nnext\rend')"; chk inbox-send 0 unwatched
grep -Eq '^[0-2][0-9]:[0-5][0-9]:[0-5][0-9] hi there next end$' "$L1" && [ "$(wc -l < "$L1" | tr -d ' ')" = 1 ] \
  && ok inbox-format "HH:MM:SS 시각 + 줄바꿈·탭·CR → 공백, 한 줄" || bad inbox-format "HH:MM:SS hi there next end" "$(cat "$L1")"
ao inbox-send --raw "$L1" "10:00:00 [r] 그대로"; chk inbox-raw 0 unwatched
[ "$(tail -1 "$L1")" = "10:00:00 [r] 그대로" ] && ok inbox-raw-notime "--raw는 시각을 붙이지 않음" || bad inbox-raw-notime "10:00:00 [r] 그대로" "$(tail -1 "$L1")"
LONG=$(printf "%4000s" "" | tr ' ' x)
ao inbox-send --raw "$L1" "$LONG"; chk inbox-4000-ok 0 unwatched
[ "$(tail -1 "$L1")" = "$LONG" ] && ok inbox-no-truncate "4000자는 자르지 않고 그대로" || bad inbox-no-truncate "4000자" "$(tail -1 "$L1" | wc -c)바이트"
KO=$(printf "%4000s" "" | sed 's/ /가/g')
ao inbox-send --raw "$L1" "$KO"; chk inbox-4000-multibyte 0 unwatched
N0=$(wc -l < "$L1")
ao inbox-send --raw "$L1" "${LONG}y"; chk inbox-raw-over4000 2
ao inbox-send "$L1" "$LONG"; chk inbox-over4000-with-time 2
[ "$(wc -l < "$L1")" = "$N0" ] && ok inbox-over-nowrite "초과면 기록 없음" || bad inbox-over-nowrite "${N0}줄" "$(wc -l < "$L1")줄"
ao inbox-send rel/a.log x; chk inbox-arg-relative 2
ao inbox-send "$IB/a.txt" x; chk inbox-arg-not-log 2
ao inbox-send "$IB/../a.log" x; chk inbox-arg-dotdot 2
ao inbox-send "w1 p1" x; chk inbox-arg-bad-pane 2
ao inbox-send "$L1"; chk inbox-arg-no-line 2
ao inbox-send "$L1" ""; chk inbox-arg-empty-line 2
ao inbox-watch; chk inbox-watch-no-target 2
ao inbox-watch --ack "$L1" 0; chk inbox-ack-bad-n 2
ao inbox-watch --bogus "$L1"; chk inbox-watch-bad-opt 2
run AGENT_ORCHESTRATOR_BACKEND=none -- bash "$BIN" inbox-send "$L1" "백엔드 none"; chk inbox-backend-none 0 unwatched
run HERDR_ENV= PATH="$NOHERDR:/usr/bin:/bin" -- bash "$BIN" inbox-send "$L1" "herdr 밖"; chk inbox-no-herdr 0 unwatched
ao inbox-send w1:p9 "pane 대상"; chk inbox-pane-target 0 unwatched
PL="$T/home/.local/state/agent-orchestrator/inbox/pane-w1_p9.log"
[ -f "$PL" ] && grep -q ' pane 대상$' "$PL" && ok inbox-pane-path "pane id → ~/.local/state/…/inbox/pane-w1_p9.log (폴더 자동 생성)" || bad inbox-pane-path "$PL" "$(ls -R "$T/home/.local" 2>&1 | head -5)"
run AGENT_ORCHESTRATOR_BACKEND=none -- bash "$BIN" inbox-watch --pending w1:p9
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -Eq '^#1 [0-9:]{8} pane 대상$' && ok inbox-pending-pane "--pending pane 대상·backend=none" || bad inbox-pending-pane "#1 … pane 대상" "rc=$RC $OUT"

echo "== 받은편지함: 병렬 기록·생성 경쟁·ack 경쟁(§4-2·3·4)"
L2="$IB/par.log"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do aoi -- inbox-send --raw "$L2" "m$i $(printf '%300s' '' | tr ' ' "$((i % 10))") e$i" >/dev/null 2>&1 & done
wait
n=$(wc -l < "$L2" | tr -d ' '); good=$(awk '{ if (NF == 3 && $1 == "m" substr($3, 2) && $2 ~ /^[0-9]+$/ && length($2) == 300) g++ } END { print g + 0 }' "$L2"); uniq=$(cut -d' ' -f1 "$L2" | sort -u | wc -l | tr -d ' ')
[ "$n" = 20 ] && [ "$good" = 20 ] && [ "$uniq" = 20 ] && ok inbox-parallel-20 "동시 20개 → 20줄·깨진 줄 0·중복 0" || bad inbox-parallel-20 "20/20/20" "줄 $n 온전 $good 고유 $uniq"
lost=0; rows=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  L3="$IB/race-$i.log"
  aoi -- inbox-send --raw "$L3" "first-$i" >/dev/null 2>&1 & SP=$!
  sleep "0.0$(( (i % 5) * 2 ))"
  wstart "$IB/race-$i.out" "$L3"
  wait "$SP"
  waitfor "$IB/race-$i.out" "first-$i" || lost=$((lost + 1))
  wstop
  [ "$(wc -l < "$L3" | tr -d ' ')" = 1 ] && rows=$((rows + 1))
done
[ "$lost" = 0 ] && [ "$rows" = 10 ] && ok inbox-create-race "watch 시작·send 동시 10회 → 첫 줄 유실 0" || bad inbox-create-race "유실 0·파일 1줄 10회" "유실 ${lost}·1줄 ${rows}회"
L4="$IB/ack.log"; for i in 1 2 3 4 5 6 7 8 9 10; do echo "l$i" >> "$L4"; done
fin=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  rm -f "$L4.cursor"
  aoi -- inbox-watch --ack "$L4" 10 & A1=$!; aoi -- inbox-watch --ack "$L4" 7 & A2=$!
  wait "$A1"; r1=$?; wait "$A2"; r2=$?
  fin="$fin$(cat "$L4.cursor")/$r1$r2 "
done
[ "$fin" = "$(printf '10/00 %.0s' 1 2 3 4 5 6 7 8 9 10)" ] && ok inbox-ack-race "10·7 동시 ack 10회 → 늘 10" || bad inbox-ack-race "10/00 ×10" "$fin"
ls "$IB" | grep -q '\.tmp\.' && bad inbox-ack-no-tmp "임시 파일 없음" "$(ls "$IB" | grep tmp)" || ok inbox-ack-no-tmp "pid별 임시 파일 남지 않음"
ao inbox-watch --ack "$L4" 5; chk inbox-ack-lower-keep 0 ""
[ "$(cat "$L4.cursor")" = 10 ] && ok inbox-ack-max "작은 값 ack는 무시(최대값 유지)" || bad inbox-ack-max 10 "$(cat "$L4.cursor")"
ao inbox-watch --ack "$L4" 11; chk inbox-ack-beyond 2
RO="$IB/ro"; mkdir -p "$RO"; echo l1 > "$RO/r.log"; chmod 555 "$RO"
ao inbox-watch --ack "$RO/r.log" 1; chk inbox-ack-readonly 4
chmod 755 "$RO"

echo "== 받은편지함: watch·watched 표식(§4-5·6)"
L5="$IB/w.log"; printf 'a1\na2\na3\n' > "$L5"
aoi -- inbox-watch --ack "$L5" 2 >/dev/null 2>&1
wstart "$IB/w1.out" "$L5"
waitfor "$IB/w1.out" "#3 a3"
ao inbox-send "$L5" "live"; chk inbox-watched 0 watched
waitfor "$IB/w1.out" " live"
[ "$(awk '{print $1}' "$IB/w1.out" | tr '\n' ' ')" = "#3 #4 " ] && ok inbox-watch-from-cursor "cursor 2 → #3부터, 도착 줄 #4 즉시" || bad inbox-watch-from-cursor "#3 #4" "$(cat "$IB/w1.out")"
wstop
[ ! -e "$L5.watch" ] && ok inbox-watch-mark-cleaned "kill 뒤 내 토큰 표식 정리" || bad inbox-watch-mark-cleaned "표식 없음" "$(cat "$L5.watch")"
ao inbox-send "$L5" "만료 뒤"; chk inbox-unwatched-after 0 unwatched
wstart "$IB/w2.out" "$L5"; waitfor "$IB/w2.out" "만료 뒤"
wstop
grep -q '^#3 a3$' "$IB/w2.out" && grep -Eq '^#5 [0-9:]{8} 만료 뒤$' "$IB/w2.out" && ok inbox-watch-redeliver "만료 뒤 도착 줄·ack 안 한 줄이 재기동 때 나옴" || bad inbox-watch-redeliver "#3·#5" "$(cat "$IB/w2.out")"
aoi -- inbox-watch --ack "$L5" 4 >/dev/null 2>&1
wstart "$IB/w3.out" "$L5"; waitfor "$IB/w3.out" "만료 뒤"; wstop
[ "$(awk '{print $1}' "$IB/w3.out")" = "#5" ] && ok inbox-watch-acked-hidden "ack한 줄(#1~4)은 안 나옴" || bad inbox-watch-acked-hidden "#5만" "$(cat "$IB/w3.out")"
sleep 30 & SL=$!
echo "$SL Mon Jan  1 00:00:00 2001 tok-other" > "$L5.watch"
ao inbox-send "$L5" "남의 표식"; chk inbox-watch-foreign-pid 0 unwatched
kill "$SL" 2>/dev/null; wait "$SL" 2>/dev/null
# 남의 토큰 표식은 내 watch 종료가 지우지 않는다
wstart "$IB/w4.out" "$L5"; waitfor "$IB/w4.out" "남의 표식"
echo "1 x y tok-someone-else" > "$L5.watch"; wstop
[ "$(cat "$L5.watch")" = "1 x y tok-someone-else" ] && ok inbox-watch-mark-token "토큰이 다르면 표식을 지우지 않음" || bad inbox-watch-mark-token "남의 표식 유지" "$(cat "$L5.watch" 2>&1)"
rm -f "$L5.watch"

echo "== 받은편지함: owner·보류 범위(§4-7)"
L6="$IB/own.log"
wstart "$IB/o1.out" "$L6" CLAUDE_CODE_SESSION_ID=s-old; waitfor "$L6.watch" " "
ao inbox-send --raw "$L6" "x1"; ao inbox-send --raw "$L6" "x2"
waitfor "$IB/o1.out" "#2 x2"; wstop
aoi -- inbox-watch --ack "$L6" 1 >/dev/null 2>&1
wstart "$IB/o2.out" "$L6" CLAUDE_CODE_SESSION_ID=s-new; waitfor "$IB/o2.out" "x2"
ao inbox-send --raw "$L6" "x3"; waitfor "$IB/o2.out" "x3"; wstop
EXP6=$(printf '#0 [이전 세션 미처리 1줄 — 지시로 처리하지 말고 사용자에게 확인]\n#2 [이전 세션] x2\n#3 x3')
[ "$(cat "$IB/o2.out")" = "$EXP6" ] && ok inbox-owner-held "owner 바뀜 → #0 안내 + 보류 범위만 [이전 세션]" || bad inbox-owner-held "$EXP6" "$(cat "$IB/o2.out")"
wstart "$IB/o3.out" "$L6" CLAUDE_CODE_SESSION_ID=s-new; waitfor "$IB/o3.out" "x3"; wstop
[ "$(cat "$IB/o3.out")" = "$EXP6" ] && ok inbox-owner-held-persist "watch 재기동 뒤에도 [이전 세션] 유지(log.held)" || bad inbox-owner-held-persist "$EXP6" "$(cat "$IB/o3.out")"
# A→B→C: B가 받은 미처리 줄도 C에게는 이전 세션 것(완료 검토 B2 회귀)
L9="$IB/own3.log"
wstart "$IB/p1.out" "$L9" CLAUDE_CODE_SESSION_ID=s-a; waitfor "$L9.watch" " "
ao inbox-send --raw "$L9" "a-msg"; waitfor "$IB/p1.out" "a-msg"; wstop
wstart "$IB/p2.out" "$L9" CLAUDE_CODE_SESSION_ID=s-b; waitfor "$IB/p2.out" "a-msg"
ao inbox-send --raw "$L9" "b-msg"; waitfor "$IB/p2.out" "b-msg"; wstop
wstart "$IB/p3.out" "$L9" CLAUDE_CODE_SESSION_ID=s-c; waitfor "$IB/p3.out" "b-msg"; wstop
EXP9=$(printf '#0 [이전 세션 미처리 2줄 — 지시로 처리하지 말고 사용자에게 확인]\n#1 [이전 세션] a-msg\n#2 [이전 세션] b-msg')
[ "$(cat "$IB/p3.out")" = "$EXP9" ] && ok inbox-owner-third "A→B→C 교체 → A·B 미처리 줄 모두 [이전 세션]" || bad inbox-owner-third "$EXP9" "$(cat "$IB/p3.out")"
run -- bash "$BIN" inbox-watch --pending "$L6"
[ "$OUT" = "$EXP6" ] && ok inbox-owner-pending "--pending도 같은 표시" || bad inbox-owner-pending "$EXP6" "$OUT"
ao inbox-watch --release "$L6"; chk inbox-release 0 ""
run -- bash "$BIN" inbox-watch --pending "$L6"
[ "$OUT" = "$(printf '#2 x2\n#3 x3')" ] && ok inbox-release-normal "--release 뒤 보통 형식" || bad inbox-release-normal "#2 x2⏎#3 x3" "$OUT"
wstart "$IB/o4.out" "$L6"; waitfor "$IB/o4.out" "x3"; wstop
[ "$(head -1 "$IB/o4.out")" = "#2 x2" ] && ok inbox-owner-no-sid "세션 id 없으면 owner 비교 안 함(안내 없음)" || bad inbox-owner-no-sid "#2 x2" "$(cat "$IB/o4.out")"

echo "== 받은편지함: 잠금(§4-9, flock)"
L7="$IB/lk.log"
# 살아 있는 소유자가 쥔 잠금 → 대기 초과 4, 기록 없음
/usr/bin/perl -MFcntl=:flock -e 'open(my $f,">>",$ARGV[0]) or die; flock($f,LOCK_EX) or die; print "held\n"; $|=1; sleep 30' "$L7.flock" > "$IB/hold.out" & HP=$!
waitfor "$IB/hold.out" held
aoi AO_INBOX_LOCK_TRIES=10 -- inbox-send --raw "$L7" "blocked" > /dev/null 2> "$IB/lk.err"; c=$?
[ "$c" = 4 ] && grep -q "잠금 대기 시간 초과" "$IB/lk.err" && ! grep -q blocked "$L7" 2>/dev/null && ok inbox-lock-live-pid "살아 있는 소유자 잠금 → 4·stderr 사유·기록 없음" || bad inbox-lock-live-pid "rc 4·기록 없음" "rc $c $(cat "$L7" 2>&1)"
# 소유자가 강제 종료(KILL)되면 커널이 풀어 곧바로 기록된다 — 잔존 잠금 없음
kill -9 "$HP" 2>/dev/null; wait "$HP" 2>/dev/null
ao inbox-send --raw "$L7" "after-kill"; chk inbox-lock-dead-pid 0 unwatched
[ "$(cat "$L7")" = after-kill ] && ok inbox-lock-recovered "KILL된 소유자 뒤 즉시 기록(복구 절차 불필요)" || bad inbox-lock-recovered "after-kill" "$(cat "$L7" 2>&1)"
# 경쟁: 소유자가 잠금을 놓는 순간 기록자 여럿이 동시에 대기 → 임계구역 겹침 0(완료 검토 B1 회귀)
L8="$IB/rec.log"; TR="$IB/trace"; : > "$TR"
/usr/bin/perl -MFcntl=:flock -e 'open(my $f,">>",$ARGV[0]) or die; flock($f,LOCK_EX) or die; print "held\n"; $|=1; select(undef,undef,undef,0.5)' "$L8.flock" > "$IB/hold2.out" & HP=$!
waitfor "$IB/hold2.out" held
for k in 1 2 3 4 5 6; do aoi AO_INBOX_TRACE="$TR" -- inbox-send --raw "$L8" "rec-$k" > /dev/null 2>&1 & done
wait "$HP"; wait
ov=$(awk '$1=="in"{d++; if(d>m)m=d} $1=="out"{d--} END{print m+0}' "$TR")
[ "$(wc -l < "$L8" | tr -d ' ')" = 6 ] && [ "$ov" = 1 ] && [ "$(grep -c '^in' "$TR")" = 6 ] \
  && ok inbox-lock-two-recoverers "소유자 해제 순간 기록자 6개 → 6줄·임계구역 겹침 0" || bad inbox-lock-two-recoverers "6줄·최대 동시 1" "$(wc -l < "$L8") 동시 $ov"

echo "== 받은편지함: 송신 기록·감시 판정(계획 2026-11-11 S1)"
# 새 호출은 상태 루트를 임시 폴더로, HERDR_PANE_ID는 비운다(계획 §1 시험 격리 조건)
SR="$T/state"; SI="$SR/inbox"; S1="$T/s1"; mkdir -p "$S1"
BASE2=(PATH="$FAKE:/usr/bin:/bin" HOME="$T/home" FAKE_DIR="$FD" HERDR_ENV=1
       HERDR_TAB_ID=w1:t1 HERDR_WORKSPACE_ID=w1 AO_STATE_ROOT="$SR")
run2() { local e=(); while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  OUT=$(cd "$T" && env -i "${BASE2[@]}" ${e[@]+"${e[@]}"} "$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }
ao2() { run2 -- bash "$BIN" "$@"; }
aoi2() { (cd "$T" && exec env -i "${BASE2[@]}" bash "$BIN" "$@"); }
lst() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'; }
# 가짜 대기자: fakew <log> <sid> <표식 토큰> <wait/pid 토큰> → FWP = sleep pid
fakew() { sleep 30 & FWP=$!; local ls; ls=$(lst "$FWP"); mkdir -p "$1.waiters" "$SI/wait"
  echo "$FWP $ls $3" > "$1.waiters/$2"; echo "$FWP $ls $4" > "$SI/wait/$2.pid"; }
killw() { kill -9 "$FWP" 2>/dev/null; wait "$FWP" 2>/dev/null; }
LT="$S1/t.log"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do aoi2 inbox-send --raw "$LT" "t$i" >/dev/null 2>&1 & done
wait
tn=$(wc -l < "$LT.times" | tr -d ' '); tu=$(cut -f1 "$LT.times" | sort -n | uniq | tr '\n' ' ')
tf=$(awk -F'\t' 'NF == 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/' "$LT.times" | wc -l | tr -d ' ')
[ "$tn" = 20 ] && [ "$tf" = 20 ] && [ "$tu" = "$(seq 1 20 | tr '\n' ' ')" ] \
  && ok inbox-send-times "동시 20개 → times n 1~20·중복 0·형식 <n>\\t<epoch>" || bad inbox-send-times "20행 1~20" "행 $tn 형식 $tf n=$tu"
LW="$S1/wt.log"
fakew "$LW" sw1 tokA tokA
ao2 inbox-send "$LW" "대기자만"; r1="$RC/$OUT"
killw
ao2 inbox-send "$LW" "대기자 KILL 뒤"; r2="$RC/$OUT"
[ "$r1" = 0/watched ] && [ "$r2" = 0/unwatched ] && ok inbox-send-waiter-watched "대기자만 → watched, KILL 뒤 → unwatched" || bad inbox-send-waiter-watched "0/watched 0/unwatched" "$r1 $r2 err=$ERR"
LS="$S1/sup.log"
fakew "$LS" sw2 tokA tokB
ao2 inbox-send "$LS" "밀려난 표식"; chk inbox-send-superseded-unwatched 0 unwatched
killw
LM="$S1/st.log"
fakew "$LM" sw3 tokC tokC
ao2 inbox-watch --state "$LM"; chk inbox-watch-state-waiter 0 waiter
fk1=0; [ ! -e "$LM.watch" ] && fk1=1
wstart "$S1/m.out" "$LM" AO_STATE_ROOT="$SR"; waitfor "$LM.watch" " "
ao2 inbox-watch --state "$LM"; chk inbox-watch-state-monitor 0 monitor
# 옛 판 파서(기존 160행 식)로 .watch 를 읽어 watched 인지
mark=$(head -1 "$LM.watch"); mpid=${mark%% *}; mrest=${mark#* }; mls=${mrest% *}
fk2=0; [[ $mpid =~ ^[0-9]+$ ]] && [ "$mrest" != "$mark" ] && [ -n "$mls" ] && [ "$(lst "$mpid")" = "$mls" ] && fk2=1
wstop; killw
ao2 inbox-send "$LM" "둘 다 끝"; fk3=$OUT
[ "$fk1/$fk2/$fk3" = 1/1/unwatched ] && ok inbox-watch-format-kept "대기자 중 .watch 없음·Monitor 표식은 옛 파서로 watched·둘 다 끝나면 unwatched" || bad inbox-watch-format-kept "1/1/unwatched" "$fk1/$fk2/$fk3"
ao2 inbox-watch --state "$LM"; chk inbox-watch-state-none 0 none
LF="$S1/mf.log"; mkdir -p "$LF.times"
ao2 inbox-send "$LF" "times 불가"
[ "$RC" = 0 ] && [ "$OUT" = unwatched ] && [ "$(wc -l < "$LF" | tr -d ' ')" = 1 ] && printf '%s' "$ERR" | grep -qF '부가 기록 실패(times)' \
  && ok inbox-send-meta-fail-times "times 쓰기 불가 → 0·줄 1개·경고" || bad inbox-send-meta-fail-times "0·1줄·경고(times)" "rc=$RC out=$OUT 줄 $(wc -l < "$LF") err=$ERR"
mkdir -p "$T/state2/inbox/events.log"
run2 AO_STATE_ROOT="$T/state2" -- bash "$BIN" inbox-send "$S1/me.log" "events 불가"
[ "$RC" = 0 ] && [ "$(wc -l < "$S1/me.log" | tr -d ' ')" = 1 ] && printf '%s' "$ERR" | grep -qF '부가 기록 실패(events)' \
  && ok inbox-send-meta-fail-events "events.log 쓰기 불가 → 0·경고" || bad inbox-send-meta-fail-events "0·경고(events)" "rc=$RC err=$ERR"
RO2="$S1/ro"; mkdir -p "$RO2"; chmod 555 "$RO2"
ao2 inbox-send "$RO2/x.log" "기록 불가"; c=$RC
chmod 755 "$RO2"
[ "$c" = 4 ] && [ ! -e "$RO2/x.log" ] && ok inbox-send-append-fail "받은편지함 쓰기 불가 → 4·기록 0" || bad inbox-send-append-fail "4·파일 없음" "rc=$c $(ls "$RO2")"
LA="$S1/ack.log"; for i in 1 2 3 4 5 6; do echo "a$i" >> "$LA"; done; echo 2 > "$LA.cursor"
run2 AO_INBOX_NOW=1700000000 -- bash "$BIN" inbox-watch --ack "$LA" 5; a1="$RC"
run2 AO_INBOX_NOW=1700000001 -- bash "$BIN" inbox-watch --ack "$LA" 4; a2="$RC"
[ "$a1$a2" = 00 ] && [ "$(cat "$LA.ackts")" = "$(printf '3\t5\t1700000000')" ] && [ "$(cat "$LA.cursor")" = 5 ] \
  && ok inbox-ack-ts "cursor 2 → ack 5 = 3\\t5\\t<epoch>, 작은 ack 4 는 행 없음" || bad inbox-ack-ts "3⇥5⇥1700000000 한 행" "rc $a1$a2 $(cat "$LA.ackts" 2>&1)"
UQ="body-uniq-$$-Zq9"
ao2 inbox-send "$S1/nb.log" "$UQ 원문"
EV="$SI/events.log"
grep -qF "$UQ" "$EV" && bad inbox-ev-no-body "원문 없음" "$(grep -F "$UQ" "$EV")" || ok inbox-ev-no-body "보낸 원문이 events.log 에 없음"
evn=$(wc -l < "$EV" | tr -d ' ')
evg=$(LC_ALL=C awk -F'\t' '$1 ~ /^ts=[0-9]+$/ && $2 ~ /^ev=(send|ack)$/ && $3 ~ /^box=./ && length($0) <= 511' "$EV" | wc -l | tr -d ' ')
[ "$evn" -gt 0 ] && [ "$evn" = "$evg" ] && grep -q $'\tev=ack\t' "$EV" && ok inbox-ev-schema "모든 줄 ts=·ev=·box= 로 시작, ev ∈ {send, ack} (${evn}줄)" || bad inbox-ev-schema "전부 형식 맞음" "$evg/$evn $(head -3 "$EV")"
ao2 inbox-send w1:p7 "루트 대상"
[ "$RC" = 0 ] && [ -f "$SI/pane-w1_p7.log" ] && [ ! -e "$T/home/.local/state/agent-orchestrator/inbox/pane-w1_p7.log" ] && grep -q $'\tbox=pane-w1_p7\t' "$EV" \
  && ok inbox-state-root "AO_STATE_ROOT → \$T/state/inbox/pane-w1_p7.log·box=pane-w1_p7" || bad inbox-state-root "$SI/pane-w1_p7.log" "rc=$RC $(ls "$SI")"

echo "== 받은편지함: 구독·대기자(계획 2026-11-11 S1 B1)"
W="$T/w"; mkdir -p "$W"; SB="$T/sb"; mkdir -p "$SB"
SA=aaaaaaaa-0001; SB1=bbbbbbbb-0002; SC=cccccccc-0003
# wfor <파일> <패턴> [초=5] — 고정 문자열이 나타날 때까지
wfor() { local i=0 n=$(( ${3:-5} * 20 )); while [ $i -lt $n ]; do grep -qF -- "$2" "$1" 2>/dev/null && return 0; sleep 0.05; i=$((i + 1)); done; return 1; }
# 대기자 띄우기: wl <이름> <sid> <hook> [VAR=값 …] → WP(pid). 결과 $W/<이름>.err, 표식 $W/<이름>.mk
#   기본 POLL 0.2·MAX 5, registered:0 정지로 등록 완료를 표식 파일에 남긴다(PAUSE를 주면 그 뒤에 덧붙음)
wl() { local n=$1 s=$2 h=$3 pz="registered:0"; shift 3
  local e=(); for a in "$@"; do case "$a" in AO_INBOX_TEST_PAUSE=*) pz="$pz,${a#*=}" ;; *) e+=("$a") ;; esac; done
  printf '{"session_id":"%s","hook_event_name":"%s","transcript_path":"%s"}' "$s" "$h" "$W/$n.tr" > "$W/$n.json"
  rm -f "$W/$n.mk" "$W/$n.mk.go"
  (cd "$T" && exec env -i "${BASE2[@]}" AO_INBOX_WAIT_POLL=0.2 AO_INBOX_WAIT_MAX=5 AO_INBOX_TEST_PAUSE="$pz" \
     AO_INBOX_TEST_PAUSE_MARK="$W/$n.mk" ${e[@]+"${e[@]}"} bash "$BIN" inbox-wait < "$W/$n.json" 2> "$W/$n.err") &
  WP=$!; eval "WP_$n=\$WP"; }
# wrc <이름> → 그 대기자의 종료 코드(끝날 때까지 기다림)
wrc() { local p; eval "p=\${WP_$1:-}"; wait "$p" 2>/dev/null; WRC=$?; }
wgo() { : > "$W/$1.mk.go"; }
# sub <sid> <대상> [옵션…] — sid 키 구독
sub() { local s=$1; shift; run2 CLAUDE_CODE_SESSION_ID="$s" -- bash "$BIN" inbox-subscribe "$@"; }
snd() { aoi2 inbox-send --raw "$1" "$2" > /dev/null 2>&1; }
evw() { grep -F $'\tev=wait-end\t' "$SI/events.log" | grep -F "tok=$(wtok "$1")" | sed 's/.*why=//' | tail -1; }
# 대기자 토큰: wait-start 사건에서 그 pid의 토큰
wtok() { local p; eval "p=\${WP_$1:-}"; grep -F $'\tev=wait-start\t' "$SI/events.log" | grep -oE "tok=w$p-[^	]+" | tail -1 | cut -c5-; }
alive() { kill -0 "$1" 2>/dev/null; }
# fd 8 수신 잠금을 바깥에서 쥔다: hold8 <초> → HP8
hold8() { mkdir -p "$SI"; /usr/bin/perl -MFcntl=:flock -e 'open(F, ">>", $ARGV[0]) or exit 4; flock(F, LOCK_EX); print "held\n"; $|=1; sleep $ARGV[1]' "$SI/recv.flock" "$1" > "$W/hold8.out" & HP8=$!; wfor "$W/hold8.out" held; }
lockfree8() { /usr/bin/perl -MFcntl=:flock -e 'open(F, ">>", $ARGV[0]) or exit 4; exit(flock(F, LOCK_EX | LOCK_NB) ? 0 : 1)' "$SI/recv.flock"; }
LS1="$SB/a.log"
sub $SA "$LS1"; r1="$RC/$OUT"
[ "$r1" = 0/ ] && [ "$(cat "$SI/subs/sid-$SA")" = "$LS1	$SA" ] && [ -f "$LS1" ] \
  && ok inbox-sub-add "등록 0·빈 출력·subs/sid-<sid> 한 줄·받은편지함 생성" || bad inbox-sub-add "0/·한 줄" "$r1 $(cat "$SI/subs/sid-$SA" 2>&1)"
sub $SA "$LS1"
[ "$RC" = 0 ] && [ "$(wc -l < "$SI/subs/sid-$SA" | tr -d ' ')" = 1 ] && [ "$(cat "$SI/subs/sid-$SA.gen")" = 1 ] \
  && ok inbox-sub-dup "같은 등록 두 번 → 줄 1개·세대 그대로 1" || bad inbox-sub-dup "1줄·gen 1" "rc=$RC $(cat "$SI/subs/sid-$SA.gen")"
sub $SA "$SB/p.log" --pane w1:p3
[ "$RC" = 0 ] && [ "$(cat "$SI/subs/pane-w1_p3")" = "$SB/p.log	$SA" ] \
  && ok inbox-sub-pane-key "--pane w1:p3 → 키 pane-w1_p3" || bad inbox-sub-pane-key "pane-w1_p3" "rc=$RC $(ls "$SI/subs")"
run2 -- bash "$BIN" inbox-subscribe "$SB/k.log"
[ "$RC" = 2 ] && printf '%s' "$ERR" | grep -qF '구독 키 없음' && ok inbox-sub-no-key "키·sid 없음 → 2 구독 키 없음" || bad inbox-sub-no-key "2·구독 키 없음" "rc=$RC err=$ERR"
sub $SA "rel/x.log"; b1=$RC; sub $SA "/a/../b.log"; b2=$RC
[ "$b1$b2" = 22 ] && ok inbox-sub-bad-target "상대 경로·.. 대상 → 2" || bad inbox-sub-bad-target "2 2" "$b1 $b2"
sub $SA --list
[ "$RC" = 0 ] && [ "$OUT" = "$LS1	$SA	active" ] && ok inbox-sub-list "--list → <경로>⇥<sid>⇥active" || bad inbox-sub-list "$LS1⇥$SA⇥active" "rc=$RC $OUT"
grep -qxF "$LS1" "$SI/known.list" && ok inbox-sub-known "등록 경로가 known.list 에 있음" || bad inbox-sub-known "있음" "$(cat "$SI/known.list" 2>&1)"
LG="$SB/g.log"; sub $SC "$LG"; g1=$(cat "$SI/subs/sid-$SC.gen")
sub $SC "$LG" --unsubscribe; g2=$(cat "$SI/subs/sid-$SC.gen"); ge=0; [ -e "$SI/subs/sid-$SC" ] || ge=1
sub $SC "$LG"; g3=$(cat "$SI/subs/sid-$SC.gen")
sub $SC "$SB/none.log" --unsubscribe; g4="$RC/$(cat "$SI/subs/sid-$SC.gen")"
[ "$g1$g2$g3/$ge/$g4" = "123/1/0/3" ] && ok inbox-sub-gen "등록·해제마다 .gen +1(1→2→3), 빈 구독 파일 삭제, 없는 줄 해제 0·세대 그대로" || bad inbox-sub-gen "123/1/0/3" "$g1$g2$g3/$ge/$g4"
sub $SC "$LG" --unsubscribe
LCL="$SB/c.log"; printf 'x1\nx2\n' > "$LCL"; echo $SA > "$LCL.owner"
sub $SB1 "$LCL"
[ "$(cat "$LCL.owner")" = $SB1 ] && [ "$(cat "$LCL.held")" = "1 2" ] && ok inbox-sub-claim "subscribe 만으로 owner A→B·held 1 2" || bad inbox-sub-claim "owner B·held 1 2" "$(cat "$LCL.owner") $(cat "$LCL.held" 2>&1)"
LMV="$SB/mv.log"; sub $SA "$LMV"; sub $SB1 "$LMV"
! grep -qF "$LMV" "$SI/subs/sid-$SA" && grep -qF "$LMV	$SB1" "$SI/subs/sid-$SB1" && grep -qF $'op=move' "$SI/events.log" \
  && ok inbox-sub-move "owner A→B → sid-A 에서 빠지고 sid-B 에 있음·move 사건" || bad inbox-sub-move "이동" "$(cat "$SI/subs/sid-$SA") / $(cat "$SI/subs/sid-$SB1")"
sub $SB1 "$LMV" --unsubscribe; sub $SB1 "$LCL" --unsubscribe; sub $SA "$LS1" --unsubscribe
# 케이스마다 새 sid(notified 행이 케이스 사이에 섞이지 않게): ns → NS
SIDN=0; ns() { SIDN=$((SIDN + 1)); NS=$(printf 'dd%06d-0000' "$SIDN"); }
# 깨움 출력의 번호 줄 수
nlines() { grep -cE '^#[0-9]+ ' "$1"; }
ns; wl nt "$NS" Stop; wrc nt; c=$WRC
[ "$c" = 0 ] && [ ! -s "$W/nt.err" ] && grep -qF "sid=$NS"$'\t' "$SI/events.log" && ok inbox-wait-no-target "대상 없음 → 0·stderr 빈 출력·wait-end 사건" || bad inbox-wait-no-target "0·빈 stderr" "rc=$c $(cat "$W/nt.err")"
printf '{"hook_event_name":"Stop"}' > "$W/ns.json"
(cd "$T" && env -i "${BASE2[@]}" bash "$BIN" inbox-wait < "$W/ns.json" > "$W/ns.out" 2> "$W/ns.err"); c=$?
[ "$c" = 0 ] && [ ! -s "$W/ns.err" ] && [ ! -s "$W/ns.out" ] && ok inbox-wait-no-sid "session_id 없음 → 0·빈 출력" || bad inbox-wait-no-sid "0" "rc=$c $(cat "$W/ns.err")"
echo 'not json {' > "$W/bj.json"
(cd "$T" && env -i "${BASE2[@]}" bash "$BIN" inbox-wait < "$W/bj.json" 2> "$W/bj.err"); c=$?
(cd "$T" && env -i "${BASE2[@]}" bash "$BIN" inbox-wait --bogus < /dev/null 2> "$W/bj2.err"); c2=$?
[ "$c$c2" = 44 ] && [ ! -s "$W/bj.err" ] && [ ! -s "$W/bj2.err" ] && grep -qF 'why=error:json' "$SI/events.log" \
  && ok inbox-wait-bad-json "JSON 해석 실패·알 수 없는 인자 → 4·stderr 빈 출력·why=error:json" || bad inbox-wait-bad-json "4 4" "$c $c2 $(cat "$W/bj.err" "$W/bj2.err")"
ao2 inbox-wait --status; chk inbox-wait-status 0 "inbox-wait 2"
ns; LW1="$SB/w1.log"; sub "$NS" "$LW1"; wl wk "$NS" Stop; wfor "$W/wk.mk" registered
snd "$LW1" "깨움 하나"; wrc wk; c=$WRC
[ "$c" = 2 ] && grep -qF 'token=' "$W/wk.err" && grep -qF '#1 깨움 하나' "$W/wk.err" && grep -qF -- '--ack' "$W/wk.err" \
  && ok inbox-wait-wake "대기 중 send 1줄 → 2·token=·#1·--ack" || bad inbox-wait-wake "2" "rc=$c $(cat "$W/wk.err")"
[ "$(cat "$LW1.cursor" 2>/dev/null || echo none)" = none ] && ok inbox-wait-cursor-untouched "깨움 뒤 .cursor 그대로(없음)" || bad inbox-wait-cursor-untouched "없음" "$(cat "$LW1.cursor")"
ns; LW2="$SB/w2a.log"; LW3="$SB/w2b.log"; sub "$NS" "$LW2"; sub "$NS" "$LW3"; wl w2 "$NS" Stop; wfor "$W/w2.mk" registered
snd "$LW2" "a"; snd "$LW3" "b"; sleep 0.1; wrc w2; c=$WRC
hb=$(grep -c '^== ' "$W/w2.err")
if [ "$hb" = 1 ]; then ns; sub "$NS" "$LW2"; sub "$NS" "$LW3"; wl w2 "$NS" Stop; wrc w2; c=$WRC; hb=$(grep -c '^== ' "$W/w2.err"); fi
[ "$c" = 2 ] && [ "$hb" = 2 ] && ok inbox-wait-wake-two "두 받은편지함 → 한 번 깨움에 == 머리 둘" || bad inbox-wait-wake-two "2·머리 2" "rc=$c 머리 $hb"
ns; LP="$SB/pn.log"; snd "$LP" "미리 온 줄"; sub "$NS" "$LP"
t0=$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%d", time*1000'); wl pn "$NS" Stop; wrc pn; c=$WRC
dt=$(( $(/usr/bin/perl -MTime::HiRes=time -e 'printf "%d", time*1000') - t0 ))
[ "$c" = 2 ] && [ "$dt" -lt 500 ] && ok inbox-wait-pending-now "시작 전 미처리 → ${dt}ms 에 2" || bad inbox-wait-pending-now "0.5초 안 2" "rc=$c ${dt}ms"
ns; LC2="$SB/cap.log"; for i in $(seq 1 25); do echo "c$i" >> "$LC2"; done; sub "$NS" "$LC2"; wl cp "$NS" Stop; wrc cp; c=$WRC
[ "$c" = 2 ] && [ "$(nlines "$W/cp.err")" = 20 ] && grep -qF '… 나머지 5줄은' "$W/cp.err" && grep -qF -- "--pending $LC2" "$W/cp.err" \
  && ok inbox-wait-cap-20 "25줄 → 번호 줄 20·나머지 5줄 안내" || bad inbox-wait-cap-20 "20·나머지 5" "rc=$c $(nlines "$W/cp.err")"
ns; LL="$SB/long.log"; long=$(printf '가%.0s' $(seq 1 600)); echo "$long" > "$LL"; sub "$NS" "$LL"; wl ln "$NS" Stop; wrc ln; c=$WRC
lg=$(grep '^#1 ' "$W/ln.err" | sed 's/^#1 //; s/ …(잘림 — --pending으로 전문)$//' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
[ "$c" = 2 ] && grep -qF '…(잘림 — --pending으로 전문)' "$W/ln.err" && [ "$lg" = 501 ] && ok inbox-wait-line-500 "600자 줄 → 앞 500자 + 잘림 안내" || bad inbox-wait-line-500 "500자" "rc=$c len=$lg"
# pane 수신자 만들기(B2의 --session-start 대신): pgset <pane 키> <gen> <sid> [issued gen]
pgset() { mkdir -p "$SI/pane-gen" "$SI/wait"; printf '%s\t%s\n' "$2" "$3" > "$SI/pane-gen/$1"; printf '%s\t%s\n' "$1" "${4:-$2}" > "$SI/wait/$3.issued"; }
ns; LCF="$SB/cf.log"; printf 'o1\no2\n' > "$LCF"; echo $SA > "$LCF.owner"; mkdir -p "$SI/subs"; printf '%s\t%s\n' "$LCF" "$NS" > "$SI/subs/sid-$NS"
wl cf "$NS" Stop; wrc cf; c=$WRC
[ "$c" = 2 ] && sed -n 3p "$W/cf.err" | grep -qF '#0 [이전 세션' && [ "$(cat "$LCF.owner")" = "$NS" ] \
  && ok inbox-wait-claim-first "owner A 미처리 2줄 → B 대기자의 첫 줄이 #0 [이전 세션" || bad inbox-wait-claim-first "#0 첫 줄" "rc=$c $(cat "$W/cf.err")"
ns; PL="$SI/pane-w9_p1.log"; printf 'p1\np2\n' > "$PL"; echo $SA > "$PL.owner"; pgset pane-w9_p1 2 "$NS"
wl cl "$NS" Stop HERDR_PANE_ID=w9:p1; wrc cl; c=$WRC
un=$(grep -E '^#[1-9][0-9]* ' "$W/cl.err" | grep -vcF '[이전 세션]')
[ "$c" = 2 ] && grep -qF '#1 [이전 세션] p1' "$W/cl.err" && [ "$un" = 0 ] && ok inbox-wait-clear-pane "같은 pane A 미처리 → B Stop 대기자 [이전 세션]·표시 없는 #n 0" || bad inbox-wait-clear-pane "[이전 세션]만" "rc=$c un=$un $(cat "$W/cl.err")"
rm -rf "$PL.waiters"; rm -f "$PL"*
ns; LTN="$SB/tn.log"; sub "$NS" "$LTN"; wl t1 "$NS" Stop AO_INBOX_TEST_PAUSE=notify-locked:4; wfor "$W/t1.mk" registered
snd "$LTN" "확정 중"; wfor "$W/t1.mk" notify-locked
wl t2 "$NS" Stop; sleep 0.6; e1=0; grep -qF registered "$W/t2.mk" 2>/dev/null && e1=1; alive "$WP_t1" || e1=2
wgo t1; wrc t1; c1=$WRC; wfor "$W/t2.mk" registered; e2=$?; wrc t2
[ "$e1/$c1/$e2" = 0/2/0 ] && grep -qF '#1 확정 중' "$W/t1.err" && ok inbox-wait-term-in-notify "W1 notify-locked 중 W2는 fd 8 대기·W1 exit 2·그 뒤 W2 등록" || bad inbox-wait-term-in-notify "0/2/0" "$e1/$c1/$e2"
ns; LTB="$SB/tb.log"; sub "$NS" "$LTB"; wl b1 "$NS" Stop AO_INBOX_TEST_PAUSE=poll:4; wfor "$W/b1.mk" poll
wl b2 "$NS" Stop; wrc b1; c1=$WRC; wfor "$W/b2.mk" registered
nf=0; [ -e "$SI/wait/$NS.notified" ] && nf=1
snd "$LTB" "새 줄"; wrc b2; c2=$WRC
[ "$c1/$nf/$c2" = 0/0/2 ] && [ "$(evw b1)" = superseded ] && grep -qF '#1 새 줄' "$W/b2.err" \
  && ok inbox-wait-term-before-notify "W1 poll 중 W2 교체 → W1 0(superseded)·notified 변화 0·새 줄은 W2" || bad inbox-wait-term-before-notify "0/0/2 superseded" "$c1/$nf/$c2 $(evw b1)"
ns; LRN="$SB/rn.log"; sub "$NS" "$LRN"; snd "$LRN" "재통지 대상"
rs=""; for k in 1 2 3 4; do wl r$k "$NS" Stop; wrc r$k; rs="$rs$WRC"; done
wl r5 "$NS" Stop AO_INBOX_WAIT_MAX=1; wrc r5; rs="$rs$WRC"
[ "$rs" = 22220 ] && ! grep -qF '[재통지]' "$W/r1.err" && grep -qF '#1 [재통지] 재통지 대상' "$W/r2.err" && grep -qF '[재통지]' "$W/r4.err" \
  && ok inbox-wait-undelivered-renotify "token 없음 → 다음 대기자 [재통지]·3회 뒤 멈춤(22220)" || bad inbox-wait-undelivered-renotify 22220 "$rs"
ns; LDQ="$SB/dq.log"; sub "$NS" "$LDQ"; snd "$LDQ" "전달됨"; wl d1 "$NS" Stop; wrc d1
tk=$(grep -oE 'token=[^ ]+' "$W/d1.err" | head -1); echo "{\"x\":\"$tk\"}" > "$W/d2.tr"
wl d2 "$NS" Stop AO_INBOX_WAIT_MAX=1; wrc d2; c=$WRC
[ "$c" = 0 ] && grep -F $'\tev=wait-delivered\t' "$SI/events.log" | grep -qF "sid=$NS" && grep -qF $'\tdelivered\t' "$SI/wait/$NS.notified" \
  && ok inbox-wait-delivered-quiet "transcript에 token → 깨움 0·wait-delivered 사건" || bad inbox-wait-delivered-quiet "0·delivered" "rc=$c $(cat "$SI/wait/$NS.notified")"
ns; LHN="$SB/hn.log"; printf 'h1\n' > "$LHN"; echo $SA > "$LHN.owner"; sub "$NS" "$LHN"
wl h1 "$NS" Stop; wrc h1; tk=$(grep -oE 'token=[^ ]+' "$W/h1.err" | head -1); echo "$tk" > "$W/h2.tr"
wl h2 "$NS" Stop AO_INBOX_WAIT_MAX=1; wrc h2; ha="$(grep -c '\[이전 세션\]' "$W/h1.err")/$WRC"
ns; printf '%s\t%s\n' "$LHN" "$NS" > "$SI/subs/sid-$NS"; hs=""
for k in 3 4 5 6; do wl h$k "$NS" Stop; wrc h$k; hs="$hs$WRC"; done
wl h7 "$NS" Stop AO_INBOX_WAIT_MAX=1; wrc h7; hs="$hs$WRC"
[ "$ha" = 1/0 ] && [ "$hs" = 22220 ] && ok inbox-wait-held-no-loop "[이전 세션] 줄: 전달 확인 뒤 깨움 0, 확인 없으면 최대 3회 재통지" || bad inbox-wait-held-no-loop "1/0 22220" "$ha $hs"
ns; LC3="$SB/c3.log"; sub "$NS" "$LC3"
for k in 1 2 3; do wl k$k "$NS" Stop AO_INBOX_TEST_PAUSE=pre-register:0.3; done
ci=0; while [ $ci -lt 100 ] && [ "$(grep -F "sid=$NS" "$SI/events.log" | grep -cF why=superseded)" -lt 2 ]; do sleep 0.05; ci=$((ci + 1)); done; sleep 0.2
live=0; for k in 1 2 3; do eval "p=\$WP_k$k"; alive "$p" && live=$((live + 1)); done
snd "$LC3" "셋 중 하나"; cs=""; for k in 1 2 3; do wrc k$k; cs="$cs$WRC"; done
ws=$(for k in 1 2 3; do evw k$k; done | sort | tr '\n' ' ')
[ "$live" = 1 ] && [ "$(printf '%s' "$cs" | tr -cd 2 | wc -c | tr -d ' ')" = 1 ] && [ "$(printf '%s' "$cs" | tr -d 02)" = "" ] && [ "$ws" = "notify superseded superseded " ] \
  && ok inbox-wait-concurrent-3 "겹친 시작 3개 → 생존 1·통지 1·나머지 superseded·잠금 4 없음" || bad inbox-wait-concurrent-3 "생존 1 notify+superseded×2" "생존 $live rc $cs why $ws"
ns; LPR="$SB/pr.log"; sub "$NS" "$LPR"; sleep 30 & SP=$!; mkdir -p "$SI/wait"; echo "$SP Mon Jan 1 00:00:00 2001 tokX" > "$SI/wait/$NS.pid"
wl pr "$NS" Stop; wfor "$W/pr.mk" registered; sleep 0.3; snd "$LPR" "끝"; wrc pr
alive "$SP" && ok inbox-wait-pid-reuse "pid 파일의 살아 있는 무관 pid·다른 lstart → TERM 안 보냄" || bad inbox-wait-pid-reuse "생존" "죽음"
kill -9 "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
ns; NO=$NS; ns; LOS="$SB/os.log"; sub "$NO" "$LOS"; sub "$NS" "$SB/os2.log"
wl o1 "$NO" Stop; wfor "$W/o1.mk" registered; wl o2 "$NS" Stop; wfor "$W/o2.mk" registered; sleep 0.3
alive "$WP_o1" && r=ok || r=dead; snd "$LOS" "o"; wrc o1; c1=$WRC; snd "$SB/os2.log" "o"; wrc o2
[ "$r/$c1" = ok/2 ] && ok inbox-wait-other-sid "다른 sid 대기자는 TERM 받지 않음(그 뒤 자기 줄로 2)" || bad inbox-wait-other-sid "ok/2" "$r/$c1"
ns; LTO="$SB/to.log"; sub "$NS" "$LTO"; wl to "$NS" Stop AO_INBOX_WAIT_MAX=1; wrc to; c=$WRC
[ "$c" = 0 ] && [ "$(evw to)" = timeout ] && [ ! -e "$LTO.waiters/$NS" ] && [ ! -e "$SI/wait/$NS.pid" ] && [ ! -s "$W/to.err" ] \
  && ok inbox-wait-timeout "시간 제한 → 0·why=timeout·표식·pid 정리" || bad inbox-wait-timeout "0 timeout" "rc=$c $(evw to) $(ls "$LTO.waiters")"
ns; LTM="$SB/tm.log"; sub "$NS" "$LTM"; wl tm "$NS" Stop; wfor "$W/tm.mk" registered
echo "1 x othertok" > "$LTM.waiters/$NS"; kill -TERM "$WP_tm"; wrc tm; c=$WRC
[ "$c" = 0 ] && [ "$(evw tm)" = term ] && [ "$(cat "$LTM.waiters/$NS")" = "1 x othertok" ] \
  && ok inbox-wait-term-mark "TERM → 0·why=term·남의 토큰 표식은 지우지 않음" || bad inbox-wait-term-mark "0 term·표식 유지" "rc=$c $(evw tm) $(cat "$LTM.waiters/$NS" 2>&1)"
ns; LF9="$SB/f9.log"; sub "$NS" "$LF9"; wl f9 "$NS" Stop AO_INBOX_TEST_PAUSE=poll:3; wfor "$W/f9.mk" poll
: > "$W/f9.rc"; for k in 1 2 3 4 5; do (aoi2 inbox-send --raw "$LF9" "f$k" > /dev/null 2>&1; echo $? >> "$W/f9.rc") & done; wait $(jobs -p | grep -v "^$WP_f9$") 2>/dev/null
wgo f9; wrc f9
[ "$(sort -u "$W/f9.rc" | tr -d '\n')" = 0 ] && [ "$(wc -l < "$W/f9.rc" | tr -d ' ')" = 5 ] && [ "$(wc -l < "$LF9" | tr -d ' ')" = 5 ] \
  && ok inbox-wait-fd9-free "대기 중 동시 send 5개 → 모두 0·5줄" || bad inbox-wait-fd9-free "0×5" "$(cat "$W/f9.rc" | tr '\n' ' ')"
ns; LLG="$SB/lg.log"; sub "$NS" "$LLG"; wl lg "$NS" Stop AO_INBOX_TEST_PAUSE=poll:4; wfor "$W/lg.mk" poll; snd "$LLG" "늦게 발견"; wrc lg
nl=$(grep -F $'\tev=wait-notify\t' "$SI/events.log" | grep -F "sid=$NS" | tail -1)
nts=$(printf '%s' "$nl" | sed -E 's/^ts=([0-9]+).*/\1/'); narr=$(printf '%s' "$nl" | sed -E 's/.*arr=([0-9]+).*/\1/')
[ -n "$nl" ] && [ $((nts - narr)) -ge 3 ] && ok inbox-ev-lag-arrival "poll 4초 정지 → wait-notify.ts − arr = $((nts - narr))(도착 기준)" || bad inbox-ev-lag-arrival "≥ 3" "$nl"
ns; LDB="$SB/db.log"; sub "$NS" "$LDB"; wl db "$NS" Stop AO_INBOX_TEST_PAUSE=notify-locked:3; wfor "$W/db.mk" registered
snd "$LDB" "장벽 전"; wfor "$W/db.mk" notify-locked
(run2 CLAUDE_CODE_SESSION_ID="$NS" -- bash "$BIN" inbox-subscribe --unsubscribe "$LDB"; echo "$RC" > "$W/db.un") & UP=$!
sleep 0.6; early=0; [ -s "$W/db.un" ] && early=1
wgo db; wrc db; c1=$WRC; wait "$UP"; u=$(cat "$W/db.un")
snd "$LDB" "장벽 뒤"; wl db2 "$NS" Stop AO_INBOX_WAIT_MAX=1; wrc db2; c2=$WRC
[ "$early/$c1/$u/$c2" = 0/2/0/0 ] && ! grep -qF '장벽 뒤' "$W/db2.err" && ok inbox-sub-del-barrier "notify-locked 중 해제는 대기·대기자 2 뒤 0·해제 뒤 줄은 후속 대기자 통지 0" || bad inbox-sub-del-barrier "0/2/0/0" "$early/$c1/$u/$c2"
ns; LDR="$SB/dr.log"; sub "$NS" "$LDR"; wl dr "$NS" Stop; wfor "$W/dr.mk" registered; sleep 0.3
sub "$NS" "$LDR" --unsubscribe; t0=$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%d", time*1000'); wrc dr; c=$WRC
dt=$(( $(/usr/bin/perl -MTime::HiRes=time -e 'printf "%d", time*1000') - t0 )); snd "$LDR" "해제 뒤"
[ "$c" = 0 ] && [ "$(evw dr)" = unsubscribed ] && [ "$dt" -lt 600 ] && [ ! -s "$W/dr.err" ] && ok inbox-sub-del-running "폴링 중 해제 → ${dt}ms 에 0(unsubscribed)·통지 0" || bad inbox-sub-del-running "0 unsubscribed 1폴링 안" "rc=$c $(evw dr) ${dt}ms"
ns; HA=$NS; ns; HB=$NS; LHO="$SB/ho.log"; sub "$HA" "$LHO"; wl ha "$HA" Stop; wfor "$W/ha.mk" registered
sub "$HA" "$LHO" --unsubscribe; sub "$HB" "$LHO"; wl hb "$HB" Stop; wfor "$W/hb.mk" registered
snd "$LHO" "인계 뒤"; wrc hb; cb=$WRC; wrc ha; ca=$WRC
[ "$ca/$cb" = 0/2 ] && [ ! -s "$W/ha.err" ] && grep -qF '#1 인계 뒤' "$W/hb.err" && ok inbox-sub-handover "A 해제 → B 등록 → 새 줄은 B만 깨움·A 통지 0" || bad inbox-sub-handover "0/2" "$ca/$cb"
ns; LX="$SB/sx.log"; LY="$SB/sy.log"; sub "$NS" "$LX"; wl sa "$NS" Stop AO_INBOX_TEST_PAUSE=registered:3; wfor "$W/sa.mk" registered
sub "$NS" "$LX" --unsubscribe; sub "$NS" "$LY"; snd "$LX" "옛 대상"; wgo sa; sleep 0.5; snd "$LY" "새 대상"; wrc sa; c=$WRC
[ "$c" = 2 ] && ! grep -qF "== $LX" "$W/sa.err" && grep -qF "== $LY" "$W/sa.err" && ok inbox-snapshot-atomic "등록 뒤 해제+새 등록 → 옛 대상 통지 0·새 스냅샷의 대상만 알림" || bad inbox-snapshot-atomic "LY만" "rc=$c $(grep '^==' "$W/sa.err")"
ns; LCD="$SB/cd.log"; sub "$NS" "$LCD"; snd "$LCD" "ctx 줄"; printf '%s\t1\tctx\tctxtok\t0\n' "$LCD" > "$SI/wait/$NS.notified"
wl cd "$NS" Stop; wrc cd; c=$WRC
[ "$c" = 2 ] && grep -qF '#1 [재통지] ctx 줄' "$W/cd.err" && [ "$(cut -f3,5 "$SI/wait/$NS.notified")" = "pending	1" ] \
  && ok inbox-ctx-demote "ctx 행·증거 없음 → Stop 대기자가 pending(0)으로 내리고 재통지 1회" || bad inbox-ctx-demote "pending 1" "rc=$c $(cat "$SI/wait/$NS.notified")"
ns; PA=$NS; ns; PB=$NS; PK=pane-w8_p1; PLG="$SI/$PK.log"; pgset $PK 1 "$PA"
wl pa "$PA" Stop HERDR_PANE_ID=w8:p1; wfor "$W/pa.mk" registered; pgset $PK 2 "$PB"
wl pb "$PB" Stop HERDR_PANE_ID=w8:p1; wfor "$W/pb.mk" registered; sleep 0.3; snd "$PLG" "pane 새 줄"; wrc pb; cb=$WRC; wrc pa; ca=$WRC
[ "$ca/$cb" = 0/2 ] && [ "$(evw pa)" = pane-superseded ] && [ ! -s "$W/pa.err" ] && ok inbox-pane-gen-supersede "같은 pane B 발급 뒤 → B만 깨움·A pane-superseded 0" || bad inbox-pane-gen-supersede "0/2 pane-superseded" "$ca/$cb $(evw pa)"
ns; PA=$NS; ns; PB=$NS; PK=pane-w8_p2; PLG="$SI/$PK.log"; pgset $PK 1 "$PA"
wl na "$PA" Stop HERDR_PANE_ID=w8:p2; wfor "$W/na.mk" registered; hold8 3; snd "$PLG" "잠금 대기 중"; sleep 0.6
pgset $PK 2 "$PB"; kill "$HP8"; wait "$HP8" 2>/dev/null; wrc na; ca=$WRC
[ "$ca" = 0 ] && [ "$(evw na)" = pane-superseded ] && [ ! -s "$W/na.err" ] && [ ! -e "$SI/wait/$PA.notified" ] && ok inbox-pane-gen-notify-check "A 통지 잠금 대기 중 B 발급 → A recheck 실패·통지 0" || bad inbox-pane-gen-notify-check "0 pane-superseded" "rc=$ca $(evw na)"
ns; PK=pane-w8_p3; pgset $PK 5 "$NS"; before=$(cat "$SI/pane-gen/$PK")
for h in Stop StopFailure UserPromptSubmit; do wl os "$NS" $h HERDR_PANE_ID=w8:p3 AO_INBOX_WAIT_MAX=1; wrc os; done
[ "$(cat "$SI/pane-gen/$PK")" = "$before" ] && [ "$(cut -f2 "$SI/wait/$NS.issued")" = 5 ] && ok inbox-pane-gen-only-sessionstart "Stop·StopFailure·UserPromptSubmit 대기자 → pane-gen·issued 그대로" || bad inbox-pane-gen-only-sessionstart "$before" "$(cat "$SI/pane-gen/$PK")"
ns; ni=$NS; ns; PK=pane-w8_p4; pgset $PK 3 "$NS"; rm -f "$SI/wait/$ni.issued"; before=$(cat "$SI/pane-gen/$PK")
wl ni "$ni" Stop HERDR_PANE_ID=w8:p4; wrc ni; c=$WRC
[ "$c" = 0 ] && [ "$(evw ni)" = no-issue ] && [ "$(cat "$SI/pane-gen/$PK")" = "$before" ] && [ ! -s "$W/ni.err" ] && ok inbox-pane-gen-no-issue "발급 기록 없음 → 0·why=no-issue·세대 그대로" || bad inbox-pane-gen-no-issue "0 no-issue" "rc=$c $(evw ni)"
ns; LTD="$SB/td.log"; sub "$NS" "$LTD"; wl td "$NS" Stop AO_INBOX_TEST_PAUSE=notify-mid:3; wfor "$W/td.mk" registered
snd "$LTD" "직접 TERM"; wfor "$W/td.mk" notify-mid; kill -TERM "$WP_td"; sleep 0.3; wgo td; wrc td; c=$WRC; lf=0; lockfree8 && lf=1
[ "$c" = 2 ] && grep -qF '#1 직접 TERM' "$W/td.err" && grep -qF -- '--ack' "$W/td.err" && grep -qF $'\tpending\t' "$SI/wait/$NS.notified" && [ "$lf" = 1 ] \
  && ok inbox-wait-term-direct "notify-mid 중 TERM → 깨움 출력 완전·pending 행·2·수신 잠금 풀림" || bad inbox-wait-term-direct "2·pending·잠금 풀림" "rc=$c lf=$lf $(cat "$SI/wait/$NS.notified" 2>&1)"
ns; LTL="$SB/tl.log"; sub "$NS" "$LTL"; wl tl "$NS" Stop; wfor "$W/tl.mk" registered; hold8 4; snd "$LTL" "잠금 대기"; sleep 0.6
kill -TERM "$WP_tl"; wrc tl; c=$WRC; kill "$HP8"; wait "$HP8" 2>/dev/null
[ "$c" = 0 ] && [ "$(evw tl)" = term ] && [ ! -e "$LTL.waiters/$NS" ] && [ ! -e "$SI/wait/$NS.notified" ] && [ ! -s "$W/tl.err" ] \
  && ok inbox-wait-term-lockwait "수신 잠금 대기 중 TERM → 0·why=term·표식 정리·notified 변화 0" || bad inbox-wait-term-lockwait "0 term" "rc=$c $(evw tl)"
ns; LNE="$SB/ne.log"; sub "$NS" "$LNE"; snd "$LNE" "증거 없음"; wl ne1 "$NS" Stop; wrc ne1
wl ne2 "$NS" UserPromptSubmit; wrc ne2; c=$WRC
[ "$c" = 2 ] && grep -qF '[재통지]' "$W/ne2.err" && ! grep -F $'\tev=wait-delivered\t' "$SI/events.log" | grep -qF "sid=$NS" \
  && ok inbox-delivered-no-event "UserPromptSubmit 만으로 delivered 아님·재통지 대상 유지" || bad inbox-delivered-no-event "2 [재통지]" "rc=$c"
ns; LDA="$SB/da.log"; sub "$NS" "$LDA"; snd "$LDA" "ack 될 줄"; wl da1 "$NS" Stop; wrc da1
ao2 inbox-watch --ack "$LDA" 1; wl da2 "$NS" Stop AO_INBOX_WAIT_MAX=1; wrc da2; c=$WRC
[ "$c" = 0 ] && [ ! -e "$SI/wait/$NS.notified" ] && ok inbox-delivered-ack "transcript 없음 + ack → 행 삭제·깨움 0" || bad inbox-delivered-ack "0·행 없음" "rc=$c $(cat "$SI/wait/$NS.notified" 2>&1)"
ns; LOF="$SB/of.log"; sub "$NS" "$LOF"; wl of "$NS" Stop AO_INBOX_TEST_PAUSE=pre-register:3; wfor "$W/of.mk" pre-register
ao2 inbox-wait --drain; d="$RC/$OUT"; wgo of; wrc of; c=$WRC
[ "$d/$c" = 0/0/0 ] && [ "$(evw of)" = off ] && [ ! -e "$LOF.waiters/$NS" ] && ok inbox-off-before-register "pre-register 중 drain → 등록 없이 why=off 0" || bad inbox-off-before-register "0/0/0 off" "$d/$c $(evw of)"
ao2 inbox-wait --undrain
ns; LDG="$SB/dg.log"; sub "$NS" "$LDG"; wl dg "$NS" Stop AO_INBOX_TEST_PAUSE=registered:3; wfor "$W/dg.mk" registered
ao2 inbox-wait --drain; d="$RC/$OUT"; snd "$LDG" "drain 뒤"; wrc dg; c=$WRC
[ "$d/$c" = 0/1/0 ] && [ ! -s "$W/dg.err" ] && [ ! -e "$SI/wait/$NS.pid" ] && ok inbox-drain-after-register "registered 중 drain → 철회 1·대기자 0·통지 0 ($(evw dg))" || bad inbox-drain-after-register "0/1/0" "$d/$c $(evw dg)"
ao2 inbox-wait --undrain
ns; LDN="$SB/dn.log"; sub "$NS" "$LDN"; wl dn "$NS" Stop AO_INBOX_TEST_PAUSE=notify-locked:3; wfor "$W/dn.mk" registered
snd "$LDN" "통지 중"; wfor "$W/dn.mk" notify-locked
(run2 -- bash "$BIN" inbox-wait --drain; echo "$RC/$OUT" > "$W/dn.d") & DP=$!; sleep 0.6; early=0; [ -s "$W/dn.d" ] && early=1
wgo dn; wrc dn; c1=$WRC; wait "$DP"; snd "$LDN" "drain 뒤 줄"; wl dn2 "$NS" Stop AO_INBOX_WAIT_MAX=1; wrc dn2; c2=$WRC
[ "$early/$c1/$(cat "$W/dn.d")/$c2" = 0/2/0/0/0 ] && [ "$(evw dn2)" = off ] && ok inbox-drain-notify-race "notify-locked 중 drain 은 대기·통지 끝난 뒤 진행·이후 새 줄 통지 0" || bad inbox-drain-notify-race "0/2/0/0/0" "$early/$c1/$(cat "$W/dn.d")/$c2"
ao2 inbox-wait --undrain; u=$RC; ns; LUD="$SB/ud.log"; sub "$NS" "$LUD"; wl ud "$NS" Stop; wfor "$W/ud.mk" registered; snd "$LUD" "다시 켬"; wrc ud
[ "$u/$WRC" = 0/2 ] && [ ! -e "$SI/hooks.off" ] && ok inbox-undrain "--undrain 뒤 새 대기자 정상 등록·깨움" || bad inbox-undrain "0/2" "$u/$WRC"
left=0; for f in "$SI"/wait/*.pid; do [ -f "$f" ] && _p=$(awk '{print $1}' "$f") && kill -0 "$_p" 2>/dev/null && left=$((left + 1)); done
lw=$(ps -axo command | grep -F "$T" | grep -cF 'inbox-wait' )
[ "$left/$lw" = 0/0 ] || echo "WARN 남은 대기자 pid $left·프로세스 $lw"
TOTAL=$((PASS + FAIL))
echo "== 집계: PASS $PASS / FAIL $FAIL / 총 $TOTAL (기대 $EXPECT)"
[ "$TOTAL" = "$EXPECT" ] || { echo "FAIL 케이스 총계 불일치: $TOTAL ≠ $EXPECT"; exit 1; }
[ "$FAIL" = 0 ]
