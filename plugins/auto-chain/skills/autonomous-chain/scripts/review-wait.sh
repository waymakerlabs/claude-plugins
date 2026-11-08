#!/usr/bin/env bash
# review-wait.sh — review-run.sh 완료 대기 (2.2.0)
#
# 사용: review-wait.sh <done-file> <runner-pid> [timeout-sec=3600]
#   0 = done 파일 있음(내용을 stdout으로 출력)
#   3 = 실행기가 done 파일 없이 사라짐(stdout "exit=lost")
#   4 = timeout(실패 아님 — 같은 명령으로 다시 대기, stdout "exit=timeout")
#   2 = 인자 오류
# 환경 변수: WAIT_INTERVAL 확인 간격 초(기본 5)
# 실행기 신원: <done-file>.run 의 "RUN <run_id> pid=<pid> start=<시작 시각>"(review-run.sh가 쓴다).
#   pid가 같고 start가 있으면, 살아 있는 프로세스의 시작 시각이 다를 때 PID 재사용으로 보고 lost(3).
#   .run이 없거나 start가 비어 있으면 존재 여부만 본다.
# 조정자는 이것만 run_in_background로 기다린다. 로그 grep·결과 파일 존재로 완료를 판단하지 않는다
# (references/sol-review.md §4).
# bash 3.2 호환.

set -u

[ $# -ge 2 ] && [ $# -le 3 ] || { echo "사용: $0 <done-file> <runner-pid> [timeout-sec]" >&2; exit 2; }
DONE=$1; PID=$2; TIMEOUT=${3:-3600}
INTERVAL=${WAIT_INTERVAL:-5}
case "$PID" in ''|*[!0-9]*) echo "review-wait: pid는 정수: $PID" >&2; exit 2 ;; esac
case "$TIMEOUT" in ''|*[!0-9]*) echo "review-wait: timeout은 정수 초: $TIMEOUT" >&2; exit 2 ;; esac
case "$INTERVAL" in ''|*[!0-9]*|0) INTERVAL=5 ;; esac

proc_start() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//'; }
WANT=""
if [ -f "$DONE.run" ]; then
  line=$(head -n 1 "$DONE.run")
  fpid=$(printf '%s\n' "$line" | sed -n 's/^RUN [^ ]* pid=\([0-9]*\).*/\1/p')
  [ "$fpid" = "$PID" ] && WANT=$(printf '%s\n' "$line" | sed -n 's/^RUN [^ ]* pid=[0-9]* start=//p')
fi
# kill -0은 다른 사용자 프로세스에 EPERM으로 실패하므로 ps로 존재를 보고, 신원(시작 시각)을 대조한다
alive() {
  ps -p "$PID" >/dev/null 2>&1 || return 1
  [ -z "$WANT" ] && return 0
  [ "$(proc_start "$PID")" = "$WANT" ]
}

start=$(date +%s)
while :; do
  if [ -f "$DONE" ]; then cat "$DONE"; exit 0; fi
  if ! alive; then
    # 실행기가 끝나는 순간(mv 직후)과 겹칠 수 있어 한 번 더 본다
    if [ -f "$DONE" ]; then cat "$DONE"; exit 0; fi
    echo "exit=lost"
    echo "review-wait: 실행기 pid=$PID 가 done 파일 없이 사라짐(또는 PID 재사용 — 시작 시각 불일치): $DONE" >&2
    exit 3
  fi
  now=$(date +%s)
  if [ $((now - start)) -ge "$TIMEOUT" ]; then
    echo "exit=timeout"
    echo "review-wait: ${TIMEOUT}초 경과, 실행기 pid=$PID 는 아직 살아 있음 — 같은 명령으로 다시 대기" >&2
    exit 4
  fi
  sleep "$INTERVAL"
done
