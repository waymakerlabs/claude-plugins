#!/usr/bin/env bash
# install-sweep.sh — 받은편지함 점검(inbox-sweep) launchd 설치·제거 (계획 2026-11-11 §3 S3)
#
# 사용: install-sweep.sh               dry-run(기본): 만들 plist 경로·내용과 실행할 launchctl 명령만 출력. 아무것도 바꾸지 않음
#       install-sweep.sh --apply       plist 를 ~/Library/LaunchAgents 에 쓰고 launchctl bootstrap gui/<uid>
#                                      (이미 같은 내용으로 등록돼 있으면 아무것도 바꾸지 않음 — 멱등)
#       install-sweep.sh --uninstall   launchctl bootout 뒤 plist 를 ~/.claude/archive/agent-orchestrator/ 로 옮김(삭제 아님)
#       (--uninstall --dry-run 은 할 일만 출력)
# 틀: 이 폴더의 kr.waymakerlabs.agent-orchestrator.inbox-sweep.plist (__HOME__ → $HOME)
# 시험 전용: AO_LAUNCHCTL(기본 /bin/launchctl — 가짜로 바꿔 호출만 기록), AO_TS(보관 폴더 이름의 시각)
# 종료: 0 / 2 인자 / 3 대상 자리에 다른 내용의 plist(--apply 가 덮어쓰지 않음 — 먼저 --uninstall) / 4 실패 / 12 틀·plutil 없음
# bash 3.2 호환.
set -u

HERE=$(cd -P "$(dirname "$0")" && pwd)
LABEL=kr.waymakerlabs.agent-orchestrator.inbox-sweep
TPL="$HERE/$LABEL.plist"
DST="$HOME/Library/LaunchAgents/$LABEL.plist"
LC=${AO_LAUNCHCTL:-/bin/launchctl}
UID_=$(id -u)
DOM="gui/$UID_"
die() { local c=$1; shift; echo "install-sweep.sh: $*" >&2; exit "$c"; }

mode=dry; dry=0
for a in "$@"; do
  case "$a" in
    --apply) mode=apply ;;
    --uninstall) mode=uninstall ;;
    --dry-run) dry=1 ;;
    *) die 2 "알 수 없는 인자: $a (사용: [--apply|--uninstall] [--dry-run])" ;;
  esac
done
[ "$mode" = apply ] && [ "$dry" = 1 ] && die 2 "--apply 와 --dry-run 은 함께 쓸 수 없음"
[ -f "$TPL" ] || die 12 "틀 없음: $TPL"
command -v plutil >/dev/null 2>&1 || die 12 "plutil 없음"

render() { sed "s#__HOME__#$HOME#g" "$TPL"; }
loaded() { "$LC" print "$DOM/$LABEL" >/dev/null 2>&1; }

if [ "$mode" = uninstall ]; then
  ARC="$HOME/.claude/archive/agent-orchestrator/inbox-sweep-${AO_TS:-$(date +%Y%m%d-%H%M%S)}"
  if [ "$dry" = 1 ]; then
    echo "할 일	$LC bootout $DOM/$LABEL (등록돼 있을 때만)"
    if [ -e "$DST" ]; then echo "할 일	mv $DST $ARC/"; else echo "없음	$DST"; fi
    exit 0
  fi
  if loaded; then "$LC" bootout "$DOM/$LABEL" 2>/dev/null || die 4 "launchctl bootout 실패"; echo "해제	$DOM/$LABEL"; fi
  if [ -e "$DST" ]; then
    # 같은 초에 두 번 보관해도 앞 보관본을 덮어쓰지 않는다(크로스체크 S3 1회차 #4): 빈 자리를 찾고 mv -n
    base=$ARC; i=1
    while [ -e "$ARC/${DST##*/}" ]; do ARC="$base.$i"; i=$((i + 1)); done
    mkdir -p "$ARC" && mv -n "$DST" "$ARC/" && [ ! -e "$DST" ] || die 4 "보관 실패: $DST → $ARC"
    echo "보관	$DST → $ARC/"
  else
    echo "없음	$DST"
  fi
  exit 0
fi

NEW=$(render)
TMPF=$(mktemp "${TMPDIR:-/tmp}/ao-sweep-plist.XXXXXX") || die 4 "임시 파일 실패"
trap 'rm -f "$TMPF"' EXIT
printf '%s\n' "$NEW" > "$TMPF"
plutil -lint "$TMPF" >/dev/null || die 4 "만든 plist 가 plutil -lint 실패"
same=0; [ -f "$DST" ] && cmp -s "$TMPF" "$DST" && same=1

if [ "$mode" = dry ]; then
  echo "== dry-run (아무것도 바꾸지 않음). 실행하려면 --apply"
  echo "plist	$DST	$( [ "$same" = 1 ] && echo '같은 내용 있음(유지)' || { [ -e "$DST" ] && echo '다른 내용 있음(--apply 거부 3)' || echo '새로 만듦'; } )"
  echo "launchd	$DOM/$LABEL	$(loaded && echo '등록됨' || echo '등록 안 됨')"
  echo "할 일	mkdir -p $HOME/.local/state/agent-orchestrator/inbox/sweep"
  [ "$same" = 1 ] || echo "할 일	write $DST"
  loaded && [ "$same" = 1 ] || echo "할 일	$LC bootstrap $DOM $DST"
  echo "확인	$LC print $DOM/$LABEL"
  echo "== plist 내용"
  printf '%s\n' "$NEW"
  exit 0
fi

# --apply
if [ -e "$DST" ] && [ "$same" = 0 ]; then die 3 "다른 내용의 plist 가 있음(덮어쓰지 않음, 먼저 --uninstall): $DST"; fi
mkdir -p "$HOME/.local/state/agent-orchestrator/inbox/sweep" "$HOME/Library/LaunchAgents" || die 4 "폴더 생성 실패"
if [ "$same" = 0 ]; then
  cp "$TMPF" "$DST" && chmod 644 "$DST" || die 4 "plist 쓰기 실패: $DST"
  echo "생성	$DST"
else
  echo "유지	$DST"
fi
if loaded; then
  echo "유지	$DOM/$LABEL (이미 등록됨)"
else
  "$LC" bootstrap "$DOM" "$DST" || die 4 "launchctl bootstrap 실패"
  echo "등록	$DOM/$LABEL"
fi
