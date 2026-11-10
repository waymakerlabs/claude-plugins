#!/usr/bin/env bash
# rc-watch.sh — 받은편지함을 처리 위치부터 지켜본다 (0.1.2, 0.1.4부터 inbox-watch 래퍼)
#
# 사용:
#   rc-watch.sh <inbox.log 절대경로>          아직 처리 안 한 줄부터 끝없이 출력(tail -F)
#                                            각 줄 앞에 "#<줄 번호> " — 처리 뒤 --ack 에 그 번호
#   rc-watch.sh --ack <inbox.log> <줄 번호>  그 줄까지 처리했다고 <inbox.log>.cursor 에 기록
#                                            (지금 값보다 클 때만 — 되감지 않는다)
#   rc-watch.sh --pending <inbox.log>        처리 안 한 줄만 출력하고 끝(재개·교체 때 확인용)
#   rc-watch.sh --release <inbox.log>        이전 세션 보류(#0 안내 줄) 해제 — 사용자 확인 뒤
#
# 실제 동작은 `agent-orchestrator inbox-watch`(같은 인자 형식, cursor 는 <경로>.cursor)가 한다.
#   이 스크립트는 인자만 검사하고 exec 한다. 환경: AGENT_ORCHESTRATOR=<실행 파일>
#   (기본 ~/.local/bin/agent-orchestrator).
#
# Monitor 예: command "<SKILL>/scripts/rc-watch.sh <$RC>/inbox.log", timeout_ms 1800000,
#   description "review-chain 받은편지함". 30분이면 끝나므로 만료 알림을 받으면 같은 명령으로 다시 켠다.
#   cursor 부터 다시 읽으므로 만료~재기동 사이에 들어온 줄도 빠지지 않는다.
# 종료 코드: 0 / 2 인자 / 4 ack·잠금 실패(inbox-watch 가 돌려줌). bash 3.2 호환.

set -u

die() { code=$1; shift; echo "rc-watch: $*" >&2; exit "$code"; }

AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}

case "${1:-}" in
  --ack)
    [ $# = 3 ] || die 2 "사용: $0 --ack <inbox.log> <줄 번호>"
    [[ $3 =~ ^[0-9]+$ ]] || die 2 "줄 번호 오류: $3"
    exec "$AO" inbox-watch --ack "$2" "$3" ;;
  --pending|--release)
    [ $# = 2 ] || die 2 "사용: $0 $1 <inbox.log>"
    exec "$AO" inbox-watch "$1" "$2" ;;
esac

[ $# = 1 ] || die 2 "사용: $0 <inbox.log> | --ack <inbox.log> <n> | --pending <inbox.log> | --release <inbox.log>"
case "$1" in /*) ;; *) die 2 "절대 경로: $1" ;; esac
exec "$AO" inbox-watch "$1"
