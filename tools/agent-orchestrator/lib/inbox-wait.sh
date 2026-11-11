# lib/inbox-wait.sh — 받은편지함 구독·대기자(계획 2026-11-11 rev 5 §2-3~§2-5). inbox.sh 다음에 source한다.
#
#   inbox-subscribe [--pane <pane>|--session <sid>] <대상>      구독 등록(수신 잠금 fd 8 안)
#   inbox-subscribe --unsubscribe [--pane|--session …] <대상>   해제 = 장벽(진행 중 통지 확정이 끝난 뒤 0)
#   inbox-subscribe --list [--pane|--session …]                 줄마다 <경로>\t<sid>\t<active|dormant>
#   inbox-wait                    stdin 훅 JSON. 0 / 2 깨움(stderr) / 4 잠금·기록·JSON·인자 오류
#   inbox-wait --status           stdout "inbox-wait 2"
#   inbox-wait --drain|--undrain  hooks.off 생성(+대기자 철회, stdout 철회 수) / 제거
#   inbox-wait --session-start    stdin SessionStart 훅 JSON → 미처리 줄이 있으면 stdout 훅 JSON(additionalContext), 항상 0
# 0·4일 때 stderr는 비우고 events.log(wait-start·wait-notify·wait-delivered·wait-end)에만 남긴다.
# 시험 전용: AO_INBOX_WAIT_MAX(초, 기본 7000)·AO_INBOX_WAIT_POLL(초, 기본 1)
#   AO_INBOX_TEST_PAUSE=<지점>:<초>[,<지점>:<초>…] — 지점마다 프로세스당 처음 한 번 멈춘다.
#   AO_INBOX_TEST_PAUSE_MARK=<파일> — 멈출 때 "<지점> <pid>" 한 줄을 덧붙인다. <파일>.go 또는
#   <파일>.go.<pid> 가 생기면 남은 시간 전에 재개한다.
#   지점: pre-register registered poll notify-mid notify-locked sub-del-locked start-mid-out issue-wait
# 스냅샷(_W_SNAP, 문자열): "off=<0|1>" / "pg=<pane-gen 내용>"(pane 있을 때) / "gen <키>=<n>"… / 대상 경로…
# shellcheck shell=bash

AOW_SID_RE='^[0-9a-fA-F-]{8,64}$'
_AOW_SUBS="$AO_INBOX_DIR/subs"; _AOW_WAIT="$AO_INBOX_DIR/wait"
_W_SID=""; _W_TOK=""; _W_LS=""; _W_HOOK=""; _W_TR=""; _W_PK=""; _W_IGEN=""
_W_SNAP=""; _W_TGTS=""; _W_WHY=""; _W_REG=0; _W_PAUSED=""; _W_BG=""; _AOI_TERM=0

# ── 시험 정지 지점(프로세스당 지점마다 한 번)
_aoiw_pause() {
  local p=$1 spec s="" n i=0 mk=${AO_INBOX_TEST_PAUSE_MARK:-} old=$IFS
  [ -n "${AO_INBOX_TEST_PAUSE:-}" ] || return 0
  case ",$_W_PAUSED," in *",$p,"*) return 0 ;; esac
  IFS=,; for spec in $AO_INBOX_TEST_PAUSE; do [ "${spec%%:*}" = "$p" ] && s=${spec#*:}; done; IFS=$old
  [ -n "$s" ] || return 0
  _W_PAUSED="$_W_PAUSED,$p"
  [ -n "$mk" ] && echo "$p $$" >> "$mk"
  n=$(awk -v s="$s" 'BEGIN { printf "%d", s * 20 }')
  while [ "$i" -lt "$n" ]; do
    if [ -n "$mk" ] && { [ -e "$mk.go" ] || [ -e "$mk.go.$$" ]; }; then break; fi
    sleep 0.05; i=$((i + 1))
  done
}

# ── 공용 작은 헬퍼
_aoiw_sid_ok() { [[ ${1:-} =~ $AOW_SID_RE ]]; }
# _aoiw_gen <키> → stdout 현재 세대(없으면 0)
_aoiw_gen() {
  local g
  g=$(head -1 "$_AOW_SUBS/$1.gen" 2>/dev/null | tr -d '[:space:]')
  [[ $g =~ ^[0-9]+$ ]] || g=0
  echo "$g"
}
# _aoiw_genup <키> → 세대 +1(수신 잠금 안에서). 새 값은 _AOW_G
_aoiw_genup() { _AOW_G=$(( $(_aoiw_gen "$1") + 1 )); _aoi_put "$_AOW_SUBS/$1.gen" "$_AOW_G"; }
# _aoiw_subs_del <키> <경로> → 줄이 있으면 지우고 1(세대 +1, 빈 파일 삭제), 없으면 0
_aoiw_subs_del() {
  local f="$_AOW_SUBS/$1" rest
  grep -qF -- "$2"$'\t' "$f" 2>/dev/null || { _AOW_DEL=0; return 0; }
  awk -F'\t' -v p="$2" '$1 == p' "$f" | grep -q . || { _AOW_DEL=0; return 0; }
  rest=$(awk -F'\t' -v p="$2" '$1 != p' "$f")
  if [ -n "$rest" ]; then _aoi_put "$f" "$rest"; else rm -f "$f" || ao_die 4 "구독 파일 삭제 실패: $f"; fi
  _aoiw_genup "$1"; _AOW_DEL=1
}
# 훅 JSON(stdin) → 키 값을 탭으로 이은 한 줄(기본 "sid\thook\ttranscript"). 해석 실패 4
_aoiw_json() {
  [ $# -gt 0 ] || set -- session_id hook_event_name transcript_path
  "$AO_PERL" -MJSON::PP -e '
    local $/; my $r = <STDIN>; my $d = eval { JSON::PP->new->decode($r) };
    exit 4 unless ref $d eq "HASH";
    print join("\t", map { my $v = $d->{$_}; (defined $v && !ref $v) ? do { (my $x = $v) =~ s/[\t\r\n]/ /g; $x } : "" }
      @ARGV), "\n";' "$@"
}

# ── inbox-subscribe (계획 §2-4)
_aoiw_sub_usage() { ao_die 2 "$*  (사용: inbox-subscribe [--unsubscribe|--list] [--pane <pane>|--session <sid>] [<대상>])"; }
# 키·sid 결정: --pane > --session > HERDR_PANE_ID > CLAUDE_CODE_SESSION_ID. 결과 _S_KEY·_S_SID
_aoiw_sub_key() {
  local pane=$1 ses=$2 need_sid=$3
  _S_SID=${ses:-${CLAUDE_CODE_SESSION_ID:-}}
  [ -z "$pane" ] && [ -z "$ses" ] && pane=${HERDR_PANE_ID:-}
  if [ -n "$pane" ]; then
    ao_is_pane "$pane" || _aoiw_sub_usage "pane id 형식 오류: $pane"
    _S_KEY="pane-${pane//:/_}"
  elif [ -n "$_S_SID" ]; then _S_KEY="sid-$_S_SID"
  else _aoiw_sub_usage "구독 키 없음"; fi
  if [ -n "$_S_SID" ]; then _aoiw_sid_ok "$_S_SID" || _aoiw_sub_usage "세션 id 형식 오류: $_S_SID"
  elif [ "$need_sid" = 1 ]; then _aoiw_sub_usage "구독 키 없음(세션 id 없음)"; fi
}
_aoiw_sub_add() {
  local f="$_AOW_SUBS/$_S_KEY" cur old rest
  _aoi_recv_lock
  mkdir -p "$_AOW_SUBS" 2>/dev/null || ao_die 4 "구독 폴더 생성 실패: $_AOW_SUBS"
  cur=$(awk -F'\t' -v p="$_AOI_LOG" '$1 == p { print $2; exit }' "$f" 2>/dev/null)
  if [ "$cur" != "$_S_SID" ]; then
    rest=$(awk -F'\t' -v p="$_AOI_LOG" '$1 != p' "$f" 2>/dev/null)
    _aoi_put "$f" "${rest:+$rest$'\n'}$_AOI_LOG	$_S_SID"
    _aoiw_genup "$_S_KEY"
    _aoi_event sub "$_AOI_LOG" "sid=$_S_SID" op=add "gen=$_AOW_G" || true
  fi
  # owner 교체 시 이동(설계 §5-2): 옛 owner의 sid- 키에서 같은 경로를 뺀다
  old=$(head -1 "$_AOI_LOG.owner" 2>/dev/null)
  if [ -n "$old" ] && [ "$old" != "$_S_SID" ] && [ "sid-$old" != "$_S_KEY" ]; then
    _aoiw_subs_del "sid-$old" "$_AOI_LOG"
    [ "$_AOW_DEL" = 1 ] && { _aoi_event sub "$_AOI_LOG" "sid=$old" op=move "gen=$_AOW_G" || true; }
  fi
  _aoi_claim "$_S_SID"
  _aoi_recv_unlock
  _aoi_known_add || _aoi_meta_warn known
}
_aoiw_sub_del() {
  _aoi_recv_lock
  _aoiw_pause sub-del-locked
  _aoiw_subs_del "$_S_KEY" "$_AOI_LOG"
  _aoi_recv_unlock
  [ "$_AOW_DEL" = 1 ] && { _aoi_event sub "$_AOI_LOG" "sid=${_S_SID:--}" op=del "gen=$_AOW_G" || true; }
  return 0
}
# --list: 키의 현재 수신 sid(pane 키면 pane-gen의 sid, 없으면 호출 sid)와 같으면 active
_aoiw_sub_list() {
  local f="$_AOW_SUBS/$_S_KEY" want=$_S_SID pg ps
  case "$_S_KEY" in pane-*)
    IFS=$'\t' read -r pg ps 2>/dev/null < "$AO_INBOX_DIR/pane-gen/$_S_KEY" && [ -n "${ps:-}" ] && want=$ps ;;
  esac
  [ -f "$f" ] || return 0
  awk -F'\t' -v w="$want" 'NF >= 2 { printf "%s\t%s\t%s\n", $1, $2, (w == "" || $2 == w) ? "active" : "dormant" }' "$f"
}
ao_inbox_subscribe() {
  local op=add pane="" ses="" tgt="" np=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --unsubscribe) op=del; shift ;;
      --list) op=list; shift ;;
      --pane) [ $# -ge 2 ] || _aoiw_sub_usage "--pane 값 없음"; pane=$2; shift 2 ;;
      --session) [ $# -ge 2 ] || _aoiw_sub_usage "--session 값 없음"; ses=$2; shift 2 ;;
      --*) _aoiw_sub_usage "알 수 없는 옵션: $1" ;;
      *) tgt=$1; np=$((np + 1)); shift ;;
    esac
  done
  if [ "$op" = list ]; then [ "$np" = 0 ] || _aoiw_sub_usage "--list 는 대상 없음"
  else [ "$np" = 1 ] || _aoiw_sub_usage "대상 하나가 필요"; fi
  case "$op" in add) _aoiw_sub_key "$pane" "$ses" 1 ;; *) _aoiw_sub_key "$pane" "$ses" 0 ;; esac
  [ "$op" = list ] && { _aoiw_sub_list; return 0; }
  _aoi_resolve "$tgt"
  _aoi_traps
  if [ "$op" = add ]; then
    _aoi_prepare
    : >> "$_AOI_LOG" 2>/dev/null || ao_die 4 "받은편지함 생성 실패: $_AOI_LOG"
    _aoiw_sub_add
  else _aoiw_sub_del; fi
}

# ── 대기자 잠금: perl을 백그라운드로 띄우고 wait 한다(wait는 신호에 바로 깨어 TERM이 늦지 않다).
#    _aoiw_lock <fd> <파일> <시도 횟수(×0.05초)> → 0, 실패는 ao_die 4(stderr는 이미 /dev/null)
_aoiw_lock() {
  local fd=$1 F=$2 rc r2
  { eval "exec $fd>>\"\$F\""; } 2>/dev/null || ao_die 4 "잠금 파일 열기 실패: $F"
  eval "_AOI_LOCK$fd=\$F"
  "$AO_PERL" -MFcntl=:flock -MTime::HiRes=sleep -e '
    open(my $f, ">&=", $ARGV[1]) or exit 4;
    for (1 .. $ARGV[0]) { exit 0 if flock($f, LOCK_EX | LOCK_NB); sleep 0.05 }
    exit 7' "$3" "$fd" & _W_BG=$!
  # 신호로 wait가 먼저 깨어나도(통지 구간의 TERM 표시) perl이 끝날 때까지 다시 기다리고, 끝난 뒤 상태를 한 번 더 읽는다
  while :; do
    wait "$_W_BG"; rc=$?
    kill -0 "$_W_BG" 2>/dev/null && continue
    if [ "$rc" -gt 128 ]; then wait "$_W_BG"; r2=$?; [ "$r2" = 127 ] || rc=$r2; fi
    break
  done
  _W_BG=""
  [ "$rc" = 0 ] && return 0
  _aoi_funlock "$fd"; ao_die 4 "잠금 실패(rc=$rc): $F"
}
_aoiw_l8() { mkdir -p "$AO_INBOX_DIR" 2>/dev/null || ao_die 4 "상태 폴더 생성 실패"; _aoiw_lock 8 "$AO_INBOX_DIR/recv.flock" 200; }

# ── 스냅샷(계획 §2-4 끝). 잠금 안·밖 어디서나 읽는다. 결과 _W_SNAP_NEW·_W_TGTS_NEW
_aoiw_snap() {
  local s t="" keys="" k f
  if [ -e "$AO_INBOX_DIR/hooks.off" ]; then s="off=1"; else s="off=0"; fi
  if [ -n "$_W_PK" ]; then
    s="$s"$'\n'"pg=$(head -1 "$AO_INBOX_DIR/pane-gen/$_W_PK" 2>/dev/null)"
    t="$AO_INBOX_DIR/$_W_PK.log"; keys=$_W_PK
  fi
  keys="$keys sid-$_W_SID"
  for k in $keys; do
    s="$s"$'\n'"gen $k=$(_aoiw_gen "$k")"
    f="$_AOW_SUBS/$k"
    [ -f "$f" ] && t="$t"$'\n'"$(awk -F'\t' -v w="$_W_SID" '$2 == w { print $1 }' "$f" 2>/dev/null)"
  done
  _W_TGTS_NEW=$(printf '%s\n' "$t" | grep -v '^$' | LC_ALL=C sort -u)
  _W_SNAP_NEW="$s"$'\n'"$_W_TGTS_NEW"
}
# pane 세대 검증(§2-3): issued = "<pk>\t<gen>", pane-gen = "<gen>\t<sid>". 실패 1 + _W_WHY
_aoiw_issue_ok() {
  local ik ig pg ps
  [ -n "$_W_PK" ] || return 0
  IFS=$'\t' read -r ik ig 2>/dev/null < "$_AOW_WAIT/$_W_SID.issued" || { _W_WHY=no-issue; return 1; }
  IFS=$'\t' read -r pg ps 2>/dev/null < "$AO_INBOX_DIR/pane-gen/$_W_PK" || { _W_WHY=pane-superseded; return 1; }
  [ "$ik" = "$_W_PK" ] && [ "$ig" = "$pg" ] && [ "$ps" = "$_W_SID" ] && [[ $pg =~ ^[0-9]+$ ]] && return 0
  _W_WHY=pane-superseded; return 1
}
# 내 토큰이 wait/<sid>.pid 에 있는가
_aoiw_mine() { [ "$(awk '{print $NF; exit}' "$_AOW_WAIT/$_W_SID.pid" 2>/dev/null)" = "$_W_TOK" ]; }
# _aoiw_recheck → 0 그대로 / 1 끝낼 이유(_W_WHY) / 3 대상이 남은 채 바뀜(_aoiw_adopt 필요)
_aoiw_recheck() {
  _aoiw_mine || { _W_WHY=superseded; return 1; }
  [ -e "$AO_INBOX_DIR/hooks.off" ] && { _W_WHY=off; return 1; }
  _aoiw_issue_ok || return 1
  _aoiw_snap
  [ "$_W_SNAP_NEW" = "$_W_SNAP" ] && return 0
  [ -n "$_W_TGTS_NEW" ] || { _W_WHY=unsubscribed; return 1; }
  return 3
}
# 새 스냅샷을 받아들인다(수신 잠금 안): 새 대상은 claim + 표식, 빠진 대상은 내 표식 삭제
_aoiw_adopt() {
  local t old=$_W_TGTS
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    printf '%s\n' "$_W_TGTS_NEW" | grep -qxF -- "$t" || _aoiw_unmark "$t"
  done <<< "$old"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    _AOI_LOG=$t; _aoi_prepare; : >> "$t" 2>/dev/null
    _aoi_claim "$_W_SID"
    mkdir -p "$t.waiters" 2>/dev/null || ao_die 4 "표식 폴더 생성 실패: $t.waiters"
    _aoi_put "$t.waiters/$_W_SID" "$$ $_W_LS $_W_TOK"
  done <<< "$_W_TGTS_NEW"
  _W_SNAP=$_W_SNAP_NEW; _W_TGTS=$_W_TGTS_NEW
}
# 내 토큰일 때만 표식 삭제
_aoiw_unmark() {
  local m="$1.waiters/$_W_SID"
  [ "$(awk '{print $NF; exit}' "$m" 2>/dev/null)" = "$_W_TOK" ] && rm -f "$m"
  return 0
}
# 종료 정리(EXIT trap): 자식 perl 종료, 내 표식·pid 파일 정리, wait-end 사건, 잠금 해제
_aoiw_cleanup() {
  local rc=$? t
  [ -n "$_W_BG" ] && kill "$_W_BG" 2>/dev/null
  if [ "$_W_REG" = 1 ]; then
    while IFS= read -r t; do [ -n "$t" ] && _aoiw_unmark "$t"; done <<< "$_W_TGTS"
    _aoiw_mine && rm -f "$_AOW_WAIT/$_W_SID.pid"
  fi
  [ -n "$_W_WHY" ] || _W_WHY="error:rc$rc"
  { [ -n "$_W_SID" ] || [ "${_W_WHY#error:}" != "$_W_WHY" ]; } && { _aoi_event wait-end - "sid=${_W_SID:--}" "tok=${_W_TOK:--}" "why=$_W_WHY" || true; }
  _aoi_cleanup
}
# TERM(통지 확정 구간 밖): 왜 밀려났는지 정하고 0
_aoiw_on_term() {
  if [ -e "$AO_INBOX_DIR/hooks.off" ]; then _W_WHY=off
  elif [ "$_W_REG" = 1 ] && ! _aoiw_mine; then _W_WHY=superseded
  else _W_WHY=term; fi
  exit 0
}

# ── notified(§2-1): 줄마다 <경로>\t<n>\t<pending|ctx|delivered>\t<token>\t<재통지 횟수>
_aoiw_cur_of() { local c; c=$(cat "$1.cursor" 2>/dev/null | tr -d '[:space:]'); [[ $c =~ ^[0-9]+$ ]] || c=0; echo "$c"; }
# 전달 확인(§2-5 4번, 수신 잠금 안). ① transcript에 token ② cursor ≥ n(행 삭제). 훅 이름은 증거가 아니다.
#   ctx 행은 증거가 없으면 pending(0)으로 내린다(§2-6) — async SessionStart 대기자는 내리지 않는다.
_aoiw_deliv() {
  local f="$_AOW_WAIT/$_W_SID.notified" p n st tk c new="" ch=0
  [ -f "$f" ] || return 0
  while IFS=$'\t' read -r p n st tk c; do
    [ -n "$p" ] && [[ $n =~ ^[0-9]+$ ]] || { ch=1; continue; }
    if [ "$(_aoiw_cur_of "$p")" -ge "$n" ]; then ch=1; continue; fi
    case "$st" in pending|ctx)
      if [ -n "$_W_TR" ] && [ -f "$_W_TR" ] && grep -qF -- "token=$tk" "$_W_TR" 2>/dev/null; then
        st=delivered; ch=1
        _aoi_event wait-delivered "$p" "sid=$_W_SID" "tok=$tk" "n=$n" || true
      elif [ "$st" = ctx ] && [ "$_W_HOOK" != SessionStart ]; then st=pending; c=0; ch=1; fi ;;
    esac
    new="${new:+$new$'\n'}$p	$n	$st	$tk	$c"
  done < "$f"
  [ "$ch" = 1 ] || return 0
  if [ -n "$new" ]; then _aoi_put "$f" "$new"; else rm -f "$f"; fi
}
# 통지 후보(잠금 없이 읽어도 된다) → _W_C 줄마다 "<경로>\t<cursor>\t<마지막 줄>\t<재통지 횟수(새 줄 0)>\t<재통지 표시 상한 n>"
_aoiw_cands() {
  local t cur tot rn rst rc row
  _W_C=""
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    _AOI_LOG=$t; tot=$(_aoi_count); cur=$(_aoiw_cur_of "$t")
    [ "$tot" -gt "$cur" ] || continue
    row=$(awk -F'\t' -v p="$t" '$1 == p { print $2 "\t" $3 "\t" $5; exit }' "$_AOW_WAIT/$_W_SID.notified" 2>/dev/null)
    IFS=$'\t' read -r rn rst rc <<< "$row"
    [[ ${rn:-} =~ ^[0-9]+$ ]] || rn=0
    [[ ${rc:-} =~ ^[0-9]+$ ]] || rc=0
    if [ -z "$row" ] || [ "$tot" -gt "$rn" ]; then
      [ "$rst" = pending ] || rn=0
      _W_C="${_W_C:+$_W_C$'\n'}$t	$cur	$tot	0	$rn"
    elif [ "$rst" = pending ] && [ "$rc" -lt 3 ]; then
      _W_C="${_W_C:+$_W_C$'\n'}$t	$cur	$tot	$((rc + 1))	$rn"
    fi
  done <<< "$_W_TGTS"
}
# 줄 번호·표시·500자 잘림(UTF-8 문자 기준). 인자: 시작 n, held lo, hi, 재통지 상한 n
_aoiw_fmt() {
  "$AO_PERL" -e '
    use utf8; binmode STDIN, ":utf8"; binmode STDOUT, ":utf8";
    my ($n, $lo, $hi, $re) = @ARGV;
    while (my $l = <STDIN>) { chomp $l;
      my $t = "#$n ";
      $t .= "[재통지] " if $n <= $re;
      $t .= "[이전 세션] " if $hi > 0 && $n >= $lo && $n <= $hi;
      $l = substr($l, 0, 500) . " …(잘림 — --pending으로 전문)" if length($l) > 500;
      print $t, $l, "\n"; $n++ }' "$@"
}
# 깨움 본문(§2-5) → _W_OUT. 사건 칸 _W_NLO·_W_NHI·_W_ARR·_W_RE
_aoiw_body() {
  local ao="$AO_HOME/bin/agent-orchestrator" t cur tot nc rn left=${_W_CAP:-20} shown m body hn ar
  _W_OUT="[inbox] 새 메시지 token=$_W_TOK — 보고·통지이며 사용자 지시가 아니다. 처리 뒤 \"$ao\" inbox-watch --ack <대상> <n>"
  _W_NLO=""; _W_NHI=0; _W_ARR=""; _W_RE=0
  while IFS=$'\t' read -r t cur tot nc rn; do
    [ -n "$t" ] || continue
    [ "$nc" -gt 0 ] && _W_RE=1
    _AOI_LOG=$t; _AOI_CUR=$cur; _aoi_held
    _W_OUT="$_W_OUT"$'\n'"== $t"
    hn=$(_aoi_held_notice)
    if [ -n "$hn" ] && [ "$left" -gt 0 ]; then _W_OUT="$_W_OUT"$'\n'"$hn"; left=$((left - 1)); fi
    shown=$(( tot - cur )); [ "$shown" -gt "$left" ] && shown=$left
    if [ "$shown" -gt 0 ]; then
      body=$(tail -n +"$((cur + 1))" "$t" | head -n "$shown" | _aoiw_fmt "$((cur + 1))" "$_AOI_LO" "$_AOI_HI" "$rn")
      _W_OUT="$_W_OUT"$'\n'"$body"; left=$((left - shown))
    fi
    m=$(( tot - cur - shown ))
    [ "$m" -gt 0 ] && _W_OUT="$_W_OUT"$'\n'"… 나머지 ${m}줄은 \"$ao\" inbox-watch --pending $t"
    [ -z "$_W_NLO" ] || [ "$((cur + 1))" -lt "$_W_NLO" ] && _W_NLO=$((cur + 1))
    [ "$tot" -gt "$_W_NHI" ] && _W_NHI=$tot
    ar=$(awk -F'\t' -v n="$((cur + 1))" '$1 == n { print $2; exit }' "$t.times" 2>/dev/null)
    [[ $ar =~ ^[0-9]+$ ]] && { [ -z "$_W_ARR" ] || [ "$ar" -lt "$_W_ARR" ]; } && _W_ARR=$ar
  done <<< "$_W_C"
}
# notified 갱신: 후보마다 "<경로>\t<마지막 줄>\tpending\t<내 token>\t<새 횟수>"
_aoiw_mark_notified() {
  local f="$_AOW_WAIT/$_W_SID.notified" t cur tot nc rn rest
  while IFS=$'\t' read -r t cur tot nc rn; do
    [ -n "$t" ] || continue
    rest=$(awk -F'\t' -v p="$t" '$1 != p' "$f" 2>/dev/null)
    _aoi_put "$f" "${rest:+$rest$'\n'}$t	$tot	pending	$_W_TOK	$nc"
  done <<< "$_W_C"
}

# ── async SessionStart 대기자의 발급 대기(§2-3 셋째 항, delta F1). 발급 기록과 현재 pane-gen 의
#    pane·gen·sid 가 모두 맞을 때까지 기다린다(옛 기록이 남아 있어도 맞지 않으면 계속).
#    확인은 수신 잠금 안, 0.2초 간격에는 놓는다. 상한 AO_INBOX_ISSUE_WAIT(초, 기본 10) → why=no-issue
_aoiw_issue_wait() {
  local i=0 n
  [ -n "$_W_PK" ] || return 0
  n=$(awk -v s="${AO_INBOX_ISSUE_WAIT:-10}" 'BEGIN { printf "%d", s * 5 }')
  while :; do
    _aoiw_l8
    [ -e "$AO_INBOX_DIR/hooks.off" ] && { _aoi_recv_unlock; _W_WHY=off; exit 0; }
    _aoiw_issue_ok && { _aoi_recv_unlock; return 0; }
    _aoi_recv_unlock
    [ "$i" -ge "$n" ] && { _W_WHY=no-issue; exit 0; }
    _aoiw_pause issue-wait
    sleep 0.2 & _W_BG=$!; wait "$_W_BG"; _W_BG=""; i=$((i + 1))
  done
}

# ── --session-start(§2-6). 수신 잠금 하나 안에서 발급 → 이어받기 → 스냅샷 → claim → 통지 예약
#    → 본문 → recheck → stdout JSON → 해제. 항상 exit 0, 실패·할 일 없음은 빈 출력.
# pane 세대 발급(§2-3): 다른 sid면 gen+1, 같으면(compact) 그대로. issued 기록
_aoiw_ss_issue() {
  local pg="" ps="" f="$AO_INBOX_DIR/pane-gen/$_W_PK"
  [ -n "$_W_PK" ] || return 0
  mkdir -p "$AO_INBOX_DIR/pane-gen" "$_AOW_WAIT" 2>/dev/null || ao_die 4 "세대 폴더 생성 실패"
  IFS=$'\t' read -r pg ps 2>/dev/null < "$f" || true
  [[ ${pg:-} =~ ^[0-9]+$ ]] || pg=0
  if [ "${ps:-}" != "$_W_SID" ] || [ "$pg" = 0 ]; then pg=$((pg + 1)); _aoi_put "$f" "$pg	$_W_SID"; fi
  _aoi_put "$_AOW_WAIT/$_W_SID.issued" "$_W_PK	$pg"
}
# 같은 pane 키의 옛 sid 구독 줄(§2-3 표): resume = sid 교체(.gen+1, op=move) /
#   clear·fork·startup(그 밖) = 휴면(op=dormant, 안내 줄 수 _W_DORM) / compact = 그대로
_aoiw_ss_inherit() {
  local f="$_AOW_SUBS/$_W_PK" old p s
  _W_DORM=0
  [ -n "$_W_PK" ] && [ -f "$f" ] || return 0
  old=$(awk -F'\t' -v w="$_W_SID" 'NF >= 2 && $2 != w { print $1 "\t" $2 }' "$f")
  [ -n "$old" ] || return 0
  case "$_W_SRC" in
    compact) return 0 ;;
    resume)
      _aoi_put "$f" "$(awk -F'\t' -v w="$_W_SID" 'BEGIN { OFS = "\t" } NF >= 2 { $2 = w } { print }' "$f")"
      _aoiw_genup "$_W_PK"
      while IFS=$'\t' read -r p s; do
        _aoi_event sub "$p" "sid=$_W_SID" op=move "gen=$_AOW_G" "from=$s" || true
      done <<< "$old" ;;
    *)
      _W_DORM=$(printf '%s\n' "$old" | grep -c .)
      while IFS=$'\t' read -r p s; do
        _aoi_event sub "$p" "sid=$s" op=dormant "gen=$(_aoiw_gen "$_W_PK")" || true
      done <<< "$old" ;;
  esac
}
# JSON 출력(→ _W_JS, 8KB 이하). 넘치면 표시 줄 상한을 줄인다(_aoiw_body 가 나머지 안내를 붙인다)
_aoiw_ss_out() {
  local cap=20 txt ao="$AO_HOME/bin/agent-orchestrator"
  _W_JS=""
  while :; do
    txt=""
    if [ -n "$_W_C" ]; then _W_CAP=$cap; _aoiw_body; txt=$_W_OUT; fi
    [ "$_W_DORM" -gt 0 ] && txt="${txt:+$txt$'\n'}[inbox] 이 pane에 이전 세션 구독 ${_W_DORM}개 — 이어받으려면 \"$ao\" inbox-subscribe <대상> (목록: inbox-subscribe --list)"
    [ -n "$txt" ] || return 0
    _W_JS=$(printf '%s' "$txt" | "$AO_PERL" -MJSON::PP -e 'local $/; my $t = <STDIN>; utf8::decode($t);
      print JSON::PP->new->utf8->canonical->encode({ hookSpecificOutput =>
        { hookEventName => "SessionStart", additionalContext => $t } })') || ao_die 4 "JSON 인코딩 실패"
    [ "$(printf '%s\n' "$_W_JS" | LC_ALL=C wc -c | tr -d ' ')" -le 8192 ] && return 0
    [ "$cap" -gt 0 ] || return 0
    cap=$((cap - 1))
  done
}
# 잠금 안 재확인: 끄기 표식·발급·스냅샷이 그대로인가(0)
_aoiw_ss_recheck() {
  [ -e "$AO_INBOX_DIR/hooks.off" ] && return 1
  _aoiw_issue_ok || return 1
  _aoiw_snap; [ "$_W_SNAP_NEW" = "$_W_SNAP" ]
}
_aoiw_session_start() {
  local js t nf old="" had=0 LC_ALL=C k
  exec 2>/dev/null
  ao_die() { _W_WHY="error:$(printf '%s' "$*" | tr ' \t' '__' | cut -c1-60)"; exit 0; }
  trap _aoi_cleanup EXIT; trap 'exit 0' TERM HUP INT
  js=$(_aoiw_json session_id source transcript_path) || exit 0
  IFS=$'\t' read -r _W_SID _W_SRC _W_TR <<< "$js"
  _aoiw_sid_ok "$_W_SID" || exit 0
  _W_HOOK=SessionStart; _W_TOK="s$$-$RANDOM$RANDOM-$(date +%s)"
  [ -n "${HERDR_PANE_ID:-}" ] && ao_is_pane "$HERDR_PANE_ID" && _W_PK="pane-${HERDR_PANE_ID//:/_}"
  _aoiw_l8
  [ -e "$AO_INBOX_DIR/hooks.off" ] && exit 0
  _aoiw_ss_issue
  _aoiw_ss_inherit
  _aoiw_snap; _W_SNAP=$_W_SNAP_NEW; _W_TGTS=$_W_TGTS_NEW
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    _AOI_LOG=$t; _aoi_prepare; : >> "$t" 2>/dev/null; _aoi_claim "$_W_SID"
  done <<< "$_W_TGTS"
  mkdir -p "$_AOW_WAIT" 2>/dev/null || exit 0
  _aoiw_deliv
  # 통지 예약: 새 줄만(재통지 몫 nc>0 은 async 대기자 경로). async가 먼저 잡은 줄은 cands에서 빠진다
  _aoiw_cands
  _W_C=$(printf '%s\n' "$_W_C" | awk -F'\t' 'NF >= 5 && $4 == 0')
  nf="$_AOW_WAIT/$_W_SID.notified"
  [ -f "$nf" ] && { old=$(cat "$nf"); had=1; }
  if [ -n "$_W_C" ]; then
    _aoiw_mark_notified
    _aoi_put "$nf" "$(awk -F'\t' -v tk="$_W_TOK" 'BEGIN { OFS = "\t" } $4 == tk { $3 = "ctx"; $5 = 0 } { print }' "$nf")"
  fi
  _aoiw_ss_out
  if ! _aoiw_ss_recheck; then
    if [ "$had" = 1 ]; then _aoi_put "$nf" "$old"; else rm -f "$nf"; fi
    exit 0
  fi
  if [ -n "$_W_JS" ]; then
    k=$(( ${#_W_JS} / 2 ))
    printf '%s' "${_W_JS:0:$k}"
    _aoiw_pause start-mid-out
    printf '%s\n' "${_W_JS:$k}"
  fi
  [ -n "$_W_C" ] && { _aoi_event wait-notify - "sid=$_W_SID" "tok=$_W_TOK" "n=$_W_NLO-$_W_NHI" "arr=${_W_ARR:--}" re=0 hook=SessionStart || true; }
  _aoi_recv_unlock
  exit 0
}

# 앞 대기자 정리(§2-5 3번, 잠금 밖): TERM → 최대 2초 → lstart 재확인 뒤 KILL
_aoiw_reap() {
  local pp=$1 pl=$2 i=0
  [ -n "$pp" ] || return 0
  [ "$(_aoi_lstart "$pp")" = "$pl" ] || return 0
  kill -TERM "$pp" 2>/dev/null
  while [ "$i" -lt 40 ]; do
    [ "$(_aoi_lstart "$pp")" = "$pl" ] || return 0
    sleep 0.05; i=$((i + 1))
  done
  [ "$(_aoi_lstart "$pp")" = "$pl" ] && kill -KILL "$pp" 2>/dev/null
  return 0
}
# 2번 등록(수신 잠금 안). 앞 대기자는 _W_PREV "<pid>\t<lstart>"
_aoiw_register() {
  local m
  _aoiw_l8
  [ -e "$AO_INBOX_DIR/hooks.off" ] && { _W_WHY=off; exit 0; }
  _aoiw_issue_ok || exit 0
  _aoiw_snap
  [ -n "$_W_TGTS_NEW" ] || { _W_WHY=no-target; exit 0; }
  mkdir -p "$_AOW_WAIT" 2>/dev/null || ao_die 4 "대기 폴더 생성 실패"
  _W_PREV=""
  if _aoi_mark_ok "$_AOW_WAIT/$_W_SID.pid"; then
    m=$(head -1 "$_AOW_WAIT/$_W_SID.pid"); m=${m#* }
    _W_PREV="$(awk '{print $1; exit}' "$_AOW_WAIT/$_W_SID.pid")	${m% *}"
  fi
  _aoi_put "$_AOW_WAIT/$_W_SID.pid" "$$ $_W_LS $_W_TOK"
  _W_REG=1; _W_TGTS=""
  _aoiw_adopt
  _aoiw_deliv
  _aoi_recv_unlock
}
# 6번 통지 확정. 0 = 통지 안 하고 계속(스냅샷 갱신) / 그 밖은 exit
_aoiw_notify() {
  local r
  # 잠금을 기다리는 동안의 TERM은 그대로 0(term). 잠금을 잡은 뒤부터 TERM은 표시만 한다(§2-5 8번)
  _aoiw_l8
  trap '_AOI_TERM=1' TERM
  _aoiw_recheck; r=$?
  if [ "$r" = 3 ]; then _aoiw_adopt; r=0; _aoiw_cands; [ -n "$_W_C" ] || r=9; fi
  if [ "$r" != 0 ]; then
    _aoi_recv_unlock
    [ "$r" = 1 ] && exit 0
    [ "$_AOI_TERM" = 1 ] && { _W_WHY=term; exit 0; }
    trap _aoiw_on_term TERM; return 0
  fi
  _aoiw_cands
  if [ -z "$_W_C" ]; then
    _aoi_recv_unlock; [ "$_AOI_TERM" = 1 ] && { _W_WHY=term; exit 0; }
    trap _aoiw_on_term TERM; return 0
  fi
  _aoiw_body
  printf "%s\n" "$_W_OUT" >&5
  _aoiw_pause notify-mid
  _aoiw_mark_notified
  _aoi_event wait-notify - "sid=$_W_SID" "tok=$_W_TOK" "n=$_W_NLO-$_W_NHI" "arr=${_W_ARR:--}" "re=$_W_RE" || true
  _W_WHY=notify
  _aoiw_pause notify-locked
  exit 2
}
_aoiw_wait_main() {
  local js max poll start now r
  js=$(_aoiw_json) || { _W_WHY="error:json"; exit 4; }
  IFS=$'\t' read -r _W_SID _W_HOOK _W_TR <<< "$js"
  _aoiw_sid_ok "$_W_SID" || { _W_SID=""; exit 0; }
  [ -n "${HERDR_PANE_ID:-}" ] && ao_is_pane "$HERDR_PANE_ID" && _W_PK="pane-${HERDR_PANE_ID//:/_}"
  _W_LS=$(_aoi_lstart $$); _W_TOK="w$$-$RANDOM$RANDOM-$(date +%s)"
  max=${AO_INBOX_WAIT_MAX:-7000}; poll=${AO_INBOX_WAIT_POLL:-1}
  mkdir -p "$_AOW_WAIT" 2>/dev/null || { _W_WHY="error:mkdir"; exit 4; }
  _aoiw_lock 7 "$_AOW_WAIT/$_W_SID.swap" 60
  _aoiw_pause pre-register
  [ "$_W_HOOK" = SessionStart ] && _aoiw_issue_wait
  _aoiw_register
  _aoi_event wait-start - "sid=$_W_SID" "tok=$_W_TOK" "hook=${_W_HOOK:--}" "targets=$(printf '%s\n' "$_W_TGTS" | grep -c .)" || true
  _aoiw_pause registered
  IFS=$'\t' read -r _W_PP _W_PL <<< "$_W_PREV"
  _aoiw_reap "${_W_PP:-}" "${_W_PL:-}"
  _aoi_funlock 7
  start=$(date +%s)
  # 5번 폴링: 잠금 없이 스냅샷·토큰·세대·hooks.off 를 보고(파일 몇 개), 바뀌었으면 잠금 안에서 다시 확인한다.
  #   (계획의 "10폴링마다 정기 검증"보다 촘촘하다 — 해제가 1폴링 안에 반영되게)
  while :; do
    _aoiw_recheck; r=$?
    if [ "$r" != 0 ]; then
      _aoiw_l8; _aoiw_recheck; r=$?
      [ "$r" = 1 ] && exit 0
      [ "$r" = 3 ] && _aoiw_adopt
      _aoi_recv_unlock
    fi
    _aoiw_cands
    [ -n "$_W_C" ] && _aoiw_notify
    now=$(date +%s); [ $((now - start)) -ge "$max" ] && { _W_WHY=timeout; exit 0; }
    _aoiw_pause poll
    sleep "$poll" & _W_BG=$!; wait "$_W_BG"; _W_BG=""
  done
}

# ── --drain(§4-3 B·C): 수신 잠금 안에서 hooks.off + 모든 wait/*.pid 비움 → 잠금 밖에서 TERM. stdout 철회 수
_aoiw_drain() {
  local f m pp pl list="" k=0
  _aoi_traps
  _aoi_recv_lock
  : >> "$AO_INBOX_DIR/hooks.off" 2>/dev/null || ao_die 4 "끄기 표식 생성 실패"
  for f in "$_AOW_WAIT"/*.pid; do
    [ -f "$f" ] || continue
    if _aoi_mark_ok "$f"; then
      m=$(head -1 "$f"); pp=${m%% *}; m=${m#* }; pl=${m% *}
      list="$list$pp	$pl"$'\n'; k=$((k + 1))
    fi
    rm -f "$f" || ao_die 4 "대기자 철회 실패: $f"
  done
  _aoi_recv_unlock
  while IFS=$'\t' read -r pp pl; do
    [ -n "$pp" ] && [ "$(_aoi_lstart "$pp")" = "$pl" ] && kill -TERM "$pp" 2>/dev/null
  done <<< "$list"
  echo "$k"
}
_aoiw_undrain() {
  _aoi_traps
  _aoi_recv_lock
  rm -f "$AO_INBOX_DIR/hooks.off" || ao_die 4 "끄기 표식 제거 실패"
  _aoi_recv_unlock
}
ao_inbox_wait() {
  case "${1:-}" in
    --status) [ $# = 1 ] || exit 4; echo "inbox-wait 2"; return 0 ;;
    --drain) [ $# = 1 ] || exit 4; _aoiw_drain; return 0 ;;
    --undrain) [ $# = 1 ] || exit 4; _aoiw_undrain; return 0 ;;
    --session-start) [ $# = 1 ] || exit 4; _aoiw_session_start; return 0 ;;
    "") ;;
    *) exit 4 ;;   # 인자 오류도 4(훅 규약에서 2는 깨움, 계획 §1)
  esac
  # stderr는 깨움 출력 전용(fd 5). 0·4일 때는 비어 있어야 하므로 그 밖의 진단은 events.log 로만
  exec 5>&2 2>/dev/null
  ao_die() { local c=$1; shift; _W_WHY="error:$(printf '%s' "$*" | tr ' \t' '__' | cut -c1-60)"; exit "$c"; }
  trap _aoiw_cleanup EXIT
  trap _aoiw_on_term TERM; trap 'exit 0' HUP INT
  _aoiw_wait_main
}
