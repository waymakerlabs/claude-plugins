#!/usr/bin/env bash
# uninstall-backend.sh — 백엔드 설치물 보관(archive-first). 기본 --dry-run
#
# 사용: uninstall-backend.sh <backend> [--dry-run|--apply]
#   dry-run(기본): core + <backend> manifest 각 항목의 처리 계획만 출력. 파일 변경 0
#   --apply: herdr·ours-backend 파일은 ~/.claude/archive/agent-orchestrator/<backend>-<ts>/ 로 이동,
#            JSON 설정은 원본 백업 후 해당 항목만 제거. rule은 위치만 출력(자동 수정 안 함),
#            existing·ours-core는 "보존"으로만 표시하고 건드리지 않음. 리포 파일은 git 이력이 보관
# 종료: 0 / 2 인자 오류 / 12 manifest·python3 없음·형식 오류
# bash 3.2 호환.
set -u

HERE=$(cd -P "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
MF="$HERE/lib/manifest.py"
die() { local c=$1; shift; echo "uninstall-backend.sh: $*" >&2; exit "$c"; }
# dry-run 파일 변경 0을 지키려고 python 바이트코드 캐시 쓰기를 막는다(~/Library/Caches/com.apple.python)
export PYTHONDONTWRITEBYTECODE=1

command -v python3 >/dev/null 2>&1 || die 12 "python3 없음"
[ -f "$MF" ] || die 12 "lib/manifest.py 없음"
[ $# -ge 1 ] && [ $# -le 2 ] || die 2 "사용: uninstall-backend.sh <backend> [--dry-run|--apply]"
b=$1; mode=${2:---dry-run}
case "$b" in ''|-*|*[!a-z0-9_-]*) die 2 "백엔드 이름 형식 오류: $b" ;; esac
[ "$b" != core ] || die 2 "core는 백엔드가 아님(오케스트레이터 자체 — 보존 대상)"
[ -f "$HERE/manifests/$b.manifest" ] || die 12 "manifest 없음: manifests/$b.manifest"
case "$mode" in
  --dry-run) apply=() ;;
  --apply) apply=(--apply) ;;
  *) die 2 "알 수 없는 옵션: $mode" ;;
esac

AO_REPO=$REPO exec python3 "$MF" uninstall "$b" "$HERE/manifests/core.manifest" "$HERE/manifests/$b.manifest" ${apply[@]+"${apply[@]}"}
