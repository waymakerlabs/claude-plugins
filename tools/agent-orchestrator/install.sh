#!/usr/bin/env bash
# install.sh — agent-orchestrator 설치(링크·config, 멱등) / 읽기 전용 점검
#
# 사용: install.sh --check <backend>     읽기 전용. core + <backend> manifest 항목 존재·rule 잔존 수 보고
#       install.sh <backend>             ~/.local/bin/agent-orchestrator 링크와 ~/.config/agent-orchestrator/config
#                                        (backend=<backend>) 생성. 이미 맞으면 아무것도 바꾸지 않음(멱등)
# 링크 대상(D6): ~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins/tools/agent-orchestrator/bin/agent-orchestrator
#   (AGENT_ORCHESTRATOR_LINK_TARGET 으로 덮어씀 — 시험용)
# 종료: 0 정상 / 1 --check 에서 필수 항목 없음 / 2 인자 오류 / 3 링크 자리에 다른 파일(덮어쓰지 않음)
#       / 12 manifest·python3 없음
# bash 3.2 호환.
set -u

HERE=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
MF="$HERE/lib/manifest.py"
die() { local c=$1; shift; echo "install.sh: $*" >&2; exit "$c"; }
# macOS /usr/bin/python3는 기본으로 ~/Library/Caches/com.apple.python 에 바이트코드를 쓴다 → --check가 진짜 읽기 전용이 되게 막는다
export PYTHONDONTWRITEBYTECODE=1

command -v python3 >/dev/null 2>&1 || die 12 "python3 없음"
[ -f "$MF" ] || die 12 "lib/manifest.py 없음"

backend_ok() {
  case "$1" in ''|*[!a-z0-9_-]*) die 2 "백엔드 이름 형식 오류: ${1:-없음}" ;; esac
  [ -f "$HERE/manifests/$1.manifest" ] || die 12 "manifest 없음: manifests/$1.manifest"
}

if [ "${1:-}" = --check ]; then
  [ $# = 2 ] || die 2 "사용: install.sh --check <backend>"
  backend_ok "$2"
  rc=0
  for m in core "$2"; do
    AO_REPO=$REPO python3 "$MF" check "$HERE/manifests/$m.manifest" || rc=$?
  done
  exit "$rc"
fi

[ $# = 1 ] || die 2 "사용: install.sh <backend> | install.sh --check <backend>"
case "$1" in -*) die 2 "알 수 없는 옵션: $1" ;; esac
backend_ok "$1"

LINK="$HOME/.local/bin/agent-orchestrator"
TARGET=${AGENT_ORCHESTRATOR_LINK_TARGET:-$HOME/.claude/plugins/marketplaces/waymakerlabs-claude-plugins/tools/agent-orchestrator/bin/agent-orchestrator}
CONF="$HOME/.config/agent-orchestrator/config"

[ -x "$TARGET" ] || die 12 "링크 대상이 없거나 실행 불가: $TARGET (마켓플레이스 갱신 먼저)"

if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$TARGET" ]; then
  echo "유지	link	$LINK → $TARGET"
elif [ -L "$LINK" ]; then
  ln -sfn "$TARGET" "$LINK" && echo "갱신	link	$LINK → $TARGET (이전 $(readlink "$LINK"))"
elif [ -e "$LINK" ]; then
  die 3 "링크 자리에 일반 파일이 있음(덮어쓰지 않음): $LINK"
else
  mkdir -p "$(dirname "$LINK")" && ln -s "$TARGET" "$LINK" && echo "생성	link	$LINK → $TARGET"
fi

want="backend=$1"
if [ -f "$CONF" ] && grep -qx "$want" "$CONF"; then
  echo "유지	config	$CONF ($want)"
elif [ -f "$CONF" ] && grep -q '^backend=' "$CONF"; then
  # 값만 바꾼다(다른 줄 보존). 임시 파일 → 교체
  tmp="$CONF.ao-tmp"
  sed "s/^backend=.*/$want/" "$CONF" > "$tmp" && mv "$tmp" "$CONF" && echo "갱신	config	$CONF ($want)"
else
  mkdir -p "$(dirname "$CONF")" && echo "$want" >> "$CONF" && echo "생성	config	$CONF ($want)"
fi
