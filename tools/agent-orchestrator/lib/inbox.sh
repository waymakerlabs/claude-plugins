# lib/inbox.sh — 받은편지함(파일 기반 세션 간 메시지). 진입점이 백엔드 결정 전에 source한다.
#
# 계약 진본: docs/plans/2026-11-08-agent-orchestrator-plan.md §1-4
#   inbox-send [--raw] <대상> <한 줄>     stdout watched|unwatched (참고용 — 전달·처리 확인 아님)
#   inbox-watch <대상>                    Monitor 명령. 줄마다 "#<n> <원문>"(flush). 종료 = 신호
#   inbox-watch --ack <대상> <n>          cursor를 n으로(현재보다 클 때만)
#   inbox-watch --pending <대상>          미처리 줄을 여러 줄로 내고 종료
#   inbox-watch --release <대상>          이전 세션 보류 범위(log.held) 해제
#   inbox-watch --state <대상>            감시 판정 monitor|waiter|none (계획 2026-11-11 §2-2)
# 대상 = 절대 경로(*.log) 또는 pane id(→ $AO_STATE_ROOT/inbox/pane-<:를 _>.log).
# 상태 루트 AO_STATE_ROOT(기본 ~/.local/state/agent-orchestrator). 시험은 임시 폴더를 준다.
# 종료 코드: 0 / 2 인자·대상 형식(4000자 초과 포함) / 4 기록·잠금·ack 실패.
#   부가 기록(times·known·events·ackts) 실패는 stderr 경고 한 줄 + 0(계획 §2-7).
# 잠금 = 커널 flock(/usr/bin/perl 경유). macOS bash 3.2.
# AO_INBOX_TRACE=<파일> 은 시험 전용: 임계구역 진입·이탈을 기록한다(겹침 검사).
# AO_INBOX_NOW=<epoch> 은 시험 전용: times·ackts·events 의 시각을 고정한다.
# shellcheck shell=bash

AO_STATE_ROOT=${AO_STATE_ROOT:-$HOME/.local/state/agent-orchestrator}
AO_INBOX_DIR="$AO_STATE_ROOT/inbox"
AO_INBOX_MAX=4000
_AOI_LOG=""; _AOI_LOCK=""; _AOI_MARK=""; _AOI_TOKEN=""; _AOI_PIDS=""; _AOI_TMPD=""
_AOI_CUR=0; _AOI_LO=0; _AOI_HI=0

_aoi_usage() {
  ao_die 2 "$*  (사용: inbox-send [--raw] <대상> <한 줄> | inbox-watch <대상> | inbox-watch --ack <대상> <n> | --pending <대상> | --state <대상> | --release <대상>)"
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
# 일반 잠금: _aoi_flock <fd 9|8|7> <파일> → 0 잡음 / 4 열기·perl 실패 / 7 대기 초과(죽지 않는다).
#   실패 사유는 _AOI_FLOCK_ERR. 잡은 파일은 _AOI_LOCK<fd>(해제·trap용).
#   fd 용도(계획 §1): 9 = <log>.flock·known.list.flock(순간), 8 = $AO_INBOX_DIR/recv.flock(수신 잠금),
#   7 = wait/<sid>.swap(교체). 잠금 순서는 항상 7 → 8 → 9(역순 금지 — 교착 방지).
_AOI_LOCK7=""; _AOI_LOCK8=""; _AOI_LOCK9=""; _AOI_FLOCK_ERR=""
_aoi_flock() {
  local fd=$1 F=$2 rc
  case "$fd" in 7|8|9) ;; *) _AOI_FLOCK_ERR="지원하지 않는 fd: $fd"; return 4 ;; esac
  [ -x "$AO_PERL" ] || { _AOI_FLOCK_ERR="잠금에 쓸 perl 없음: $AO_PERL"; return 4; }
  # 묶음 밖 stderr는 그대로(exec 단독이면 2>/dev/null이 셸에 남는다)
  { eval "exec $fd>>\"\$F\""; } 2>/dev/null || { _AOI_FLOCK_ERR="잠금 파일 열기 실패: $F"; return 4; }
  eval "_AOI_LOCK$fd=\$F"
  "$AO_PERL" -MFcntl=:flock -MTime::HiRes=sleep -e '
    open(my $f, ">&=", $ARGV[1]) or exit 4;
    for (1 .. $ARGV[0]) { exit 0 if flock($f, LOCK_EX | LOCK_NB); sleep 0.05 }
    exit 7' "${AO_INBOX_LOCK_TRIES:-200}" "$fd"; rc=$?
  case "$rc" in
    0) return 0 ;;
    7) _aoi_funlock "$fd"; _AOI_FLOCK_ERR="잠금 대기 시간 초과: $F"; return 7 ;;
    *) _aoi_funlock "$fd"; _AOI_FLOCK_ERR="잠금 실패(perl rc=$rc): $F"; return 4 ;;
  esac
}
# _aoi_funlock <fd> — 쥔 적 없으면 무동작
_aoi_funlock() {
  local fd=$1 cur
  eval "cur=\${_AOI_LOCK$fd:-}"
  [ -n "$cur" ] || return 0
  # 변수를 먼저 비운다: 닫은 뒤·비우기 전 TERM 이면 정리가 "쥐고 있다"로 오판해 잠금 없이 지운다
  # (크로스체크 3회차 #1). 비운 뒤·닫기 전 TERM 은 정리가 fd 를 다시 열어 새로 잡으므로 안전하다
  eval "_AOI_LOCK$fd="
  eval "exec $fd>&-"
}
# 받은편지함 기록 잠금(fd 9, <log>.flock). 실패 4(기존 동작)
_aoi_lock() {
  _aoi_flock 9 "$_AOI_LOG.flock" || ao_die 4 "$_AOI_FLOCK_ERR"
  _AOI_LOCK=$_AOI_LOCK9
}
_aoi_unlock() { _aoi_funlock 9; _AOI_LOCK=""; }
# 수신 잠금(fd 8, $AO_INBOX_DIR/recv.flock). 실패 4. 단계 B(inbox-wait·subscribe)가 쓴다
_aoi_recv_lock() {
  mkdir -p "$AO_INBOX_DIR" 2>/dev/null || ao_die 4 "상태 폴더 생성 실패: $AO_INBOX_DIR"
  _aoi_flock 8 "$AO_INBOX_DIR/recv.flock" || ao_die 4 "$_AOI_FLOCK_ERR"
}
_aoi_recv_unlock() { _aoi_funlock 8; }

# trap: 잠금·복구 잠금 해제, 내 토큰일 때만 watch 표식 정리, 자식(tail·awk) 종료
_aoi_cleanup() {
  local p tok=""
  for p in $_AOI_PIDS; do kill "$p" 2>/dev/null; done
  _aoi_unlock; _aoi_funlock 8; _aoi_funlock 7
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

# ── 부가 기록 공용(계획 §2-7·§2-9)
# 지금 epoch(시험은 AO_INBOX_NOW로 고정)
_aoi_now() { if [[ ${AO_INBOX_NOW:-} =~ ^[0-9]+$ ]]; then echo "$AO_INBOX_NOW"; else date +%s; fi; }
# _aoi_box_name <log 절대 경로> → 표시 이름. $AO_INBOX_DIR 아래면 상대 경로, 아니면 파일 이름(둘 다 .log 뺌)
_aoi_box_name() {
  local p=$1
  case "$p" in "$AO_INBOX_DIR"/*) p=${p#"$AO_INBOX_DIR"/} ;; *) p=${p##*/} ;; esac
  printf '%s\n' "${p%.log}"
}
# _aoi_pane_key <log 절대 경로> → pane 받은편지함($AO_INBOX_DIR/pane-*.log 바로 아래)이면 키 출력·0, 아니면 1
_aoi_pane_key() {
  local p=$1 b
  [ "${p%/*}" = "$AO_INBOX_DIR" ] || return 1
  b=${p##*/}
  case "$b" in pane-?*.log) printf '%s\n' "${b%.log}"; return 0 ;; esac
  return 1
}
# _aoi_event <ev> <box 경로|-> [k=v …] → events.log 한 줄(512바이트 이하, >> 한 번). 실패 1(죽지 않음).
#   원문은 넘기지 않는다(호출자 책임 — 칸 값은 번호·시각·식별자만).
_aoi_event() {
  local ev=$1 box=$2 line kv LC_ALL=C
  shift 2
  [ "$box" = - ] || box=$(_aoi_box_name "$box")
  line="ts=$(_aoi_now)	ev=$ev	box=$box"
  for kv in "$@"; do line="$line	${kv//[$'\t\n\r']/ }"; done
  [ "${#line}" -le 511 ] || line=${line:0:511}
  mkdir -p "$AO_INBOX_DIR" 2>/dev/null || return 1
  { printf '%s\n' "$line" >> "$AO_INBOX_DIR/events.log"; } 2>/dev/null || return 1
}
# 부가 기록 실패 경고(이름을 쉼표로 묶어 한 줄). 종료 코드는 바꾸지 않는다
_aoi_meta_warn() {
  [ -n "$1" ] || return 0
  echo "agent-orchestrator: 경고: 부가 기록 실패($1) — 메시지는 기록됨, 다시 보내지 말 것" >&2
}
_AOI_META_FAIL=""
_aoi_meta_fail() { _AOI_META_FAIL="${_AOI_META_FAIL:+$_AOI_META_FAIL,}$1"; }
# known.list 에 경로 추가(없을 때만, known.list.flock 잠금 fd 9). 실패 1. 기록 잠금 밖에서 부른다
_aoi_known_add() {
  local K="$AO_INBOX_DIR/known.list"
  mkdir -p "$AO_INBOX_DIR" 2>/dev/null || return 1
  _aoi_flock 9 "$K.flock" || return 1
  if ! grep -qxF -- "$_AOI_LOG" "$K" 2>/dev/null; then
    { printf '%s\n' "$_AOI_LOG" >> "$K"; } 2>/dev/null || { _aoi_funlock 9; return 1; }
  fi
  _aoi_funlock 9
}

# ── 기록 계층: 받은 줄을 그대로(줄바꿈·탭·CR만 공백) 잠금 안에서 >>. 4000자 초과 2(자르지 않음)
#    같은 잠금 안에서 <log>.times 에 "<n>\t<epoch>"(n = append 뒤 줄 수). 결과 _AOI_SENT_N·_AOI_SENT_TS.
#    times 실패는 _AOI_META_FAIL 에 times 를 더하고 계속한다(append 실패만 4)
ao_inbox_append() {
  local line n
  [ -n "$1" ] || _aoi_usage "빈 줄"
  line=$(printf '%s' "$1" | LC_ALL=C tr '\n\t\r' '   ')
  n=$(printf '%s' "$line" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
  [ "$n" -le "$AO_INBOX_MAX" ] || _aoi_usage "줄이 ${n}자 — ${AO_INBOX_MAX}자 초과(자르지 않음)"
  _aoi_prepare
  _aoi_lock
  if [ -n "${AO_INBOX_TRACE:-}" ]; then echo "in $$" >> "$AO_INBOX_TRACE"; sleep 0.2; fi
  { printf '%s\n' "$line" >> "$_AOI_LOG"; } 2>/dev/null || ao_die 4 "기록 실패: $_AOI_LOG"
  _AOI_SENT_N=$(_aoi_count); _AOI_SENT_TS=$(_aoi_now)
  { printf '%s\t%s\n' "$_AOI_SENT_N" "$_AOI_SENT_TS" >> "$_AOI_LOG.times"; } 2>/dev/null || _aoi_meta_fail times
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
  local raw=0 line w
  [ "${1:-}" = --raw ] && { raw=1; shift; }
  [ $# = 2 ] || _aoi_usage "inbox-send [--raw] <대상> <한 줄>"
  _aoi_resolve "$1"
  [ -n "$2" ] || _aoi_usage "빈 줄"
  _aoi_traps
  if [ "$raw" = 1 ]; then line=$2; else line="$(date +%H:%M:%S) $2"; fi
  ao_inbox_append "$line"
  # 이 아래는 append 확정 뒤 — 어떤 실패도 4로 만들지 않는다(계획 §2-7)
  _aoi_known_add || _aoi_meta_fail known
  case "$(_aoi_watch_state)" in monitor|waiter) w=watched ;; *) w=unwatched ;; esac
  _aoi_event send "$_AOI_LOG" "n=$_AOI_SENT_N" "arr=$_AOI_SENT_TS" "watch=$w" || _aoi_meta_fail events
  _aoi_meta_warn "$_AOI_META_FAIL"
  echo "$w"
}

# _aoi_mark_ok <표식 파일> → 세 칸 "<pid> <lstart> <token>"의 pid가 살아 있고 lstart가 같으면 0.
#   토큰은 _AOI_MARK_TOK 에 남긴다. .watch 판정은 기존 160행 식과 같다(lstart 안의 공백 허용)
_aoi_mark_ok() {
  local mark mpid mrest mls
  _AOI_MARK_TOK=""
  mark=$(head -1 "$1" 2>/dev/null)
  mpid=${mark%% *}; mrest=${mark#* }; mls=${mrest% *}
  [[ $mpid =~ ^[0-9]+$ ]] && [ "$mrest" != "$mark" ] && [ -n "$mls" ] || return 1
  [ "$(_aoi_lstart "$mpid")" = "$mls" ] || return 1
  _AOI_MARK_TOK=${mrest##* }
}
# _aoi_watch_state → stdout monitor|waiter|none (계획 §2-2, 대상 _AOI_LOG). 판정 실패는 none
_aoi_watch_state() {
  local wf sid tok wtok pk pg pgsid iss ign isg
  if _aoi_mark_ok "$_AOI_LOG.watch"; then echo monitor; return 0; fi
  if [ -d "$_AOI_LOG.waiters" ] && [ ! -e "$AO_INBOX_DIR/hooks.off" ]; then
    pk=$(_aoi_pane_key "$_AOI_LOG") || pk=""
    for wf in "$_AOI_LOG.waiters"/*; do
      [ -f "$wf" ] || continue
      sid=${wf##*/}
      _aoi_mark_ok "$wf" || continue
      tok=$_AOI_MARK_TOK
      _aoi_mark_ok "$AO_INBOX_DIR/wait/$sid.pid" || continue
      wtok=$_AOI_MARK_TOK
      [ -n "$tok" ] && [ "$tok" = "$wtok" ] || continue
      if [ -n "$pk" ]; then
        IFS=$'\t' read -r pg pgsid 2>/dev/null < "$AO_INBOX_DIR/pane-gen/$pk" || continue
        IFS=$'\t' read -r ign isg 2>/dev/null < "$AO_INBOX_DIR/wait/$sid.issued" || continue
        [[ ${pg:-} =~ ^[0-9]+$ ]] && [ "$pgsid" = "$sid" ] && [ "$ign" = "$pk" ] && [ "$isg" = "$pg" ] || continue
      fi
      echo waiter; return 0
    done
  fi
  echo none
}

# ── inbox-watch --ack <대상> <n>
_aoi_ack() {
  local n=$1 total adv=0
  _aoi_prepare; _aoi_lock
  total=$(_aoi_count)
  [ "$n" -le "$total" ] || { _aoi_unlock; _aoi_usage "ack 번호 $n 이 마지막 줄($total)보다 큼"; }
  _aoi_cursor
  if [ "$n" -gt "$_AOI_CUR" ]; then
    _aoi_put "$_AOI_LOG.cursor" "$n"; adv=1
    # 실제로 전진시킨 범위만, 같은 fd 9 잠금 안에서(계획 §2-1 <log>.ackts)
    { printf '%s\t%s\t%s\n' "$((_AOI_CUR + 1))" "$n" "$(_aoi_now)" >> "$_AOI_LOG.ackts"; } 2>/dev/null || _aoi_meta_fail ackts
  fi
  _aoi_unlock
  if [ "$adv" = 1 ]; then
    _aoi_event ack "$_AOI_LOG" "n=$n" "sid=${CLAUDE_CODE_SESSION_ID:--}" || _aoi_meta_fail events
  fi
  _aoi_meta_warn "$_AOI_META_FAIL"
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

# ── _aoi_claim <sid> — owner·held 확정(계획 §2-3, 대상 _AOI_LOG). 모든 읽기 경로의 첫 단계.
#    세션 id가 있을 때만 기록·비교. 바뀌었고 미처리 줄이 있으면 보류 범위를 log.held 에. fd 9
_aoi_claim() {
  local sid=${1:-} old total
  [ -n "$sid" ] || return 0
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
}

# ── inbox-watch <대상>
_aoi_watch() {
  local sid=${CLAUDE_CODE_SESSION_ID:-} ls fifo tp ap
  _aoi_prepare
  : >> "$_AOI_LOG" 2>/dev/null || ao_die 4 "받은편지함 생성 실패: $_AOI_LOG"   # 비파괴 생성(: > 금지)
  _aoi_claim "$sid"
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

# ── inbox-watch [--ack <대상> <n> | --pending <대상> | --state <대상> | --release <대상> | <대상>]
ao_inbox_watch() {
  case "${1:-}" in
    --ack)
      [ $# = 3 ] || _aoi_usage "inbox-watch --ack <대상> <n>"
      _aoi_resolve "$2"; ao_is_uint "$3" || _aoi_usage "ack 번호는 양의 정수: $3"
      _aoi_traps; _aoi_ack "$3" ;;
    --pending)
      [ $# = 2 ] || _aoi_usage "inbox-watch --pending <대상>"
      _aoi_resolve "$2"; _aoi_pending ;;
    --state)
      [ $# = 2 ] || _aoi_usage "inbox-watch --state <대상>"
      _aoi_resolve "$2"; _aoi_watch_state ;;
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
