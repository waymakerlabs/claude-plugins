#!/usr/bin/env bash
# rc-send.sh — review-chain 메시지 한 줄을 받은편지함 파일에 덧붙인다 (0.1.2, 기록은 0.1.4부터 inbox-send, 0.2.0 watch 필드)
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
#   치던 프롬프트와 섞인다. 받는 쪽은 받은편지함을 구독(rc-watch.sh --subscribe, 0.2.0)해 두면
#   새 줄이 inbox-hooks 깨움으로 들어온다(훅이 없는 도구는 Monitor 대체 — messages.md §1).
#   입력창을 건드리지 않는다(2026-11-09 실측).
#   파일이 기록이므로 OC·worker가 교체돼도 아직 처리 안 한 줄이 남는다.
# 요지의 줄바꿈·탭은 공백으로 바꾸고 300자에서 자른다. 시각·머리·종류 검사는 이 스크립트가
#   만들고, 마지막 기록만 `agent-orchestrator inbox-send --raw <받은편지함> "<완성된 한 줄>"`로 한다
#   (시각을 다시 붙이지 않고 잠금 안에서 그대로 덧붙임 — rc-claim.sh 와 같은 잠금).
#
# 출력(0.2.0): OK box=<경로> kind=<종류> watch=<watched|unwatched>  (inbox-send stdout 을 받아 붙임.
#   빈 값·이상값은 unwatched). unwatched 면 보낸 쪽 기록 한 줄 `- 미감시 전송 <BOX> <HH:MM>`:
#     worker→OC  $RC/workers/<이름>/report.md 의 `- 진행:` 줄 아래(없으면 파일 끝). report.md 없으면 생략+경고
#     OC→worker  $RC/state.md 의 "## 미감시 전송" 절 끝(절이 없으면 파일 끝에 만듦)
#   기록 실패는 stderr 경고만(종료 0 유지). 재시도·알림 없음. inbox-send 가 0이면 inbox-send 의 부가
#   기록 경고(stderr)가 있어도 4를 내지 않는다.
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
W=$("$AO" inbox-send --raw "$BOX" "$LINE") || die 4 "기록 실패: $BOX"
W=$(printf '%s' "$W" | tr -d '[:space:]')
case "$W" in watched|unwatched) ;; *) W=unwatched ;; esac
echo "OK box=$BOX kind=$KIND watch=$W"

# ── 미감시 전송 기록(0.2.0): 실패해도 경고만, 종료 0 ──────────────────────────────
if [ "$W" = unwatched ]; then
  REC="- 미감시 전송 $BOX $(printf %.5s "$NOW")"
  if [ -n "$TO" ]; then
    F="$RC/state.md"   # OC→worker: "## 미감시 전송" 절 끝(없으면 파일 끝에 절을 만든다)
    if [ ! -f "$F" ]; then
      echo "rc-send: 경고: state.md 없음 — 미감시 전송 기록 생략 ($F)" >&2
    else
      RC_REC=$REC awk 'BEGIN { rec = ENVIRON["RC_REC"] }
        { L[NR] = $0 }
        END {
          s = 0; e = NR
          for (i = 1; i <= NR; i++) if (L[i] == "## 미감시 전송") { s = i; break }
          if (s) { for (i = s + 1; i <= NR; i++) if (L[i] ~ /^## /) { e = i - 1; break }
                   at = s; for (i = s + 1; i <= e; i++) if (L[i] !~ /^[ \t]*$/) at = i }
          for (i = 1; i <= NR; i++) { print L[i]; if (s && i == at) print rec }
          if (!s) { if (NR > 0) print ""; print "## 미감시 전송"; print rec }
        }' "$F" > "$F.tmp.$$" && mv "$F.tmp.$$" "$F" \
        || { rm -f "$F.tmp.$$"; echo "rc-send: 경고: 미감시 전송 기록 실패 ($F)" >&2; }
    fi
  else
    F="$RC/workers/$NAME/report.md"   # worker→OC: report.md 의 `- 진행:` 줄 아래(없으면 파일 끝)
    if [ ! -f "$F" ]; then
      echo "rc-send: 경고: report.md 없음 — 미감시 전송 기록 생략 ($F)" >&2
    else
      RC_REC=$REC awk 'BEGIN { rec = ENVIRON["RC_REC"] }
        { L[NR] = $0 }
        END {
          at = 0
          for (i = 1; i <= NR; i++) if (L[i] ~ /^- 진행:/) { at = i; break }
          if (at) while (at < NR && L[at + 1] ~ /^- 미감시 전송 /) at++
          for (i = 1; i <= NR; i++) { print L[i]; if (at && i == at) print rec }
          if (!at) print rec
        }' "$F" > "$F.tmp.$$" && mv "$F.tmp.$$" "$F" \
        || { rm -f "$F.tmp.$$"; echo "rc-send: 경고: 미감시 전송 기록 실패 ($F)" >&2; }
    fi
  fi
fi
exit 0
