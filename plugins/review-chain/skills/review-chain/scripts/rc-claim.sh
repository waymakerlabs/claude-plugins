#!/usr/bin/env bash
# rc-claim.sh — worker 파일 범위 선점·충돌 판정 (0.1.2, 0.2.0 미감시 기록)
#
# 사용:
#   rc-claim.sh <chain 폴더> <이름> <경로|glob> [...]   범위 선점(처음·확대 모두). 리포 루트 기준 경로
#   rc-claim.sh --release <chain 폴더> <이름>           그 worker 선점 전부 해제(OC — 병합·닫기·승격 뒤)
#   rc-claim.sh --list <chain 폴더>                     살아 있는 선점 출력
#
# 진본: <chain 폴더>/claims.tsv  (이름 TAB 패턴 TAB active|released TAB 시각)
# 공용 파일: <chain 폴더>/shared-files (OC가 체인 시작 때 한 줄 한 패턴). 걸리면 선점 거부.
# 판정(보수적 — 애매하면 충돌):
#   두 패턴의 고정 접두(첫 * ? [ 앞까지)를 구한다. glob이 하나라도 있으면 한쪽 접두가 다른 쪽
#   접두로 시작하면 충돌. glob이 없으면 같은 경로이거나 한쪽이 다른 쪽의 폴더(<a>/…)면 충돌.
#   끝의 / 와 /** 는 폴더로 본다.
# 동작: 잠금(claims.lock 폴더) → 판정 → 겹침 없음이면 기록하고 0. 겹치면 기록하지 않고
#   OC 받은편지함(inbox.log)에 [충돌] 한 줄을 남기고 4. 공용 파일이면 5.
#   [충돌] 줄은 `agent-orchestrator inbox-send --raw`로 덧붙인다(rc-send.sh 와 같은 잠금).
#   (0.2.0) inbox-send stdout 이 unwatched(빈 값·이상값 포함)면 $RC/workers/<이름>/report.md 에
#   `- 미감시 전송 <받은편지함> <HH:MM>` 한 줄을 덧붙인다(report.md 가 없으면 조용히 생략, 쓰기 실패는 경고만).
#   환경: AGENT_ORCHESTRATOR=<실행 파일> (기본 ~/.local/bin/agent-orchestrator)
#   이미 같은 worker가 같은 패턴을 쥐고 있으면 다시 쓰지 않는다(재실행 무해).
# 종료 코드: 0 선점 / 2 인자 / 4 충돌(대기 — OC 답을 기다린다) / 5 공용 파일 / 6 잠금 실패
# bash 3.2 호환.

set -u

die() { code=$1; shift; echo "rc-claim: $*" >&2; exit "$code"; }

norm() { local p=$1; p=${p#./}; p=${p%/\*\*}; p=${p%/}; printf '%s' "$p"; }
prefix() { local p=$1; p=${p%%[*?[]*}; printf '%s' "$p"; }
has_glob() { case "$1" in *[*?[]*) return 0 ;; esac; return 1; }

overlap() {
  local a b pa pb
  a=$(norm "$1"); b=$(norm "$2")
  if has_glob "$a" || has_glob "$b"; then
    pa=$(prefix "$a"); pb=$(prefix "$b")
    case "$pa" in "$pb"*) return 0 ;; esac
    case "$pb" in "$pa"*) return 0 ;; esac
    return 1
  fi
  [ "$a" = "$b" ] && return 0
  case "$a" in "$b"/*) return 0 ;; esac
  case "$b" in "$a"/*) return 0 ;; esac
  return 1
}

lock() {
  local i=0
  until mkdir "$RC/claims.lock" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -ge 50 ] && die 6 "잠금 실패: $RC/claims.lock (다른 선점이 끝나지 않음 — 오래 남았으면 OC가 확인 뒤 지운다)"
    sleep 0.2
  done
  trap 'rmdir "$RC/claims.lock" 2>/dev/null' EXIT
}

chk_rc() { case "$RC" in /*) ;; *) die 2 "chain 폴더는 절대 경로: $RC" ;; esac; [ -d "$RC" ] || die 2 "chain 폴더 없음: $RC"; }
chk_name() { [[ $1 =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die 2 "이름 형식 오류: $1"; }

case "${1:-}" in
  --list)
    [ $# = 2 ] || die 2 "사용: $0 --list <chain 폴더>"
    RC=${2%/}; chk_rc
    [ -f "$RC/claims.tsv" ] && awk -F'\t' '$3 == "active"' "$RC/claims.tsv"
    exit 0 ;;
  --release)
    [ $# = 3 ] || die 2 "사용: $0 --release <chain 폴더> <이름>"
    RC=${2%/}; chk_rc; chk_name "$3"; lock
    [ -f "$RC/claims.tsv" ] || exit 0
    awk -F'\t' -v OFS='\t' -v n="$3" -v t="$(date +%H:%M:%S)" '$1 == n && $3 == "active" { $3 = "released"; $4 = t } { print }' \
      "$RC/claims.tsv" > "$RC/claims.tsv.tmp" && mv "$RC/claims.tsv.tmp" "$RC/claims.tsv"
    echo "RELEASED $3"
    exit 0 ;;
esac

[ $# -ge 3 ] || die 2 "사용: $0 <chain 폴더> <이름> <경로|glob> [...]"
RC=${1%/}; NAME=$2; shift 2
chk_rc; chk_name "$NAME"
for p in "$@"; do
  case "$p" in /*|*..*|-*) die 2 "리포 루트 기준 상대 경로만: $p" ;; esac
  case "$p" in *$'\t'*|*$'\n'*) die 2 "탭·줄바꿈 금지: $p" ;; esac
done

lock
touch "$RC/claims.tsv"

if [ -f "$RC/shared-files" ]; then
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    for p in "$@"; do overlap "$p" "$s" && die 5 "공용 파일(OC 전용): ${p} ↔ ${s} — 범위에서 빼고 다시 선점"; done
  done < "$RC/shared-files"
fi

HITS=""
while IFS=$'\t' read -r n q st _; do
  [ "$st" = active ] && [ "$n" != "$NAME" ] || continue
  for p in "$@"; do overlap "$p" "$q" && HITS="${HITS} ${p}↔${n}:${q}"; done
done < "$RC/claims.tsv"

if [ -n "$HITS" ]; then
  AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}
  LINE=$(printf '%s [rc %s] [WO %s] [충돌] %s/workers/%s/report.md 선점 거부:%s' \
    "$(date +%H:%M:%S)" "$(basename "$RC")" "$NAME" "$RC" "$NAME" "$HITS")
  if W=$("$AO" inbox-send --raw "$RC/inbox.log" "$LINE"); then
    W=$(printf '%s' "$W" | tr -d '[:space:]')
    if [ "$W" != watched ]; then
      # 미감시 전송 기록(0.2.0): 보고서 `- 진행:` 줄 아래(없으면 끝). 실패해도 경고만
      F="$RC/workers/$NAME/report.md"
      if [ -f "$F" ]; then
        "$(cd "$(dirname "$0")" && pwd)/rc-note-unwatched.sh" report "$F" "- 미감시 전송 $RC/inbox.log $(date +%H:%M)" 2>/dev/null \
          || echo "rc-claim: 경고: 미감시 전송 기록 실패 ($F)" >&2
      fi   # report.md 없으면 조용히 생략(stderr 를 이전과 똑같이 유지)
    fi
  else
    echo "rc-claim: 경고: 충돌 알림 기록 실패 ($RC/inbox.log) — OC에 직접 알릴 것" >&2
  fi
  echo "CONFLICT$HITS" >&2
  exit 4
fi

NOW=$(date +%H:%M:%S)
for p in "$@"; do
  awk -F'\t' -v n="$NAME" -v q="$p" '$1 == n && $2 == q && $3 == "active" { f = 1 } END { exit !f }' "$RC/claims.tsv" && continue
  printf '%s\t%s\tactive\t%s\n' "$NAME" "$p" "$NOW" >> "$RC/claims.tsv"
done
echo "CLAIMED $NAME $*"
