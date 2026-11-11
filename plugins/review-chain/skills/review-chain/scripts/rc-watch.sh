#!/usr/bin/env bash
# rc-watch.sh — 받은편지함을 처리 위치부터 지켜본다 (0.1.2, 0.1.4부터 inbox-watch 래퍼, 0.2.0 구독 추가)
#
# 사용:
#   rc-watch.sh --subscribe <inbox.log>      (0.2.0) 이 세션을 받은편지함 구독자로 등록한다(기본 수신 방법).
#                                            새 줄이 오면 inbox-hooks 훅이 쉬는 세션을 깨운다. 출력 없음
#   rc-watch.sh --unsubscribe <inbox.log>    (0.2.0) 구독 해제(OC·worker 교체 인계 때)
#   rc-watch.sh <inbox.log 절대경로>          [훅이 없는 도구용 대체] 아직 처리 안 한 줄부터 끝없이 출력(tail -F)
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
# 구독(--subscribe)은 `agent-orchestrator inbox-subscribe`를 그대로 부른다. 구독 키는 herdr pane 안이면
#   HERDR_PANE_ID(pane 키), 아니면 CLAUDE_CODE_SESSION_ID(세션 키)다. 둘 다 없으면 inbox-subscribe 가
#   2(구독 키 없음)로 끝난다. pane 받은편지함은 구독 없이 자동이다.
# 대체(훅이 없는 도구) Monitor 예: command "<SKILL>/scripts/rc-watch.sh <$RC>/inbox.log", timeout_ms 1800000,
#   description "review-chain 받은편지함". 30분이면 끝나므로 만료 알림을 받으면 같은 명령으로 다시 켠다.
#   cursor 부터 다시 읽으므로 만료~재기동 사이에 들어온 줄도 빠지지 않는다.
# 종료 코드: 0 / 2 인자 / 4 ack·잠금 실패(inbox-watch 가 돌려줌). bash 3.2 호환.

set -u

die() { code=$1; shift; echo "rc-watch: $*" >&2; exit "$code"; }

AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}

case "${1:-}" in
  --subscribe|--unsubscribe)
    [ $# = 2 ] || die 2 "사용: $0 $1 <inbox.log 절대경로>"
    case "$2" in /*) ;; *) die 2 "절대 경로: $2" ;; esac
    if [ "$1" = --subscribe ]; then exec "$AO" inbox-subscribe "$2"
    else exec "$AO" inbox-subscribe --unsubscribe "$2"; fi ;;
  --ack)
    [ $# = 3 ] || die 2 "사용: $0 --ack <inbox.log> <줄 번호>"
    [[ $3 =~ ^[0-9]+$ ]] || die 2 "줄 번호 오류: $3"
    exec "$AO" inbox-watch --ack "$2" "$3" ;;
  --pending|--release)
    [ $# = 2 ] || die 2 "사용: $0 $1 <inbox.log>"
    exec "$AO" inbox-watch "$1" "$2" ;;
esac

[ $# = 1 ] || die 2 "사용: $0 --subscribe <inbox.log> | --unsubscribe <inbox.log> | <inbox.log> | --ack <inbox.log> <n> | --pending <inbox.log> | --release <inbox.log>"
case "$1" in /*) ;; *) die 2 "절대 경로: $1" ;; esac
exec "$AO" inbox-watch "$1"
