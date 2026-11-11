#!/usr/bin/env bash
# run-rc-tests.sh — review-chain 스크립트(rc-send/rc-watch/rc-claim) 호환 시험 (0.1.4, 0.2.0 감시 시험 추가)
#
# 사용:
#   run-rc-tests.sh                      골든 대조 + 동시 기록 + 래퍼 시험
#   run-rc-tests.sh --make-golden <옛 scripts 폴더>   옛 스크립트로 test/golden/ 을 다시 만든다
#                                        (inbox-send 도입 전 커밋의 scripts 를 풀어서 넘긴다)
# 환경: AGENT_ORCHESTRATOR=<agent-orchestrator 실행 파일> (inbox-send --raw·inbox-watch 지원본).
#   미지정이면 개발 리포의 tools/agent-orchestrator/bin/agent-orchestrator 를 쓴다.
# 종료: 0 전부 통과 / 1 실패 있음 / 3 agent-orchestrator 가 inbox-send 를 지원하지 않아 못 돌림
# bash 3.2 호환.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS_DEFAULT=$(cd "$HERE/.." && pwd)
GOLDEN="$HERE/golden"
REPO=$(cd "$HERE/../../../../../.." && pwd)
export AGENT_ORCHESTRATOR=${AGENT_ORCHESTRATOR:-$REPO/tools/agent-orchestrator/bin/agent-orchestrator}
for l in en_US.UTF-8 ko_KR.UTF-8 C.UTF-8; do
  if locale -a 2>/dev/null | grep -qix "${l/UTF-8/utf8}\|$l"; then export LC_ALL=$l; break; fi
done
TMP=$(mktemp -d "$(printf %s "${TMPDIR:-/tmp}" | sed 's#/*$##')/rc-tests.XXXXXX")   # inbox-send 는 경로의 // 를 거부한다
trap 'rm -rf "$TMP"' EXIT
# 실제 상태 폴더(~/.local/state/agent-orchestrator)를 건드리지 않는다 — 구독·known·이벤트 모두 임시 폴더로
export AO_STATE_ROOT="$TMP/ao-state"; mkdir -p "$AO_STATE_ROOT"
unset HERDR_PANE_ID CLAUDE_CODE_SESSION_ID
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/     /'; }

# 시각·임시 경로를 고정 문자열로 바꾼다.
# 0.2.0: 옛 골든(0.1.4)과 대조하려고 새로 생긴 두 가지만 지운다 — OK 줄 끝의 ` watch=…` 와
#   "report.md/state.md 없음 — 미감시 전송 기록 생략" 경고 줄. 나머지는 옛 골든과 그대로 같아야 한다.
#   새 동작 자체는 아래 신규 시험이 직접 확인한다.
CUR_S=/nonexistent
norm() { sed -E -e "s#$TMP#<TMP>#g" -e "s#$CUR_S#<SCRIPTS>#g" -e 's/[0-2][0-9]:[0-5][0-9]:[0-5][0-9]/HH:MM:SS/g' \
  -e 's/^(OK box=.* kind=[^ ]*) watch=[a-z]*$/\1/' -e '/^rc-send: 경고: (report\.md|state\.md) 없음 — 미감시 전송 기록 생략/d'; }

# run_case <출력 폴더> <이름> <스크립트 폴더> -- 명령... : stdout/stderr/종료코드/inbox 를 파일로
cap() { # cap <out> <name> <inbox 파일들...> -- cmd...
  local out=$1 name=$2; shift 2
  local boxes=(); while [ "$1" != "--" ]; do boxes+=("$1"); shift; done; shift
  local so se rc
  so=$("$@" 2>"$TMP/se"); rc=$?
  { echo "[stdout]"; printf '%s\n' "$so"; echo "[stderr]"; cat "$TMP/se"; echo "[rc] $rc"
    local b; for b in "${boxes[@]+"${boxes[@]}"}"; do echo "[box $(basename "$(dirname "$b")")/$(basename "$b")]"; [ -f "$b" ] && cat "$b"; done
  } | norm > "$out/$name.txt"
}

# 새 체인 폴더(워커 alice·bob)를 만든다. echo 로 경로를 돌려준다.
mkchain() { # mkchain <기준 폴더> <체인 id>
  local d="$1/$2"; mkdir -p "$d/workers/alice" "$d/workers/bob"; echo "$d"
}

# 골든 대상 시나리오를 <scripts>로 돌려 <out>/*.txt 를 만든다.
run_scenarios() { # run_scenarios <scripts 폴더> <out>
  local S=$1 out=$2 base RC LONG i
  CUR_S=$S; mkdir -p "$out"; base="$TMP/sc"; rm -rf "$base"; mkdir -p "$base"
  RC=$(mkchain "$base" rc-20260101-demo)
  cap "$out" send-w2o "$RC/inbox.log" -- "$S/rc-send.sh" "$RC" alice 완료 "구현 끝. 시험 12개 통과"
  cap "$out" send-o2w "$RC/workers/alice/inbox.log" -- "$S/rc-send.sh" --to alice "$RC" 답 "계속 진행해"
  cap "$out" send-w2o-trailing-slash "$RC/inbox.log" -- "$S/rc-send.sh" "$RC/" bob 질문 "줄바꿈
탭	포함 요지"
  LONG=$(printf '가나다라마바사%.0s' $(seq 1 60))
  local DEEP="$base"; for i in 1 2 3 4 5 6 7 8; do DEEP="$DEEP/deep-directory-name-number-$i"; done
  local LRC; LRC=$(mkchain "$DEEP" rc-20260101-a-very-long-chain-folder-name-for-path-length)
  cap "$out" send-long-summary-long-path "$LRC/inbox.log" -- "$S/rc-send.sh" "$LRC" alice 막힘 "$LONG"
  cap "$out" send-o2w-long "$LRC/workers/bob/inbox.log" -- "$S/rc-send.sh" --to bob "$LRC" 보류 "$LONG"
  cap "$out" err-kind-w2o -- "$S/rc-send.sh" "$RC" alice 진행 "x"
  cap "$out" err-kind-o2w -- "$S/rc-send.sh" --to alice "$RC" 완료 "x"
  cap "$out" err-name -- "$S/rc-send.sh" "$RC" Alice 완료 "x"
  cap "$out" err-name-to -- "$S/rc-send.sh" --to 9bad "$RC" 답 "x"
  cap "$out" err-relative -- "$S/rc-send.sh" rel/path alice 완료 "x"
  cap "$out" err-nodir -- "$S/rc-send.sh" "$base/nodir" alice 완료 "x"
  cap "$out" err-noworker -- "$S/rc-send.sh" --to carol "$RC" 답 "x"
  cap "$out" err-argc -- "$S/rc-send.sh" "$RC" alice 완료
  cap "$out" dry-w2o "$RC/inbox.log" -- env RC_DRY_RUN=1 "$S/rc-send.sh" "$RC" alice 완료 "dry 요지"
  cap "$out" dry-o2w "$RC/workers/bob/inbox.log" -- env RC_DRY_RUN=1 "$S/rc-send.sh" --to bob "$RC" 확인 "dry 한 줄"
  # rc-claim: 선점 → 충돌(inbox.log 에 [충돌] 줄) → 공용 파일
  local CR; CR=$(mkchain "$base" rc-20260101-claim)
  printf 'docs/shared.md\n' > "$CR/shared-files"
  cap "$out" claim-ok -- "$S/rc-claim.sh" "$CR" alice src/a/ "lib/*.sh"
  cap "$out" claim-conflict "$CR/inbox.log" -- "$S/rc-claim.sh" "$CR" bob src/a/b.txt "lib/x.sh"
  cap "$out" claim-shared "$CR/inbox.log" -- "$S/rc-claim.sh" "$CR" bob docs/shared.md
  rm -rf "$base"
}

if [ "${1:-}" = "--make-golden" ]; then
  [ $# = 2 ] && [ -x "$2/rc-send.sh" ] || { echo "사용: $0 --make-golden <옛 scripts 폴더>" >&2; exit 2; }
  rm -rf "$GOLDEN"; run_scenarios "$2" "$GOLDEN"
  echo "골든 $(ls "$GOLDEN" | wc -l | tr -d ' ')개 생성: $GOLDEN"; exit 0
fi

# ── 사전 확인: AO 가 inbox-send --raw 를 지원하는가 ──────────────────────────────
PROBE="$TMP/probe.log"
"$AGENT_ORCHESTRATOR" inbox-send --raw "$PROBE" "probe line" >/dev/null 2>"$TMP/probe.err"; PRC=$?
if [ "$PRC" != 0 ] || [ "$(cat "$PROBE" 2>/dev/null)" != "probe line" ]; then
  echo "SKIP: $AGENT_ORCHESTRATOR 가 inbox-send --raw 를 지원하지 않음 (종료 $PRC) — A 구현 뒤 다시 실행"
  sed 's/^/     /' "$TMP/probe.err" | head -3
  exit 3
fi

# ── 1. 골든 대조 ────────────────────────────────────────────────────────────────
NEWOUT="$TMP/new-golden"
run_scenarios "$SCRIPTS_DEFAULT" "$NEWOUT"
for g in "$GOLDEN"/*.txt; do
  n=$(basename "$g")
  if [ ! -f "$NEWOUT/$n" ]; then bad "골든 $n (결과 없음)"
  elif diff -u "$g" "$NEWOUT/$n" >"$TMP/d" 2>&1; then ok "골든 $n"
  else bad "골든 $n" "$(head -12 "$TMP/d")"; fi
done

# ── 2. 동시 기록: rc-send 20 + rc-claim 충돌 20 → 깨진 줄 없음 ──────────────────
CRC=$(mkchain "$TMP" rc-20260101-conc)
"$SCRIPTS_DEFAULT/rc-claim.sh" "$CRC" alice src/ >/dev/null
i=0
while [ $i -lt 20 ]; do
  "$SCRIPTS_DEFAULT/rc-send.sh" "$CRC" bob 질문 "동시 보내기 $i 끝" >/dev/null 2>&1 &
  "$SCRIPTS_DEFAULT/rc-claim.sh" "$CRC" w$i src/x$i >/dev/null 2>&1 &
  i=$((i + 1))
done
wait
BOX="$CRC/inbox.log"
TOTAL=$(wc -l < "$BOX" | tr -d ' ')
SENDS=$(grep -c "\[WO bob\] \[질문\] .*/workers/bob/report.md 동시 보내기 [0-9]* 끝$" "$BOX")
CLAIMS=$(grep -c "\[WO w[0-9]*\] \[충돌\] .*/workers/w[0-9]*/report.md 선점 거부: src/x[0-9]*↔alice:src/$" "$BOX")
BROKEN=$(grep -vc "^[0-9][0-9]:[0-9][0-9]:[0-9][0-9] \[rc rc-20260101-conc\] \[WO [a-z0-9]*\] \[\(질문\|충돌\)\] /" "$BOX")
if [ "$TOTAL" = 40 ] && [ "$SENDS" = 20 ] && [ "$CLAIMS" = 20 ] && [ "$BROKEN" = 0 ]; then
  ok "동시 기록 rc-send 20 + rc-claim 20 (40줄, 깨진 줄 0)"
else
  bad "동시 기록" "total=$TOTAL sends=$SENDS claims=$CLAIMS broken=$BROKEN (기대 40/20/20/0)"
fi
# 잠금은 커널 flock(<log>.flock 파일)이라 남는 폴더가 없다 — 옛 mkdir 잠금 폴더가 생기지 않는지 본다
ls -d "$CRC"/inbox.log.lock* >/dev/null 2>&1 && bad "동시 기록 뒤 잠금 폴더 잔존" "$(ls -d "$CRC"/inbox.log.lock*)" || ok "동시 기록 뒤 잠금 폴더 잔존 없음"

# ── 3. rc-send 종료 4: 기록 실패 ────────────────────────────────────────────────
FRC=$(mkchain "$TMP" rc-20260101-fail)
mkdir "$FRC/inbox.log"   # 받은편지함 자리에 폴더 → 기록 불가
"$SCRIPTS_DEFAULT/rc-send.sh" "$FRC" alice 완료 "x" >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "기록 실패 → 종료 4" || bad "기록 실패 종료 코드" "got $rc, want 4"
FAKE="$TMP/fake-ao"; printf '#!/bin/sh\nexit 4\n' > "$FAKE"; chmod +x "$FAKE"
AGENT_ORCHESTRATOR=$FAKE "$SCRIPTS_DEFAULT/rc-send.sh" "$CRC" alice 완료 "x" >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && ok "AO 종료 4 → rc-send 종료 4" || bad "AO 실패 종료 코드" "got $rc, want 4"

# ── 4. rc-watch 래퍼: 인자 오류 2, pending/ack/watch 가 옛 형식과 같다 ──────────────
W="$SCRIPTS_DEFAULT/rc-watch.sh"
"$W" >/dev/null 2>&1; [ $? = 2 ] && ok "rc-watch 인자 없음 → 2" || bad "rc-watch 인자 없음"
"$W" relative.log >/dev/null 2>&1; [ $? = 2 ] && ok "rc-watch 상대 경로 → 2" || bad "rc-watch 상대 경로"
"$W" --ack "$TMP/x.log" abc >/dev/null 2>&1; [ $? = 2 ] && ok "rc-watch --ack 숫자 아님 → 2" || bad "rc-watch --ack 숫자 아님"
"$W" --pending >/dev/null 2>&1; [ $? = 2 ] && ok "rc-watch --pending 인자 부족 → 2" || bad "rc-watch --pending 인자 부족"

WRC=$(mkchain "$TMP" rc-20260101-watch); WB="$WRC/inbox.log"
for n in 1 2 3; do "$SCRIPTS_DEFAULT/rc-send.sh" "$WRC" alice 질문 "줄 $n" >/dev/null 2>&1; done
P=$("$W" --pending "$WB")
case "$P" in "#1 "*"줄 1"$'\n'"#2 "*"줄 2"$'\n'"#3 "*"줄 3") ok "rc-watch --pending 은 #n 접두로 전부 출력" ;; *) bad "rc-watch --pending" "$P" ;; esac
"$W" --ack "$WB" 2; rc=$?
C=$(head -n 1 "$WB.cursor" 2>/dev/null)
[ "$rc" = 0 ] && [ "$C" = 2 ] && ok "rc-watch --ack 2 → $WB.cursor = 2" || bad "rc-watch --ack" "rc=$rc cursor=$C"
"$W" --ack "$WB" 1; C=$(head -n 1 "$WB.cursor")
[ "$C" = 2 ] && ok "rc-watch --ack 되감지 않음" || bad "rc-watch --ack 되감김" "cursor=$C"
P=$("$W" --pending "$WB")
case "$P" in "#3 "*"줄 3") ok "rc-watch --pending 은 cursor 뒤만" ;; *) bad "rc-watch --pending(ack 뒤)" "$P" ;; esac
"$W" --release "$WB"; [ $? = 0 ] && ok "rc-watch --release 전달(0)" || bad "rc-watch --release"
"$W" --release >/dev/null 2>&1; [ $? = 2 ] && ok "rc-watch --release 인자 부족 → 2" || bad "rc-watch --release 인자 부족"

# watch: cursor 뒤 줄부터 나오고, 켠 뒤 도착한 줄도 나온다
"$W" "$WB" > "$TMP/watch.out" 2>"$TMP/watch.err" & WPID=$!; disown "$WPID" 2>/dev/null
sleep 1.5
"$SCRIPTS_DEFAULT/rc-send.sh" "$WRC" bob 완료 "줄 4" >/dev/null 2>&1
sleep 2.5
kill "$WPID" 2>/dev/null; pkill -P "$WPID" 2>/dev/null; pkill -f "tail -n .* -F $WB" 2>/dev/null; sleep 0.2
if grep -q "^#3 .*줄 3" "$TMP/watch.out" && grep -q "^#4 .*줄 4" "$TMP/watch.out" && ! grep -q "^#[12] " "$TMP/watch.out"; then
  ok "rc-watch 감시: cursor 뒤(#3)부터, 이후 도착(#4)도 출력"
else
  bad "rc-watch 감시" "out=$(cat "$TMP/watch.out") err=$(head -3 "$TMP/watch.err")"
fi

# ── 4b. 0.2.0 watch 필드·미감시 전송 기록·구독 (AO_STATE_ROOT 는 위에서 임시 폴더로 고정) ───
# 가짜 AO: FAKE_W 를 stdout 으로, FAKE_ERR 를 stderr 로 내고 FAKE_RC 로 끝낸다.
FAKE2="$TMP/fake-ao2"
cat > "$FAKE2" <<'FAKEEND'
#!/bin/sh
[ -n "${FAKE_ERR:-}" ] && echo "$FAKE_ERR" >&2
printf '%s' "${FAKE_W-}"
[ -n "${FAKE_W-}" ] && echo
exit "${FAKE_RC:-0}"
FAKEEND
chmod +x "$FAKE2"
mkreport() { printf '# report\n- 상태: 진행\n- 진행: 2/5\n- 다음: 시험\n' > "$1/workers/$2/report.md"; }
S="$SCRIPTS_DEFAULT"

# rc-send-watch-field: 출력 끝이 watch=<watched|unwatched>, 빈 값·이상값은 unwatched
WC=$(mkchain "$TMP" rc-20260101-wf); mkreport "$WC" alice
O=$("$S/rc-send.sh" "$WC" alice 질문 "실제 AO" 2>/dev/null)
case "$O" in "OK box=$WC/inbox.log kind=질문 watch=unwatched") ok "rc-send-watch-field 실제 AO(대기자 없음) → watch=unwatched" ;; *) bad "rc-send-watch-field 실제 AO" "$O" ;; esac
O=$(AGENT_ORCHESTRATOR=$FAKE2 FAKE_W=watched "$S/rc-send.sh" "$WC" alice 질문 "가짜 watched" 2>/dev/null)
case "$O" in "OK box=$WC/inbox.log kind=질문 watch=watched") ok "rc-send-watch-field 가짜 AO watched → watch=watched" ;; *) bad "rc-send-watch-field watched" "$O" ;; esac
O=$(AGENT_ORCHESTRATOR=$FAKE2 FAKE_W= "$S/rc-send.sh" "$WC" alice 질문 "빈 값" 2>/dev/null)
case "$O" in *" watch=unwatched") ok "rc-send-watch-field 빈 값 → unwatched" ;; *) bad "rc-send-watch-field 빈 값" "$O" ;; esac
O=$(AGENT_ORCHESTRATOR=$FAKE2 FAKE_W=maybe "$S/rc-send.sh" "$WC" alice 질문 "이상값" 2>/dev/null)
case "$O" in *" watch=unwatched") ok "rc-send-watch-field 이상값 → unwatched" ;; *) bad "rc-send-watch-field 이상값" "$O" ;; esac

# rc-send-unwatched-record: worker→OC 는 report.md 의 '- 진행:' 아래, OC→worker 는 state.md '## 미감시 전송' 절 끝
UC=$(mkchain "$TMP" rc-20260101-uw); mkreport "$UC" alice
"$S/rc-send.sh" "$UC" alice 완료 "끝" >/dev/null 2>&1; rc=$?
L=$(sed -n '4p' "$UC/workers/alice/report.md")
case "$L" in "- 미감시 전송 $UC/inbox.log "[0-2][0-9]:[0-5][0-9]) [ "$rc" = 0 ] && ok "rc-send-unwatched-record worker→OC: '- 진행:' 바로 아래 기록" || bad "rc-send-unwatched-record rc" "rc=$rc" ;; *) bad "rc-send-unwatched-record worker→OC" "$(cat "$UC/workers/alice/report.md")" ;; esac
[ "$(sed -n '3p' "$UC/workers/alice/report.md")" = "- 진행: 2/5" ] && [ "$(sed -n '5p' "$UC/workers/alice/report.md")" = "- 다음: 시험" ] \
  && ok "rc-send-unwatched-record 기존 줄 보존" || bad "rc-send-unwatched-record 기존 줄" "$(cat "$UC/workers/alice/report.md")"
"$S/rc-send.sh" "$UC" alice 질문 "둘째" >/dev/null 2>&1
[ "$(grep -c '^- 미감시 전송 ' "$UC/workers/alice/report.md")" = 2 ] && [ "$(sed -n '5p' "$UC/workers/alice/report.md" | cut -c1-8)" = "- 미감시 전송" ] \
  && ok "rc-send-unwatched-record 두 번째 기록은 첫 기록 아래" || bad "rc-send-unwatched-record 연속 기록" "$(cat "$UC/workers/alice/report.md")"
printf '# report\n- 상태: 진행\n' > "$UC/workers/bob/report.md"
"$S/rc-send.sh" "$UC" bob 완료 "끝" >/dev/null 2>&1
[ "$(tail -n 1 "$UC/workers/bob/report.md" | cut -c1-8)" = "- 미감시 전송" ] && ok "rc-send-unwatched-record '- 진행:' 없으면 파일 끝" || bad "rc-send-unwatched-record 파일 끝" "$(cat "$UC/workers/bob/report.md")"
rm -f "$UC/workers/alice/report.md"
"$S/rc-send.sh" "$UC" alice 막힘 "report 없음" >/dev/null 2>"$TMP/se"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$UC/workers/alice/report.md" ] && grep -q "report.md 없음" "$TMP/se" && ok "rc-send-unwatched-record report.md 없으면 생략+경고(종료 0)" || bad "rc-send-unwatched-record report 없음" "rc=$rc $(cat "$TMP/se")"
printf '# state\n## 큐\n- a\n## 미감시 전송\n- 미감시 전송 /x/y.log 09:00\n\n## 뒤 절\n- z\n' > "$UC/state.md"
"$S/rc-send.sh" --to alice "$UC" 답 "o2w" >/dev/null 2>&1
if [ "$(sed -n '6p' "$UC/state.md" | cut -c1-8)" = "- 미감시 전송" ] && [ "$(sed -n '5p' "$UC/state.md")" = "- 미감시 전송 /x/y.log 09:00" ] && [ "$(sed -n '9p' "$UC/state.md")" = "- z" ]; then
  ok "rc-send-unwatched-record OC→worker: state.md 절 끝에 기록(뒤 절 보존)"
else bad "rc-send-unwatched-record state.md" "$(cat "$UC/state.md")"; fi
printf '# state\n- a\n' > "$UC/state.md"
"$S/rc-send.sh" --to bob "$UC" 확인 "o2w2" >/dev/null 2>&1
if [ "$(grep -c '^## 미감시 전송$' "$UC/state.md")" = 1 ] && [ "$(tail -n 1 "$UC/state.md" | cut -c1-8)" = "- 미감시 전송" ]; then
  ok "rc-send-unwatched-record state.md 절이 없으면 파일 끝에 절 생성"
else bad "rc-send-unwatched-record 절 생성" "$(cat "$UC/state.md")"; fi
rm -f "$UC/state.md"
"$S/rc-send.sh" --to bob "$UC" 확인 "state 없음" >/dev/null 2>"$TMP/se"; rc=$?
[ "$rc" = 0 ] && grep -q "state.md 없음" "$TMP/se" && ok "rc-send-unwatched-record state.md 없으면 생략+경고(종료 0)" || bad "rc-send-unwatched-record state 없음" "rc=$rc $(cat "$TMP/se")"

# rc-send-watched-norecord: watched 면 보낸 쪽 파일을 건드리지 않는다
NC=$(mkchain "$TMP" rc-20260101-nr); mkreport "$NC" alice; printf '# state\n' > "$NC/state.md"
cp "$NC/workers/alice/report.md" "$TMP/rep.before"; cp "$NC/state.md" "$TMP/st.before"
AGENT_ORCHESTRATOR=$FAKE2 FAKE_W=watched "$S/rc-send.sh" "$NC" alice 완료 "w" >/dev/null 2>&1
AGENT_ORCHESTRATOR=$FAKE2 FAKE_W=watched "$S/rc-send.sh" --to alice "$NC" 답 "w" >/dev/null 2>&1
cmp -s "$NC/workers/alice/report.md" "$TMP/rep.before" && cmp -s "$NC/state.md" "$TMP/st.before" \
  && ok "rc-send-watched-norecord watched 면 report.md·state.md 불변" || bad "rc-send-watched-norecord" "$(cat "$NC/workers/alice/report.md")"

# rc-send-meta-warn-no-retry: AO 가 stderr 경고 + unwatched + 종료 0 → rc-send 종료 0, 재실행 안내 없음
MC=$(mkchain "$TMP" rc-20260101-mw); mkreport "$MC" alice
O=$(AGENT_ORCHESTRATOR=$FAKE2 FAKE_W=unwatched FAKE_ERR="inbox-send: 경고: 부가 기록 실패(events)" "$S/rc-send.sh" "$MC" alice 완료 "w" 2>"$TMP/se"); rc=$?
if [ "$rc" = 0 ] && grep -q "부가 기록 실패(events)" "$TMP/se" && ! grep -q "다시\|재시도\|재실행" "$TMP/se" && ! printf '%s' "$O" | grep -q "다시\|재시도\|재실행"; then
  ok "rc-send-meta-warn-no-retry AO 경고는 흘려보내고 종료 0·재실행 안내 없음"
else bad "rc-send-meta-warn-no-retry" "rc=$rc out=$O err=$(cat "$TMP/se")"; fi

# rc-claim-conflict-kept: 충돌 시 stderr CONFLICT…·종료 4·stdout 빈 출력
KC=$(mkchain "$TMP" rc-20260101-kc); mkreport "$KC" bob
"$S/rc-claim.sh" "$KC" alice src/ >/dev/null 2>&1
O=$("$S/rc-claim.sh" "$KC" bob src/a.txt 2>"$TMP/se"); rc=$?
if [ "$rc" = 4 ] && [ -z "$O" ] && [ "$(cat "$TMP/se")" = "CONFLICT src/a.txt↔alice:src/" ]; then
  ok "rc-claim-conflict-kept 종료 4·stdout 빈 출력·stderr CONFLICT 한 줄만"
else bad "rc-claim-conflict-kept" "rc=$rc out=$O err=$(cat "$TMP/se")"; fi

# rc-claim-unwatched-record: unwatched 면 worker report.md 에 같은 형식 한 줄, watched 면 기록 없음
case "$(sed -n '4p' "$KC/workers/bob/report.md")" in "- 미감시 전송 $KC/inbox.log "[0-2][0-9]:[0-5][0-9]) ok "rc-claim-unwatched-record report.md '- 진행:' 아래 기록" ;; *) bad "rc-claim-unwatched-record" "$(cat "$KC/workers/bob/report.md")" ;; esac
mkreport "$KC" bob; cp "$KC/workers/bob/report.md" "$TMP/rep.before"
O=$(AGENT_ORCHESTRATOR=$FAKE2 FAKE_W=watched "$S/rc-claim.sh" "$KC" bob src/b.txt 2>"$TMP/se"); rc=$?
[ "$rc" = 4 ] && [ -z "$O" ] && cmp -s "$KC/workers/bob/report.md" "$TMP/rep.before" && ok "rc-claim-unwatched-record watched 면 기록 없음" || bad "rc-claim watched" "rc=$rc $(cat "$KC/workers/bob/report.md")"
rm -f "$KC/workers/bob/report.md"
"$S/rc-claim.sh" "$KC" bob src/c.txt >/dev/null 2>"$TMP/se"; rc=$?
[ "$rc" = 4 ] && [ "$(cat "$TMP/se")" = "CONFLICT src/c.txt↔alice:src/" ] && ok "rc-claim-unwatched-record report.md 없으면 조용히 생략(stderr 이전과 동일)" || bad "rc-claim report 없음" "rc=$rc $(cat "$TMP/se")"

# rc-watch-subscribe: --subscribe 뒤 --list 에 경로, --unsubscribe 뒤 사라짐 (AO_STATE_ROOT 임시 폴더, pane 없음)
SC=$(mkchain "$TMP" rc-20260101-sub); SB="$SC/inbox.log"; SID=0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d
env -u HERDR_PANE_ID CLAUDE_CODE_SESSION_ID=$SID "$W" --subscribe "$SB" >/dev/null 2>"$TMP/se"; rc=$?
LST=$(env -u HERDR_PANE_ID CLAUDE_CODE_SESSION_ID=$SID "$AGENT_ORCHESTRATOR" inbox-subscribe --list 2>/dev/null)
if [ "$rc" = 0 ] && printf '%s\n' "$LST" | cut -f1 | grep -qxF "$SB"; then ok "rc-watch-subscribe --subscribe → inbox-subscribe --list 에 경로"
else bad "rc-watch-subscribe --subscribe" "rc=$rc list=$LST err=$(cat "$TMP/se")"; fi
env -u HERDR_PANE_ID CLAUDE_CODE_SESSION_ID=$SID "$W" --unsubscribe "$SB" >/dev/null 2>"$TMP/se"; rc=$?
LST=$(env -u HERDR_PANE_ID CLAUDE_CODE_SESSION_ID=$SID "$AGENT_ORCHESTRATOR" inbox-subscribe --list 2>/dev/null)
if [ "$rc" = 0 ] && ! printf '%s\n' "$LST" | cut -f1 | grep -qxF "$SB"; then ok "rc-watch-subscribe --unsubscribe → list 에서 사라짐"
else bad "rc-watch-subscribe --unsubscribe" "rc=$rc list=$LST err=$(cat "$TMP/se")"; fi
"$W" --subscribe relative.log >/dev/null 2>&1; [ $? = 2 ] && ok "rc-watch-subscribe 상대 경로 → 2" || bad "rc-watch-subscribe 상대 경로"
"$W" --unsubscribe >/dev/null 2>&1; [ $? = 2 ] && ok "rc-watch-subscribe 인자 부족 → 2" || bad "rc-watch-subscribe 인자 부족"

# ── 5. 문서 점검: 실행 중 세션에 agent-send 를 허용하는 문장이 없다 ────────────────
DOC_ROOT=$(cd "$HERE/../.." && pwd)
if grep -rn "agent-send.*알리는 것은\|agent-send.*허용" "$DOC_ROOT/SKILL.md" "$DOC_ROOT/references" >"$TMP/doc.out" 2>&1; then
  bad "문서에 agent-send 허용 예외가 남아 있음" "$(cat "$TMP/doc.out")"
else ok "문서에 agent-send 허용 예외 없음"; fi

echo "── 통과 $PASS · 실패 $FAIL"
[ "$FAIL" = 0 ]
