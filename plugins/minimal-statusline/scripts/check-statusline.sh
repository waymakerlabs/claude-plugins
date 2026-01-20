#!/bin/bash
# ============================================================================
# Minimal Statusline - SessionStart Hook
# Check if statusline is configured, prompt setup if not
# ============================================================================

SETTINGS_FILE="$HOME/.claude/settings.json"

# Check if settings.json exists
if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo '{"systemMessage": "📊 Statusline is not configured. Run /minimal-statusline-start to set up the minimal statusline with Nord Aurora theme."}'
    exit 0
fi

# Check if statusLine is configured
STATUSLINE=$(jq -r '.statusLine // empty' "$SETTINGS_FILE" 2>/dev/null)

if [[ -z "$STATUSLINE" || "$STATUSLINE" == "null" ]]; then
    echo '{"systemMessage": "📊 Statusline is not configured. Run /minimal-statusline-start to set up the minimal statusline with Nord Aurora theme."}'
fi

exit 0
