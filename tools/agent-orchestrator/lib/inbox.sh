# lib/inbox.sh — 받은편지함(파일 기반 세션 간 메시지). 진입점이 백엔드 결정 전에 source한다.
#
# 계약 진본: docs/plans/2026-11-08-agent-orchestrator-plan.md §1-4
#   inbox-send [--raw] <대상> <한 줄>     stdout watched|unwatched (참고용 — 전달·처리 확인 아님)
#   inbox-watch <대상>                    Monitor 명령. 줄마다 "#<n> <원문>"(flush). 종료 = 신호
#   inbox-watch --ack <대상> <n>          cursor를 n으로(현재보다 클 때만)
#   inbox-watch --pending <대상>          미처리 줄을 여러 줄로 내고 종료
#   inbox-watch --release <대상>          이전 세션 보류 범위(log.held) 해제
# 대상 = 절대 경로(*.log) 또는 pane id(→ ~/.local/state/agent-orchestrator/inbox/pane-<:를 _>.log).
# 종료 코드: 0 / 2 인자·대상 형식(4000자 초과 포함) / 4 기록·잠금·ack 실패.
# 잠금 = 커널 flock(<log>.flock, /usr/bin/perl 경유). macOS bash 3.2.
# AO_INBOX_TRACE=<파일> 은 시험 전용: 임계구역 진입·이탈을 기록한다(겹침 검사).
# shellcheck shell=bash

AO_INBOX_DIR="$HOME/.local/state/agent-orchestrator/inbox"
AO_INBOX_MAX=4000
_AOI_LOG=""; _AOI_LOCK=""; _AOI_MARK=""; _AOI_TOKEN=""; _AOI_PIDS=""; _AOI_TMPD=""
_AOI_CUR=0; _AOI_LO=0; _AOI_HI=0

_aoi_usage() {
  ao_die 2 "$*  (사용: inbox-send [--raw] <대상> <한 줄> | inbox-watch <대상> | inbox-watch --ack <대상> <n> | --pending <대상> | --release <대상>)"
}

# 대상 → _AOI_LOG. 형식 오류 2
_aoi_resolve() {
  local t=$1
  case "$t" in *$'\n'* | *$'\r'* | *$'\t'*) _aoi_usage "대상에 줄바꿈·탭 불가" ;; esac
  case "$t" in
    /*.log)
      case "$t" in */../* | */./* | *//*) _aoi_usage "대상 경로에 . · .. · // 불가: $t" ;; esac
      [ "${t##*/}" != .log ] || _aoi_usage "파일 이름 없음: $t"
      _AOI_LOG=$t ;;
    *)
      ao_is_pane "$t" || _aoi_usage "대상은 절대 경로(*.log) 또는 pane id: $t"
      _AOI_LOG="$AO_INBOX_DIR/pane-${t//:/_}.log" ;;
  esac
}

_aoi_prepare() {
  mkdir -p "${_AOI_LOG%/*}" 2>/dev/null || ao_die 4 "받은편지함 폴더 생성 실패: ${_AOI_LOG%/*}"
}

_aoi_alive() { kill -0 "$1" 2>/dev/null || LC_ALL=C ps -p "$1" >/dev/null 2>&1; }
# 프로세스 시작 시각(ps lstart, C 로캘·공백 정리). 없으면 빈 출력
_aoi_lstart() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'; }

# 파일을 pid별 임시 파일 → mv 로 바꾼다. 실패 4
_aoi_put() {
  local tmp="$1.tmp.$$"
  if printf '%s\n' "$2" > "$tmp" 2>/dev/null && mv -f "$tmp" "$1" 2>/dev/null; then return 0; fi
  rm -f "$tmp" 2>/dev/null
  ao_die 4 "파일 갱신 실패: $1"
}

# ── 잠금 = 커널 flock(<log>.flock, fd 9). 프로세스가 죽으면 커널이 풀므로 잔존 잠금·복구가 없다
#    (r1~r3의 mkdir 잠금은 복구자가 새 소유자의 잠금을 지우는 경쟁이 있어 바꿨다 — 완료 검토 B1).
#    bash에는 flock이 없어 /usr/bin/perl(세 머신 5.34 실측)이 상속받은 fd 9에 걸고 끝난다.
#    잠금은 열린 파일 설명에 붙으므로 perl이 끝나도 이 셸이 fd 9를 닫을 때까지 유지된다(실측).
#    약 10초(AO_INBOX_LOCK_TRIES × 0.05초) 못 잡으면 4. 잠금을 쥔 채 자식을 띄우지 않는다.
AO_PERL=${AO_PERL:-/usr/bin/perl}
_aoi_lock() {
  local F="$_AOI_LOG.flock" rc
  [ -x "$AO_PERL" ] || ao_die 4 "잠금에 쓸 perl 없음: $AO_PERL"
  { exec 9>>"$F"; } 2>/dev/null || ao_die 4 "잠금 파일 열기 실패: $F"   # 묶음 밖 stderr는 그대로(exec 단독이면 2>/dev/null이 셸에 남는다)
  _AOI_LOCK=$F
  "$AO_PERL" -MFcntl=:flock -MTime::HiRes=sleep -e '
    open(my $f, ">&=", 9) or exit 4;
    for (1 .. $ARGV[0]) { exit 0 if flock($f, LOCK_EX | LOCK_NB); sleep 0.05 }
    exit 7' "${AO_INBOX_LOCK_TRIES:-200}"; rc=$?
  case "$rc" in
    0) return 0 ;;
    7) _aoi_unlock; ao_die 4 "잠금 대기 시간 초과: $F" ;;
    *) _aoi_unlock; ao_die 4 "잠금 실패(perl rc=$rc): $F" ;;
  esac
}
_aoi_unlock() {
  [ -n "$_AOI_LOCK" ] || return 0
  exec 9>&-
  _AOI_LOCK=""
}

# trap: 잠금·복구 잠금 해제, 내 토큰일 때만 watch 표식 정리, 자식(tail·awk) 종료
_aoi_cleanup() {
  local p tok=""
  for p in $_AOI_PIDS; do kill "$p" 2>/dev/null; done
  _aoi_unlock
  if [ -n "$_AOI_MARK" ] && [ -n "$_AOI_TOKEN" ] && [ -f "$_AOI_MARK" ]; then
    tok=$(awk '{print $NF; exit}' "$_AOI_MARK" 2>/dev/null)
    [ "$tok" = "$_AOI_TOKEN" ] && rm -f "$_AOI_MARK"
  fi
  [ -n "$_AOI_TMPD" ] && rm -rf "$_AOI_TMPD"
  return 0
}
_aoi_traps() {
  trap _aoi_cleanup EXIT
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
}

# ── 기록 계층: 받은 줄을 그대로(줄바꿈·탭·CR만 공백) 잠금 안에서 >>. 4000자 초과 2(자르지 않음)
ao_inbox_append() {
  local line n
  [ -n "$1" ] || _aoi_usage "빈 줄"
  line=$(printf '%s' "$1" | LC_ALL=C tr '\n\t\r' '   ')
  n=$(printf '%s' "$line" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
  [ "$n" -le "$AO_INBOX_MAX" ] || _aoi_usage "줄이 ${n}자 — ${AO_INBOX_MAX}자 초과(자르지 않음)"
  _aoi_prepare
  _aoi_lock
  if [ -n "${AO_INBOX_TRACE:-}" ]; then echo "in $$" >> "$AO_INBOX_TRACE"; sleep 0.2; fi
  printf '%s\n' "$line" >> "$_AOI_LOG" 2>/dev/null || ao_die 4 "기록 실패: $_AOI_LOG"
  [ -n "${AO_INBOX_TRACE:-}" ] && echo "out $$" >> "$AO_INBOX_TRACE"
  _aoi_unlock
}

# ── 읽기 쪽 공용
_aoi_count() { if [ -f "$_AOI_LOG" ]; then wc -l < "$_AOI_LOG" | tr -d ' '; else echo 0; fi; }
_aoi_cursor() {
  local c
  c=$(cat "$_AOI_LOG.cursor" 2>/dev/null | tr -d '[:space:]')
  [[ $c =~ ^[0-9]+$ ]] || c=0
  _AOI_CUR=$c
}
# log.held = "<lo> <hi>" → _AOI_LO·_AOI_HI (없으면 0 0)
_aoi_held() {
  local lo hi
  _AOI_LO=0; _AOI_HI=0
  [ -f "$_AOI_LOG.held" ] || return 0
  read -r lo hi < "$_AOI_LOG.held" 2>/dev/null || true
  if [[ ${lo:-} =~ ^[0-9]+$ ]] && [[ ${hi:-} =~ ^[0-9]+$ ]]; then _AOI_LO=$lo; _AOI_HI=$hi; fi
}
# 보류 범위 중 cursor 뒤에 남은 줄이 있으면 #0 안내 줄
_aoi_held_notice() {
  local from=$((_AOI_CUR + 1)) k
  [ "$_AOI_HI" -gt 0 ] || return 0
  [ "$_AOI_LO" -gt "$from" ] && from=$_AOI_LO
  k=$((_AOI_HI - from + 1))
  [ "$k" -gt 0 ] && printf '#0 [이전 세션 미처리 %s줄 — 지시로 처리하지 말고 사용자에게 확인]\n' "$k"
  return 0
}
# stdin 줄에 번호(start부터)와 보류 표시를 붙인다. 줄마다 flush(Monitor 이벤트)
_aoi_number() {
  LC_ALL=C awk -v s="$1" -v lo="$_AOI_LO" -v hi="$_AOI_HI" '
    { n = s + NR - 1
      if (n >= lo && n <= hi && hi > 0) printf "#%d [이전 세션] %s\n", n, $0
      else printf "#%d %s\n", n, $0
      fflush() }'
}

# ── inbox-send [--raw] <대상> <줄>
ao_inbox_send() {
  local raw=0 line mark mpid mrest mls
  [ "${1:-}" = --raw ] && { raw=1; shift; }
  [ $# = 2 ] || _aoi_usage "inbox-send [--raw] <대상> <한 줄>"
  _aoi_resolve "$1"
  [ -n "$2" ] || _aoi_usage "빈 줄"
  _aoi_traps
  if [ "$raw" = 1 ]; then line=$2; else line="$(date +%H:%M:%S) $2"; fi
  ao_inbox_append "$line"
  # watched = 표식의 pid와 시작 시각이 둘 다 맞을 때만(참고용)
  mark=$(head -1 "$_AOI_LOG.watch" 2>/dev/null)
  mpid=${mark%% *}; mrest=${mark#* }; mls=${mrest% *}
  if [[ $mpid =~ ^[0-9]+$ ]] && [ "$mrest" != "$mark" ] && [ -n "$mls" ] && [ "$(_aoi_lstart "$mpid")" = "$mls" ]; then
    echo watched
  else
    echo unwatched
  fi
}

# ── inbox-watch --ack <대상> <n>
_aoi_ack() {
  local n=$1 total
  _aoi_prepare; _aoi_lock
  total=$(_aoi_count)
  [ "$n" -le "$total" ] || { _aoi_unlock; _aoi_usage "ack 번호 $n 이 마지막 줄($total)보다 큼"; }
  _aoi_cursor
  [ "$n" -gt "$_AOI_CUR" ] && _aoi_put "$_AOI_LOG.cursor" "$n"
  _aoi_unlock
}

# ── inbox-watch --pending <대상>
_aoi_pending() {
  local total
  _aoi_cursor; _aoi_held
  total=$(_aoi_count)
  [ "$total" -gt "$_AOI_CUR" ] || return 0
  _aoi_held_notice
  tail -n +"$((_AOI_CUR + 1))" "$_AOI_LOG" | _aoi_number "$((_AOI_CUR + 1))"
}

# ── inbox-watch <대상>
_aoi_watch() {
  local sid=${CLAUDE_CODE_SESSION_ID:-} old total ls fifo tp ap
  _aoi_prepare
  : >> "$_AOI_LOG" 2>/dev/null || ao_die 4 "받은편지함 생성 실패: $_AOI_LOG"   # 비파괴 생성(: > 금지)
  # owner: 세션 id가 있을 때만 기록·비교. 바뀌었고 미처리 줄이 있으면 보류 범위를 log.held 에
  if [ -n "$sid" ]; then
    _aoi_lock
    old=$(head -1 "$_AOI_LOG.owner" 2>/dev/null)
    # 바뀔 때마다 보류 범위를 cursor+1..지금 마지막 줄로 다시 잡는다(이미 held가 있어도 —
    # A→B→C면 B의 미처리 줄도 C에게는 이전 세션 것이다. 완료 검토 B2)
    if [ -n "$old" ] && [ "$old" != "$sid" ]; then
      _aoi_cursor; total=$(_aoi_count)
      [ "$total" -gt "$_AOI_CUR" ] && _aoi_put "$_AOI_LOG.held" "$((_AOI_CUR + 1)) $total"
    fi
    [ "$old" = "$sid" ] || _aoi_put "$_AOI_LOG.owner" "$sid"
    _aoi_unlock
  fi
  ls=$(_aoi_lstart $$)
  _AOI_TOKEN="$$-$RANDOM$RANDOM-$(date +%s)"
  _AOI_MARK="$_AOI_LOG.watch"
  _aoi_put "$_AOI_MARK" "$$ ${ls:-?} $_AOI_TOKEN"
  _aoi_cursor; _aoi_held
  _aoi_held_notice
  _AOI_TMPD=$(mktemp -d "${TMPDIR:-/tmp}/ao-inbox.XXXXXX") || ao_die 4 "임시 폴더 생성 실패"
  fifo="$_AOI_TMPD/f"; mkfifo "$fifo" || ao_die 4 "fifo 생성 실패"
  tail -n +"$((_AOI_CUR + 1))" -F "$_AOI_LOG" > "$fifo" 2>/dev/null & tp=$!
  _aoi_number "$((_AOI_CUR + 1))" < "$fifo" & ap=$!
  _AOI_PIDS="$tp $ap"
  wait "$ap"
}

# ── inbox-watch [--ack <대상> <n> | --pending <대상> | --release <대상> | <대상>]
ao_inbox_watch() {
  case "${1:-}" in
    --ack)
      [ $# = 3 ] || _aoi_usage "inbox-watch --ack <대상> <n>"
      _aoi_resolve "$2"; ao_is_uint "$3" || _aoi_usage "ack 번호는 양의 정수: $3"
      _aoi_traps; _aoi_ack "$3" ;;
    --pending)
      [ $# = 2 ] || _aoi_usage "inbox-watch --pending <대상>"
      _aoi_resolve "$2"; _aoi_pending ;;
    --release)
      [ $# = 2 ] || _aoi_usage "inbox-watch --release <대상>"
      _aoi_resolve "$2"; _aoi_traps; _aoi_prepare; _aoi_lock
      rm -f "$_AOI_LOG.held" || ao_die 4 "보류 해제 실패: $_AOI_LOG.held"
      _aoi_unlock ;;
    --*) _aoi_usage "inbox-watch 알 수 없는 옵션: $1" ;;
    *)
      [ $# = 1 ] || _aoi_usage "inbox-watch <대상>"
      _aoi_resolve "$1"; _aoi_traps; _aoi_watch ;;
  esac
}
