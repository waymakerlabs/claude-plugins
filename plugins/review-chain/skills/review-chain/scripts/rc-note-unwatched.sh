#!/usr/bin/env bash
# rc-note-unwatched.sh — 보낸 쪽 기록에 `- 미감시 전송 <받은편지함> <HH:MM>` 한 줄 (0.2.0)
#
# 사용(rc-send.sh·rc-claim.sh 전용):
#   rc-note-unwatched.sh report <report.md> "<기록 줄>"   `- 진행:` 줄(과 그 아래 기존 기록) 바로 아래, 없으면 파일 끝
#   rc-note-unwatched.sh state  <state.md>  "<기록 줄>"   "## 미감시 전송" 절 끝, 절이 없으면 파일 끝에 절을 만듦
#
# 같은 파일을 고치는 rc-send/rc-claim 끼리는 <파일>.flock 커널 잠금(perl flock, 최대 10초)으로 직렬화한다.
#   읽고 → 임시 파일 → mv 를 잠금 안에서 하므로 동시 송신의 기록이 서로 지우지 않는다.
#   (사람·세션이 편집기로 같은 파일을 동시에 고치는 경우까지는 막지 못한다.)
# 종료 코드: 0 기록 / 2 인자 / 4 잠금·쓰기 실패. 호출자는 실패를 경고로만 다룬다. bash 3.2 호환.

set -u
[ $# = 3 ] || { echo "rc-note-unwatched: 사용: $0 report|state <파일> <기록 줄>" >&2; exit 2; }
MODE=$1; F=$2; REC=$3
case "$MODE" in report|state) ;; *) echo "rc-note-unwatched: 모드 오류: $MODE" >&2; exit 2 ;; esac
[ -f "$F" ] || { echo "rc-note-unwatched: 파일 없음: $F" >&2; exit 4; }

# 잠금 안에서 이 스크립트를 _locked 모드로 다시 부른다(perl 부모가 잠금을 쥔 채 기다린다)
if [ "${RC_NOTE_LOCKED:-}" != 1 ]; then
  RC_NOTE_LOCKED=1 /usr/bin/perl -MFcntl=:flock -e '
    my $lk = shift;
    open(my $fh, ">>", $lk) or exit 4;
    my $ok = eval { local $SIG{ALRM} = sub { die "t\n" }; alarm 10; flock($fh, LOCK_EX) or die "f\n"; alarm 0; 1 };
    exit 4 unless $ok;
    my $rc = system(@ARGV);
    exit($rc == 0 ? 0 : 4);
  ' "$F.flock" "$0" "$MODE" "$F" "$REC"
  exit $?
fi

T="$F.tmp.$$"
if [ "$MODE" = report ]; then
  RC_REC=$REC awk 'BEGIN { rec = ENVIRON["RC_REC"] }
    { L[NR] = $0 }
    END {
      at = 0
      for (i = 1; i <= NR; i++) if (L[i] ~ /^- 진행:/) { at = i; break }
      if (at) while (at < NR && L[at + 1] ~ /^- 미감시 전송 /) at++
      for (i = 1; i <= NR; i++) { print L[i]; if (at && i == at) print rec }
      if (!at) print rec
    }' "$F" > "$T" && mv "$T" "$F" || { rm -f "$T"; exit 4; }
else
  RC_REC=$REC awk 'BEGIN { rec = ENVIRON["RC_REC"] }
    { L[NR] = $0 }
    END {
      s = 0; e = NR
      for (i = 1; i <= NR; i++) if (L[i] == "## 미감시 전송") { s = i; break }
      if (s) { for (i = s + 1; i <= NR; i++) if (L[i] ~ /^## /) { e = i - 1; break }
               at = s; for (i = s + 1; i <= e; i++) if (L[i] !~ /^[ \t]*$/) at = i }
      for (i = 1; i <= NR; i++) { print L[i]; if (s && i == at) print rec }
      if (!s) { if (NR > 0) print ""; print "## 미감시 전송"; print rec }
    }' "$F" > "$T" && mv "$T" "$F" || { rm -f "$T"; exit 4; }
fi
exit 0
