#!/bin/bash
# ============================================================================
# Minimal Statusline - SessionStart Hook
# Auto-update statusline script when plugin version changes
# ============================================================================
# plugin.json is the single source of truth for the version. The version that
# was last installed is recorded in a marker file, so the hook never depends
# on a "# vX.Y.Z" comment in the script header being kept in sync by hand.
# ============================================================================

SETTINGS_FILE="$HOME/.claude/settings.json"
TARGET_SCRIPT="$HOME/.claude/minimal-statusline.sh"
MARKER_FILE="$HOME/.claude/.minimal-statusline.version"
SOURCE_SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/minimal-statusline.sh"

# Get plugin version from plugin.json
PLUGIN_VERSION=$(jq -r '.version // "unknown"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)

# Without a readable plugin version there is nothing meaningful to compare
if [[ -z "$PLUGIN_VERSION" || "$PLUGIN_VERSION" == "unknown" ]]; then
    exit 0
fi

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
    printf '%s\n' "$PLUGIN_VERSION" > "$MARKER_FILE"
    echo '{"systemMessage": "✅ Minimal Statusline v'"$PLUGIN_VERSION"' installed. Restart Claude Code to apply."}'
    exit 0
fi

# Installed version: read the marker written by this hook.
# Installs that predate the marker fall back to the script header once.
if [[ -f "$MARKER_FILE" ]]; then
    INSTALLED_VERSION=$(tr -d '[:space:]' < "$MARKER_FILE")
else
    INSTALLED_VERSION=$(grep "^# v" "$TARGET_SCRIPT" 2>/dev/null | head -1 | sed 's/^# v//' | cut -d' ' -f1)
fi

# Versions match: just make sure the marker exists, then stay silent
if [[ "$INSTALLED_VERSION" == "$PLUGIN_VERSION" ]]; then
    [[ -f "$MARKER_FILE" ]] || printf '%s\n' "$PLUGIN_VERSION" > "$MARKER_FILE"
    exit 0
fi

# Versions differ but the script is already identical (e.g. a metadata-only
# bump): record the new version without bothering the user.
if cmp -s "$SOURCE_SCRIPT" "$TARGET_SCRIPT"; then
    printf '%s\n' "$PLUGIN_VERSION" > "$MARKER_FILE"
    exit 0
fi

# Script content actually changed: update and ask for a restart
cp "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"
printf '%s\n' "$PLUGIN_VERSION" > "$MARKER_FILE"
echo '{"systemMessage": "✅ Minimal Statusline updated: v'"${INSTALLED_VERSION:-unknown}"' → v'"$PLUGIN_VERSION"'. Restart Claude Code to apply."}'
exit 0
