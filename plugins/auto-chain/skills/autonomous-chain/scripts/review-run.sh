#!/usr/bin/env bash
# review-run.sh — auto-chain 리뷰 실행기 (2.2.0)
#
# 사용: review-run.sh <reviewer> <request-file> <result-file> <done-file> [repo]
#   reviewer     codex-cli | opencode-sol | opencode-build
#   request-file 요청 파일(리뷰어에게 그대로 넘긴다)
#   result-file  결과 파일(codex-cli는 -o로 직접, opencode-*는 로그의 마지막 판정 블록을 추출)
#   done-file    완료 기록(어떤 경우에도 trap EXIT로 원자적으로 쓴다 — review-wait.sh가 기다린다)
#   repo         git 작업 트리(기본 $PWD)
# 환경 변수(선택):
#   REVIEW_MODEL      codex-cli 기본 gpt-6.1-sol, opencode-* 기본 ai-gateway-openai/gpt-6.1-sol
#   REVIEW_EFFORT     low|medium|high|xhigh, 기본 high (codex-cli만 적용 — opencode의 모델 꼬리
#                     '#high'는 거부된 실측이 있어 붙이지 않는다)
#   REVIEW_LOG        기본 <done-file>.log
#   REVIEW_AGENT_FILE opencode-build가 첨부할 리뷰 정의(기본 ~/.config/opencode/agent/review-sol.md)
#   REVIEW_OPENCODE_BIN opencode 실행 파일(기본 ~/.opencode/bin/opencode → PATH의 opencode).
#                     게이트웨이 키(AIGW_OPENCODE_KEY 등)가 필요하면 호출 전에 export한다(값은 기록하지 않음)
#   REVIEW_KILL_GRACE TERM·INT·HUP을 받았을 때 리뷰어에 TERM 뒤 KILL까지 기다릴 초(기본 10)
#
# 하는 일 (references/sol-review.md §3, interface §1):
#   1. RUN_ID=<YYYYmmdd-HHMMSS>-<4자 hex>. 이미 있는 result·done·log·run 파일은 *.stale-<RUN_ID>로 옮긴다
#   2. <done-file>.run에 "RUN <RUN_ID> pid=<pid> start=<시작 시각>" 한 줄을 쓰고 stdout에도 같은 줄
#      (start = LC_ALL=C ps -o lstart= — review-wait.sh가 PID 재사용을 가려낸다)
#   3. 전 snapshot(HEAD, 작업 트리 식별자) → 리뷰어 실행(로그로 리다이렉트, 실제 종료 코드) → 후 snapshot
#      git 실패는 값 error, 전후 어느 쪽이든 error면 ro=unverified
#   4. done 파일(키=값 줄): run_id reviewer model effort started ended exit [signal] result result_bytes
#      verdict head_before head_after tree_before tree_after ro sandbox log
# 판정 규칙(문서 쪽): exit=0·verdict≠none·ro=same·(codex-cli면 sandbox=read-only)일 때만 유효.
#   ro = same | changed | unverified(snapshot의 git 명령 실패)
# 인자·전제 오류는 done 파일 없이 exit 2(아직 시작 전). 그 밖의 종료 코드는 리뷰어의 실제 값.
# bash 3.2 호환.

# 아래 함수들은 trap(EXIT·TERM·INT·HUP)에서 간접 호출된다
# shellcheck disable=SC2329
set -u

die() { echo "review-run: $*" >&2; exit 2; }

[ $# -ge 4 ] && [ $# -le 5 ] || die "사용: $0 <codex-cli|opencode-sol|opencode-build> <request-file> <result-file> <done-file> [repo]"

abs() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }

REVIEWER=$1
REQ=$(abs "$2"); RESULT=$(abs "$3"); DONE=$(abs "$4"); REPO=$(abs "${5:-$PWD}")
LOG=$(abs "${REVIEW_LOG:-$DONE.log}")
RUNF="$DONE.run"
EFFORT=${REVIEW_EFFORT:-high}
AGENT_FILE=${REVIEW_AGENT_FILE:-$HOME/.config/opencode/agent/review-sol.md}
GRACE=${REVIEW_KILL_GRACE:-10}
case "$GRACE" in ''|*[!0-9]*) GRACE=10 ;; esac

case "$REVIEWER" in
  codex-cli) MODEL=${REVIEW_MODEL:-gpt-6.1-sol} ;;
  opencode-sol|opencode-build) MODEL=${REVIEW_MODEL:-ai-gateway-openai/gpt-6.1-sol} ;;
  *) die "reviewer는 codex-cli|opencode-sol|opencode-build: $REVIEWER" ;;
esac
case "$EFFORT" in low|medium|high|xhigh) ;; *) die "REVIEW_EFFORT는 low|medium|high|xhigh: $EFFORT" ;; esac
[ -f "$REQ" ] || die "요청 파일 없음: $REQ"
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "git 작업 트리 아님: $REPO"
OC=""
case "$REVIEWER" in
  codex-cli) command -v codex >/dev/null 2>&1 || die "codex 없음" ;;
  *)
    # (2.2.1) 셸 래퍼(예: ~/.local/bin/opencode — 게이트웨이 키를 스스로 갱신하는 zsh 스크립트)는
    # 비대화형 실행에서 provider 초기화에 실패했다(office 2026-11-08 실측). 실제 바이너리를 우선한다.
    if [ -n "${REVIEW_OPENCODE_BIN:-}" ]; then OC=$REVIEW_OPENCODE_BIN
    elif [ -x "$HOME/.opencode/bin/opencode" ]; then OC="$HOME/.opencode/bin/opencode"
    else OC=$(command -v opencode 2>/dev/null || true); fi
    { [ -n "$OC" ] && [ -x "$OC" ]; } || die "opencode 없음 (REVIEW_OPENCODE_BIN으로 지정)" ;;
esac
if [ "$REVIEWER" = opencode-build ]; then
  [ -f "$AGENT_FILE" ] || die "리뷰 정의 파일 없음: $AGENT_FILE (REVIEW_AGENT_FILE)"
fi
for f in "$RESULT" "$DONE" "$LOG"; do
  d=$(dirname "$f"); [ -d "$d" ] || die "폴더 없음: $d"
done
# 결과·로그가 리포 안이면 그 쓰기 자체가 작업 트리를 바꿔 ro=changed가 된다
case "$RESULT$DONE$LOG" in *"$REPO"/*) echo "review-run: 경고 — result/done/log가 리포 안에 있으면 ro=changed로 기록된다. /tmp 아래를 권장" >&2 ;; esac

sha12() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -c1-12
}
head_id() { git -C "$REPO" rev-parse HEAD 2>/dev/null || echo error; }
tree_id() {
  # 작업 트리 식별자 = (status -z + diff HEAD --binary)의 sha256 앞 12자 (interface §1)
  # 주의: 추적 안 된 파일은 경로만 반영된다(내용 변경은 잡지 못함)
  # git 명령이 하나라도 비0이면 error (파이프가 실패를 삼키지 않게 임시 파일로 받는다)
  local tf s
  tf=$(mktemp "${TMPDIR:-/tmp}/review-run-tree.XXXXXX") || { echo error; return; }
  if git -C "$REPO" status --porcelain=v1 -z > "$tf" 2>/dev/null \
     && git -C "$REPO" diff HEAD --binary >> "$tf" 2>/dev/null; then
    s=$(sha12 < "$tf")
  else
    s=""
  fi
  rm -f "$tf"
  if [ -n "$s" ]; then printf '%s\n' "$s"; else echo error; fi
}
# 프로세스 시작 시각(신원) — macOS·Linux 모두 ps -o lstart=, 공백 정규화
proc_start() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//'; }
iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

RAND=$(od -An -N2 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
RUN_ID="$(date +%Y%m%d-%H%M%S)-${RAND:-0000}"

# 1. 이전 결과 잔존 방지
for f in "$RESULT" "$DONE" "$LOG" "$RUNF"; do
  if [ -e "$f" ] || [ -L "$f" ]; then mv -f "$f" "$f.stale-$RUN_ID" || die "stale 이동 실패: $f"; fi
done

HEAD_BEFORE=$(head_id); TREE_BEFORE=$(tree_id)
STARTED=$(iso)
CHILD=""; RC=""; SIG=""

# opencode 로그에서 마지막으로 시작된 '# 판정:' 블록이 REVIEW-DONE으로 닫혔을 때만 결과로 쓴다
# (마지막 블록이 미완성이면 이전 닫힌 블록을 쓰지 않고 빈 결과 → verdict=none. sol-review.md §5 awk 이전)
extract_opencode() {
  local esc tmp
  esc=$(printf '\033')
  tmp="$RESULT.tmp.$$"
  [ -f "$LOG" ] || return 0
  tr -d '\r' < "$LOG" | sed "s/${esc}\[[0-9;]*[A-Za-z]//g" | awk '
    /^# 판정:/ {buf=""; last=""; on=1}
    on {buf=buf $0 "\n"}
    /^REVIEW-DONE[[:space:]]*$/ {if(on){last=buf; on=0}}
    END {printf "%s", last}' > "$tmp" && mv -f "$tmp" "$RESULT"
  rm -f "$tmp"
}

read_verdict() {
  [ -f "$RESULT" ] || { echo none; return; }
  local first v
  first=$(awk 'NF {print; exit}' "$RESULT")
  # 첫 비어 있지 않은 줄이 SHIP/BLOCK 또는 '# 판정: SHIP|BLOCK'(굵게 표시 허용)
  v=$(printf '%s\n' "$first" | grep -Eo '^[[:space:]]*(#+[[:space:]]*판정:[[:space:]]*)?(\*\*)?(SHIP|BLOCK)([^A-Za-z]|$)' \
      | grep -Eo 'SHIP|BLOCK' | head -1)
  echo "${v:-none}"
}

finish() {
  trap - EXIT TERM INT HUP
  local ended head_after tree_after ro verdict bytes sandbox exitv tmp
  [ "$REVIEWER" = codex-cli ] || extract_opencode
  ended=$(iso)
  head_after=$(head_id); tree_after=$(tree_id)
  if [ "$HEAD_BEFORE" = "$head_after" ] && [ "$TREE_BEFORE" = "$tree_after" ] \
     && [ "$head_after" != error ] && [ "$tree_after" != error ]; then ro=same; else ro=changed; fi
  case "$HEAD_BEFORE $head_after $TREE_BEFORE $tree_after" in *error*) ro=unverified ;; esac
  verdict=$(read_verdict)
  if [ -f "$RESULT" ]; then bytes=$(wc -c < "$RESULT" | tr -d ' '); else bytes=0; fi
  if [ "$REVIEWER" = codex-cli ]; then
    if [ -f "$LOG" ] && head -n 40 "$LOG" | grep -q 'sandbox: read-only'; then sandbox=read-only; else sandbox=unverified; fi
  else
    sandbox=n/a
  fi
  if [ -n "$SIG" ]; then exitv=signal; else exitv=${RC:-unknown}; fi
  tmp="$DONE.tmp.$$"
  {
    echo "run_id=$RUN_ID"
    echo "reviewer=$REVIEWER"
    echo "model=$MODEL"
    echo "effort=$EFFORT"
    echo "started=$STARTED"
    echo "ended=$ended"
    echo "exit=$exitv"
    [ -n "$SIG" ] && echo "signal=$SIG"
    echo "result=$RESULT"
    echo "result_bytes=$bytes"
    echo "verdict=$verdict"
    echo "head_before=$HEAD_BEFORE"
    echo "head_after=$head_after"
    echo "tree_before=$TREE_BEFORE"
    echo "tree_after=$tree_after"
    echo "ro=$ro"
    echo "sandbox=$sandbox"
    echo "log=$LOG"
  } > "$tmp" && mv -f "$tmp" "$DONE"
}

on_sig() {  # $1 = 이름, $2 = 종료 코드
  SIG=$1
  if [ -n "$CHILD" ]; then
    # TERM 뒤 최대 GRACE초 기다리고, 그래도 살아 있으면 KILL (TERM을 무시하는 리뷰어 대비)
    kill -TERM "$CHILD" 2>/dev/null
    local n=$((GRACE * 5))
    while [ "$n" -gt 0 ] && kill -0 "$CHILD" 2>/dev/null; do sleep 0.2; n=$((n - 1)); done
    kill -0 "$CHILD" 2>/dev/null && kill -KILL "$CHILD" 2>/dev/null
    wait "$CHILD" 2>/dev/null
  fi
  exit "$2"
}

trap finish EXIT
trap 'on_sig TERM 143' TERM
trap 'on_sig INT 130' INT
trap 'on_sig HUP 129' HUP

# 2. 시작 기록
RUNLINE="RUN $RUN_ID pid=$$ start=$(proc_start $$)"
printf '%s\n' "$RUNLINE" > "$RUNF.tmp.$$" && mv -f "$RUNF.tmp.$$" "$RUNF"
printf '%s\n' "$RUNLINE"

# 3. 실행 — 백그라운드 + wait: 신호를 즉시 받고, 종료 코드는 리뷰어 프로세스의 실제 값
MSG_SOL='첨부한 요청 파일을 읽고 그대로 검토해. 마지막 줄은 REVIEW-DONE.'
MSG_BUILD='첨부한 정의대로 읽기 전용으로, 요청 파일을 읽고 그대로 검토해. 마지막 줄은 REVIEW-DONE.'
case "$REVIEWER" in
  codex-cli)
    # command: alias·함수 우회
    command codex exec -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" -c 'sandbox_mode="read-only"' \
      -s read-only --ephemeral -C "$REPO" -o "$RESULT" - < "$REQ" > "$LOG" 2>&1 &
    ;;
  # opencode의 -f는 배열 옵션이라 뒤의 위치 인자(메시지)까지 파일로 먹는다(office 실측:
  # "File not found: <메시지>"). 메시지를 -f보다 앞에 둔다.
  opencode-sol)
    ( cd "$REPO" && exec "$OC" run "$MSG_SOL" --agent review-sol -m "$MODEL" -f "$REQ" ) < /dev/null > "$LOG" 2>&1 &
    ;;
  opencode-build)
    ( cd "$REPO" && exec "$OC" run "$MSG_BUILD" --agent build -m "$MODEL" -f "$AGENT_FILE" -f "$REQ" ) < /dev/null > "$LOG" 2>&1 &
    ;;
esac
CHILD=$!
wait "$CHILD"
RC=$?
CHILD=""
exit "$RC"
