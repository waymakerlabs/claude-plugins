# lib/wait-status.sh — wait-status: 이 세션이 기다리는 것을 실제 상태와 함께 낸다(2026-11-13).
#   대기 목록을 모델 판단이 아니라 측정으로 만들기 위한 명령. 스킬 「대기 목록과 끝맺음」이 이 출력을 옮겨 쓴다.
#
#   wait-status [--session <sid>]
#   stdout 줄마다 "<종류>\t<이름>\t<상태>\t<근거>"(탭 구분), 마지막 줄 "합계\t대기 <N>\t완료 <M>\t<HH:MM>"
#     서브에이전트  <설명> [<id>]   진행 중|완료      마지막 활동 HH:MM  (subagents/*.meta.json finished, background만)
#                   완료는 최근 AO_WAIT_DONE_WINDOW(기본 3600)초 안에 끝난 것 — 호출자가 이미 회수했으면 무시한다(id로 구분)
#     pane          <id> <이름>     working|idle|done|blocked   같은 탭의 다른 pane(herdr 안일 때만)
#     받은편지함    <경로>          미처리 <k>        #a~#b(구독 대상·pane 받은편지함, cursor 기준)
#   세션 id: --session > CLAUDE_CODE_SESSION_ID. 없으면 서브에이전트 칸만 건너뛴다.
#   백그라운드 셸(run_in_background) 작업은 보지 못한다 — 그 출력 파일은 호출자가 직접 확인한다.
#   종료 0(항상, 칸마다 실패는 건너뜀) / 2 인자
# shellcheck shell=bash

ao_wait_status() {
  local sid=${CLAUDE_CODE_SESSION_ID:-} key pane=${HERDR_PANE_ID:-} f t c n
  case "${1:-}" in
    --session) [ $# = 2 ] || ao_die 2 "사용: wait-status [--session <sid>]"; sid=$2 ;;
    "") ;;
    *) ao_die 2 "사용: wait-status [--session <sid>]" ;;
  esac
  [ "${CLAUDE_CODE_SESSION_KIND:-}" = bg ] && pane=""
  {
    # 1. 서브에이전트
    if [ -n "$sid" ]; then
      AOW_SID=$sid AOW_WIN=${AO_WAIT_DONE_WINDOW:-3600} "$AO_PERL" -MJSON::PP -e '
        use utf8; binmode STDOUT, ":utf8";
        my ($sid, $win) = @ENV{qw(AOW_SID AOW_WIN)}; my $now = time;
        for my $m (glob("$ENV{HOME}/.claude/projects/*/$sid/subagents/agent-*.meta.json")) {
          open my $fh, "<", $m or next; local $/; my $d = eval { decode_json(<$fh>) } or next;
          next unless ($d->{requestShape} // "") eq "background";
          (my $j = $m) =~ s/\.meta\.json$/.jsonl/; my $mt = (stat($j))[9] // (stat($m))[9];
          # 중단(TaskStop)된 것은 finished 가 없다 → 부모 transcript 의 task-notification status 로 가린다
          (my $aid = $m) =~ s{.*/agent-|\.meta\.json$}{}g; (my $pt = $m) =~ s{/subagents/.*}{.jsonl};
          #   마지막 알림 기준. 중단 뒤 다시 이어 받은(resume) 것은 10분 안에 활동이 있으면 진행 중으로 남긴다
          my $killed = 0;
          if (!$d->{finished} && open my $ph, "<", $pt) { local $/; my $x = <$ph>; my $last = "";
            $last = $1 while $x =~ /<task-id>\Q$aid\E<\/task-id>.{0,400}?<status>(\w+)/sg;
            $killed = 1 if $last =~ /^(killed|stopped|failed)$/ && $now - $mt > 600 }
          next if $killed;
          my $st = $d->{finished} ? "완료" : $now - $mt > 600 ? "진행 중(10분 넘게 활동 없음)" : "진행 중";
          next if $d->{finished} && $now - $mt > $win;
          my @l = localtime $mt; (my $ds = $d->{description} // "?") =~ s/[\t\n]/ /g;
          printf "서브에이전트\t%s [%s]\t%s\t마지막 활동 %02d:%02d\n", $ds, $aid, $st, $l[2], $l[1] }' 2>/dev/null
    fi
    # 2. 같은 탭의 다른 pane
    if [ -n "$pane" ] && [ -n "${HERDR_TAB_ID:-}" ] && command -v herdr >/dev/null 2>&1; then
      herdr pane list 2>/dev/null | AOW_TAB=$HERDR_TAB_ID AOW_ME=$pane "$AO_PERL" -MJSON::PP -e '
        use utf8; binmode STDOUT, ":utf8"; local $/; my $d = eval { decode_json(<STDIN>) } or exit 0;
        for my $p (@{ $d->{result}{panes} // [] }) {
          next if $p->{tab_id} ne $ENV{AOW_TAB} || $p->{pane_id} eq $ENV{AOW_ME};
          (my $lb = $p->{label} // $p->{terminal_title_stripped} // "") =~ s/[\t\n]/ /g;
          printf "pane\t%s %s\t%s\t%s\n", $p->{pane_id}, $lb, $p->{agent_status} // "unknown", $p->{agent} ? "agent " . $p->{agent} : "셸" }' 2>/dev/null
    fi
    # 3. 받은편지함(구독 대상 + pane 받은편지함)
    if [ -n "$pane" ] && ao_is_pane "$pane"; then key="pane-${pane//:/_}"; elif [ -n "$sid" ]; then key="sid-$sid"; else key=""; fi
    if [ -n "$key" ]; then
      { cut -f1 "$AO_INBOX_DIR/subs/$key" 2>/dev/null
        case "$key" in pane-*) [ -f "$AO_INBOX_DIR/$key.log" ] && echo "$AO_INBOX_DIR/$key.log" ;; esac
      } | grep '^/' | LC_ALL=C sort -u | while IFS= read -r t; do
        _AOI_LOG=$t; n=$(_aoi_count); c=$(_aoi_num "$t.cursor")
        [ "$n" -gt "$c" ] && printf '받은편지함\t%s\t미처리 %s\t#%s~#%s\n' "$t" "$((n - c))" "$((c + 1))" "$n"
      done
    fi
  } > "${TMPDIR:-/tmp}/aows.$$" 2>/dev/null
  cat "${TMPDIR:-/tmp}/aows.$$"
  f=$(cat "${TMPDIR:-/tmp}/aows.$$")
  n=$(printf '%s\n' "$f" | grep -cE $'\t(진행 중[^\t]*|working|blocked|미처리 [0-9]+)\t')
  c=$(printf '%s\n' "$f" | grep -c $'\t완료\t')
  rm -f "${TMPDIR:-/tmp}/aows.$$"
  printf '합계\t대기 %s\t완료 %s\t%s\n' "$n" "$c" "$(date +%H:%M)"
}
