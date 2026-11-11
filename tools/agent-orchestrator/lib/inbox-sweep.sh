# lib/inbox-sweep.sh — 받은편지함 바깥 점검(launchd 5분 주기, 계획 2026-11-11 §2-8). inbox.sh 다음에 source한다.
#
#   inbox-sweep [--dry-run] [--age-min <분, 15>] [--repeat-min <분, 60>]
#   inbox-sweep --register <대상>…   known.list 에 넣고 끝(상태 폴더 밖 받은편지함 — 전환 절차, 계획 §3 S3)
# 대상: known.list + $AO_INBOX_DIR 아래 *.log(깊이 3, events.log 제외). 없는 파일은 건너뛴다.
# 나이: 가장 오래된 미처리 줄(cursor+1)의 <log>.times 도착 시각(exact). 행이 없으면 sweep/obs 의 첫 관측
#   시각(observed — 실제 나이의 하한, 본문에 ≥). 부분 ack 뒤에는 남은 줄 중 가장 오래된 줄로 다시 잰다.
# 경보: 나이 > age-min 이고 sweep/alerts 의 마지막 경보로부터 repeat-min 이 지났으면 사람에게만 1건
#   herdr notification show "받은편지함 미처리" --body "<표시 이름> <k>줄 · [≥]<분>분" --sound request
#   herdr 없음·서버 꺼짐·실패 → events.log 에만(sent=0), alerts 갱신 안 함, exit 0(launchd 재시작 방지).
#   alerts 행은 ack 로 지우지 않는다(받은편지함 단위 1시간 1번).
# 입력 주입·agent-send·agent-keys 는 쓰지 않는다. 세션을 깨우지 않는다.
# --dry-run: 알림·상태 기록·events 없이 stdout "<경로>\t<k>\t<분>\t<exact|observed>\t<alert|quiet|skip>"
#   (미처리 줄이 있는 받은편지함만). 잠금도 잡지 않는다(읽기 전용).
# 종료 0 / 2 인자 / 4 상태 파일 기록 실패. 겹친 실행(fd 6 sweep/state.flock 을 곧바로 못 잡음)은 0.
# 상태(sweep/): obs "<경로>\t<hi>\t<관측>\t<inode>" · alerts "<경로>\t<epoch>\t<bl>" · open "<경로>\t<bl>\t<n>\t<arr>\t<exact>\t<inode>"
#   · seen "<경로>\t<줄 수>\t<inode>\t<첫 줄 해시>"(잘림·교체 판정)
# events: backlog-open·backlog-close·sweep-alert(계획 §2-9). events.log 가 AO_INBOX_EV_MAX(바이트, 기본 10MB)를
#   넘으면 events.log.<epoch> 로 옮기고 새 파일을 연다(삭제 없음).
# 시험 전용: AO_INBOX_NOW(epoch 고정), AO_SWEEP_HERDR_TIMEOUT(초, 기본 10 — herdr 호출 상한),
#   AO_SWEEP_TEST_HOLD(초 — 잠금을 쥔 채 멈춤, 겹침 시험).
# shellcheck shell=bash

_AOS_D=""; _AOS_DRY=0; _AOS_NOW=0; _AOS_AGE=15; _AOS_REP=60

_aos_usage() { ao_die 2 "$*  (사용: inbox-sweep [--dry-run] [--age-min <분>] [--repeat-min <분>] | inbox-sweep --register <대상>…)"; }

# _aos_get <파일> <경로> → 그 경로 행의 나머지 칸. 없으면 빈 출력(경로는 ENVIRON 비교 — 백슬래시 안전)
_aos_get() {
  [ -f "$1" ] || return 0
  P=$2 awk -F'\t' '$1 == ENVIRON["P"] { sub(/^[^\t]*\t/, ""); print; exit }' "$1" 2>/dev/null
}
# _aos_set <파일> <경로> [나머지 칸] → 그 경로 행을 바꾸거나(값 있음) 지운다(값 없음). 임시 파일 → mv. 실패 4
_aos_set() {
  local f=$1 tmp="$1.tmp.$$"
  if ! { if [ -f "$f" ]; then P=$2 awk -F'\t' '$1 != ENVIRON["P"]' "$f"; fi
         if [ -n "${3:-}" ]; then printf '%s\t%s\n' "$2" "$3"; fi; } > "$tmp" 2>/dev/null \
     || ! mv -f "$tmp" "$f" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    ao_die 4 "상태 파일 기록 실패: $f"
  fi
}

# 알림 본문용 표시 이름: 상태 폴더 안이면 상대 경로, 밖이면 "<상위 폴더>/<파일>"(홈 경로를 넣지 않는다). .log 뺌
_aos_name() {
  local p=$1 d
  case "$p" in
    "$AO_INBOX_DIR"/*) p=${p#"$AO_INBOX_DIR"/} ;;
    *) d=${p%/*}; p="${d##*/}/${p##*/}" ;;
  esac
  printf '%s\n' "${p%.log}"
}

# herdr 호출: 새 프로세스 그룹에서 실행하고 시간 상한(AO_SWEEP_HERDR_TIMEOUT초, 기본 10)이 지나면 그룹 전체를
#   KILL 한다. stdout 은 파이프가 아니라 임시 파일로 받는다 — 손자 프로세스가 출력 fd 를 물고 남아도 sweep 이
#   기다리지 않게(크로스체크 S3 1회차 #1). stdin 막음, fd 6(sweep 잠금) 닫음 — 남는 자식이 잠금을 물려받으면
#   다음 sweep 이 모두 "겹친 실행"으로 끝나기 때문이다. 출력은 _AOS_HOUT(파일 경로)
_AOS_HOUT=""
_aos_herdr() {
  command -v herdr >/dev/null 2>&1 || return 127
  [ -n "$_AOS_HOUT" ] || _AOS_HOUT=$(mktemp "${TMPDIR:-/tmp}/ao-sweep-h.XXXXXX") || return 1
  "$AO_PERL" -e '
    my $t = shift; my $pid = fork; defined $pid or exit 1;
    if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$pid; kill "KILL", $pid; exit 142 };
    alarm $t; waitpid($pid, 0); exit($? & 127 ? 1 : $? >> 8)' \
    "${AO_SWEEP_HERDR_TIMEOUT:-10}" herdr "$@" > "$_AOS_HOUT" 2>/dev/null 6>&- </dev/null
}
# _aos_notify <본문> → 0 보냄 / 1 못 보냄(herdr 없음·서버 꺼짐·실패·시간 초과)
_aos_notify() {
  _aos_herdr status server || return 1
  grep -q '^status: running' "$_AOS_HOUT" 2>/dev/null || return 1
  _aos_herdr notification show "받은편지함 미처리" --body "$1" --sound request
}

# 대상 목록(정렬·중복 제거)
_aos_targets() {
  {
    if [ -f "$AO_INBOX_DIR/known.list" ]; then cat "$AO_INBOX_DIR/known.list"; fi
    find "$AO_INBOX_DIR" -maxdepth 3 -type f -name '*.log' ! -path "$AO_INBOX_DIR/events.log"
  } 2>/dev/null | LC_ALL=C sort -u
}

_aos_rotate() {
  local E="$AO_INBOX_DIR/events.log" sz dst
  [ -f "$E" ] || return 0
  sz=$(wc -c < "$E" | tr -d ' ')
  [ "${sz:-0}" -gt "${AO_INBOX_EV_MAX:-10485760}" ] || return 0
  dst="$E.$_AOS_NOW"; [ -e "$dst" ] && dst="$dst.$$"
  mv "$E" "$dst" 2>/dev/null || ao_die 4 "events.log 회전 실패: $E"
  : >> "$E" 2>/dev/null || ao_die 4 "events.log 생성 실패: $E"
}

# ── sweep/obs: 받은편지함마다 "<경로>\t<그때 줄 수 hi>\t<관측 epoch>" 행을 줄 수가 늘 때 덧붙인다(times 에
#    행이 빠진 줄이 새로 생겼을 때만). 줄 m 의 첫 관측 = hi ≥ m 인 첫 행의 epoch. cursor ≥ hi 인 행은 지운다.
#    행 끝 칸은 받은편지함 파일의 inode 다(다른 inode 의 행은 쓰지 않는다).
# ── 잘림·교체 판정(크로스체크 S3 1·2회차 #2): sweep/seen "<경로>\t<지난 줄 수>\t<inode>\t<첫 줄 해시>".
#    inode 가 다르거나, 줄 수가 줄었거나, 첫 줄이 바뀌었으면 그 받은편지함의 옛 관측(obs 전 행)과 열린 backlog 는
#    옛 파일의 것이다 → obs 를 모두 버리고 backlog 는 reset=1 로 닫는다. 잘린 뒤 새 줄에 옛 관측 시각을 쓰면
#    "실제 나이의 하한"이 깨지기 때문이다. seen 행이 없으면(첫 점검·옛 상태) 잘림으로 보지 않는다.
#    남은 한계: 같은 inode 에서 잘린 뒤 같은 첫 줄로 시작해 예전 줄 수 이상으로 다시 채워지면 알 수 없다.
_aos_ino() { stat -f %i "$1" 2>/dev/null || echo 0; }
_aos_h1() { head -1 "$1" 2>/dev/null | shasum | cut -c1-12; }
# _aos_reset <경로> <줄 수> <inode> <첫 줄 해시> → 0 잘림·교체 / 1 아님
_aos_reset() {
  local st ot oi oh
  st=$(_aos_get "$_AOS_D/seen" "$1"); [ -n "$st" ] || return 1
  IFS=$'\t' read -r ot oi oh <<< "$st"
  [ "$oi" != "$3" ] || [ "${ot:-0}" -gt "$2" ] || { [ "${ot:-0}" -gt 0 ] && [ "$oh" != "$4" ]; }
}
_aos_obs_first() {   # <경로> <m> <inode> <줄 수> → epoch 또는 빈 출력
  [ -f "$_AOS_D/obs" ] || return 0
  P=$1 awk -F'\t' -v m="$2" -v ino="$3" -v tot="$4" '$1 == ENVIRON["P"] && $4 == ino && $2 + 0 <= tot + 0 && $2 + 0 >= m + 0 { print $3; exit }' "$_AOS_D/obs" 2>/dev/null
}
_aos_obs_update() {  # <경로> <cursor> <줄 수> <inode> <reset 0|1>
  local p=$1 c=$2 total=$3 ino=$4 rs=$5 F="$_AOS_D/obs" lasthi miss tmp
  # reset 이면 그 경로의 행을 모두 버린 것으로 보고 다시 잰다
  [ "$rs" = 1 ] && ino="reset:$ino"
  lasthi=$(P=$p awk -F'\t' -v ino="$ino" -v tot="$total" '$1 == ENVIRON["P"] && $4 == ino && $2 + 0 <= tot + 0 { h = $2 } END { print h + 0 }' "$F" 2>/dev/null) || lasthi=0
  [ "${lasthi:-0}" -lt "$c" ] && lasthi=$c
  miss=0
  if [ "$total" -gt "$lasthi" ]; then
    miss=$(awk -F'\t' -v lo="$lasthi" -v hi="$total" '{ t[$1] = 1 } END { for (i = lo + 1; i <= hi; i++) if (!(i in t)) { print 1; exit } print 0 }' "$p.times" 2>/dev/null) || miss=1
    [ -f "$p.times" ] || miss=1
  fi
  tmp="$F.tmp.$$"
  if ! { if [ -f "$F" ]; then P=$p awk -F'\t' -v c="$c" -v ino="$ino" -v tot="$total" '!($1 == ENVIRON["P"] && ($2 + 0 <= c + 0 || $4 != ino || $2 + 0 > tot + 0))' "$F"; fi
         if [ "$miss" = 1 ]; then printf '%s\t%s\t%s\t%s\n' "$p" "$total" "$_AOS_NOW" "${ino#reset:}"; fi; } > "$tmp" 2>/dev/null \
     || ! mv -f "$tmp" "$F" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null; ao_die 4 "상태 파일 기록 실패: $F"
  fi
}
_aos_bl() { printf '%s-%s\n' "$(printf '%s' "$1" | shasum | cut -c1-8)" "$2"; }

# _aos_box <경로> — 한 받은편지함 점검
_aos_box() {
  local p=$1 c total m k arr exact ex age min cls open on obl oarr oex oino ats cage last lbl body ino h1 rs=0 ge=""
  [ -f "$p" ] || return 0
  _AOI_LOG=$p; _aoi_cursor; c=$_AOI_CUR; total=$(_aoi_count); ino=$(_aos_ino "$p"); h1=$(_aos_h1 "$p")
  _aos_reset "$p" "$total" "$ino" "$h1" && rs=1
  # 1. 열린 backlog 가 끝났으면(cursor 가 그 줄을 넘음) 닫는다
  if [ "$_AOS_DRY" = 0 ]; then
    open=$(_aos_get "$_AOS_D/open" "$p")
    if [ -n "$open" ]; then
      IFS=$'\t' read -r obl on oarr oex oino <<< "$open"
      # 잘림·교체(seen 판정)이거나 open 행의 inode 가 다르면 옛 backlog 는 reset 으로 닫는다(ackts 판정 안 함).
      # inode 칸이 없는 옛 5칸 행은 inode 로 판정하지 않는다(크로스체크 S3 2회차 #2)
      [ -n "${oino:-}" ] && [ "$oino" != "$ino" ] && rs=1
      [ "$total" -lt "${on:-0}" ] && rs=1
      if [ "$rs" = 1 ] || [ "$c" -ge "${on:-0}" ]; then
        ats=""
        [ "$rs" = 0 ] && [ -f "$p.ackts" ] && ats=$(awk -F'\t' -v n="$on" '$1 + 0 <= n + 0 && n + 0 <= $2 + 0 { print $3; exit }' "$p.ackts" 2>/dev/null)
        if [[ ${ats:-} =~ ^[0-9]+$ ]]; then cage=$((ats - oarr)); else cage=$((_AOS_NOW - oarr)); ats=-; fi
        if [ "$rs" = 1 ]; then _aoi_event backlog-close "$p" "bl=$obl" "age=$cage" "exact=$oex" "ackts=$ats" reset=1 || true
        else _aoi_event backlog-close "$p" "bl=$obl" "age=$cage" "exact=$oex" "ackts=$ats" || true; fi
        _aos_set "$_AOS_D/open" "$p"; open=""
      fi
    fi
    _aos_obs_update "$p" "$c" "$total" "$ino" "$rs"
    _aos_set "$_AOS_D/seen" "$p" "$total	$ino	$h1"
  fi
  [ "$total" -gt "$c" ] || return 0
  # 2. 가장 오래된 미처리 줄의 도착 시각
  m=$((c + 1)); k=$((total - c))
  arr=$(awk -F'\t' -v m="$m" '$1 + 0 == m + 0 { print $2; exit }' "$p.times" 2>/dev/null)
  if [[ ${arr:-} =~ ^[0-9]+$ ]]; then exact=exact; ex=1
  else exact=observed; ex=0; arr=""; [ "$rs" = 1 ] || arr=$(_aos_obs_first "$p" "$m" "$ino" "$total"); [[ ${arr:-} =~ ^[0-9]+$ ]] || arr=$_AOS_NOW; ge="≥"; fi
  age=$((_AOS_NOW - arr)); [ "$age" -lt 0 ] && age=0; min=$((age / 60))
  lbl=$(_aos_bl "$p" "$m")
  last=$(_aos_get "$_AOS_D/alerts" "$p"); last=${last%%$'\t'*}
  if [ "$age" -le $((_AOS_AGE * 60)) ]; then cls=quiet
  elif [[ ${last:-} =~ ^[0-9]+$ ]] && [ $((_AOS_NOW - last)) -lt $((_AOS_REP * 60)) ]; then cls=skip
  else cls=alert; fi
  if [ "$_AOS_DRY" = 1 ]; then printf '%s\t%s\t%s\t%s\t%s\n' "$p" "$k" "$min" "$exact" "$cls"; return 0; fi
  # 3. 새 backlog 열기
  if [ -z "$open" ]; then
    _aos_set "$_AOS_D/open" "$p" "$lbl	$m	$arr	$ex	$ino"
    _aoi_event backlog-open "$p" "bl=$lbl" "arr=$arr" "exact=$ex" || true
  fi
  [ "$cls" = alert ] || return 0
  # 4. 경보(사람에게만). 보냈을 때만 alerts 갱신
  body="$(_aos_name "$p") ${k}줄 · ${ge}${min}분"
  if _aos_notify "$body"; then
    _aos_set "$_AOS_D/alerts" "$p" "$_AOS_NOW	$lbl"
    _aoi_event sweep-alert "$p" "bl=$lbl" "age=$age" sent=1 || true
  else
    _aoi_event sweep-alert "$p" "bl=$lbl" "age=$age" sent=0 || true
  fi
}

# fd 6 겹침 방지 잠금(한 번만 시도). 0 잡음 / 1 이미 다른 sweep / 4 실패
_aos_lock() {
  { exec 6>>"$_AOS_D/state.flock"; } 2>/dev/null || return 4
  "$AO_PERL" -MFcntl=:flock -e 'open(my $f, ">&=", 6) or exit 4; exit(flock($f, LOCK_EX | LOCK_NB) ? 0 : 1)'
}

ao_inbox_sweep() {
  local p reg=0 rc
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) _AOS_DRY=1; shift ;;
      --age-min|--repeat-min)
        [ $# -ge 2 ] && ao_is_uint "$2" || _aos_usage "$1 은 양의 정수(분)"
        if [ "$1" = --age-min ]; then _AOS_AGE=$2; else _AOS_REP=$2; fi; shift 2 ;;
      --register) reg=1; shift; break ;;
      *) _aos_usage "알 수 없는 인자: $1" ;;
    esac
  done
  if [ "$reg" = 1 ]; then
    # --register 는 쓰기 동작이라 --dry-run·--age-min 등과 함께 받지 않는다(크로스체크 S3 1회차 #3)
    [ "$_AOS_DRY" = 0 ] || _aos_usage "--register 는 --dry-run 과 함께 쓸 수 없음"
    [ $# -ge 1 ] || _aos_usage "--register 뒤에 대상이 없음"
    for p in "$@"; do _aoi_resolve "$p"; done   # 형식 검사를 먼저(하나라도 틀리면 아무것도 넣지 않음)
    for p in "$@"; do _aoi_resolve "$p"; _aoi_known_add || ao_die 4 "known.list 기록 실패: $_AOI_LOG"; done
    return 0
  fi
  _AOS_NOW=$(_aoi_now); _AOS_D="$AO_INBOX_DIR/sweep"
  if [ "$_AOS_DRY" = 0 ]; then
    mkdir -p "$_AOS_D" 2>/dev/null || ao_die 4 "상태 폴더 생성 실패: $_AOS_D"
    _aos_lock; rc=$?
    [ "$rc" = 1 ] && return 0
    [ "$rc" = 0 ] || ao_die 4 "sweep 잠금 실패: $_AOS_D/state.flock"
    [ -n "${AO_SWEEP_TEST_HOLD:-}" ] && sleep "$AO_SWEEP_TEST_HOLD"
    _aos_rotate
  fi
  [ -d "$AO_INBOX_DIR" ] || return 0
  trap '[ -n "$_AOS_HOUT" ] && rm -f "$_AOS_HOUT"' EXIT
  while IFS= read -r p; do
    case "$p" in /*.log) _aos_box "$p" ;; esac
  done <<< "$(_aos_targets)"
  return 0
}
