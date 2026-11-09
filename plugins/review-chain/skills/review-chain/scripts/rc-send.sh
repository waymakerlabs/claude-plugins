#!/usr/bin/env bash
# rc-send.sh — review-chain worker → 현재 OC 보고 한 줄 전송
#
# 사용: rc-send.sh <chain 폴더 절대경로> <내 이름> <종류> "<한 줄 요지>"
#   종류: 범위 | 범위변경 | 완료 | 질문 | 막힘 | 승격제안   (대괄호 없이)
#
# 하는 일: <chain 폴더>/current-oc 를 매번 읽어(pane id 를 외우지 않는다) 아래 형식으로 보낸다.
#   current-oc 는 agent-orchestrator 의 pane id 형식(^[A-Za-z0-9]+:[A-Za-z0-9]+$)만 받는다. 고쳐 쓰지 않는다.
#   [rc <chain-id>] [WO <이름>] [<종류>] <chain 폴더>/workers/<이름>/report.md <요지>
#   chain-id = chain 폴더 이름. 요지의 줄바꿈·탭은 공백으로 바꾸고 300자에서 자른다.
# 전송: agent-orchestrator agent-send <OC pane> "<메시지>" (--confirm 없음 — OC가 일하는 중이어도 된다)
#
# 종료 코드: 0 전송 / 2 인자·형식 / 3 current-oc 없음·형식 오류 / 그 밖 = agent-send 의 코드 그대로
#   실패하면 report.md 의 "- 진행:" 줄에 "미전송 [<종류>]"를 남기는 것은 호출자(worker) 몫이다.
# 환경: AGENT_ORCHESTRATOR(진입점, 기본 $HOME/.local/bin/agent-orchestrator), RC_DRY_RUN=1 이면 보내지 않고 메시지만 출력.
# bash 3.2 호환.

set -u

die() { code=$1; shift; echo "rc-send: $*" >&2; exit "$code"; }

[ $# = 4 ] || die 2 "사용: $0 <chain 폴더> <이름> <종류> \"<요지>\""
RC=${1%/}; NAME=$2; KIND=$3; MSG=$4
AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}

case "$RC" in /*) ;; *) die 2 "chain 폴더는 절대 경로: $RC" ;; esac
[ -d "$RC" ] || die 2 "chain 폴더 없음: $RC"
[[ $NAME =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die 2 "이름 형식 오류: $NAME"
case "$KIND" in 범위|범위변경|완료|질문|막힘|승격제안) ;; *) die 2 "종류 오류: $KIND" ;; esac

OC_FILE="$RC/current-oc"
[ -f "$OC_FILE" ] || die 3 "current-oc 없음: $OC_FILE"
# 매 전송마다 다시 읽는다(OC 교체 뒤 [OC변경]을 받은 worker가 재전송하면 새 값으로 간다).
# 끝의 CR만 떼고 안쪽 공백은 그대로 둔다 — 'w2: p4' 같은 값을 고쳐 주지 않고 거부한다.
OC=$(head -n 1 "$OC_FILE")
OC=${OC%$'\r'}
# agent-orchestrator lib/common.sh AO_PANE_RE 와 같은 엄격 형식(<workspace>:<pane>). '-'로 시작하는 값(옵션 오인)도 여기서 걸린다.
[[ $OC =~ ^[A-Za-z0-9]+:[A-Za-z0-9]+$ ]] || die 3 "current-oc 형식 오류: '$OC'"

CHAIN_ID=$(basename "$RC")
REPORT="$RC/workers/$NAME/report.md"
SUMMARY=$(printf '%s' "$MSG" | tr '\n\t\r' '   ')
SUMMARY=${SUMMARY:0:300}
LINE="[rc $CHAIN_ID] [WO $NAME] [$KIND] $REPORT $SUMMARY"

if [ "${RC_DRY_RUN:-0}" = 1 ]; then
  printf 'to=%s\t%s\n' "$OC" "$LINE"
  exit 0
fi

[ -x "$AO" ] || die 12 "agent-orchestrator 실행 불가: $AO"
"$AO" agent-send "$OC" "$LINE" >/dev/null
c=$?
[ "$c" = 0 ] || die "$c" "agent-send 실패 rc=$c (to=$OC) — report.md 진행 줄에 미전송 [$KIND] 기록"
echo "OK to=$OC kind=$KIND"
