#!/usr/bin/env bash
# rc-watch.sh — 받은편지함을 처리 위치부터 지켜본다 (0.1.2, Monitor 명령으로 쓴다)
#
# 사용:
#   rc-watch.sh <inbox.log 절대경로>          아직 처리 안 한 줄부터 끝없이 출력(tail -F)
#                                            각 줄 앞에 "#<줄 번호> " — 처리 뒤 --ack 에 그 번호
#   rc-watch.sh --ack <inbox.log> <줄 번호>  그 줄까지 처리했다고 <inbox.log>.cursor 에 기록
#                                            (지금 값보다 클 때만 — 되감지 않는다)
#   rc-watch.sh --pending <inbox.log>        처리 안 한 줄만 출력하고 끝(재개·교체 때 확인용)
#
# Monitor 예: command "<SKILL>/scripts/rc-watch.sh <$RC>/inbox.log", timeout_ms 1800000,
#   description "review-chain 받은편지함". 30분이면 끝나므로 만료 알림을 받으면 같은 명령으로 다시 켠다.
#   cursor 부터 다시 읽으므로 만료~재기동 사이에 들어온 줄도 빠지지 않는다.
# 종료 코드: 0 / 2 인자. bash 3.2 호환.

set -u

die() { code=$1; shift; echo "rc-watch: $*" >&2; exit "$code"; }

cursor_of() { local c=0; [ -f "$1.cursor" ] && c=$(head -n 1 "$1.cursor"); [[ $c =~ ^[0-9]+$ ]] || c=0; echo "$c"; }

case "${1:-}" in
  --ack)
    [ $# = 3 ] || die 2 "사용: $0 --ack <inbox.log> <줄 번호>"
    [[ $3 =~ ^[0-9]+$ ]] || die 2 "줄 번호 오류: $3"
    c=$(cursor_of "$2")
    if [ "$3" -gt "$c" ]; then printf '%s\n' "$3" > "$2.cursor.tmp" && mv "$2.cursor.tmp" "$2.cursor"; fi
    exit 0 ;;
  --pending)
    [ $# = 2 ] || die 2 "사용: $0 --pending <inbox.log>"
    [ -f "$2" ] || exit 0
    c=$(cursor_of "$2")
    awk -v s="$c" 'NR > s { print "#" NR " " $0 }' "$2"
    exit 0 ;;
esac

[ $# = 1 ] || die 2 "사용: $0 <inbox.log> | --ack <inbox.log> <n> | --pending <inbox.log>"
case "$1" in /*) ;; *) die 2 "절대 경로: $1" ;; esac
[ -f "$1" ] || : > "$1"
c=$(cursor_of "$1")
tail -n +"$((c + 1))" -F "$1" 2>/dev/null | awk -v s="$c" '{ print "#" (s + NR) " " $0; fflush() }'
