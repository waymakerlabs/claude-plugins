# lib/inbox.sh — 받은편지함(파일 기반 세션 간 메시지). 진입점이 백엔드 결정 전에 source한다.
#
# 계약 진본: docs/plans/2026-11-08-agent-orchestrator-plan.md §1-4, 2026-11-11-inbox-simplify-plan.md §2
#   inbox-send [--raw] <대상> <한 줄>     stdout watched|unwatched (참고용 — 전달·처리 확인 아님)
#   inbox-watch <대상>                    Monitor 명령. 줄마다 "#<n> <원문>"(flush). 종료 = 신호
#   inbox-watch --ack <대상> <n>          cursor를 n으로(현재보다 클 때만)
#   inbox-watch --pending <대상>          미처리 줄을 여러 줄로 내고 종료
#   inbox-watch --release <대상>          이전 세션 보류 범위(log.held) 해제
#   inbox-watch --state <대상>            감시 판정 monitor|waiter|none
# 대상 = 절대 경로(*.log) 또는 pane id(→ $AO_STATE_ROOT/inbox/pane-<:를 _>.log).
# 상태 루트 AO_STATE_ROOT(기본 ~/.local/state/agent-orchestrator). 시험은 임시 폴더를 준다.
# 종료 코드: 0 / 2 인자·대상 형식(4000자 초과 포함) / 3 inbox-send 대상 pane 없음(herdr 확인, 줄은 기록됨)
#   / 4 기록·잠금·ack 실패.
# events.log 는 send·wake 두 사건만(실패는 무시). 잠금 = 커널 flock(fd 9, /usr/bin/perl 경유). bash 3.2.
# shellcheck shell=bash

AO_STATE_ROOT=${AO_STATE_ROOT:-$HOME/.local/state/agent-orchestrator}
AO_INBOX_DIR="$AO_STATE_ROOT/inbox"
AO_INBOX_MAX=4000
_AOI_LOG=""; _AOI_LOCK=""; _AOI_MARK=""; _AOI_TOKEN=""; _AOI_PIDS=""; _AOI_TMPD=""
_AOI_CUR=0; _AOI_LO=0; _AOI_HI=0

_aoi_usage() { ao_die 2 "$*  (사용: inbox-send [--raw] <대상> <한 줄> | inbox-watch <대상> | inbox-watch --ack <대상> <n> | --pending <대상> | --state <대상> | --release <대상>)"; }

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

_aoi_prepare() { mkdir -p "${_AOI_LOG%/*}" 2>/dev/null || ao_die 4 "받은편지함 폴더 생성 실패: ${_AOI_LOG%/*}"; }

# 프로세스 시작 시각(ps lstart, C 로캘·공백 정리). 없으면 빈 출력
_aoi_lstart() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'; }

# 파일을 pid별 임시 파일 → mv 로 바꾼다. 실패 4
_aoi_put() {
  local tmp="$1.tmp.$$"
  if printf '%s\n' "$2" > "$tmp" 2>/dev/null && mv -f "$tmp" "$1" 2>/dev/null; then return 0; fi
  rm -f "$tmp" 2>/dev/null
  ao_die 4 "파일 갱신 실패: $1"
}

# ── 잠금 = 커널 flock(fd 9, 죽으면 커널이 푼다). perl이 상속받은 fd 9에 걸고 끝난다(열린 파일 설명에 붙어 유지).
#    _aoi_flock <파일> — <log>.flock(기록)·subs/<키>.flock(구독), 한 번에 하나. 약 10초 못 잡으면 4.
AO_PERL=${AO_PERL:-/usr/bin/perl}
_aoi_flock() {
  local F=$1 rc
  [ -x "$AO_PERL" ] || ao_die 4 "잠금에 쓸 perl 없음: $AO_PERL"
  { exec 9>>"$F"; } 2>/dev/null || ao_die 4 "잠금 파일 열기 실패: $F"   # 묶음 밖 stderr는 그대로
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
_aoi_lock() { _aoi_flock "$_AOI_LOG.flock"; }
_aoi_unlock() { [ -n "$_AOI_LOCK" ] || return 0; _AOI_LOCK=""; exec 9>&-; }

# trap: 잠금 해제, 내 토큰일 때만 watch 표식 정리, 자식(tail·awk) 종료
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
_aoi_traps() { trap _aoi_cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; }

# _aoi_pane_key <log 절대 경로> → pane 받은편지함($AO_INBOX_DIR/pane-*.log 바로 아래)이면 키 출력·0, 아니면 1
_aoi_pane_key() {
  local b=${1##*/}
  [ "${1%/*}" = "$AO_INBOX_DIR" ] || return 1
  case "$b" in pane-?*.log) printf '%s\n' "${b%.log}"; return 0 ;; esac
  return 1
}
# _aoi_event <ev> <box 경로|-> [k=v …] → events.log 한 줄 "ts ev box k=v…"(탭 구분). 실패는 무시한다.
#   원문은 넘기지 않는다(칸 값은 번호·식별자만).
_aoi_event() {
  local ev=$1 box=$2 line kv LC_ALL=C
  shift 2
  # 표시 이름: $AO_INBOX_DIR 아래면 상대 경로, 아니면 파일 이름(둘 다 .log 뺌)
  case "$box" in -) ;; "$AO_INBOX_DIR"/*) box=${box#"$AO_INBOX_DIR"/}; box=${box%.log} ;; *) box=${box##*/}; box=${box%.log} ;; esac
  line="ts=$(date +%s)	ev=$ev	box=$box"
  for kv in "$@"; do line="$line	${kv//[$'\t\n\r']/ }"; done
  { mkdir -p "$AO_INBOX_DIR" && printf '%s\n' "${line:0:511}" >> "$AO_INBOX_DIR/events.log"; } 2>/dev/null
  return 0
}

# ── 기록 계층: 받은 줄을 그대로(줄바꿈·탭·CR만 공백) 잠금 안에서 >>. 4000자 초과 2(자르지 않음). 결과 _AOI_SENT_N
ao_inbox_append() {
  local line n
  [ -n "$1" ] || _aoi_usage "빈 줄"
  line=$(printf '%s' "$1" | LC_ALL=C tr '\n\t\r' '   ')
  n=$(printf '%s' "$line" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
  [ "$n" -le "$AO_INBOX_MAX" ] || _aoi_usage "줄이 ${n}자 — ${AO_INBOX_MAX}자 초과(자르지 않음)"
  _aoi_prepare
  _aoi_lock
  { printf '%s\n' "$line" >> "$_AOI_LOG"; } 2>/dev/null || ao_die 4 "기록 실패: $_AOI_LOG"
  _AOI_SENT_N=$(_aoi_count)
  _aoi_unlock
}

# ── 읽기 쪽 공용
_aoi_count() { if [ -f "$_AOI_LOG" ]; then wc -l < "$_AOI_LOG" | tr -d ' '; else echo 0; fi; }
# _aoi_num <파일> → 첫 줄 정수(없거나 형식 오류면 0)
_aoi_num() { local c; c=$(head -1 "$1" 2>/dev/null | tr -d '[:space:]'); [[ $c =~ ^[0-9]+$ ]] || c=0; echo "$c"; }
_aoi_cursor() { _AOI_CUR=$(_aoi_num "$_AOI_LOG.cursor"); }
# log.held = "<lo> <hi>" → _AOI_LO·_AOI_HI (없으면 0 0)
_aoi_held() {
  local lo hi
  _AOI_LO=0; _AOI_HI=0
  read -r lo hi 2>/dev/null < "$_AOI_LOG.held" || [ -n "${lo:-}" ] || return 0
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
  # 이 아래는 append 확정 뒤 — 어떤 실패도 4로 만들지 않는다
  case "$(_aoi_watch_state)" in monitor|waiter) w=watched ;; *) w=unwatched ;; esac
  # (2026-11-13) pane id 대상인데 herdr가 그 pane이 없다고 답하면 3. 줄은 이미 기록됐다(지우지 않음).
  #   읽을 세션이 없는 곳에 보고가 조용히 쌓이는 것을 막는다. herdr 밖·응답 불명은 판정하지 않는다(0 유지)
  if [ "${1#/}" = "$1" ] && _aoi_pane_gone "$1"; then
    _aoi_event send "$_AOI_LOG" "n=$_AOI_SENT_N" "watch=gone"
    echo unwatched
    ao_die 3 "대상 pane 없음: $1 — 줄 #$_AOI_SENT_N 은 기록했지만 읽을 세션이 없다. 사용자에게 알릴 것(notify)"
  fi
  _aoi_event send "$_AOI_LOG" "n=$_AOI_SENT_N" "watch=$w"
  echo "$w"
}

# _aoi_pane_gone <pane id> → herdr 안이고 herdr가 pane_not_found 로 답하면 0. 그 밖(herdr 밖·바이너리 없음·다른 오류)은 1
_aoi_pane_gone() {
  local out
  [ "${HERDR_ENV:-}" = 1 ] || return 1
  command -v herdr >/dev/null 2>&1 || return 1
  out=$(herdr pane get "$1" 2>&1)
  # 해석한 error.code 가 정확히 pane_not_found 일 때만(본문·라벨에 같은 글자가 있어도 오판하지 않음)
  [ "$(printf '%s' "$out" | ao_json "(d.get('error') or {}).get('code')" 2>/dev/null)" = pane_not_found ]
}

# _aoi_mark_ok <표식 파일> → 세 칸 "<pid> <lstart> <token>"의 pid가 살아 있고 lstart가 같으면 0.
#   토큰은 _AOI_MARK_TOK 에 남긴다(lstart 안의 공백 허용)
_aoi_mark_ok() {
  local mark mpid mrest mls
  _AOI_MARK_TOK=""
  mark=$(head -1 "$1" 2>/dev/null); mpid=${mark%% *}; mrest=${mark#* }; mls=${mrest% *}
  [[ $mpid =~ ^[0-9]+$ ]] && [ "$mrest" != "$mark" ] && [ -n "$mls" ] || return 1
  [ "$(_aoi_lstart "$mpid")" = "$mls" ] || return 1
  _AOI_MARK_TOK=${mrest##* }
}
# _aoi_watch_state → stdout monitor|waiter|none (대상 _AOI_LOG). waiter = 그 경로를 담은 subs/<키>
#   (또는 pane 받은편지함이면 그 pane 키)의 wait/<키>.pid 가 살아 있고 hooks.off 가 없다
_aoi_watch_state() {
  local f k keys=""
  if _aoi_mark_ok "$_AOI_LOG.watch"; then echo monitor; return 0; fi
  if [ ! -e "$AO_INBOX_DIR/hooks.off" ]; then
    keys=$(_aoi_pane_key "$_AOI_LOG")
    for f in "$AO_INBOX_DIR/subs"/*; do
      case "$f" in *.flock|*.gen|*.tmp.*) continue ;; esac
      [ -f "$f" ] && cut -f1 "$f" 2>/dev/null | grep -qxF -- "$_AOI_LOG" && keys="$keys ${f##*/}"
    done
    for k in $keys; do
      _aoi_mark_ok "$AO_INBOX_DIR/wait/$k.pid" && { echo waiter; return 0; }
    done
  fi
  echo none
}

# ── inbox-watch --ack <대상> <n>
_aoi_ack() {
  local n=$1 total
  _aoi_prepare; _aoi_lock; total=$(_aoi_count)
  [ "$n" -le "$total" ] || { _aoi_unlock; _aoi_usage "ack 번호 $n 이 마지막 줄($total)보다 큼"; }
  _aoi_cursor
  [ "$n" -gt "$_AOI_CUR" ] && _aoi_put "$_AOI_LOG.cursor" "$n"
  _aoi_unlock
}

# ── inbox-watch --pending <대상>
_aoi_pending() {
  _aoi_cursor; _aoi_held
  [ "$(_aoi_count)" -gt "$_AOI_CUR" ] || return 0
  _aoi_held_notice
  tail -n +"$((_AOI_CUR + 1))" "$_AOI_LOG" | _aoi_number "$((_AOI_CUR + 1))"
}

# ── _aoi_claim <sid> — owner·held 확정(대상 _AOI_LOG). 모든 읽기 경로의 첫 단계. fd 9
#    세션 id가 있을 때만 기록·비교. 바뀌었고 미처리 줄이 있으면 보류 범위를 log.held 에
#    (바뀔 때마다 cursor+1..지금 마지막 줄로 다시 잡는다 — A→B→C면 B의 미처리 줄도 C에게는 이전 세션 것)
_aoi_claim() {
  local sid=${1:-} old total
  [ -n "$sid" ] || return 0
  _aoi_lock; old=$(head -1 "$_AOI_LOG.owner" 2>/dev/null)
  if [ -n "$old" ] && [ "$old" != "$sid" ]; then
    _aoi_cursor; total=$(_aoi_count)
    [ "$total" -gt "$_AOI_CUR" ] && _aoi_put "$_AOI_LOG.held" "$((_AOI_CUR + 1)) $total"
  fi
  [ "$old" = "$sid" ] || _aoi_put "$_AOI_LOG.owner" "$sid"
  _aoi_unlock
}

# ── inbox-watch <대상>
_aoi_watch() {
  local ls fifo tp ap
  _aoi_prepare
  : >> "$_AOI_LOG" 2>/dev/null || ao_die 4 "받은편지함 생성 실패: $_AOI_LOG"   # 비파괴 생성(: > 금지)
  _aoi_claim "${CLAUDE_CODE_SESSION_ID:-}"
  ls=$(_aoi_lstart $$)
  _AOI_TOKEN="$$-$RANDOM$RANDOM-$(date +%s)"
  _AOI_MARK="$_AOI_LOG.watch"
  _aoi_put "$_AOI_MARK" "$$ ${ls:-?} $_AOI_TOKEN"
  _aoi_cursor; _aoi_held; _aoi_held_notice
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
