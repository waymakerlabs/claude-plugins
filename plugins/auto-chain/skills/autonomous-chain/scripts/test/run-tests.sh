#!/usr/bin/env bash
# run-tests.sh — auto-chain 2.4.0 스크립트 시험 (가짜 codex·opencode·herdr, 실제 agent-orchestrator 개발 사본)
#
# 사용: scripts/test/run-tests.sh
# 실제 herdr pane·리뷰어를 부르지 않는다. PATH 앞에 임시 폴더를 두고 가짜 실행 파일을 만든다.
# pane worker 스크립트는 리포의 tools/agent-orchestrator(개발 사본)를 AGENT_ORCHESTRATOR로 부르고,
# 그 어댑터가 가짜 herdr를 부른다. HOME은 임시 폴더로 바꿔 실제 설정·transcript를 읽지 않는다.
# 결과: 케이스마다 "PASS|FAIL <이름> — <기대> / <실제>" 한 줄, 끝에 집계. 실패가 있으면 exit 1.
# bash 3.2 호환.

# 시험 판정은 "[ 조건 ] && ok … || bad …" 형태를 쓴다(ok는 항상 0을 돌려준다)
# shellcheck disable=SC2015
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS=$(cd "$HERE/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/ac22-test.XXXXXX")
REAL_GIT=$(command -v git)
export REAL_GIT
FAKE="$T/bin"
mkdir -p "$FAKE"
export PATH="$FAKE:$PATH"
export FAKE_DIR="$T/fake"
mkdir -p "$FAKE_DIR"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "PASS $1 — $2"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1 — 기대 $2 / 실제 $3"; }
# done 파일 키 읽기
key() { grep -E "^$2=" "$1" 2>/dev/null | head -1 | cut -d= -f2-; }
expect_keys() {  # $1 이름, $2 done 파일, 나머지 "k=v"
  local name=$1 f=$2 want got miss=""
  shift 2
  for want in "$@"; do
    got="${want%%=*}=$(key "$f" "${want%%=*}")"
    [ "$got" = "$want" ] || miss="$miss $want(실제 $got)"
  done
  if [ -z "$miss" ]; then ok "$name" "$*"; else bad "$name" "$*" "${miss# }"; fi
}

# ───────── 가짜 codex: FAKE_MODE = ship | exit7 | noverdict | modify | sleep
cat > "$FAKE/codex" <<'SH'
#!/usr/bin/env bash
out=""; repo=""; s_ro=0; c_ro=0
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift ;;
    -C) repo=$2; shift ;;
    -s) [ "${2:-}" = read-only ] && s_ro=1; shift ;;
    -c) [ "${2:-}" = 'sandbox_mode="read-only"' ] && c_ro=1; shift ;;
  esac
  shift
done
cat > /dev/null
echo "OpenAI Codex (fake)"
# 실제 codex처럼: 두 샌드박스 인자가 모두 있어야 read-only
if [ $s_ro = 1 ] && [ $c_ro = 1 ]; then echo "sandbox: read-only"; else echo "sandbox: danger-full-access"; fi
case "${FAKE_MODE:-ship}" in
  ship) printf '# 판정: SHIP\n\n## 검증 원장\n- ok\n' > "$out" ;;
  exit7) echo "boom" >&2; exit 7 ;;
  noverdict) printf '\n검토를 마치지 못했다\n' > "$out" ;;
  modify) echo changed >> "$repo/a.txt"; printf '# 판정: SHIP\n' > "$out" ;;
  sleep) exec sleep 30 ;;
  ignoreterm) trap '' TERM; i=0; while [ $i -lt 75 ]; do sleep 0.2; i=$((i + 1)); done ;;
esac
exit 0
SH

# ───────── 가짜 opencode: headless-run.sh의 worker:opencode-<agent> 시험용
cat > "$FAKE/opencode" <<'SH'
#!/usr/bin/env bash
# 실제 opencode(yargs)처럼 -f/--file은 배열: 다음 플래그 전까지 오는 값을 모두 파일로 받는다.
# 파일로 받은 값이 없는 경로면 실제와 같이 "File not found"로 끝난다(office 실측).
shift  # run
infile=0
for a in "$@"; do
  case "$a" in
    -f|--file) infile=1 ;;
    -*) infile=0 ;;
    *) if [ $infile = 1 ] && [ ! -e "$a" ]; then printf 'Error: File not found: %s\n' "$a"; exit 1; fi ;;
  esac
done
printf '\033[32m> reading request\033[0m\n'
printf '# 판정: SHIP\n(이전 회차 인용 — 닫히지 않음)\n'
printf 'tool: read file\n'
printf '# 판정: BLOCK\n\n## BLOCK\n- B1 x.sh:3 근거\nREVIEW-DONE\n'
exit 0
SH

# ───────── 가짜 herdr: 상태는 $FAKE_DIR 파일로 조정
cat > "$FAKE/herdr" <<'SH'
#!/usr/bin/env bash
D=$FAKE_DIR
echo "herdr $*" >> "$D/calls.log"
case "$1 $2" in
  "status server") echo "status: running" ;;
  "agent list")
    if [ -f "$D/started" ]; then n=$(cat "$D/started"); echo "{\"result\":{\"agents\":[{\"name\":\"$n\"}]}}"
    else echo '{"result":{"agents":[]}}'; fi ;;
  "pane layout") echo '{"result":{"layout":{"panes":[{"pane_id":"w1:p1","rect":{"x":0,"y":0,"height":50}}]}}}' ;;
  "pane split") echo '{"result":{"pane":{"pane_id":"w1:p9"}}}' ;;
  "agent start") echo "$3" > "$D/started"; echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent prompt")
    # 실제 herdr처럼: 빠른 완료(done·idle)면 --until done 없이는 대기가 성공하지 않는다
    st=$(cat "$D/status-$3" 2>/dev/null || echo "")
    case "$st" in
      done|idle)
        case " $* " in *" --until done "*) ;; *) echo '{"error":{"code":"timeout"}}'; exit 1 ;; esac ;;
    esac
    echo '{"result":{"ok":true}}' ;;
  "agent get")
    st=$(cat "$D/status-$3" 2>/dev/null || echo "")
    if [ -z "$st" ]; then echo '{"error":{"code":"agent_not_found"}}'; exit 1; fi
    echo "{\"result\":{\"agent\":{\"agent\":\"${FAKE_KIND:-claude}\",\"agent_status\":\"$st\",\"cwd\":\"/tmp/x\",\"agent_session\":{\"value\":\"uuid-1\"}}}}" ;;
  *) echo '{}' ;;
esac
SH
# ───────── 가짜 git: FAKE_GIT_FAIL=status 면 status만 exit 128, 그 밖은 실제 git
cat > "$FAKE/git" <<'SH'
#!/usr/bin/env bash
if [ "${FAKE_GIT_FAIL:-}" = status ]; then
  for a in "$@"; do [ "$a" = status ] && { echo "fatal: fake" >&2; exit 128; }; done
fi
exec "$REAL_GIT" "$@"
SH
chmod +x "$FAKE/codex" "$FAKE/opencode" "$FAKE/herdr" "$FAKE/git"
# 2.2.1: 실행기는 ~/.opencode/bin/opencode를 우선하므로 시험은 가짜를 명시한다
export REVIEW_OPENCODE_BIN="$FAKE/opencode"

# ───────── 시험용 git 리포
R="$T/repo"; mkdir -p "$R"
git -C "$R" init -q
echo a > "$R/a.txt"
git -C "$R" -c user.email=t@t -c user.name=t add a.txt
git -C "$R" -c user.email=t@t -c user.name=t commit -qm init
REQ="$T/req.md"; echo "# 요청" > "$REQ"
O="$T/out"; mkdir -p "$O"
RR="$SCRIPTS/review-run.sh"

echo "== review-run"
FAKE_MODE=ship "$RR" codex-cli "$REQ" "$O/r1.md" "$O/d1" "$R" > /dev/null; rc=$?
[ $rc = 0 ] || bad rr-ship-rc 0 $rc
expect_keys rr-ship "$O/d1" exit=0 verdict=SHIP ro=same sandbox=read-only reviewer=codex-cli effort=high

FAKE_MODE=exit7 "$RR" codex-cli "$REQ" "$O/r2.md" "$O/d2" "$R" > /dev/null; rc=$?
[ $rc = 7 ] && ok rr-exit7-rc "rc=7" || bad rr-exit7-rc 7 $rc
expect_keys rr-exit7 "$O/d2" exit=7 verdict=none result_bytes=0

FAKE_MODE=noverdict "$RR" codex-cli "$REQ" "$O/r3.md" "$O/d3" "$R" > /dev/null
expect_keys rr-noverdict "$O/d3" exit=0 verdict=none ro=same

FAKE_MODE=modify "$RR" codex-cli "$REQ" "$O/r4.md" "$O/d4" "$R" > /dev/null
expect_keys rr-modify "$O/d4" exit=0 verdict=SHIP ro=changed
git -C "$R" checkout -q -- a.txt

echo "old-result" > "$O/r5.md"; echo "run_id=old" > "$O/d5"; echo "old-log" > "$O/d5.log"
FAKE_MODE=ship "$RR" codex-cli "$REQ" "$O/r5.md" "$O/d5" "$R" > "$O/run5.out"
rid=$(sed -n 's/^RUN \([^ ]*\) pid=.*/\1/p' "$O/run5.out")
n=0; for f in "$O/r5.md.stale-$rid" "$O/d5.stale-$rid" "$O/d5.log.stale-$rid"; do [ -f "$f" ] && n=$((n + 1)); done
if [ "$n" = 3 ] && [ "$(key "$O/d5" run_id)" = "$rid" ] && [ "$(cat "$O/r5.md.stale-$rid")" = old-result ]; then
  ok rr-stale "stale 3개 이동, 새 run_id=$rid"
else bad rr-stale "stale 3개·새 run_id" "stale $n개 run_id=$(key "$O/d5" run_id) rid=$rid"; fi

FAKE_MODE="sleep" "$RR" codex-cli "$REQ" "$O/r6.md" "$O/d6" "$R" > "$O/run6.out" &
bg=$!
i=0; while [ ! -f "$O/d6.run" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
sleep 0.3
kill -TERM "$bg"; wait "$bg"; rc=$?
[ $rc = 143 ] && ok rr-sigterm-rc "rc=143" || bad rr-sigterm-rc 143 $rc
expect_keys rr-sigterm "$O/d6" exit=signal signal=TERM verdict=none
pid6=$(sed -n 's/^RUN [^ ]* pid=\([0-9]*\).*/\1/p' "$O/run6.out")
[ "$pid6" = "$bg" ] && ok rr-runline "RUN 줄 pid=$bg" || bad rr-runline "pid=$bg" "pid=$pid6"

"$RR" bogus "$REQ" "$O/r8.md" "$O/d8" "$R" 2> /dev/null; rc=$?
[ $rc = 2 ] && [ ! -f "$O/d8" ] && ok rr-badarg "rc=2, done 없음" || bad rr-badarg "rc=2 done 없음" "rc=$rc"

# 2.4.0: opencode 리뷰어는 제거됐다 — done 파일 없이 exit 2, 안내 메시지
for rv in opencode-sol opencode-build; do
  "$RR" $rv "$REQ" "$O/r-$rv.md" "$O/d-$rv" "$R" > /dev/null 2> "$O/e-$rv.txt"; rc=$?
  if [ $rc = 2 ] && [ ! -f "$O/d-$rv" ] && grep -q '2.4.0부터 리뷰어는 codex-cli만 지원한다' "$O/e-$rv.txt"; then
    ok rr-removed-$rv "rc=2, done 없음, 안내 메시지"
  else bad rr-removed-$rv "rc=2 done 없음 안내" "rc=$rc done=$([ -f "$O/d-$rv" ] && echo 있음 || echo 없음)"; fi
done

# F2: snapshot의 git 실패를 삼키지 않는다
FAKE_GIT_FAIL=status FAKE_MODE=ship "$RR" codex-cli "$REQ" "$O/r10.md" "$O/d10" "$R" > /dev/null
expect_keys rr-snapshot-gitfail "$O/d10" tree_before=error tree_after=error ro=unverified

# F6: TERM을 무시하는 자식 — 유예(REVIEW_KILL_GRACE) 뒤 KILL, done 기록
FAKE_MODE=ignoreterm REVIEW_KILL_GRACE=1 "$RR" codex-cli "$REQ" "$O/r11.md" "$O/d11" "$R" > /dev/null &
bg=$!
i=0; while [ ! -f "$O/d11.run" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
sleep 0.3
t0=$(date +%s); kill -TERM "$bg"; wait "$bg"; rc=$?; el=$(( $(date +%s) - t0 ))
[ $rc = 143 ] && [ "$el" -le 6 ] && ok rr-sigterm-ignore "rc=143, ${el}초 안에 종료" || bad rr-sigterm-ignore "rc=143 ≤6초" "rc=$rc ${el}초"
expect_keys rr-sigterm-ignore-done "$O/d11" exit=signal signal=TERM

# F7: <done>.run 한 줄 = RUN <run_id> pid=<pid> start=<신원>, stdout 줄과 같다
FAKE_MODE=ship "$RR" codex-cli "$REQ" "$O/r12.md" "$O/d12" "$R" > "$O/run12.out"
l=$(head -n 1 "$O/d12.run" 2> /dev/null); n=$(wc -l < "$O/d12.run" 2> /dev/null | tr -d ' ')
rid=$(key "$O/d12" run_id)
case "$l" in "RUN $rid pid="[0-9]*" start="?*) [ "$n" = 1 ] && [ "$l" = "$(cat "$O/run12.out")" ] && ok rr-runfile "한 줄 RUN·pid·start" || bad rr-runfile "한 줄, stdout과 같음" "줄 $n" ;;
  *) bad rr-runfile "RUN $rid pid=… start=…" "$l" ;; esac

# F10 음성 대조: sandbox 인자 하나를 빼면 가짜 codex가 read-only를 찍지 않는다
sed "s/ -c 'sandbox_mode=\"read-only\"'//" "$RR" > "$T/rr-nosb.sh"
if grep -q sandbox_mode "$T/rr-nosb.sh"; then bad rr-neg-sandbox "sed 적용" "sandbox_mode 남음"; else
  FAKE_MODE=ship bash "$T/rr-nosb.sh" codex-cli "$REQ" "$O/r13.md" "$O/d13" "$R" > /dev/null
  expect_keys rr-neg-sandbox "$O/d13" sandbox=unverified
fi

# F5: 문서의 CMD 구성(sol-review.md §3)이 따옴표·셸 구문이 든 경로에서도 안전하다
cmdline=$(grep -m 1 '^CMD=' "$SCRIPTS/../references/sol-review.md")
QD="$T/q'd \$(touch $T/pwned) dir"; mkdir -p "$QD"
REQ_KEEP=$REQ
# 아래 변수는 eval한 문서 CMD 줄이 읽는다
# shellcheck disable=SC2034
S=$(cd "$SCRIPTS/.." && pwd)
# shellcheck disable=SC2034
REVIEWER=codex-cli
REQ="$QD/it's req.md"; cp "$REQ_KEEP" "$REQ"
# shellcheck disable=SC2034
RES="$QD/res.md"
DONE="$QD/d.done"
# shellcheck disable=SC2034
REPO=$R
CMD=""; eval "$cmdline"
FAKE_MODE=ship bash -c "$CMD" > /dev/null 2>&1
if [ "$(key "$DONE" verdict)" = SHIP ] && [ ! -e "$T/pwned" ]; then ok doc-cmd-quote "따옴표 경로 실행·주입 없음"
else bad doc-cmd-quote "verdict=SHIP, 주입 없음" "verdict=$(key "$DONE" verdict) pwned=$([ -e "$T/pwned" ] && echo y || echo n) CMD=$CMD"; fi
REQ=$REQ_KEEP; unset S REVIEWER RES DONE REPO CMD

# F3: 안전 예외 태그가 요청 형식·매핑·SKILL 규칙에 모두 있다
SR="$SCRIPTS/../references/sol-review.md"; SK="$SCRIPTS/../SKILL.md"
if grep -q '\[안전\]' "$SR" && grep -E '^[[:space:]]*\| MAJOR ' "$SR" | grep -q '\[안전\]' && grep -q '\[안전\]' "$SK"; then ok doc-safety-tag "[안전] 태그 요청·매핑·SKILL"
else bad doc-safety-tag "[안전] 3곳" "없음"; fi

RW="$SCRIPTS/review-wait.sh"
export WAIT_INTERVAL=1
echo "== headless-run"
HR="$SCRIPTS/headless-run.sh"
"$HR" opencode:work-x "$REQ" "$O/h1" "$R" > "$O/h1.out"; rc=$?
expect_keys hr-opencode "$O/h1" exit=0 cli=opencode:work-x changed=no
grep -q '^RUN .* pid=[0-9]* start=' "$O/h1.run" && [ "$(cat "$O/h1.run")" = "$(cat "$O/h1.out")" ] && ok hr-runfile "RUN 줄 = stdout" || bad hr-runfile "RUN 줄" "$(cat "$O/h1.run" 2>/dev/null)"
grep -q 'File not found' "$O/h1.log" && bad hr-msg-order "메시지가 -f 앞" "File not found" || ok hr-msg-order "메시지가 -f 앞(파일로 읽히지 않음)"
"$HR" bogus "$REQ" "$O/h2" "$R" 2> /dev/null; rc=$?
[ $rc = 2 ] && [ ! -f "$O/h2" ] && ok hr-badarg "rc=2, done 없음" || bad hr-badarg "rc=2 done 없음" "rc=$rc"
"$RW" "$O/h1" "$(sed -n 's/^RUN [^ ]* pid=\([0-9]*\).*/\1/p' "$O/h1.run")" 3 > /dev/null 2>&1; rc=$?
[ $rc = 0 ] && ok hr-wait "review-wait.sh로 회수 rc=0" || bad hr-wait 0 "rc=$rc"


RW="$SCRIPTS/review-wait.sh"
export WAIT_INTERVAL=1
"$RW" "$O/d1" $$ 5 > "$O/w1.out"; rc=$?
[ $rc = 0 ] && grep -q '^verdict=SHIP$' "$O/w1.out" && ok rw-done "rc=0, 내용 출력" || bad rw-done 0 $rc
sh -c 'exit 0' & dead=$!; wait "$dead"
"$RW" "$O/none" "$dead" 5 > "$O/w2.out" 2> /dev/null; rc=$?
[ $rc = 3 ] && grep -q '^exit=lost$' "$O/w2.out" && ok rw-lost "rc=3 exit=lost" || bad rw-lost 3 $rc
sleep 30 & live=$!
"$RW" "$O/none" "$live" 2 > "$O/w3.out" 2> /dev/null; rc=$?
kill "$live" 2> /dev/null; wait "$live" 2> /dev/null
[ $rc = 4 ] && grep -q '^exit=timeout$' "$O/w3.out" && ok rw-timeout "rc=4" || bad rw-timeout 4 $rc

# F4: pid가 살아 있어도 <done>.run의 신원이 다르면 lost
sleep 30 & live=$!
echo "RUN x pid=$live start=Mon Jan  1 00:00:00 2001" > "$O/dr.run"
"$RW" "$O/dr" "$live" 3 > "$O/w4.out" 2> /dev/null; rc=$?
[ $rc = 3 ] && grep -q '^exit=lost$' "$O/w4.out" && ok rw-pidreuse "신원 불일치 rc=3" || bad rw-pidreuse 3 $rc
printf 'RUN y pid=%s start=%s\n' "$live" "$(LC_ALL=C ps -o lstart= -p "$live" | tr -s ' ' | sed 's/^ //;s/ $//')" > "$O/dr2.run"
"$RW" "$O/dr2" "$live" 2 > /dev/null 2>&1; rc=$?
kill "$live" 2> /dev/null; wait "$live" 2> /dev/null
[ $rc = 4 ] && ok rw-identity-ok "신원 일치 rc=4(timeout)" || bad rw-identity-ok 4 $rc

# ───────── pane worker 시험 공통: 개발 사본 agent-orchestrator, 격리 HOME
REPO_ROOT=$(cd "$SCRIPTS/../../../../.." && pwd)
AO_DEV="$REPO_ROOT/tools/agent-orchestrator"
[ -x "$AO_DEV/bin/agent-orchestrator" ] || { echo "FAIL ao-dev — 기대 $AO_DEV/bin/agent-orchestrator / 실제 없음"; exit 1; }
export AGENT_ORCHESTRATOR="$AO_DEV/bin/agent-orchestrator"
export HOME="$T/home"; mkdir -p "$HOME"
export HERDR_ENV=1 HERDR_WORKSPACE_ID=w1
unset HERDR_PANE_ID HERDR_TAB_ID AGENT_ORCHESTRATOR_BACKEND AGENT_ORCHESTRATOR_HOME
# 실제 herdr를 건드리지 않음을 보장: 가짜가 아니면 즉시 중단(2.3.0 codex NOTE)
if [ "$(command -v herdr)" = "$FAKE/herdr" ]; then ok ao-fake-herdr "PATH의 herdr = 가짜"
else echo "FAIL ao-fake-herdr — 기대 $FAKE/herdr / 실제 $(command -v herdr) — 실제 herdr 접촉 위험으로 중단"; exit 1; fi

echo "== agent-stall-watch"
SW="$SCRIPTS/agent-stall-watch.sh"
J="$T/jsonl"; mkdir -p "$J"
# 분 전 → ISO UTC
ago() { python3 -c "import datetime,sys;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=float(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%S.000Z'))" "$1"; }
mk() {  # $1 파일, $2 진척 분 전, $3 api-request 수(진척 뒤)
  local f=$1 i
  {
    echo '{"type":"permission-mode","permissionMode":"default"}'
    echo "{\"type\":\"user\",\"timestamp\":\"$(ago 60)\",\"message\":{\"role\":\"user\",\"content\":\"시작\"}}"
    echo "{\"type\":\"assistant\",\"timestamp\":\"$(ago "$2")\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\"}]}}"
    echo "{\"type\":\"assistant\",\"timestamp\":\"$(ago 0.5)\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"  \"}]}}"
    echo "{\"type\":\"attachment\",\"timestamp\":\"$(ago 0.4)\"}"
    i=0; while [ $i -lt "$3" ]; do echo "{\"type\":\"api-request\",\"timestamp\":\"$(ago 1)\"}"; i=$((i + 1)); done
  } > "$f"
}
mk "$J/normal.jsonl" 1 1
mk "$J/stale.jsonl" 15 0
mk "$J/api.jsonl" 20 5
TSV="$T/watch.tsv"
printf '# task\tagent\tjsonl\n' > "$TSV"
for c in normal stale api missing; do printf 'T-%s\tag-%s\t%s\n' "$c" "$c" "$J/$c.jsonl" >> "$TSV"; done

exp_for() {  # $1 case, $2 status → 기대 접두(빈 값 = 출력 없음)
  case "$2" in
    blocked) echo "T-$1 권한·입력 대기 · status=blocked (실측)" ;;
    done) echo "T-$1 끝남 · status=done" ;;
    working)
      case "$1" in
        normal) echo "" ;;
        stale) echo "T-stale 정지 후보 · 마지막 진척 15분 전 · working (실측)" ;;
        api) echo "T-api API 재시도 반복 · 진척 뒤 api-request 5건 · 20분 (실측)" ;;
        missing) echo "T-missing 감시 불가 · jsonl 읽기 실패 (UNVERIFIED)" ;;
      esac ;;
  esac
}
for st in working blocked "done"; do
  for c in normal stale api missing; do echo "$st" > "$FAKE_DIR/status-ag-$c"; done
  SD="$T/state-$st"
  out=$(STALL_ONCE=1 STALL_STATE_DIR="$SD" "$SW" "$TSV")
  for c in normal stale api missing; do
    want=$(exp_for "$c" "$st")
    got=$(printf '%s\n' "$out" | grep "^T-$c " || true)
    if [ "$got" = "$want" ]; then ok "sw-$c-$st" "'${want:-출력 없음}'"; else bad "sw-$c-$st" "'${want:-출력 없음}'" "'${got:-출력 없음}'"; fi
  done
  out2=$(STALL_ONCE=1 STALL_STATE_DIR="$SD" "$SW" "$TSV")
  [ -z "$out2" ] && ok "sw-dedupe-$st" "두 번째 회차 출력 없음" || bad "sw-dedupe-$st" "출력 없음" "$out2"
done
# agent 없음(herdr agent get 실패)
rm -f "$FAKE_DIR/status-ag-normal"
out=$(STALL_ONCE=1 STALL_STATE_DIR="$T/state-x" "$SW" "$TSV" | grep '^T-normal ')
[ "$out" = "T-normal 감시 불가 · agent 상태 읽기 실패 status=unknown (UNVERIFIED)" ] && ok sw-noagent "감시 불가 status=unknown" || bad sw-noagent "감시 불가" "$out"

# F8: 마지막 진척 뒤 깨진 JSON 줄 → 감시 불가. 창 첫 줄의 깨진 줄은 무시
mk "$J/bad.jsonl" 15 0; echo '{"type":"assistant","timestamp' >> "$J/bad.jsonl"
{ echo '{broken'; cat "$J/normal.jsonl"; } > "$J/badhead.jsonl"
printf 'T-bad\tag-bad\t%s\nT-badhead\tag-badhead\t%s\n' "$J/bad.jsonl" "$J/badhead.jsonl" > "$T/w8.tsv"
echo working > "$FAKE_DIR/status-ag-bad"; echo working > "$FAKE_DIR/status-ag-badhead"
out=$(STALL_ONCE=1 STALL_STATE_DIR="$T/state-8" "$SW" "$T/w8.tsv")
[ "$(printf '%s\n' "$out" | grep '^T-bad ')" = "T-bad 감시 불가 · jsonl 읽기 실패 (UNVERIFIED)" ] && ok sw-badjson "진척 뒤 깨진 줄 → 감시 불가" || bad sw-badjson "감시 불가" "$out"
! printf '%s\n' "$out" | grep -q '^T-badhead ' && ok sw-badjson-head "진척 앞 깨진 줄은 판정에 영향 없음" || bad sw-badjson-head "출력 없음" "$out"
# r2 MINOR: 창 첫 줄이 깨졌고 그 뒤 진척이 없으면 감시 불가(첫 줄도 온전한 줄로 본다)
# codex r2 반례 그대로: 깨진 첫 줄 → 15분 전 api-request (진척 항목 없음)
{ echo '{broken'; echo "{\"type\":\"api-request\",\"timestamp\":\"$(ago 15)\"}"; } > "$J/badfirst-stale.jsonl"
mk "$J/partial.jsonl" 0 0; printf '%s' '{"type":"assistant","timest' >> "$J/partial.jsonl"
printf 'T-bfs\tag-bfs\t%s\nT-part\tag-part\t%s\n' "$J/badfirst-stale.jsonl" "$J/partial.jsonl" > "$T/w8b.tsv"
echo working > "$FAKE_DIR/status-ag-bfs"; echo working > "$FAKE_DIR/status-ag-part"
out=$(STALL_ONCE=1 STALL_STATE_DIR="$T/state-8b" "$SW" "$T/w8b.tsv")
[ "$(printf '%s\n' "$out" | grep '^T-bfs ')" = "T-bfs 감시 불가 · jsonl 읽기 실패 (UNVERIFIED)" ] && ok sw-badfirst-stale "첫 줄 깨짐 + 진척 없음 → 감시 불가" || bad sw-badfirst-stale "감시 불가" "$out"
! printf '%s\n' "$out" | grep -q '^T-part ' && ok sw-partial-tail "기록 중인 마지막 줄(개행 없음)은 무시" || bad sw-partial-tail "출력 없음" "$out"

# F9: 중복 억제 키 — T/a·T:a 충돌 없음, agent가 바뀌면(재기동) 새 알림
for c in sa sb; do echo working > "$FAKE_DIR/status-ag-$c"; done
printf 'T/a\tag-sa\t%s\nT:a\tag-sb\t%s\n' "$J/stale.jsonl" "$J/stale.jsonl" > "$T/w9.tsv"
out=$(STALL_ONCE=1 STALL_STATE_DIR="$T/state-9" "$SW" "$T/w9.tsv")
[ "$(printf '%s\n' "$out" | grep -c '정지 후보')" = 2 ] && ok sw-key-collide "T/a·T:a 둘 다 알림" || bad sw-key-collide "2줄" "$out"
printf 'T/a\tag-sb\t%s\n' "$J/stale.jsonl" > "$T/w9.tsv"
out=$(STALL_ONCE=1 STALL_STATE_DIR="$T/state-9" "$SW" "$T/w9.tsv")
[ -n "$out" ] && ok sw-key-restart "agent 바뀌면 새 알림" || bad sw-key-restart "알림 1줄" "출력 없음"

# 2.3.0: 옛 이름 래퍼가 같은 출력을 낸다
out=$(STALL_ONCE=1 STALL_STATE_DIR="$T/state-w" "$SCRIPTS/herdr-stall-watch.sh" "$T/w9.tsv")
out2=$(STALL_ONCE=1 STALL_STATE_DIR="$T/state-w2" "$SW" "$T/w9.tsv")
[ -n "$out" ] && [ "$out" = "$out2" ] && ok sw-wrapper "옛 이름 래퍼 = 새 스크립트 출력" || bad sw-wrapper "같은 출력" "'$out' / '$out2'"
# 2.3.0: jsonl 칸 unsupported(transcript 10) → 상태만 감시
echo working > "$FAKE_DIR/status-ag-un"
printf 'T-un\tag-un\tunsupported\n' > "$T/w10.tsv"
out=$(STALL_ONCE=1 STALL_STATE_DIR="$T/state-10" "$SW" "$T/w10.tsv")
[ "$out" = "T-un 감시 불가 · transcript unsupported (상태만 감시)" ] && ok sw-transcript-unsupported "unsupported 줄" || bad sw-transcript-unsupported "transcript unsupported" "$out"
# 2.3.0: jsonl 칸이 비면 agent-transcript로 구한다. codex kind면 10 → unsupported
printf 'T-cx\tag-un\t\n' > "$T/w11.tsv"
out=$(FAKE_KIND=codex STALL_ONCE=1 STALL_STATE_DIR="$T/state-11" "$SW" "$T/w11.tsv")
[ "$out" = "T-cx 감시 불가 · transcript unsupported (상태만 감시)" ] && ok sw-transcript-kind10 "빈 jsonl + codex kind → unsupported" || bad sw-transcript-kind10 "transcript unsupported" "$out"
# 빈 jsonl + claude kind → agent-transcript가 격리 HOME의 transcript를 찾아 판정
mkdir -p "$HOME/.claude/projects/-tmp-x"; cp "$J/stale.jsonl" "$HOME/.claude/projects/-tmp-x/uuid-1.jsonl"
out=$(STALL_ONCE=1 STALL_STATE_DIR="$T/state-12" "$SW" "$T/w11.tsv")
[ "$out" = "T-cx 정지 후보 · 마지막 진척 15분 전 · working (실측)" ] && ok sw-transcript-lookup "빈 jsonl → agent-transcript 경로로 판정" || bad sw-transcript-lookup "정지 후보 15분" "$out"
# 2.3.0: 백엔드 없음(11)은 상태 읽기 실패와 구분해 rc를 보인다
out=$(AGENT_ORCHESTRATOR_BACKEND=none STALL_ONCE=1 STALL_STATE_DIR="$T/state-13" "$SW" "$T/w10.tsv")
[ "$out" = "T-un 감시 불가 · agent-orchestrator rc=11 (UNVERIFIED)" ] && ok sw-ao-rc "rc=11 줄" || bad sw-ao-rc "rc=11" "$out"
out=$(AGENT_ORCHESTRATOR="$T/none/agent-orchestrator" STALL_ONCE=1 "$SW" "$T/w10.tsv" 2>/dev/null); rc=$?
[ $rc = 12 ] && ok sw-ao-missing "진입점 없음 rc=12" || bad sw-ao-missing 12 "rc=$rc"

echo "== spawn-pane-worker"
BR="$T/brief.md"; echo brief > "$BR"
# 같은 케이스를 새 경로(이름 그대로)와 옛 이름 래퍼(접두 w-)로 돌린다
for SPV in new wrap; do
if [ "$SPV" = new ]; then SP="$SCRIPTS/spawn-pane-worker.sh"; px=""; else SP="$SCRIPTS/herdr-spawn-worker.sh"; px="w-"; fi
spawn() {  # $1 name, $2 effort, $3 첫 지시 뒤 상태
  rm -f "$FAKE_DIR/started"; echo "$3" > "$FAKE_DIR/status-$1"
  PERM_FLAGS=--dangerously-skip-permissions ROLE=none \
    "$SP" "$1" sonnet "$2" "$BR" w1:p1 2> "$T/spawn.err"
}
: > "$FAKE_DIR/calls.log"
out=$(spawn sp-a medium working); rc=$?
case "$out" in "OK name=sp-a pane=w1:p9 model=sonnet effort=medium status=working "*) ok "${px}sp-medium" "OK effort=medium status=working" ;; *) bad "${px}sp-medium" "OK effort=medium" "rc=$rc $out $(cat "$T/spawn.err")" ;; esac
grep -qF 'pane rename w1:p9 [WO] 작업자 sp-a' "$FAKE_DIR/calls.log" && ok "${px}sp-pane-label" "split 직후 [WO] 한글 pane 이름" || bad "${px}sp-pane-label" "pane rename w1:p9 [WO] 작업자 sp-a" "$(grep 'pane rename' "$FAKE_DIR/calls.log")"
grep -q 'agent start sp-a .* --effort medium' "$FAKE_DIR/calls.log" && ok "${px}sp-medium-arg" "--effort medium 전달" || bad "${px}sp-medium-arg" "--effort medium" "$(grep 'agent start' "$FAKE_DIR/calls.log")"
# --parent 호환: HERDR_PANE_ID 없이 5번째 인자가 배치 기준이 된다
grep -q 'pane layout --pane w1:p1' "$FAKE_DIR/calls.log" && ok "${px}sp-parent" "5번째 인자 → pane-open --parent w1:p1" || bad "${px}sp-parent" "pane layout --pane w1:p1" "$(grep 'pane layout' "$FAKE_DIR/calls.log")"
out=$(spawn sp-b high "done"); rc=$?
case "$out" in "OK name=sp-b "*"status=done "*) ok "${px}sp-fastdone" "OK status=done (빠른 완료)" ;; *) bad "${px}sp-fastdone" "OK status=done" "rc=$rc $out $(cat "$T/spawn.err")" ;; esac
out=$(spawn sp-c high idle); rc=$?
case "$out" in "OK name=sp-c "*"status=idle "*) ok "${px}sp-idle" "OK status=idle" ;; *) bad "${px}sp-idle" "OK status=idle" "rc=$rc $out" ;; esac
out=$(spawn sp-d high blocked); rc=$?
[ $rc = 6 ] && ok "${px}sp-blocked" "rc=6" || bad "${px}sp-blocked" 6 "rc=$rc $out"
out=$(spawn sp-e max working); rc=$?
[ $rc = 2 ] && ok "${px}sp-badeffort" "effort max 거부 rc=2" || bad "${px}sp-badeffort" 2 "rc=$rc"
# jsonl: transcript 파일이 있으면 그 경로, codex kind면 unsupported
out=$(spawn sp-j high working); out=${out% parent_watch=none}   # 2.8.0: 실제 AO는 부모 대기자가 없으면 끝에 칸을 붙인다
case "$out" in *" jsonl=$HOME/.claude/projects/-tmp-x/uuid-1.jsonl") ok "${px}sp-jsonl" "jsonl=agent-transcript 경로" ;; *) bad "${px}sp-jsonl" "jsonl=…/uuid-1.jsonl" "$out" ;; esac
out=$(FAKE_KIND=codex spawn sp-k high working); out=${out% parent_watch=none}
case "$out" in *" jsonl=unsupported") ok "${px}sp-jsonl-unsupported" "transcript 10 → jsonl=unsupported" ;; *) bad "${px}sp-jsonl-unsupported" "jsonl=unsupported" "$out" ;; esac

# F10 음성 대조(2.3.0 이전): 변형 대상은 실제 구현 위치인 어댑터 사본이다.
# --until done 을 빼면 빠른 완료에서 가짜 herdr가 실패시킨다
rm -rf "$T/ao"; cp -R "$AO_DEV" "$T/ao"
sed 's/ --until "done"//' "$AO_DEV/adapters/herdr.sh" > "$T/ao/adapters/herdr.sh"
if grep -q -- '--until "done"' "$T/ao/adapters/herdr.sh" || ! grep -q -- '--until "done"' "$AO_DEV/adapters/herdr.sh"; then bad "${px}sp-neg-until" "sed 적용(원본엔 있고 사본엔 없음)" "아님"; else
  rm -f "$FAKE_DIR/started"; echo "done" > "$FAKE_DIR/status-sp-f"
  AGENT_ORCHESTRATOR_HOME="$T/ao" PERM_FLAGS=--dangerously-skip-permissions ROLE=none \
    "$SP" sp-f sonnet high "$BR" w1:p1 > /dev/null 2>&1; rc=$?
  [ $rc = 6 ] && ok "${px}sp-neg-until" "어댑터 사본에서 --until done 없으면 rc=6" || bad "${px}sp-neg-until" 6 "rc=$rc"
fi
done

# 2.3.0 spawn 계약: agent-orchestrator의 10·11·12는 같은 코드 그대로, stderr에 사유
cat > "$FAKE/fake-ao" <<'AO'
#!/usr/bin/env bash
echo "ao $*" >> "$FAKE_DIR/ao.log"
case "$1" in
  whoami) [ -n "${FAKE_AO_WHOAMI:-}" ] && { echo "$FAKE_AO_WHOAMI"; exit 0; }; echo "agent-orchestrator: 자기 pane id 없음" >&2; exit 3 ;;
  list) exit 0 ;;
  pane-open) echo "agent-orchestrator: 사유-$FAKE_AO_RC" >&2; exit "$FAKE_AO_RC" ;;
esac
exit 4
AO
chmod +x "$FAKE/fake-ao"
SP="$SCRIPTS/spawn-pane-worker.sh"
for code in 10 11 12; do
  AGENT_ORCHESTRATOR="$FAKE/fake-ao" FAKE_AO_RC=$code PERM_FLAGS=x ROLE=none \
    "$SP" sp-x sonnet high "$BR" w1:p1 > /dev/null 2> "$T/spawn.err"; rc=$?
  [ $rc = "$code" ] && grep -q "rc=$code" "$T/spawn.err" && grep -q "사유-$code" "$T/spawn.err" \
    && ok "spc-pass-$code" "rc=$code 그대로, stderr 사유" || bad "spc-pass-$code" "rc=$code + 사유" "rc=$rc $(cat "$T/spawn.err")"
done
AGENT_ORCHESTRATOR="$FAKE/fake-ao" FAKE_AO_RC=4 PERM_FLAGS=x ROLE=none "$SP" sp-x sonnet high "$BR" w1:p1 > /dev/null 2>&1; rc=$?
[ $rc = 4 ] && ok spc-place-4 "pane-open 4 → 배치 실패 4" || bad spc-place-4 4 "rc=$rc"
grep -q -- 'pane-open \[WO\] 작업자 sp-x --parent w1:p1 --cwd ' "$FAKE_DIR/ao.log" && ok spc-parent-arg "5번째 인자 → --parent" || bad spc-parent-arg "--parent w1:p1" "$(grep pane-open "$FAKE_DIR/ao.log" | tail -1)"
AGENT_ORCHESTRATOR="$T/none/agent-orchestrator" PERM_FLAGS=x ROLE=none "$SP" sp-x sonnet high "$BR" w1:p1 > /dev/null 2> "$T/spawn.err"; rc=$?
[ $rc = 12 ] && grep -q 'adapter error' "$T/spawn.err" && ok spc-missing-12 "진입점 없음 rc=12" || bad spc-missing-12 12 "rc=$rc"
: > "$FAKE_DIR/ao.log"
AGENT_ORCHESTRATOR="$FAKE/fake-ao" FAKE_AO_WHOAMI=w1:p7 FAKE_AO_RC=10 PERM_FLAGS=x ROLE=none "$SP" sp-x sonnet high "$BR" > /dev/null 2>&1
grep -q -- '--parent w1:p7' "$FAKE_DIR/ao.log" && ok spc-whoami "5번째 인자 없으면 whoami가 기준" || bad spc-whoami "--parent w1:p7" "$(cat "$FAKE_DIR/ao.log")"
AGENT_ORCHESTRATOR="$FAKE/fake-ao" PERM_FLAGS=x ROLE=none "$SP" sp-x sonnet high "$BR" > /dev/null 2>&1; rc=$?
[ $rc = 2 ] && ok spc-noparent "기준 pane 없음 rc=2" || bad spc-noparent 2 "rc=$rc"

# 2.8.0 부모 pane 받은편지함 감시 판정: 가짜 AO가 inbox-wait --status·inbox-watch --state에 답한다
cat > "$FAKE/fake-ao2" <<'AO'
#!/usr/bin/env bash
echo "ao $*" >> "$FAKE_DIR/ao2.log"
case "$1" in
  inbox-wait) [ "${FAKE_AO_STATUS:-inbox-wait 2}" = fail ] && exit 4; echo "${FAKE_AO_STATUS:-inbox-wait 2}"; exit 0 ;;
  inbox-watch) echo "${FAKE_AO_STATE:-none}"; exit 0 ;;
  list) [ -f "$FAKE_DIR/ao2-started" ] && printf 'w1:p9\t%s\n' "$(cat "$FAKE_DIR/ao2-started")"; exit 0 ;;
  pane-open) echo w1:p9; exit 0 ;;
  agent-start) echo "$2" > "$FAKE_DIR/ao2-started"; exit 0 ;;
  agent-send) exit 0 ;;
  agent-status) echo working; exit 0 ;;
  agent-transcript) echo /tmp/x.jsonl; exit 0 ;;
esac
exit 4
AO
chmod +x "$FAKE/fake-ao2"
spawn2() {  # 환경 FAKE_AO_STATUS·FAKE_AO_STATE로 판정을 고른다
  rm -f "$FAKE_DIR/ao2-started"; : > "$FAKE_DIR/ao2.log"
  AGENT_ORCHESTRATOR="$FAKE/fake-ao2" PERM_FLAGS=x ROLE=none "$SP" sp-pw sonnet high "$BR" w1:p1 2> "$T/spawn.err"
}
out=$(FAKE_AO_STATUS="inbox-wait 2" FAKE_AO_STATE=none spawn2); rc=$?
case "$out" in "OK name=sp-pw "*" parent_watch=none") w=1 ;; *) w=0 ;; esac
[ $rc = 0 ] && [ $w = 1 ] && grep -q 'parent_watch=none' "$T/spawn.err" && grep -q 'inbox-watch --state w1:p1' "$FAKE_DIR/ao2.log" && grep -q '^ao agent-send ' "$FAKE_DIR/ao2.log" \
  && ok spawn-parent-unhooked-warn "경고 + parent_watch=none + rc 0 + 기동 계속" || bad spawn-parent-unhooked-warn "경고·칸·rc0·기동" "rc=$rc out=$out err=$(cat "$T/spawn.err")"
out=$(FAKE_AO_STATUS="inbox-wait 2" FAKE_AO_STATE=waiter spawn2); rc=$?
case "$out" in "OK name=sp-pw "*"jsonl=/tmp/x.jsonl") w=1 ;; *) w=0 ;; esac
[ $rc = 0 ] && [ $w = 1 ] && ! grep -q 'parent_watch' "$T/spawn.err" && ok spawn-parent-waiter-ok "waiter → 경고·칸 없음" || bad spawn-parent-waiter-ok "경고·칸 없음" "rc=$rc out=$out err=$(cat "$T/spawn.err")"
out=$(FAKE_AO_STATUS=fail FAKE_AO_STATE=none spawn2); rc=$?
case "$out" in *parent_watch*) w=1 ;; *) w=0 ;; esac
[ $rc = 0 ] && [ $w = 0 ] && ! grep -q 'parent_watch' "$T/spawn.err" && ! grep -q 'inbox-watch' "$FAKE_DIR/ao2.log" && ok spawn-parent-oldao-silent "옛 판(status 실패) → 판정 안 함, 칸·경고 없음" || bad spawn-parent-oldao-silent "판정 불가 무음" "rc=$rc out=$out err=$(cat "$T/spawn.err")"

echo "== 집계: PASS $PASS / FAIL $FAIL"
[ "$FAIL" = 0 ]
