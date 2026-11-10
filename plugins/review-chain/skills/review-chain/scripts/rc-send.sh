#!/usr/bin/env bash
# rc-send.sh — review-chain 메시지 한 줄을 받은편지함 파일에 덧붙인다 (0.1.2, 기록은 0.1.4부터 inbox-send)
#
# 사용:
#   worker → OC : rc-send.sh <chain 폴더> <내 이름> <종류> "<한 줄 요지>"
#                 종류: 범위 | 범위변경 | 완료 | 질문 | 막힘 | 승격제안   (대괄호 없이)
#                 → <chain 폴더>/inbox.log 에
#                   <HH:MM:SS> [rc <chain-id>] [WO <이름>] [<종류>] <report 절대경로> <요지>
#   OC → worker : rc-send.sh --to <worker 이름> <chain 폴더> <종류> "<한 줄>"
#                 종류: 진행 | 보류 | 답 | main갱신 | 확인 | OC변경 | 닫기 | 승격
#                 → <chain 폴더>/workers/<이름>/inbox.log 에
#                   <HH:MM:SS> [rc <chain-id>] [OC] [<종류>] <한 줄>
#
# 왜 파일인가: agent-send 는 상대 pane 입력창에 키보드처럼 쳐 넣어, 사용자가 그 pane에서
#   치던 프롬프트와 섞인다. 받는 쪽은 Monitor(rc-watch.sh)로 이 파일을 지켜보고, 새 줄은
#   대화에 시스템 알림으로 들어온다(입력창을 건드리지 않음 — 2026-11-09 실측).
#   파일이 기록이므로 OC·worker가 교체돼도 아직 처리 안 한 줄이 남는다.
# 요지의 줄바꿈·탭은 공백으로 바꾸고 300자에서 자른다. 시각·머리·종류 검사는 이 스크립트가
#   만들고, 마지막 기록만 `agent-orchestrator inbox-send --raw <받은편지함> "<완성된 한 줄>"`로 한다
#   (시각을 다시 붙이지 않고 잠금 안에서 그대로 덧붙임 — rc-claim.sh 와 같은 잠금).
#
# 종료 코드: 0 기록 / 2 인자·형식 / 4 기록 실패(inbox-send 가 0이 아니게 끝남 — 잠금·쓰기 오류 등)
# 환경: RC_DRY_RUN=1 이면 기록하지 않고 줄만 출력.
#       AGENT_ORCHESTRATOR=<실행 파일> (기본 ~/.local/bin/agent-orchestrator)
# bash 3.2 호환.

set -u

die() { code=$1; shift; echo "rc-send: $*" >&2; exit "$code"; }

TO=""
if [ "${1:-}" = "--to" ]; then
  [ $# = 5 ] || die 2 "사용: $0 --to <worker 이름> <chain 폴더> <종류> \"<한 줄>\""
  TO=$2; RC=${3%/}; KIND=$4; MSG=$5
  [[ $TO =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die 2 "이름 형식 오류: $TO"
  case "$KIND" in 진행|보류|답|main갱신|확인|OC변경|닫기|승격) ;; *) die 2 "종류 오류: $KIND" ;; esac
else
  [ $# = 4 ] || die 2 "사용: $0 <chain 폴더> <이름> <종류> \"<요지>\"  |  $0 --to <이름> <chain 폴더> <종류> \"<한 줄>\""
  RC=${1%/}; NAME=$2; KIND=$3; MSG=$4
  [[ $NAME =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die 2 "이름 형식 오류: $NAME"
  case "$KIND" in 범위|범위변경|완료|질문|막힘|승격제안) ;; *) die 2 "종류 오류: $KIND" ;; esac
fi

case "$RC" in /*) ;; *) die 2 "chain 폴더는 절대 경로: $RC" ;; esac
[ -d "$RC" ] || die 2 "chain 폴더 없음: $RC"

CHAIN_ID=$(basename "$RC")
SUMMARY=$(printf '%s' "$MSG" | tr '\n\t\r' '   ')
SUMMARY=${SUMMARY:0:300}
NOW=$(date +%H:%M:%S)

if [ -n "$TO" ]; then
  [ -d "$RC/workers/$TO" ] || die 2 "worker 폴더 없음: $RC/workers/$TO"
  BOX="$RC/workers/$TO/inbox.log"
  LINE="$NOW [rc $CHAIN_ID] [OC] [$KIND] $SUMMARY"
else
  BOX="$RC/inbox.log"
  LINE="$NOW [rc $CHAIN_ID] [WO $NAME] [$KIND] $RC/workers/$NAME/report.md $SUMMARY"
fi

if [ "${RC_DRY_RUN:-0}" = 1 ]; then
  printf 'box=%s\t%s\n' "$BOX" "$LINE"
  exit 0
fi

AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}
"$AO" inbox-send --raw "$BOX" "$LINE" >/dev/null || die 4 "기록 실패: $BOX"
echo "OK box=$BOX kind=$KIND"
