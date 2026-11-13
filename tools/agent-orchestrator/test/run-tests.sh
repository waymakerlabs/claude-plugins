#!/usr/bin/env bash
# run-tests.sh — agent-orchestrator S1·S2·S3 계약 시험 (가짜 herdr, PATH 격리)
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
# 실제 상태 폴더 변경 검사(inbox-real-state-untouched)용: env -i 전에 진짜 HOME을 저장하고 기준 시각을 남긴다
REAL_HOME=$HOME; touch "$T/stamp"
REAL_EV="$REAL_HOME/.local/state/agent-orchestrator/inbox/events.log"; REAL_EV_SZ=$(wc -c < "$REAL_EV" 2>/dev/null | tr -d ' '); REAL_EV_SZ=${REAL_EV_SZ:-0}
cp "$HERE/fake-herdr.py" "$FAKE/herdr"; chmod +x "$FAKE/herdr"
EXPECT=275

PASS=0; FAIL=0
# 여러 줄 값은 ⏎로 이어 한 줄 한 케이스를 지킨다
ok()  { PASS=$((PASS + 1)); echo "$1" >> "$T/pass.names"; echo "PASS $1 — $(printf '%s' "$2" | tr '\n' '⏎')"; }
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
run AGENT_ORCHESTRATOR_MAX_RIGHT=5 -- bash "$BIN" pane-open "작업자 4" --cwd "$T"; run AGENT_ORCHESTRATOR_MAX_RIGHT=5 -- bash "$BIN" pane-open "작업자 5" --cwd "$T"; chk pane-open-fifth 0 w1:p6
run AGENT_ORCHESTRATOR_MAX_RIGHT=5 -- bash "$BIN" pane-open "작업자 6" --cwd "$T"; chk pane-open-overflow-tab 0 w1:p7
called "tab create --workspace w1 --cwd $T --label [WO] 작업 넘침 --no-focus" && ok pane-open-overflow-label "넘침 탭 '[WO] 작업 넘침'" || bad pane-open-overflow-label "tab create [WO] 작업 넘침" "$(grep 'tab create' "$FD/calls.log")"
# 넘침 탭이 이미 있고 첫 pane이 비어 있으면 그대로 쓴다
run AGENT_ORCHESTRATOR_MAX_RIGHT=5 -- bash "$BIN" pane-open "작업자 7" --cwd "$T"; chk pane-open-overflow-reuse 0 w1:p7
ao pane-open "작업자 8" --parent w1:p99 --cwd "$T"; chk pane-open-missing-parent 3
# (2026-11-13) 기본은 제한 없음: 6번째도 같은 탭 오른쪽 열(넘침 탭 없음)
reset_state; for i in 1 2 3 4 5 6; do ao pane-open "작업자 u$i" --cwd "$T"; done
[ "$RC" = 0 ] && ! grep -q 'tab create' "$FD/calls.log" && ok pane-open-unlimited "기본 제한 없음 → 6번째도 split·넘침 탭 없음" || bad pane-open-unlimited "split" "rc=$RC $(grep 'tab create' "$FD/calls.log")"
ao pane-swap w1:p2 w1:p1; [ "$RC" = 0 ] && called "pane swap --source-pane w1:p2 --target-pane w1:p1" && ok pane-swap-args "pane-swap → herdr pane swap --source-pane --target-pane" || bad pane-swap-args "swap" "rc=$RC $ERR"
ao pane-swap w1:p2; [ "$RC" = 2 ] && ok pane-swap-usage "인자 하나 → 2" || bad pane-swap-usage 2 "$RC"
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
[ "$RC" = 0 ] && called "pane rename w1:p1 [OC] 구현" && ! called "tab rename" && ok self-name-skip-tab "탭 - 건너뜀(이미 [OC] 탭은 가드도 rename 없음), pane만 --force" || bad self-name-skip-tab "pane만 rename" "rc=$RC $(grep rename "$FD/calls.log")"
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

echo "== self-name 탭 가드(탭 -·[OC] pane이면 탭 접두어 한 번 확인)"
reset_state; setlabel tab w1:t1 "Peter review"; setlabel pane w1:p1 "[OC] 이전"
ao self-name --force - "[OC] 이름 · 대기 1 (x)"
[ "$RC" = 0 ] && called "tab rename w1:t1 [OC] Peter review" && called "pane rename w1:p1 [OC] 이름 · 대기 1 (x)" && echo "$ERR" | grep -q '탭 접두어 보정: Peter review → \[OC\] Peter review' \
  && ok tab-guard-user "사용자 탭 → [OC] 접두어만·stderr 보정 한 줄" || bad tab-guard-user "[OC] Peter review" "rc=$RC $(grep rename "$FD/calls.log") err=$ERR"
reset_state; setlabel tab w1:t1 ""
ao self-name --force - "[OC] 이름 · 대기 1 (x)"
[ "$RC" = 0 ] && called "tab rename w1:t1 [OC] 이름" && ! called "tab rename w1:t1 [OC] 이름 ·" && ok tab-guard-empty "빈 탭 → [OC] <pane 본문 ' · ' 앞>" || bad tab-guard-empty "[OC] 이름" "rc=$RC $(grep rename "$FD/calls.log")"
reset_state; setlabel tab w1:t1 "[RV] 남의 접두어"
ao self-name --force - "[OC] 이름 · 대기 1 (x)"
[ "$RC" = 0 ] && ! called "tab rename" && [ -z "$(printf '%s' "$ERR" | grep '탭 접두어')" ] && ok tab-guard-prefixed "이미 [XX] 탭 → 그대로·조용히" || bad tab-guard-prefixed "tab rename 없음" "rc=$RC $(grep rename "$FD/calls.log") err=$ERR"
reset_state; setlabel tab w1:t1 "Peter review"
ao self-name --force - "[WO] 작업자 · 대기"
[ "$RC" = 0 ] && ! called "tab " && called "pane rename w1:p1 [WO] 작업자 · 대기" && ok tab-guard-wo "[WO] pane → 탭 조회·변경 없음" || bad tab-guard-wo "tab 호출 없음" "rc=$RC $(cat "$FD/calls.log")"
reset_state; setlabel tab w1:t1 "Peter review"; echo internal > "$FD/fail-tab-rename"
ao self-name --force - "[OC] 이름"
rm -f "$FD/fail-tab-rename"
[ "$RC" = 0 ] && called "pane rename w1:p1 [OC] 이름" && echo "$ERR" | grep -q '보정 실패' && ok tab-guard-fail-warn "가드 실패는 경고만·pane rc=0" || bad tab-guard-fail-warn "rc=0 + 경고" "rc=$RC err=$ERR"

echo "== session-init(이름 + 받은편지함 구독 한 번에)"
SIS="$T/si-state"; SIR=(AO_STATE_ROOT="$SIS")
reset_state; setlabel pane w1:p1 7
run "${SIR[@]}" -- bash "$BIN" session-init OC "조정자" --tab "체인 탭"
[ "$RC" = 0 ] && called "tab rename w1:t1 [OC] 체인 탭" && called "pane rename w1:p1 [OC] 조정자" \
  && [ "$OUT" = "session-init role=OC tab=[OC] 체인 탭 pane=[OC] 조정자 subs=0" ] \
  && ok session-init-oc-default "숫자·기본 이름 → 인자 그대로·증거 줄" || bad session-init-oc-default "rename 둘·증거 줄" "rc=$RC out=$OUT $(grep rename "$FD/calls.log") err=$ERR"
reset_state; setlabel tab w1:t1 "헬프AI"
run "${SIR[@]}" -- bash "$BIN" session-init OC "조정자"
[ "$RC" = 0 ] && called "tab rename w1:t1 [OC] 헬프AI" && called "pane rename w1:p1 [OC] 조정자" && ok session-init-oc-user "사용자 탭 → 접두어만" || bad session-init-oc-user "[OC] 헬프AI" "rc=$RC $(grep rename "$FD/calls.log")"
reset_state; setlabel tab w1:t1 ""
run "${SIR[@]}" -- bash "$BIN" session-init WO "작업자 A"
[ "$RC" = 0 ] && ! called "tab rename" && called "pane rename w1:p1 [WO] 작업자 A" && printf '%s' "$OUT" | grep -q '^session-init role=WO tab=- pane=\[WO\] 작업자 A subs=0$' \
  && ok session-init-wo-pane-only "WO → pane만 rename(탭은 증거 읽기만)·빈 탭은 tab=-" || bad session-init-wo-pane-only "pane만" "rc=$RC out=$OUT $(cat "$FD/calls.log")"
reset_state; SID1="$T/si/parent/main-x.log"
run "${SIR[@]}" -- bash "$BIN" session-init RV "리뷰어" --inbox "$SID1" --inbox w1:p4
[ "$RC" = 0 ] && [ -d "$T/si/parent" ] && [ -f "$SID1" ] && grep -qxF "$SID1" "$SIS/inbox/subs/pane-w1_p1" && grep -qxF "$SIS/inbox/pane-w1_p4.log" "$SIS/inbox/subs/pane-w1_p1" \
  && printf '%s' "$OUT" | grep -q ' subs=2$' && ok session-init-inbox "--inbox → 폴더 생성·구독 2·subs=2" || bad session-init-inbox "구독 2" "rc=$RC out=$OUT err=$ERR $(cat "$SIS/inbox/subs/pane-w1_p1" 2>&1)"
reset_state; SID2="$T/si/out/main-y.log"
run "${SIR[@]}" HERDR_ENV= -- bash "$BIN" session-init OC "밖" --inbox "$SID2"
[ "$RC" = 0 ] && ! called "rename" && grep -qxF "$SID2" "$SIS/inbox/subs/pane-w1_p1" && echo "$ERR" | grep -q '이름 붙이기 건너뜀' \
  && [ "$OUT" = "session-init role=OC tab=- pane=- subs=3" ] && ok session-init-no-backend "herdr 밖 → 이름 건너뜀 안내·구독은 함·0" || bad session-init-no-backend "rc=0 구독" "rc=$RC out=$OUT err=$ERR"
reset_state; rm -rf "$T/si/bad"
run "${SIR[@]}" -- bash "$BIN" session-init XX "이름" --inbox "$T/si/bad/a.log"; c1=$RC
run "${SIR[@]}" -- bash "$BIN" session-init OC "이름" --inbox "rel/a.log"; c2=$RC
run "${SIR[@]}" -- bash "$BIN" session-init WO "이름" --tab "탭"; c3=$RC
run "${SIR[@]}" -- bash "$BIN" session-init OC; c4=$RC
[ "$c1/$c2/$c3/$c4" = 2/2/2/2 ] && [ ! -s "$FD/calls.log" ] && [ ! -e "$T/si/bad" ] && ok session-init-arg-error "역할·대상·--tab(WO)·인자 부족 → 2·부작용 0" || bad session-init-arg-error "2/2/2/2·호출 0" "$c1/$c2/$c3/$c4 $(cat "$FD/calls.log")"
reset_state; echo internal > "$FD/fail-pane-get"
run "${SIR[@]}" -- bash "$BIN" session-init WO "작업자" --inbox "$T/si/f/z.log"; rm -f "$FD/fail-pane-get"
[ "$RC" != 0 ] && [ "$RC" != 2 ] && grep -qxF "$T/si/f/z.log" "$SIS/inbox/subs/pane-w1_p1" && printf '%s' "$OUT" | grep -q '^session-init role=WO tab=1 pane=- subs=4$' \
  && ok session-init-step-fail "이름 단계 실패 → 구독은 하고 증거 줄 뒤 그 코드" || bad session-init-step-fail "rc≠0·구독·증거" "rc=$RC out=$OUT err=$ERR"

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
run HERDR_ENV= -- bash "$BIN" inbox-send w1:p9 "pane 대상"; chk inbox-pane-target 0 unwatched
PL="$T/home/.local/state/agent-orchestrator/inbox/pane-w1_p9.log"
[ -f "$PL" ] && grep -q ' pane 대상$' "$PL" && ok inbox-pane-path "pane id → ~/.local/state/…/inbox/pane-w1_p9.log (폴더 자동 생성)" || bad inbox-pane-path "$PL" "$(ls -R "$T/home/.local" 2>&1 | head -5)"
run AGENT_ORCHESTRATOR_BACKEND=none -- bash "$BIN" inbox-watch --pending w1:p9
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -Eq '^#1 [0-9:]{8} pane 대상$' && ok inbox-pending-pane "--pending pane 대상·backend=none" || bad inbox-pending-pane "#1 … pane 대상" "rc=$RC $OUT"

echo "== 받은편지함: 없는 pane 대상·notify (2026-11-13 메인 고정 받은편지함)"
reset_state
ao inbox-send w1:p8 "닫힌 pane"; PG="$T/home/.local/state/agent-orchestrator/inbox/pane-w1_p8.log"
[ "$RC" = 3 ] && [ "$OUT" = unwatched ] && grep -q ' 닫힌 pane$' "$PG" 2>/dev/null && printf '%s' "$ERR" | grep -q '대상 pane 없음' \
  && ok inbox-send-pane-gone "없는 pane → 3·줄은 기록·stderr 대상 pane 없음" || bad inbox-send-pane-gone "rc=3 unwatched 기록" "rc=$RC out=$OUT err=$ERR"
ao inbox-send w1:p1 "살아 있는 pane"; chk inbox-send-pane-alive 0 unwatched
echo garbage > "$FD/fail-pane-get"; ao inbox-send w1:p8 "응답 불명"; rm -f "$FD/fail-pane-get"; chk inbox-send-pane-unknown 0 unwatched
ao notify "제목 하나" "본문 하나"; [ "$RC" = 0 ] && called "notification show 제목 하나 --body 본문 하나 --sound request" \
  && ok notify-herdr "herdr 안 → herdr notification show" || bad notify-herdr "rc=0·호출" "rc=$RC $(tail -1 "$FD/calls.log")"
printf '#!/bin/sh\nprintf "%%s|" "$@" > "%s/osa.log"\n' "$T" > "$T/osa"; chmod +x "$T/osa"
run HERDR_ENV= AO_OSASCRIPT="$T/osa" -- bash "$BIN" notify "밖 제목" "밖 본문"
[ "$RC" = 0 ] && grep -qF -- '|--|밖 제목|밖 본문|' "$T/osa.log" 2>/dev/null && ok notify-osascript "herdr 밖 → osascript 인자 그대로" || bad notify-osascript "rc=0·인자" "rc=$RC $(cat "$T/osa.log" 2>&1)"
ao notify "제목만"; chk notify-bad-args 2
run HERDR_ENV= AO_OSASCRIPT="$T/osa" -- bash "$BIN" notify "-s" "o"
[ "$RC" = 0 ] && grep -qF -- '|--|-s|o|' "$T/osa.log" 2>/dev/null && ok notify-dash-args "'-'로 시작하는 제목·본문 앞에 -- (옵션 해석 방지)" || bad notify-dash-args "|--|-s|o|" "$(cat "$T/osa.log" 2>&1)"
FD="$FD" /usr/bin/python3 - <<'PY2'
import json, os
p = os.path.join(os.environ["FD"], "state.json"); s = json.load(open(p))
s["panes"].append({"pane_id": "w1:p6", "tab_id": "w1:t1", "rect": {"x": 0, "y": 0, "height": 50}, "cwd": "/tmp/x", "label": "pane_not_found"})
json.dump(s, open(p, "w"))
PY2
ao inbox-send w1:p6 "라벨에 같은 글자"; chk inbox-send-pane-label-literal 0 unwatched

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
# 경쟁: 소유자가 잠금을 놓는 순간 기록자 여럿이 동시에 대기 → 6줄 모두 온전(겹친 쓰기 0, 완료 검토 B1 회귀)
L8="$IB/rec.log"
/usr/bin/perl -MFcntl=:flock -e 'open(my $f,">>",$ARGV[0]) or die; flock($f,LOCK_EX) or die; print "held\n"; $|=1; select(undef,undef,undef,0.5)' "$L8.flock" > "$IB/hold2.out" & HP=$!
waitfor "$IB/hold2.out" held
for k in 1 2 3 4 5 6; do aoi -- inbox-send --raw "$L8" "rec-$k $(printf '%2000s' '' | tr ' ' "$k") e$k" > /dev/null 2>&1 & done
wait "$HP"; wait
gd=$(awk '{ k = substr($1, 5); if (NF == 3 && $3 == "e" k && length($2) == 2000 && $2 !~ "[^" k "]") g++ } END { print g + 0 }' "$L8")
[ "$(wc -l < "$L8" | tr -d ' ')" = 6 ] && [ "$gd" = 6 ] && [ "$(cut -d' ' -f1 "$L8" | sort -u | wc -l | tr -d ' ')" = 6 ] \
  && ok inbox-lock-two-recoverers "소유자 해제 순간 기록자 6개 → 6줄·온전 6·중복 0" || bad inbox-lock-two-recoverers "6줄·온전 6" "$(wc -l < "$L8") 온전 $gd"

echo "== 받은편지함: 송신 기록·감시 판정(계획 2026-11-11 simplify)"
# 새 호출은 상태 루트를 임시 폴더로, HERDR_PANE_ID는 비운다(시험 격리 조건)
SR="$T/state"; SI="$SR/inbox"; S1="$T/s1"; mkdir -p "$S1"
BASE2=(PATH="$FAKE:/usr/bin:/bin" HOME="$T/home" FAKE_DIR="$FD" HERDR_ENV=1
       HERDR_TAB_ID=w1:t1 HERDR_WORKSPACE_ID=w1 AO_STATE_ROOT="$SR")
run2() { local e=(); while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  OUT=$(cd "$T" && env -i "${BASE2[@]}" ${e[@]+"${e[@]}"} "$@" 2>"$T/err"); RC=$?; ERR=$(cat "$T/err"); }
ao2() { run2 -- bash "$BIN" "$@"; }
aoi2() { (cd "$T" && exec env -i "${BASE2[@]}" bash "$BIN" "$@"); }
lst() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'; }
# 가짜 대기자: fakew <log> <키> → FWP = sleep pid (subs/<키> 에 경로, wait/<키>.pid 에 표식)
fakew() { sleep 30 & FWP=$!; mkdir -p "$SI/subs" "$SI/wait"; echo "$1" > "$SI/subs/$2"; echo "$FWP $(lst "$FWP") tok" > "$SI/wait/$2.pid"; }
killw() { kill -9 "$FWP" 2>/dev/null; wait "$FWP" 2>/dev/null; }
LW="$S1/wt.log"
fakew "$LW" sid-ffff0001
ao2 inbox-send "$LW" "대기자만"; r1="$RC/$OUT"
killw
ao2 inbox-send "$LW" "대기자 KILL 뒤"; r2="$RC/$OUT"
[ "$r1" = 0/watched ] && [ "$r2" = 0/unwatched ] && ok inbox-send-waiter-watched "대기자만 → watched, KILL 뒤 → unwatched" || bad inbox-send-waiter-watched "0/watched 0/unwatched" "$r1 $r2 err=$ERR"
LWW="$S1/ww.log"; fakew "$LWW" sid-ffff0009
ao2 inbox-send "$LWW" "감시 중"; w1="$RC/$OUT"; e1=$ERR; killw
ao2 inbox-send "$LWW" "감시 끝"; w2="$RC/$OUT"; e2=$ERR
[ "$w1" = 0/watched ] && ! printf '%s' "$e1" | grep -q '미감시' && ok inbox-send-watched-no-warn "watched → 미감시 경고 없음" || bad inbox-send-watched-no-warn "0/watched·경고 없음" "$w1 err=$e1"
[ "$w2" = 0/unwatched ] && printf '%s' "$e2" | grep -qF "미감시: $LWW 줄 #2 — 받는 세션이 구독하지 않았다(inbox-subscribe 안 함). 부모·조정자 받은편지함이면 사용자에게 알릴 것(notify)" \
  && ok inbox-send-unwatched-warn "unwatched → stdout·rc 그대로 + stderr 미감시 한 줄" || bad inbox-send-unwatched-warn "0/unwatched·미감시 줄" "$w2 err=$e2"
LM="$S1/st.log"
fakew "$LM" sid-ffff0003
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
# pane 받은편지함은 subs 없이 pane 키의 대기자로 waiter, hooks.off 면 none
sleep 30 & FWP=$!; echo "$FWP $(lst "$FWP") tok" > "$SI/wait/pane-w5_p5.pid"
ao2 inbox-watch --state w5:p5; s1=$OUT; : > "$SI/hooks.off"; ao2 inbox-watch --state w5:p5; s2=$OUT; rm -f "$SI/hooks.off"; killw
[ "$s1/$s2" = waiter/none ] && ok inbox-watch-state-pane "pane 받은편지함 → pane 키 대기자로 waiter·hooks.off 면 none" || bad inbox-watch-state-pane "waiter/none" "$s1/$s2"
RO2="$S1/ro"; mkdir -p "$RO2"; chmod 555 "$RO2"
ao2 inbox-send "$RO2/x.log" "기록 불가"; c=$RC
chmod 755 "$RO2"
[ "$c" = 4 ] && [ ! -e "$RO2/x.log" ] && ok inbox-send-append-fail "받은편지함 쓰기 불가 → 4·기록 0" || bad inbox-send-append-fail "4·파일 없음" "rc=$c $(ls "$RO2")"
mkdir -p "$T/state2/inbox/events.log"
run2 AO_STATE_ROOT="$T/state2" -- bash "$BIN" inbox-send "$S1/me.log" "events 불가"
[ "$RC/$OUT" = 0/unwatched ] && [ -z "$(printf '%s' "$ERR" | grep -v '미감시: ')" ] && [ "$(wc -l < "$S1/me.log" | tr -d ' ')" = 1 ] \
  && ok inbox-send-event-fail-quiet "events.log 쓰기 불가 → 0·events 경고 없음(미감시 한 줄만)" || bad inbox-send-event-fail-quiet "0·미감시 외 stderr 없음" "rc=$RC err=$ERR"
UQ="body-uniq-$$-Zq9"
ao2 inbox-send "$S1/nb.log" "$UQ 원문"
EV="$SI/events.log"
grep -qF "$UQ" "$EV" && bad inbox-ev-no-body "원문 없음" "$(grep -F "$UQ" "$EV")" || ok inbox-ev-no-body "보낸 원문이 events.log 에 없음"
run2 HERDR_ENV= -- bash "$BIN" inbox-send w1:p7 "루트 대상"
[ "$RC" = 0 ] && [ -f "$SI/pane-w1_p7.log" ] && [ ! -e "$T/home/.local/state/agent-orchestrator/inbox/pane-w1_p7.log" ] && grep -q $'\tbox=pane-w1_p7\t' "$EV" \
  && ok inbox-state-root "AO_STATE_ROOT → \$T/state/inbox/pane-w1_p7.log·box=pane-w1_p7" || bad inbox-state-root "$SI/pane-w1_p7.log" "rc=$RC $(ls "$SI")"

echo "== 받은편지함: 구독·대기자(계획 2026-11-11 simplify §3·§10)"
W="$T/w"; mkdir -p "$W"; SB="$T/sb"; mkdir -p "$SB"
SA=aaaaaaaa-0001; SB1=bbbbbbbb-0002
# wfor <파일> <패턴> [초=5] — 고정 문자열이 나타날 때까지
wfor() { local i=0 n=$(( ${3:-5} * 20 )); while [ $i -lt $n ]; do grep -qF -- "$2" "$1" 2>/dev/null && return 0; sleep 0.05; i=$((i + 1)); done; return 1; }
# 대기자 띄우기: wl <이름> <sid> <hook> [VAR=값 …] → WP_<이름>. stderr $W/<이름>.err, 등록 표식 $W/<이름>.mk
#   기본 POLL 0.2·MAX 5, registered:0 으로 등록 완료를 표식 파일에 남긴다(PAUSE를 주면 덧붙음)
wl() { local n=$1 s=$2 h=$3 pz="registered:0"; shift 3
  local e=(); for a in "$@"; do case "$a" in AO_INBOX_TEST_PAUSE=*) pz="$pz,${a#*=}" ;; *) e+=("$a") ;; esac; done
  printf '{"session_id":"%s","hook_event_name":"%s","transcript_path":"%s","prompt":"%s"}' "$s" "$h" "${WL_TP:-}" "${WL_PROMPT:-}" > "$W/$n.json"
  rm -f "$W/$n.mk" "$W/$n.mk.go"
  (cd "$T" && exec env -i "${BASE2[@]}" AO_INBOX_WAIT_POLL=0.2 AO_INBOX_WAIT_MAX=5 AO_INBOX_TEST_PAUSE="$pz" \
     AO_INBOX_TEST_PAUSE_MARK="$W/$n.mk" ${e[@]+"${e[@]}"} bash "$BIN" inbox-wait < "$W/$n.json" 2> "$W/$n.err") &
  eval "WP_$n=\$!"; }
# wrc <이름> → 그 대기자의 종료 코드(끝날 때까지 기다림)
wrc() { local p; eval "p=\${WP_$1:-}"; wait "$p" 2>/dev/null; WRC=$?; }
wgo() { : > "$W/$1.mk.go"; }
sub() { local s=$1; shift; run2 CLAUDE_CODE_SESSION_ID="$s" -- bash "$BIN" inbox-subscribe "$@"; }
snd() { aoi2 inbox-send --raw "$1" "$2" > /dev/null 2>&1; }
alive() { kill -0 "$1" 2>/dev/null; }
ptok() { awk '{print $NF; exit}' "$SI/wait/$1.pid" 2>/dev/null; }
ms() { /usr/bin/perl -MTime::HiRes=time -e 'printf "%d", time*1000'; }
# 케이스마다 새 sid: ns → NS
SIDN=0; ns() { SIDN=$((SIDN + 1)); NS=$(printf 'dd%06d-0000' "$SIDN"); }
nlines() { grep -cE '^#[0-9]+ ' "$1"; }
LS1="$SB/a.log"
sub $SA "$LS1"; r1="$RC/$OUT"
[ "$r1" = 0/ ] && [ "$(cat "$SI/subs/sid-$SA")" = "$LS1" ] && [ -f "$LS1" ] \
  && ok inbox-sub-add "등록 0·빈 출력·subs/sid-<sid> 에 경로 한 줄·받은편지함 생성" || bad inbox-sub-add "0/·경로 한 줄" "$r1 $(cat "$SI/subs/sid-$SA" 2>&1)"
sub $SA "$LS1"; l1=$(cd "$T" && env -i "${BASE2[@]}" CLAUDE_CODE_SESSION_ID=$SA bash "$BIN" inbox-subscribe --list)
sub $SA "$LS1" --unsubscribe; u1=$RC; sub $SA --list; l2="$RC/$OUT"; sub $SA "$SB/none.log" --unsubscribe; u2=$RC
[ "$l1" = "$LS1" ] && [ "$u1/$l2/$u2" = "0/0//0" ] && [ ! -e "$SI/subs/sid-$SA" ] \
  && ok inbox-sub-list "같은 경로 두 번 → --list 한 줄·해제 뒤 빈 출력·빈 파일 삭제·없는 경로 해제 0" || bad inbox-sub-list "$LS1 0/0//0" "$l1 $u1/$l2/$u2"
sub $SA "$SB/p.log" --pane w1:p3
[ "$RC" = 0 ] && [ "$(cat "$SI/subs/pane-w1_p3")" = "$SB/p.log" ] \
  && ok inbox-sub-pane-key "--pane w1:p3 → 키 pane-w1_p3" || bad inbox-sub-pane-key "pane-w1_p3" "rc=$RC $(ls "$SI/subs")"
run2 -- bash "$BIN" inbox-subscribe "$SB/k.log"
[ "$RC" = 2 ] && printf '%s' "$ERR" | grep -qF '구독 키 없음' && ok inbox-sub-no-key "키·sid 없음 → 2 구독 키 없음" || bad inbox-sub-no-key "2·구독 키 없음" "rc=$RC err=$ERR"
sub $SA "rel/x.log"; b1=$RC; sub $SA "/a/../b.log"; b2=$RC; sub zz "$SB/z.log"; b3=$RC
[ "$b1$b2$b3" = 222 ] && ok inbox-sub-bad-target "상대 경로·..·sid 형식 오류 → 2" || bad inbox-sub-bad-target "2 2 2" "$b1 $b2 $b3"
LCL="$SB/c.log"; printf 'x1\nx2\n' > "$LCL"; echo $SA > "$LCL.owner"
sub $SB1 "$LCL"
[ "$(cat "$LCL.owner")" = $SB1 ] && [ "$(cat "$LCL.held")" = "1 2" ] && ok inbox-sub-claim "subscribe 만으로 owner A→B·held 1 2" || bad inbox-sub-claim "owner B·held 1 2" "$(cat "$LCL.owner") $(cat "$LCL.held" 2>&1)"
sub $SB1 "$LCL" --unsubscribe
# 옛 2.8.1 줄(<경로>\t<sid>)은 첫 칸만: --list 경로·중복 추가 없음·대기자가 그 경로로 깨움
ns; LLG="$SB/legacy.log"; : > "$LLG"; printf '%s\t%s\n' "$LLG" "$SA" > "$SI/subs/sid-$NS"
sub "$NS" "$LLG"; sub "$NS" --list; lg="$OUT/$(wc -l < "$SI/subs/sid-$NS" | tr -d ' ')"
wl lg "$NS" Stop; wfor "$W/lg.mk" registered; snd "$LLG" "옛 줄로 받음"; wrc lg
[ "$lg" = "$LLG/1" ] && [ "$WRC" = 2 ] && grep -qF '#1 옛 줄로 받음' "$W/lg.err" \
  && ok inbox-sub-legacy "옛 <경로>⇥<sid> 줄 → --list 경로 한 칸·중복 추가 0·대기자 깨움" || bad inbox-sub-legacy "$LLG/1 2" "$lg $WRC"
ns; wl nt "$NS" Stop; wrc nt; c=$WRC
[ "$c" = 0 ] && [ ! -s "$W/nt.err" ] && [ ! -e "$SI/wait/sid-$NS.pid" ] && ok inbox-wait-no-target "대상 없음 → 0·stderr 빈 출력·표식 없음" || bad inbox-wait-no-target "0·빈 stderr" "rc=$c $(cat "$W/nt.err")"
printf '{"hook_event_name":"Stop"}' > "$W/ns.json"
(cd "$T" && env -i "${BASE2[@]}" bash "$BIN" inbox-wait < "$W/ns.json" > "$W/ns.out" 2> "$W/ns.err"); c=$?
[ "$c" = 0 ] && [ ! -s "$W/ns.err" ] && [ ! -s "$W/ns.out" ] && ok inbox-wait-no-sid "session_id 없음 → 0·빈 출력" || bad inbox-wait-no-sid "0" "rc=$c $(cat "$W/ns.err")"
echo 'not json {' > "$W/bj.json"
(cd "$T" && env -i "${BASE2[@]}" bash "$BIN" inbox-wait < "$W/bj.json" 2> "$W/bj.err"); c=$?
(cd "$T" && env -i "${BASE2[@]}" bash "$BIN" inbox-wait --bogus < /dev/null 2> "$W/bj2.err"); c2=$?
[ "$c$c2" = 44 ] && [ ! -s "$W/bj.err" ] && [ ! -s "$W/bj2.err" ] \
  && ok inbox-wait-bad-json "JSON 해석 실패·알 수 없는 인자 → 4·stderr 빈 출력" || bad inbox-wait-bad-json "4 4" "$c $c2 $(cat "$W/bj.err" "$W/bj2.err")"
ao2 inbox-wait --status; chk inbox-wait-status 0 "inbox-wait 2"
(cd "$T" && printf '{"session_id":"%s"}' "$SA" | env -i "${BASE2[@]}" bash "$BIN" inbox-wait --session-start > "$W/sn.out" 2> "$W/sn.err"); c=$?
[ "$c" = 0 ] && [ ! -s "$W/sn.out" ] && [ ! -s "$W/sn.err" ] && ok inbox-wait-ss-noop "--session-start(옛 래퍼) → stdin 버림·빈 출력·0" || bad inbox-wait-ss-noop "0·빈 출력" "rc=$c $(cat "$W/sn.out")"
ns; LW1="$SB/w1.log"; sub "$NS" "$LW1"; wl wk "$NS" Stop; wfor "$W/wk.mk" registered
snd "$LW1" "깨움 하나"; wrc wk; c=$WRC
[ "$c" = 2 ] && grep -qF 'token=' "$W/wk.err" && grep -qF '#1 깨움 하나' "$W/wk.err" && grep -qF -- '--ack' "$W/wk.err" && ! grep -qF '재통지' "$W/wk.err" \
  && ok inbox-wait-wake "대기 중 send 1줄 → 2·token=·#1·--ack·재통지 표시 없음" || bad inbox-wait-wake "2" "rc=$c $(cat "$W/wk.err")"
[ "$(cat "$LW1.cursor" 2>/dev/null || echo none)/$(cat "$LW1.notified" 2>/dev/null)" = none/1 ] && grep -qF $'\tev=wake\t' "$SI/events.log" \
  && ok inbox-wait-notified "깨움 뒤 .cursor 그대로(없음)·.notified=1·wake 사건" || bad inbox-wait-notified "none/1" "$(cat "$LW1.cursor" 2>&1)/$(cat "$LW1.notified" 2>&1)"
wl wn "$NS" Stop AO_INBOX_WAIT_MAX=1; wrc wn; c=$WRC
[ "$c" = 2 ] && grep -qF '대기 만료(재등록)' "$W/wn.err" && [ "$(nlines "$W/wn.err")" = 0 ] \
  && ok inbox-wait-notified-quiet "notified=1 뒤 같은 sid Stop 대기자 → 그 줄로 깨지 않음(만료 재등록만)" || bad inbox-wait-notified-quiet "2·만료만" "rc=$c $(cat "$W/wn.err")"
wl wc "$NS" SessionStart; wrc wc; c=$WRC
[ "$c" = 2 ] && grep -qF '#1 깨움 하나' "$W/wc.err" && ok inbox-wait-ss-cursor "notified=1·cursor 0 → SessionStart 대기자는 곧바로 2·#1" || bad inbox-wait-ss-cursor "2·#1" "rc=$c $(cat "$W/wc.err")"
ns; LW2="$SB/w2a.log"; LW3="$SB/w2b.log"; sub "$NS" "$LW2"; sub "$NS" "$LW3"; snd "$LW2" "a"; snd "$LW3" "b"; wl w2 "$NS" Stop; wrc w2; c=$WRC
[ "$c" = 2 ] && [ "$(grep -c '^== ' "$W/w2.err")" = 2 ] && ok inbox-wait-wake-two "두 받은편지함 미처리 → 한 번 깨움에 == 머리 둘" || bad inbox-wait-wake-two "2·머리 2" "rc=$c $(cat "$W/w2.err")"
ns; LP="$SB/pn.log"; snd "$LP" "미리 온 줄"; sub "$NS" "$LP"
t0=$(ms); wl pn "$NS" Stop; wrc pn; c=$WRC; dt=$(( $(ms) - t0 ))
[ "$c" = 2 ] && [ "$dt" -lt 1500 ] && ok inbox-wait-pending-now "시작 전 미처리 → ${dt}ms 에 2" || bad inbox-wait-pending-now "1.5초 안 2" "rc=$c ${dt}ms"
ns; LC2="$SB/cap.log"; for i in $(seq 1 25); do echo "c$i" >> "$LC2"; done; sub "$NS" "$LC2"; wl cp "$NS" Stop; wrc cp; c=$WRC
[ "$c" = 2 ] && [ "$(nlines "$W/cp.err")" = 20 ] && grep -qF '… 나머지 5줄은' "$W/cp.err" && grep -qF -- "--pending $LC2" "$W/cp.err" \
  && ok inbox-wait-cap-20 "25줄 → 번호 줄 20·나머지 5줄 안내" || bad inbox-wait-cap-20 "20·나머지 5" "rc=$c $(nlines "$W/cp.err")"
ns; LL="$SB/long.log"; long=$(printf '가%.0s' $(seq 1 600)); echo "$long" > "$LL"; sub "$NS" "$LL"; wl ln "$NS" Stop; wrc ln; c=$WRC
lg=$(grep '^#1 ' "$W/ln.err" | sed 's/^#1 //; s/ …(잘림 — --pending으로 전문)$//' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
[ "$c" = 2 ] && grep -qF '…(잘림 — --pending으로 전문)' "$W/ln.err" && [ "$lg" = 501 ] && ok inbox-wait-line-500 "600자 줄 → 앞 500자 + 잘림 안내" || bad inbox-wait-line-500 "500자" "rc=$c len=$lg"
ns; LCF="$SB/cf.log"; printf 'o1\no2\n' > "$LCF"; echo $SA > "$LCF.owner"; echo "$LCF" > "$SI/subs/sid-$NS"
wl cf "$NS" Stop; wrc cf; c=$WRC
[ "$c" = 2 ] && sed -n 3p "$W/cf.err" | grep -qF '#0 [이전 세션' && grep -qF '#1 [이전 세션] o1' "$W/cf.err" && [ "$(cat "$LCF.owner")" = "$NS" ] \
  && ok inbox-wait-claim-first "owner A 미처리 2줄 → B 대기자 #0 안내·[이전 세션] 표시·owner B" || bad inbox-wait-claim-first "#0 첫 줄" "rc=$c $(cat "$W/cf.err")"
ns; PL="$SI/pane-w9_p1.log"; t0=$(ms); wl pa "$NS" Stop HERDR_PANE_ID=w9:p1; wfor "$W/pa.mk" registered; snd "$PL" "pane 새 줄"; wrc pa; c=$WRC
[ "$c" = 2 ] && grep -qF '#1 pane 새 줄' "$W/pa.err" && [ ! -e "$SI/subs/pane-w9_p1" ] && [ -f "$SI/wait/pane-w9_p1.pid" ] \
  && ok inbox-wait-pane-auto "HERDR_PANE_ID 만·subs 없음 → pane 받은편지함 새 줄에 2·표식 wait/pane-…pid" || bad inbox-wait-pane-auto "2" "rc=$c $(cat "$W/pa.err")"
ns; LRP="$SB/rp.log"; sub "$NS" "$LRP"; wl ra "$NS" Stop; wfor "$W/ra.mk" registered; wl rb "$NS" Stop; wfor "$W/rb.mk" registered
wrc ra; ca=$WRC; tb=$(ptok "sid-$NS"); alive "$WP_rb" && rb=live || rb=dead
snd "$LRP" "교체 뒤"; wrc rb; cb=$WRC
[ "$ca/$rb/$cb" = 0/live/2 ] && [ ! -s "$W/ra.err" ] && printf '%s' "$tb" | grep -q "^w$WP_rb-" && grep -qF '#1 교체 뒤' "$W/rb.err" \
  && ok inbox-wait-replace "같은 키 A 뒤 B → A 는 TERM 으로 0·.pid 는 B 토큰·새 줄은 B" || bad inbox-wait-replace "0/live/2" "$ca/$rb/$cb tok=$tb"
ns; LSP="$SB/sp.log"; sub "$NS" "$LSP"; snd "$LSP" "곧바로"; wl sa "$NS" Stop; wrc sa; t1=$(ptok "sid-$NS")
ao2 inbox-watch --state "$LSP"; st=$OUT; ao2 inbox-send "$LSP" "끝난 뒤"; sw=$OUT
[ "$WRC" = 2 ] && printf '%s' "$t1" | grep -q "^w$WP_sa-" && [ "$st/$sw" = none/unwatched ] \
  && ok inbox-wait-stale-pid "깨움 종료 뒤 .pid 는 남음(지우지 않음)·죽은 표식은 none·unwatched" || bad inbox-wait-stale-pid "2 남음 none/unwatched" "$WRC $t1 $st/$sw"
ns; LPR="$SB/pr.log"; sub "$NS" "$LPR"; sleep 30 & SP=$!; echo "$SP Mon Jan 1 00:00:00 2001 tokX" > "$SI/wait/sid-$NS.pid"
wl pr "$NS" Stop; wfor "$W/pr.mk" registered; sleep 0.3; snd "$LPR" "끝"; wrc pr
alive "$SP" && ok inbox-wait-pid-reuse "pid 파일의 살아 있는 무관 pid·다른 lstart → TERM 안 보냄" || bad inbox-wait-pid-reuse "생존" "죽음"
kill -9 "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
ns; NO=$NS; ns; LOS="$SB/os.log"; sub "$NO" "$LOS"; sub "$NS" "$SB/os2.log"
wl o1 "$NO" Stop; wfor "$W/o1.mk" registered; wl o2 "$NS" Stop; wfor "$W/o2.mk" registered; sleep 0.3
alive "$WP_o1" && r=ok || r=dead; snd "$LOS" "o"; wrc o1; c1=$WRC; snd "$SB/os2.log" "o"; wrc o2
[ "$r/$c1" = ok/2 ] && ok inbox-wait-other-sid "다른 sid 대기자는 TERM 받지 않음(그 뒤 자기 줄로 2)" || bad inbox-wait-other-sid "ok/2" "$r/$c1"
ns; LEX="$SB/ex.log"; sub "$NS" "$LEX"; t0=$(ms); wl ex "$NS" Stop AO_INBOX_WAIT_MAX=1; wrc ex; c1=$WRC; dt=$(( $(ms) - t0 ))
wl ex2 "$NS" Stop; wfor "$W/ex2.mk" registered; snd "$LEX" "만료 뒤 새 줄"; wrc ex2; c2=$WRC
[ "$c1/$c2" = 2/2 ] && [ "$dt" -lt 3000 ] && [ "$(cat "$W/ex.err")" = "[inbox] 대기 만료(재등록) — 새 메시지 없음. 할 일 없으면 아무 말 없이 쉬어라" ] && grep -qF '#1 만료 뒤 새 줄' "$W/ex2.err" \
  && ok inbox-wait-expire-rewake "대상 있는 만료 → 2·한 줄 안내 → 새 대기자가 새 줄로 2" || bad inbox-wait-expire-rewake "2/2" "$c1/$c2 ${dt}ms $(cat "$W/ex.err")"
ns; LTN="$SB/tn.log"; sub "$NS" "$LTN"; wl tn "$NS" Stop AO_INBOX_TEST_PAUSE=notify-mid:3; wfor "$W/tn.mk" registered
snd "$LTN" "깨움 중 TERM"; wfor "$W/tn.mk" notify-mid; kill -TERM "$WP_tn"; sleep 0.3; wgo tn; wrc tn; c=$WRC
[ "$c" = 2 ] && grep -qF '#1 깨움 중 TERM' "$W/tn.err" && grep -qF -- '--ack' "$W/tn.err" && [ "$(cat "$LTN.notified")" = 1 ] \
  && ok inbox-wait-term-notify "notified 기록 뒤·출력 전 TERM → 무시·깨움 출력 완전·2" || bad inbox-wait-term-notify "2·완전" "rc=$c $(cat "$W/tn.err")"
ns; LTM="$SB/tm.log"; sub "$NS" "$LTM"; wl tm "$NS" Stop; wfor "$W/tm.mk" registered
kill -TERM "$WP_tm"; wrc tm; c=$WRC
[ "$c" = 0 ] && [ ! -s "$W/tm.err" ] && [ -f "$SI/wait/sid-$NS.pid" ] && ok inbox-wait-term "폴링 중 TERM → 0·stderr 빈 출력·.pid 남김" || bad inbox-wait-term "0" "rc=$c $(cat "$W/tm.err")"
ns; LF9="$SB/f9.log"; sub "$NS" "$LF9"; wl f9 "$NS" Stop; wfor "$W/f9.mk" registered
: > "$W/f9.rc"; for k in 1 2 3 4 5; do (aoi2 inbox-send --raw "$LF9" "f$k" > /dev/null 2>&1; echo $? >> "$W/f9.rc") & done
wrc f9; c=$WRC; sleep 0.5
[ "$c" = 2 ] && [ "$(sort -u "$W/f9.rc" | tr -d '\n')" = 0 ] && [ "$(wc -l < "$W/f9.rc" | tr -d ' ')" = 5 ] && [ "$(wc -l < "$LF9" | tr -d ' ')" = 5 ] \
  && ok inbox-wait-fd9-free "대기 중 동시 send 5개 → 모두 0·5줄·대기자 2" || bad inbox-wait-fd9-free "0×5" "$c $(cat "$W/f9.rc" | tr '\n' ' ')"
ns; LDR="$SB/dr.log"; sub "$NS" "$LDR"; wl dr "$NS" Stop; wfor "$W/dr.mk" registered
sub "$NS" "$LDR" --unsubscribe; t0=$(ms); wrc dr; c=$WRC; dt=$(( $(ms) - t0 ))
[ "$c" = 0 ] && [ "$dt" -lt 1500 ] && [ ! -s "$W/dr.err" ] && ok inbox-sub-del-running "폴링 중 해제 → ${dt}ms 에 0·통지 0" || bad inbox-sub-del-running "0 1.5초 안" "rc=$c ${dt}ms"
ns; HA=$NS; ns; HB=$NS; LHO="$SB/ho.log"; sub "$HA" "$LHO"; wl ha "$HA" Stop; wfor "$W/ha.mk" registered
sub "$HA" "$LHO" --unsubscribe; sub "$HB" "$LHO"; wl hb "$HB" Stop; wfor "$W/hb.mk" registered
snd "$LHO" "인계 뒤"; wrc hb; cb=$WRC; wrc ha; ca=$WRC
[ "$ca/$cb" = 0/2 ] && [ ! -s "$W/ha.err" ] && grep -qF '#1 인계 뒤' "$W/hb.err" && ok inbox-sub-handover "A 해제 → B 등록 → 새 줄은 B만 깨움·A 통지 0" || bad inbox-sub-handover "0/2" "$ca/$cb"
ns; LOF="$SB/of.log"; sub "$NS" "$LOF"; snd "$LOF" "끈 동안"; : > "$SI/hooks.off"; wl of "$NS" Stop; wrc of; c=$WRC; rm -f "$SI/hooks.off"
[ "$c" = 0 ] && [ ! -s "$W/of.err" ] && [ ! -e "$SI/wait/sid-$NS.pid" ] && ok inbox-wait-off "hooks.off → 미처리가 있어도 즉시 0·stderr 빈 출력" || bad inbox-wait-off "0" "rc=$c $(cat "$W/of.err")"
ns; D1=$NS; ns; D2=$NS; LD1="$SB/d1.log"; LD2="$SB/d2.log"; sub "$D1" "$LD1"; sub "$D2" "$LD2"
wl da "$D1" Stop; wl db "$D2" Stop; wfor "$W/da.mk" registered; wfor "$W/db.mk" registered
ao2 inbox-wait --drain; d="$RC/$OUT"; wrc da; c1=$WRC; wrc db; c2=$WRC; snd "$LD1" "끈 뒤"
wl dc "$D1" Stop; wrc dc; c3=$WRC; ao2 inbox-wait --undrain; u=$RC
wl dd "$D1" Stop; wrc dd; c4=$WRC
[ "$d/$c1$c2$c3/$u/$c4" = 0/2/000/0/2 ] && [ ! -s "$W/da.err" ] && [ ! -e "$SI/hooks.off" ] && grep -qF '#1 끈 뒤' "$W/dd.err" \
  && ok inbox-drain "대기자 2개 → --drain stdout 2·둘 다 0·끈 동안 새 대기자 0·--undrain 뒤 다시 깨움" || bad inbox-drain "0/2/000/0/2" "$d/$c1$c2$c3/$u/$c4"
# bg(daemon) 세션은 물려받은 HERDR_PANE_ID 를 쓰지 않는다(2026-11-12 p6K)
ns; LBG="$SB/bg.log"; sub "$NS" "$LBG"; : > "$SI/wait/pane-w9_p2.pid"
wl bg "$NS" Stop HERDR_PANE_ID=w9:p2 CLAUDE_CODE_SESSION_KIND=bg; wfor "$W/bg.mk" registered; snd "$LBG" "bg 새 줄"; wrc bg; c=$WRC
[ "$c" = 2 ] && [ -f "$SI/wait/sid-$NS.pid" ] && [ ! -s "$SI/wait/pane-w9_p2.pid" ] && grep -qF '#1 bg 새 줄' "$W/bg.err" \
  && ok inbox-wait-bg-key "SESSION_KIND=bg → pane 키 대신 sid 키·pane 표식 안 건드림" || bad inbox-wait-bg-key "2·sid 키" "rc=$c $(ls "$SI/wait" | tr '\n' ' ')"
# 멈춤 점검: transcript 픽스처(마지막 assistant 글)
mktp() { printf '{"type":"assistant","isSidechain":false,"message":{"content":[{"type":"text","text":"%s"}]}}\n' "$2" > "$W/$1.jsonl"; }
EXM='[inbox] 대기 만료(재등록)'
ns; LST="$SB/st.log"; sub "$NS" "$LST"; snd "$LST" "완료 보고"; echo 1 > "$LST.notified"; mktp st1 "보고 드렸습니다."
WL_TP="$W/st1.jsonl" wl s1 "$NS" Stop AO_INBOX_STALL=1; wrc s1; c1=$WRC
WL_TP="$W/st1.jsonl" wl s2 "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAIT_MAX=2; wrc s2; c2=$WRC
[ "$c1/$c2" = 2/2 ] && grep -qF '멈춤 점검 — 안 읽은' "$W/s1.err" && grep -qF '#1~#1' "$W/s1.err" && grep -qF "$EXM" "$W/s2.err" \
  && ok inbox-wait-stall-unacked "알렸지만 ack 없는 줄 → 1초 뒤 멈춤 깨움·같은 n 은 다시 안 깨움" || bad inbox-wait-stall-unacked "2/2" "$c1/$c2 $(cat "$W/s1.err" "$W/s2.err")"
ns; LSPR="$SB/spr.log"; sub "$NS" "$LSPR"; mktp sp1 "검수 끝. 이어서 3단계를 진행하겠습니다."
WL_TP="$W/sp1.jsonl" wl p1 "$NS" Stop AO_INBOX_STALL=1; wrc p1; c1=$WRC
WL_TP="$W/sp1.jsonl" wl p2 "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAIT_MAX=2; wrc p2; c2=$WRC
WL_TP="$W/sp1.jsonl" WL_PROMPT="계속해" wl p3 "$NS" UserPromptSubmit AO_INBOX_STALL=1 AO_INBOX_WAIT_MAX=2; wrc p3; c3=$WRC
WL_TP="$W/sp1.jsonl" wl p4 "$NS" Stop AO_INBOX_STALL=1; wrc p4; c4=$WRC
[ "$c1/$c2/$c3/$c4" = 2/2/2/2 ] && grep -qF '이어서 하겠다' "$W/p1.err" && grep -qF "$EXM" "$W/p2.err" && grep -qF "$EXM" "$W/p3.err" && grep -qF '이어서 하겠다' "$W/p4.err" \
  && ok inbox-wait-stall-promise "약속으로 끝난 턴 → 멈춤 깨움 1회·연속 안 깨움·사람 입력 뒤 다시 1회" || bad inbox-wait-stall-promise "2/2/2/2" "$c1/$c2/$c3/$c4"
ns; LSQ="$SB/sq.log"; sub "$NS" "$LSQ"; mktp sq1 "기다리는 동안 어느 쪽으로 진행할까요?"
WL_TP="$W/sq1.jsonl" wl q1 "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAIT_MAX=2; wrc q1; c=$WRC
[ "$c" = 2 ] && grep -qF "$EXM" "$W/q1.err" && ok inbox-wait-stall-question "질문으로 끝난 턴 → 멈춤 깨움 없음" || bad inbox-wait-stall-question "만료만" "rc=$c $(cat "$W/q1.err")"
ns; LSD="$SB/sd.log"; sub "$NS" "$LSD"; mktp sd1 "M2를 마감했습니다. 다음 작업은 내일 합니다."
WL_TP="$W/sd1.jsonl" wl d1 "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAIT_MAX=2; wrc d1; c=$WRC
[ "$c" = 2 ] && grep -qF "$EXM" "$W/d1.err" && ok inbox-wait-stall-done "약속 없이 끝난 턴 → 멈춤 깨움 없음" || bad inbox-wait-stall-done "만료만" "rc=$c $(cat "$W/d1.err")"
ns; LSN="$SB/sn.log"; sub "$NS" "$LSN"; mktp sn1 "끝나면 이어서 진행하겠습니다."
WL_TP="$W/sn1.jsonl" wl n1 "$NS" Stop AO_INBOX_STALL=1; wrc n1; c1=$WRC
WL_TP="$W/sn1.jsonl" WL_PROMPT="<task-notification> Stop hook feedback [inbox] 멈춤 점검" wl n2 "$NS" UserPromptSubmit AO_INBOX_STALL=1 AO_INBOX_WAIT_MAX=2; wrc n2
WL_TP="$W/sn1.jsonl" wl n3 "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAIT_MAX=2; wrc n3; c3=$WRC
[ "$c1/$c3" = 2/2 ] && grep -qF '이어서 하겠다' "$W/n1.err" && grep -qF "$EXM" "$W/n3.err" \
  && ok inbox-wait-stall-notify-no-reset "깨움 통지로 들어온 UserPromptSubmit 은 1회 표식을 풀지 않음(되풀이 없음)" || bad inbox-wait-stall-notify-no-reset "2/2·만료만" "$c1/$c3 $(cat "$W/n3.err")"
ns; LSO="$SB/so.log"; sub "$NS" "$LSO"; mktp so1 "기다린다로 끝나면 깨웁니다. 원하시면 추가하겠습니다."
WL_TP="$W/so1.jsonl" wl o1 "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAIT_MAX=2; wrc o1; c=$WRC
[ "$c" = 2 ] && grep -qF "$EXM" "$W/o1.err" && ok inbox-wait-stall-offer "\"원하시면 ~\" 제안으로 끝난 턴 → 멈춤 깨움 없음" || bad inbox-wait-stall-offer "만료만" "rc=$c $(cat "$W/o1.err")"
ns; LWL="$SB/wl.log"; sub "$NS" "$LWL"; mktp wl1 "보고드렸습니다.\\n대기 목록 (1): - [WO] portalds2 — Q5 — 보고서 진행 3/7 (09:41 확인)"
WL_TP="$W/wl1.jsonl" wl w1 "$NS" Stop AO_INBOX_STALL=1; wrc w1; c1=$WRC
WL_TP="$W/wl1.jsonl" wl w2 "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAITLIST_EVERY=1; wrc w2; c2=$WRC
WL_TP="$W/wl1.jsonl" wl w3 "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAITLIST_EVERY=3 AO_INBOX_WAIT_MAX=2; wrc w3; c3=$WRC
[ "$c1/$c2/$c3" = 2/2/2 ] && grep -qF '대기 점검' "$W/w1.err" && grep -qF '대기 점검' "$W/w2.err" && grep -qF "$EXM" "$W/w3.err" && [ -f "$SI/wait/sid-$NS.wl" ] \
  && ok inbox-wait-waitlist "대기 목록으로 끝난 턴 → 대기 점검 되풀이(1회 제한 없음)·다음 간격은 WAITLIST_EVERY" || bad inbox-wait-waitlist "2/2/2" "$c1/$c2/$c3 $(cat "$W/w3.err")"
ns; LWN="$SB/wn.log"; sub "$NS" "$LWN"; mktp wn1 "체인을 마감했습니다. 이어서 할 것은 없습니다.\\n대기 없음 — 더 기다리는 것이 없습니다. 이 세션은 닫아도 됩니다."
WL_TP="$W/wn1.jsonl" wl wn "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAIT_MAX=2; wrc wn; c=$WRC
[ "$c" = 0 ] && [ ! -s "$W/wn.err" ] && ok inbox-wait-waitlist-none "\"대기 없음\"으로 끝난 턴 → 깨움 없음·만료도 조용히 0" || bad inbox-wait-waitlist-none "0·빈 출력" "rc=$c $(cat "$W/wn.err")"
ns; LWO="$SB/wo.log"; sub "$NS" "$LWO"; mktp wo1 "앞의 대기 목록 (1)은 모두 끝났습니다.\\n대기 없음 — 이 세션은 닫아도 됩니다."
WL_TP="$W/wo1.jsonl" wl wo "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAIT_MAX=2; wrc wo; c=$WRC
[ "$c" = 0 ] && [ ! -s "$W/wo.err" ] && ok inbox-wait-waitlist-order "목록 언급 뒤 \"대기 없음\"으로 끝남 → 대기 점검 아님" || bad inbox-wait-waitlist-order "0" "rc=$c $(cat "$W/wo.err")"
ns; LWS="$SB/ws.log"; sub "$NS" "$LWS"; : > "$SI/wait/sid-$NS.wl"; mktp ws1 "끝나면 이어서 진행하겠습니다."
WL_TP="$W/ws1.jsonl" wl ws "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAITLIST_EVERY=30; wrc ws; c=$WRC
[ "$c" = 2 ] && grep -qF '이어서 하겠다' "$W/ws.err" && [ ! -e "$SI/wait/sid-$NS.wl" ] && ok inbox-wait-waitlist-stale "앞 턴 .wl 이 남아도 목록 없는 턴은 STALL 간격·.wl 지움" || bad inbox-wait-waitlist-stale "2·멈춤" "rc=$c $(cat "$W/ws.err")"
ns; LWG="$SB/wg.log"; sub "$NS" "$LWG"; items=$(for i in $(seq 1 60); do printf -- '- [WO] 작업자 %02d — 긴 작업 설명 칸을 채우는 문장 — 보고서 진행 1/9 (09:41 확인) ' "$i"; done); mktp wg1 "대기 목록 (60): $items"
WL_TP="$W/wg1.jsonl" wl wg "$NS" Stop AO_INBOX_STALL=1; wrc wg; c=$WRC
[ "$c" = 2 ] && grep -qF '대기 점검' "$W/wg.err" && ok inbox-wait-waitlist-long "6KB 넘는 대기 목록도 머리 줄을 놓치지 않음" || bad inbox-wait-waitlist-long "대기 점검" "rc=$c $(head -c 200 "$W/wg.err")"
ns; LWU="$SB/wu.log"; sub "$NS" "$LWU"; snd "$LWU" "완료 보고"; echo 1 > "$LWU.notified"; : > "$SI/wait/sid-$NS.wl"; mktp wu1 "대기 목록 (1): - [WO] a — b — 진행 중 (09:41 확인)"
WL_TP="$W/wu1.jsonl" wl wu "$NS" Stop AO_INBOX_STALL=1 AO_INBOX_WAITLIST_EVERY=30; wrc wu; c=$WRC
[ "$c" = 2 ] && grep -qF '안 읽은 받은편지함' "$W/wu.err" && ok inbox-wait-waitlist-unacked "이어진 대기 목록(30분 간격)이어도 미처리 줄 점검은 STALL 간격" || bad inbox-wait-waitlist-unacked "2·미처리" "rc=$c $(cat "$W/wu.err")"
ns; LWI="$SB/wi.log"; sub "$NS" "$LWI"; mktp wi1 "대기 목록 (1):\\n- 서브에이전트: 점검 — 결과가 대기 없음 — 이면 닫는다 — 진행 중 (09:41 확인)"
WL_TP="$W/wi1.jsonl" wl wi "$NS" Stop AO_INBOX_STALL=1; wrc wi; c=$WRC
[ "$c" = 2 ] && grep -qF '대기 점검' "$W/wi.err" && ok inbox-wait-waitlist-inline "항목 안의 \"대기 없음\" 글자는 끝맺음으로 보지 않음" || bad inbox-wait-waitlist-inline "대기 점검" "rc=$c $(cat "$W/wi.err")"
# wait-status: 가짜 HOME 의 서브에이전트 표식·같은 탭 pane·미처리 받은편지함을 측정해 낸다
WSID=cccccccc-0009; WSD="$T/home/.claude/projects/-x/$WSID/subagents"; mkdir -p "$WSD"; echo '{}' > "$T/home/.claude/projects/-x/$WSID.jsonl"
printf '%s' '{"description":"분해 A","requestShape":"background","finished":true}' > "$WSD/agent-a1.meta.json"; : > "$WSD/agent-a1.jsonl"
printf '%s' '{"description":"조사 B","requestShape":"background"}' > "$WSD/agent-a2.meta.json"; : > "$WSD/agent-a2.jsonl"
printf '%s' '{"description":"앞에서 끝남","requestShape":"foreground","finished":true}' > "$WSD/agent-a3.meta.json"
printf '%s' '{"description":"중단됨","requestShape":"background"}' > "$WSD/agent-a4.meta.json"; : > "$WSD/agent-a4.jsonl"
printf '%s\n' '<task-id>a4</task-id><status>killed</status>' >> "$T/home/.claude/projects/-x/$WSID.jsonl"; touch -t 202601010000 "$WSD/agent-a4.jsonl"
LWQ="$SB/wq.log"; run2 CLAUDE_CODE_SESSION_ID=$WSID -- bash "$BIN" inbox-subscribe --session $WSID "$LWQ"; printf 'a\nb\nc\n' >> "$LWQ"; echo 1 > "$LWQ.cursor"
run2 CLAUDE_CODE_SESSION_ID=$WSID HERDR_PANE_ID= -- bash "$BIN" wait-status
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^서브에이전트"$'\t'"분해 A \[a1\]"$'\t'"완료"$'\t' && printf '%s\n' "$OUT" | grep -q "^서브에이전트"$'\t'"조사 B \[a2\]"$'\t'"진행 중" \
  && ! printf '%s\n' "$OUT" | grep -qF '앞에서 끝남' && ! printf '%s\n' "$OUT" | grep -qF '중단됨' \
  && printf '%s\n' "$OUT" | grep -qF "받은편지함"$'\t'"$LWQ"$'\t'"미처리 2"$'\t'"#2~#3" && printf '%s\n' "$OUT" | tail -1 | grep -q "^합계"$'\t'"대기 2"$'\t'"완료 1"$'\t' \
  && ok wait-status-measure "서브에이전트 완료·진행/foreground·중단 제외/미처리 2줄/합계" || bad wait-status-measure "측정 4칸" "rc=$RC $(printf '%s' "$OUT" | tr '\t' '|')"
run2 -- bash "$BIN" wait-status --bogus; [ "$RC" = 2 ] && ok wait-status-usage "알 수 없는 인자 → 2" || bad wait-status-usage 2 "$RC"
# 받은편지함 케이스 이름 — 하나라도 PASS로 실행되지 않으면 FAIL(하니스 전제: 지운 시험이 조용히 빠지지 않게)
INBOX_OLD="
  inbox-send inbox-format inbox-raw inbox-raw-notime inbox-4000-ok inbox-no-truncate inbox-4000-multibyte
  inbox-raw-over4000 inbox-over4000-with-time inbox-over-nowrite inbox-arg-relative inbox-arg-not-log
  inbox-arg-dotdot inbox-arg-bad-pane inbox-arg-no-line inbox-arg-empty-line inbox-watch-no-target inbox-ack-bad-n
  inbox-watch-bad-opt inbox-backend-none inbox-no-herdr inbox-pane-target inbox-pane-path inbox-pending-pane
  inbox-parallel-20 inbox-create-race inbox-ack-race inbox-ack-no-tmp inbox-ack-lower-keep inbox-ack-max
  inbox-ack-beyond inbox-ack-readonly inbox-watched inbox-watch-from-cursor inbox-watch-mark-cleaned
  inbox-unwatched-after inbox-watch-redeliver inbox-watch-acked-hidden inbox-watch-foreign-pid inbox-watch-mark-token
  inbox-owner-held inbox-owner-held-persist inbox-owner-third inbox-owner-pending inbox-release inbox-release-normal
  inbox-owner-no-sid inbox-lock-live-pid inbox-lock-dead-pid inbox-lock-recovered inbox-lock-two-recoverers
  inbox-send-waiter-watched inbox-watch-state-waiter inbox-watch-state-monitor inbox-watch-format-kept
  inbox-watch-state-none inbox-watch-state-pane inbox-send-append-fail inbox-send-event-fail-quiet inbox-ev-no-body
  inbox-state-root inbox-sub-add inbox-sub-list inbox-sub-pane-key inbox-sub-no-key inbox-sub-bad-target
  inbox-sub-claim inbox-sub-legacy inbox-wait-no-target inbox-wait-no-sid inbox-wait-bad-json inbox-wait-status
  inbox-wait-ss-noop inbox-wait-wake inbox-wait-notified inbox-wait-notified-quiet inbox-wait-ss-cursor
  inbox-wait-wake-two inbox-wait-pending-now inbox-wait-cap-20 inbox-wait-line-500 inbox-wait-claim-first
  inbox-wait-pane-auto inbox-wait-replace inbox-wait-stale-pid inbox-wait-pid-reuse inbox-wait-other-sid
  inbox-wait-expire-rewake inbox-wait-term-notify inbox-wait-term inbox-wait-fd9-free inbox-sub-del-running
  inbox-sub-handover inbox-wait-off inbox-drain
"
miss=""; for nm in $INBOX_OLD; do grep -qxF "$nm" "$T/pass.names" || miss="$miss $nm"; done; nold=$(printf '%s\n' $INBOX_OLD | grep -c .)
[ -z "$miss" ] && [ "$nold" = 95 ] && ok inbox-regress-all "받은편지함 케이스 ${nold}개 모두 PASS 로 실행됨" || bad inbox-regress-all "95개 전부" "${nold}개, 누락:$miss"
left=0; for f in "$SI"/wait/*.pid; do [ -f "$f" ] && _p=$(awk '{print $1}' "$f") && kill -0 "$_p" 2>/dev/null && left=$((left + 1)); done
lw=$(ps -axo command | grep -F "$T" | grep -cF 'inbox-wait' )
[ "$left/$lw" = 0/0 ] || echo "WARN 남은 대기자 pid $left·프로세스 $lw"
# 맨 끝: 실제 상태 폴더에 시험이 만든 흔적이 없는가.
#   다른 세션이 실제로 쓰는 받은편지함(*.log·.cursor·.owner·.flock 등)은 시험과 무관하게 바뀌므로 세지 않는다
RS="$REAL_HOME/.local/state/agent-orchestrator"; touched=""
if [ -d "$RS" ]; then
  # 실제 세션(옛 core 포함)도 subs·wait·.waiters 를 쓰므로 시각만으로 보지 않는다: 시험만 쓰는 sid·키가 든 이름, 또는 hooks.off
  touched=$(find "$RS" -newer "$T/stamp" 2>/dev/null | grep -E '/hooks\.off$|(dd[0-9]{6}-0000|aaaaaaaa-0001|bbbbbbbb-0002|ffff000[13])')
  # events.log 는 실제 세션도 쓰므로 시각이 아니라 내용으로 본다: 시작 뒤 붙은 줄에 시험 고유 sid·box 가 있으면 시험이 쓴 것
  tail -c +"$((REAL_EV_SZ + 1))" "$REAL_EV" 2>/dev/null | grep -qE 'sid=(dd[0-9]{6}-0000|aaaaaaaa-0001|bbbbbbbb-0002)|box=(pane-w1_p7|pane-w9_p1|pane-w1_p9|pane-w5_p5|legacy|rp|f9)'$'\t' && touched="$touched $REAL_EV"
fi
[ -z "$touched" ] && ok inbox-real-state-untouched "실제 $RS 에 시험 상태 이름 변경 0" || bad inbox-real-state-untouched "0" "$touched"
TOTAL=$((PASS + FAIL))
echo "== 집계: PASS $PASS / FAIL $FAIL / 총 $TOTAL (기대 $EXPECT)"
[ "$TOTAL" = "$EXPECT" ] || { echo "FAIL 케이스 총계 불일치: $TOTAL ≠ $EXPECT"; exit 1; }
[ "$FAIL" = 0 ]
