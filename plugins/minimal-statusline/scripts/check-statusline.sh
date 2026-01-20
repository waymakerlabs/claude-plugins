#!/bin/bash
# ============================================================================
# Minimal Statusline - SessionStart Hook
# Auto-update statusline script when plugin version changes
# ============================================================================

SETTINGS_FILE="$HOME/.claude/settings.json"
TARGET_SCRIPT="$HOME/.claude/minimal-statusline.sh"
SOURCE_SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/minimal-statusline.sh"

# Get plugin version from plugin.json
PLUGIN_VERSION=$(jq -r '.version // "unknown"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)

# Check if statusLine is configured
if [[ -f "$SETTINGS_FILE" ]]; then
    STATUSLINE=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
fi

# If statusline not configured, show setup message
if [[ -z "$STATUSLINE" || "$STATUSLINE" == "null" ]]; then
    echo '{"systemMessage": "📊 Statusline is not configured. Run /minimal-statusline-start to set up the minimal statusline with Nord Aurora theme."}'
    exit 0
fi

# If configured but target script doesn't exist, copy it
if [[ ! -f "$TARGET_SCRIPT" ]]; then
    cp "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
    chmod +x "$TARGET_SCRIPT"
    echo '{"systemMessage": "✅ Minimal Statusline v'"$PLUGIN_VERSION"' installed. Restart Claude Code to apply."}'
    exit 0
fi

# Check installed version (from script header comment)
INSTALLED_VERSION=$(grep "^# v" "$TARGET_SCRIPT" 2>/dev/null | head -1 | sed 's/^# v//')

# If versions differ, update
if [[ "$INSTALLED_VERSION" != "$PLUGIN_VERSION" ]]; then
    cp "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
    chmod +x "$TARGET_SCRIPT"
    echo '{"systemMessage": "✅ Minimal Statusline updated: v'"$INSTALLED_VERSION"' → v'"$PLUGIN_VERSION"'. Restart Claude Code to apply."}'
    exit 0
fi

exit 0
