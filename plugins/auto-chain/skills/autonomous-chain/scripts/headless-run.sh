#!/usr/bin/env bash
# headless-run.sh — ② 다른 CLI의 비리뷰 일회성 실행기 (2.3.0)
#
# 사용: headless-run.sh <cli> <brief-file> <done-file> [repo]
#   cli        opencode:<agent>   (예: opencode:work-sol-xhigh — `opencode run --agent <agent>`)
#              codex              (`codex exec -s workspace-write` — 리포에 쓰는 구현 실행)
#   brief-file worker 지시서(형식 references/task-brief.md). 그대로 넘긴다
#   done-file  완료 기록(어떤 경우에도 trap EXIT로 원자적으로 쓴다 — review-wait.sh로 기다린다)
#   repo       git 작업 트리(기본 $PWD)
# 환경 변수(선택):
#   HEADLESS_MODEL       codex 기본 gpt-6.1-sol, opencode는 에이전트 정의의 모델(비우면 -m 없음)
#   HEADLESS_EFFORT      codex만: low|medium|high|xhigh, 기본 high
#   HEADLESS_LOG         기본 <done-file>.log
#   REVIEW_OPENCODE_BIN  opencode 실행 파일(기본 ~/.opencode/bin/opencode → PATH의 opencode — review-run.sh와 같다)
#   REVIEW_KILL_GRACE    TERM·INT·HUP 뒤 KILL까지 기다릴 초(기본 10)
#
# review-run.sh와 같은 done 형식·RUN 기록을 쓰고, 판정(verdict·ro·sandbox)만 없다.
#   1. RUN_ID, 이전 done·log·run 파일은 *.stale-<RUN_ID>로 옮긴다
#   2. <done-file>.run 에 "RUN <RUN_ID> pid=<pid> start=<시작 시각>" 한 줄, stdout에도 같은 줄
#   3. 전 snapshot → CLI 실행(로그로 리다이렉트, 실제 종료 코드) → 후 snapshot
#   4. done 파일(키=값 줄): run_id cli model started ended exit [signal] head_before head_after
#      tree_before tree_after changed(yes|no|unverified) log
# 완료 판정은 done 파일 + worker 보고서와 diff(SKILL.md §5)로 한다. exit=0만으로 task 완료가 아니다.
# 인자·전제 오류는 done 파일 없이 exit 2. 그 밖의 종료 코드는 CLI의 실제 값.
# bash 3.2 호환.

# 아래 함수들은 trap(EXIT·TERM·INT·HUP)에서 간접 호출된다
# shellcheck disable=SC2329
set -u

die() { echo "headless-run: $*" >&2; exit 2; }

[ $# -ge 3 ] && [ $# -le 4 ] || die "사용: $0 <opencode:<agent>|codex> <brief-file> <done-file> [repo]"

abs() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }

CLI=$1
BRIEF=$(abs "$2"); DONE=$(abs "$3"); REPO=$(abs "${4:-$PWD}")
LOG=$(abs "${HEADLESS_LOG:-$DONE.log}")
RUNF="$DONE.run"
GRACE=${REVIEW_KILL_GRACE:-10}
case "$GRACE" in ''|*[!0-9]*) GRACE=10 ;; esac
AGENT=""; MODEL=""; OC=""

case "$CLI" in
  codex)
    MODEL=${HEADLESS_MODEL:-gpt-6.1-sol}
    EFFORT=${HEADLESS_EFFORT:-high}
    case "$EFFORT" in low|medium|high|xhigh) ;; *) die "HEADLESS_EFFORT는 low|medium|high|xhigh: $EFFORT" ;; esac
    command -v codex >/dev/null 2>&1 || die "codex 없음" ;;
  opencode:*)
    AGENT=${CLI#opencode:}
    [[ $AGENT =~ ^[A-Za-z0-9_.-]{1,64}$ ]] || die "opencode 에이전트 이름 형식 오류: $AGENT"
    MODEL=${HEADLESS_MODEL:-}
    if [ -n "${REVIEW_OPENCODE_BIN:-}" ]; then OC=$REVIEW_OPENCODE_BIN
    elif [ -x "$HOME/.opencode/bin/opencode" ]; then OC="$HOME/.opencode/bin/opencode"
    else OC=$(command -v opencode 2>/dev/null || true); fi
    { [ -n "$OC" ] && [ -x "$OC" ]; } || die "opencode 없음 (REVIEW_OPENCODE_BIN으로 지정)" ;;
  *) die "cli는 opencode:<agent>|codex: $CLI" ;;
esac
[ -f "$BRIEF" ] || die "지시서 없음: $BRIEF"
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "git 작업 트리 아님: $REPO"
for f in "$DONE" "$LOG"; do
  d=$(dirname "$f"); [ -d "$d" ] || die "폴더 없음: $d"
done

sha12() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -c1-12
}
head_id() { git -C "$REPO" rev-parse HEAD 2>/dev/null || echo error; }
tree_id() {  # review-run.sh와 같은 작업 트리 식별자
  local tf s
  tf=$(mktemp "${TMPDIR:-/tmp}/headless-run-tree.XXXXXX") || { echo error; return; }
  if git -C "$REPO" status --porcelain=v1 -z > "$tf" 2>/dev/null \
     && git -C "$REPO" diff HEAD --binary >> "$tf" 2>/dev/null; then
    s=$(sha12 < "$tf")
  else
    s=""
  fi
  rm -f "$tf"
  if [ -n "$s" ]; then printf '%s\n' "$s"; else echo error; fi
}
proc_start() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//'; }
iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

RAND=$(od -An -N2 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
RUN_ID="$(date +%Y%m%d-%H%M%S)-${RAND:-0000}"

for f in "$DONE" "$LOG" "$RUNF"; do
  if [ -e "$f" ] || [ -L "$f" ]; then mv -f "$f" "$f.stale-$RUN_ID" || die "stale 이동 실패: $f"; fi
done

HEAD_BEFORE=$(head_id); TREE_BEFORE=$(tree_id)
STARTED=$(iso)
CHILD=""; RC=""; SIG=""

finish() {
  trap - EXIT TERM INT HUP
  local ended head_after tree_after changed exitv tmp
  ended=$(iso)
  head_after=$(head_id); tree_after=$(tree_id)
  if [ "$HEAD_BEFORE" = "$head_after" ] && [ "$TREE_BEFORE" = "$tree_after" ]; then changed=no; else changed=yes; fi
  case "$HEAD_BEFORE $head_after $TREE_BEFORE $tree_after" in *error*) changed=unverified ;; esac
  if [ -n "$SIG" ]; then exitv=signal; else exitv=${RC:-unknown}; fi
  tmp="$DONE.tmp.$$"
  {
    echo "run_id=$RUN_ID"
    echo "cli=$CLI"
    echo "model=${MODEL:-default}"
    echo "started=$STARTED"
    echo "ended=$ended"
    echo "exit=$exitv"
    [ -n "$SIG" ] && echo "signal=$SIG"
    echo "head_before=$HEAD_BEFORE"
    echo "head_after=$head_after"
    echo "tree_before=$TREE_BEFORE"
    echo "tree_after=$tree_after"
    echo "changed=$changed"
    echo "log=$LOG"
  } > "$tmp" && mv -f "$tmp" "$DONE"
}

on_sig() {  # $1 = 이름, $2 = 종료 코드
  SIG=$1
  if [ -n "$CHILD" ]; then
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

RUNLINE="RUN $RUN_ID pid=$$ start=$(proc_start $$)"
printf '%s\n' "$RUNLINE" > "$RUNF.tmp.$$" && mv -f "$RUNF.tmp.$$" "$RUNF"
printf '%s\n' "$RUNLINE"

MSG='첨부한 지시서를 끝까지 읽고 그대로 진행해. 보고서는 지시서가 정한 경로에 쓴다.'
case "$CLI" in
  codex)
    command codex exec -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" -c 'sandbox_mode="workspace-write"' \
      -s workspace-write --ephemeral -C "$REPO" - < "$BRIEF" > "$LOG" 2>&1 &
    ;;
  opencode:*)
    # -f는 배열 옵션이라 메시지를 -f보다 앞에 둔다(review-run.sh 2.2.1과 같다)
    if [ -n "$MODEL" ]; then
      ( cd "$REPO" && exec "$OC" run "$MSG" --agent "$AGENT" -m "$MODEL" -f "$BRIEF" ) < /dev/null > "$LOG" 2>&1 &
    else
      ( cd "$REPO" && exec "$OC" run "$MSG" --agent "$AGENT" -f "$BRIEF" ) < /dev/null > "$LOG" 2>&1 &
    fi
    ;;
esac
CHILD=$!
wait "$CHILD"
RC=$?
CHILD=""
exit "$RC"
