#!/usr/bin/env bash
# run-rc-tests.sh — review-chain 스크립트(rc-send/rc-watch/rc-claim) 호환 시험 (0.1.4)
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
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/     /'; }

# 시각·임시 경로를 고정 문자열로 바꾼다.
CUR_S=/nonexistent
norm() { sed -e "s#$TMP#<TMP>#g" -e "s#$CUR_S#<SCRIPTS>#g" -e 's/[0-2][0-9]:[0-5][0-9]:[0-5][0-9]/HH:MM:SS/g'; }

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
  "$SCRIPTS_DEFAULT/rc-send.sh" "$CRC" bob 질문 "동시 보내기 $i 끝" >/dev/null &
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
ls "$CRC"/inbox.log.lock* >/dev/null 2>&1 && bad "동시 기록 뒤 잠금 잔존" "$(ls -d "$CRC"/inbox.log.lock*)" || ok "동시 기록 뒤 잠금 잔존 없음"

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
for n in 1 2 3; do "$SCRIPTS_DEFAULT/rc-send.sh" "$WRC" alice 질문 "줄 $n" >/dev/null; done
P=$("$W" --pending "$WB")
case "$P" in "#1 "*"줄 1"$'\n'"#2 "*"줄 2"$'\n'"#3 "*"줄 3") ok "rc-watch --pending 은 #n 접두로 전부 출력" ;; *) bad "rc-watch --pending" "$P" ;; esac
"$W" --ack "$WB" 2; rc=$?
C=$(head -n 1 "$WB.cursor" 2>/dev/null)
[ "$rc" = 0 ] && [ "$C" = 2 ] && ok "rc-watch --ack 2 → $WB.cursor = 2" || bad "rc-watch --ack" "rc=$rc cursor=$C"
"$W" --ack "$WB" 1; C=$(head -n 1 "$WB.cursor")
[ "$C" = 2 ] && ok "rc-watch --ack 되감지 않음" || bad "rc-watch --ack 되감김" "cursor=$C"
P=$("$W" --pending "$WB")
case "$P" in "#3 "*"줄 3") ok "rc-watch --pending 은 cursor 뒤만" ;; *) bad "rc-watch --pending(ack 뒤)" "$P" ;; esac

# watch: cursor 뒤 줄부터 나오고, 켠 뒤 도착한 줄도 나온다
"$W" "$WB" > "$TMP/watch.out" 2>"$TMP/watch.err" & WPID=$!; disown "$WPID" 2>/dev/null
sleep 1.5
"$SCRIPTS_DEFAULT/rc-send.sh" "$WRC" bob 완료 "줄 4" >/dev/null
sleep 2.5
kill "$WPID" 2>/dev/null; pkill -P "$WPID" 2>/dev/null; pkill -f "tail -n .* -F $WB" 2>/dev/null; sleep 0.2
if grep -q "^#3 .*줄 3" "$TMP/watch.out" && grep -q "^#4 .*줄 4" "$TMP/watch.out" && ! grep -q "^#[12] " "$TMP/watch.out"; then
  ok "rc-watch 감시: cursor 뒤(#3)부터, 이후 도착(#4)도 출력"
else
  bad "rc-watch 감시" "out=$(cat "$TMP/watch.out") err=$(head -3 "$TMP/watch.err")"
fi

# ── 5. 문서 점검: 실행 중 세션에 agent-send 를 허용하는 문장이 없다 ────────────────
DOC_ROOT=$(cd "$HERE/../.." && pwd)
if grep -rn "agent-send.*알리는 것은\|agent-send.*허용" "$DOC_ROOT/SKILL.md" "$DOC_ROOT/references" >"$TMP/doc.out" 2>&1; then
  bad "문서에 agent-send 허용 예외가 남아 있음" "$(cat "$TMP/doc.out")"
else ok "문서에 agent-send 허용 예외 없음"; fi

echo "── 통과 $PASS · 실패 $FAIL"
[ "$FAIL" = 0 ]
