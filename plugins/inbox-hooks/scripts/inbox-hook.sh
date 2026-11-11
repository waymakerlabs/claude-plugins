#!/usr/bin/env bash
# inbox-hook.sh — inbox-hooks 플러그인 래퍼(계획 2026-11-11-inbox-simplify §3·§10).
#   inbox-hook.sh wait   Stop·StopFailure·UserPromptSubmit·SessionStart asyncRewake 대기자
#                        → exec "$AO" inbox-wait (stdin 훅 JSON 그대로, 종료 코드·stderr 그대로)
# AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}
# 조용한 무동작(stdin 버리고 exit 0, 출력 없음):
#   - AO가 없거나 실행 불가, `--status`가 "inbox-wait 2"가 아님(옛 판)
#   - $AO_STATE_ROOT/inbox/hooks.off 표식, 알 수 없는 모드(옛 session-start 포함)
# 이 래퍼는 상태 파일을 쓰지 않는다.

_quiet() { cat >/dev/null 2>&1; exit 0; }

AO=${AGENT_ORCHESTRATOR:-$HOME/.local/bin/agent-orchestrator}
root=${AO_STATE_ROOT:-$HOME/.local/state/agent-orchestrator}

[ "${1:-}" = wait ] || _quiet
[ -e "$root/inbox/hooks.off" ] && _quiet
[ -x "$AO" ] || _quiet
st=$("$AO" inbox-wait --status </dev/null 2>/dev/null) || _quiet
[ "$st" = "inbox-wait 2" ] || _quiet
exec "$AO" inbox-wait
