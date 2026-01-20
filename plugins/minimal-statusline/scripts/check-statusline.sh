#!/bin/bash
# ============================================================================
# Minimal Statusline - SessionStart Hook
# Check if statusline is configured, prompt setup if not
# ============================================================================

SETTINGS_FILE="$HOME/.claude/settings.json"

# Check if settings.json exists
if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo '{"systemMessage": "📊 Statusline이 설정되지 않았습니다. /minimal-statusline-start 명령으로 Nord Aurora 테마의 미니멀 statusline을 설정할 수 있습니다."}'
    exit 0
fi

# Check if statusLine is configured
STATUSLINE=$(jq -r '.statusLine // empty' "$SETTINGS_FILE" 2>/dev/null)

if [[ -z "$STATUSLINE" || "$STATUSLINE" == "null" ]]; then
    echo '{"systemMessage": "📊 Statusline이 설정되지 않았습니다. /minimal-statusline-start 명령으로 Nord Aurora 테마의 미니멀 statusline을 설정할 수 있습니다."}'
fi

exit 0
