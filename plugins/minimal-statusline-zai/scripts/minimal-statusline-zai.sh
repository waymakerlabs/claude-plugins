#!/bin/bash
# ============================================================================
# Minimal Statusline by WaymakerLabs (z.ai Modified)
# ============================================================================
# Single line: Model | path (branch) | Context left % | 5H % (time) | MON % (day)
# No progress bars - just clean gradient-colored percentages
# ============================================================================
# v1.4.3-zai - Modified for z.ai API
# ============================================================================

input=$(cat)

# Parse JSON input
MODEL=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // "."')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
CURRENT_USAGE=$(echo "$input" | jq -r '.context_window.current_usage // null')

# ============================================================================
# Colors (Nord theme)
# ============================================================================
RESET="\033[0m"
BOLD="\033[1m"
CLR="\033[K"

# Nord Frost (cool blues)
C_FROST_TEAL="\033[38;2;143;188;187m"    # #8FBCBB - Model name
C_FROST_BLUE="\033[38;2;129;161;193m"    # #81A1C1 - 5H label

# Nord Aurora (accent colors)
C_AURORA_RED="\033[38;2;191;97;106m"     # #BF616A - Critical
C_AURORA_ORANGE="\033[38;2;208;135;112m" # #D08770 - Warnings
C_AURORA_YELLOW="\033[38;2;235;203;139m" # #EBCB8B - 7D label
C_AURORA_GREEN="\033[38;2;163;190;140m"  # #A3BE8C - Git clean
C_AURORA_PURPLE="\033[38;2;180;142;173m" # #B48EAD - Context label

# Nord Snow Storm & Polar Night
C_SNOW="\033[38;2;216;222;233m"          # #D8DEE9 - Subtext
C_POLAR="\033[38;2;76;86;106m"           # #4C566A - Overlay/dimmed

# ============================================================================
# Gradient Functions (Nord Aurora)
# ============================================================================

# For usage metrics (5H, 7D): low=green, high=red
get_nord_gradient_color() {
    local pct=$1
    local r g b

    if [[ $pct -lt 30 ]]; then
        # Green (#A3BE8C) → Yellow (#EBCB8B)
        local t=$((pct * 100 / 30))
        r=$((163 + (235 - 163) * t / 100))
        g=$((190 + (203 - 190) * t / 100))
        b=$((140 + (139 - 140) * t / 100))
    elif [[ $pct -lt 60 ]]; then
        # Yellow (#EBCB8B) → Orange (#D08770)
        local t=$(((pct - 30) * 100 / 30))
        r=$((235 + (208 - 235) * t / 100))
        g=$((203 + (135 - 203) * t / 100))
        b=$((139 + (112 - 139) * t / 100))
    elif [[ $pct -lt 85 ]]; then
        # Orange (#D08770) → Red (#BF616A)
        local t=$(((pct - 60) * 100 / 25))
        r=$((208 + (191 - 208) * t / 100))
        g=$((135 + (97 - 135) * t / 100))
        b=$((112 + (106 - 112) * t / 100))
    else
        # Red (#BF616A)
        r=191; g=97; b=106
    fi
    echo "$r;$g;$b"
}

# For context status: returns "label|r;g;b"
get_context_status() {
    local pct=$1
    local label r g b

    if [[ $pct -gt 50 ]]; then
        label="Full"
        r=163; g=190; b=140  # Green (#A3BE8C)
    elif [[ $pct -gt 30 ]]; then
        label="Half"
        r=235; g=203; b=139  # Yellow (#EBCB8B)
    elif [[ $pct -gt 15 ]]; then
        label="Low"
        r=208; g=135; b=112  # Orange (#D08770)
    elif [[ $pct -gt 5 ]]; then
        label="Compact"
        r=191; g=97; b=106   # Red (#BF616A)
    else
        label="Compact!"
        r=191; g=97; b=106   # Red (#BF616A)
    fi
    echo "${label}|${r};${g};${b}"
}

# ============================================================================
# Line 1: Model | Style | Directory + Git
# ============================================================================

MODEL_DISPLAY="${BOLD}${C_FROST_TEAL}${MODEL}${RESET}"

DIR_DISPLAY="${C_SNOW}${CURRENT_DIR/$HOME/~}${RESET}"

GIT_DISPLAY=""
cd "$CURRENT_DIR" 2>/dev/null
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    [[ -n "$BRANCH" ]] && GIT_DISPLAY="${C_AURORA_GREEN}(${BRANCH})${RESET}"

    STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    UNSTAGED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$STAGED" -eq 0 && "$UNSTAGED" -eq 0 && "$UNTRACKED" -eq 0 ]]; then
        GIT_DISPLAY="${GIT_DISPLAY}${C_AURORA_GREEN}✓${RESET}"
    else
        STATUS=""
        [[ "$STAGED" -gt 0 ]] && STATUS="${STATUS}+"
        [[ "$UNSTAGED" -gt 0 ]] && STATUS="${STATUS}!"
        [[ "$UNTRACKED" -gt 0 ]] && STATUS="${STATUS}?"
        GIT_DISPLAY="${GIT_DISPLAY}${C_AURORA_YELLOW}${STATUS}${RESET}"
    fi
fi

LINE1="${MODEL_DISPLAY} | ${DIR_DISPLAY} ${GIT_DISPLAY}"

# ============================================================================
# Line 2: Context + 5H + 7D (no bars, just percentages)
# ============================================================================

# Calculate context remaining until auto-compact (80% threshold)
CONTEXT_USED=0
if [[ "$CURRENT_USAGE" != "null" && -n "$CURRENT_USAGE" ]]; then
    INPUT_TOKENS=$(echo "$CURRENT_USAGE" | jq -r '.input_tokens // 0')
    CACHE_CREATE=$(echo "$CURRENT_USAGE" | jq -r '.cache_creation_input_tokens // 0')
    CACHE_READ=$(echo "$CURRENT_USAGE" | jq -r '.cache_read_input_tokens // 0')
    CURRENT_TOKENS=$((INPUT_TOKENS + CACHE_CREATE + CACHE_READ))
    [[ "$CONTEXT_SIZE" -gt 0 ]] && CONTEXT_USED=$((CURRENT_TOKENS * 100 / CONTEXT_SIZE))
fi

# Context left = 80% (auto-compact threshold) - used%
CONTEXT_LEFT=$((80 - CONTEXT_USED))
[[ $CONTEXT_LEFT -lt 0 ]] && CONTEXT_LEFT=0

CTX_STATUS=$(get_context_status "$CONTEXT_LEFT")
CTX_LABEL=$(echo "$CTX_STATUS" | cut -d'|' -f1)
CTX_COLOR=$(echo "$CTX_STATUS" | cut -d'|' -f2)

# Bold for Compact! (urgent)
if [[ "$CTX_LABEL" == "Compact!" ]]; then
    CTX_DISPLAY="${BOLD}\033[38;2;${CTX_COLOR}m${CTX_LABEL}${RESET}"
else
    CTX_DISPLAY="\033[38;2;${CTX_COLOR}m${CTX_LABEL}${RESET}"
fi

# Usage data (z.ai API)
get_usage_data() {
    local token
    # Get token from settings.json
    token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN // empty' ~/.claude/settings.json 2>/dev/null)
    [[ -z "$token" ]] && return 1

    local cache_file="/tmp/.zai_usage_cache"
    if [[ -f "$cache_file" ]]; then
        local file_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || echo 0)))
        [[ "$file_age" -lt 300 ]] && cat "$cache_file" && return 0
    fi

    local response
    response=$(curl -s --max-time 3 \
        -H "Authorization: Bearer $token" \
        "https://api.z.ai/api/monitor/usage/quota/limit" 2>/dev/null)

    if [[ -n "$response" ]] && echo "$response" | jq -e '.success' &>/dev/null; then
        echo "$response" > "$cache_file"
        echo "$response"
        return 0
    fi
    return 1
}

format_time_remaining_ms() {
    local ts_ms="$1"
    [[ -z "$ts_ms" || "$ts_ms" == "null" ]] && return
    local reset_epoch=$((ts_ms / 1000))
    local now_epoch=$(date +%s)
    local remaining=$((reset_epoch - now_epoch))
    [[ $remaining -lt 0 ]] && remaining=0
    local hours=$((remaining / 3600))
    local minutes=$(((remaining % 3600) / 60))
    echo "${hours}h${minutes}m"
}

format_reset_day_ms() {
    local ts_ms="$1"
    [[ -z "$ts_ms" || "$ts_ms" == "null" ]] && return
    local reset_epoch=$((ts_ms / 1000))
    date -j -f "%s" "$reset_epoch" "+%m/%d" 2>/dev/null
}

USAGE_DATA=$(get_usage_data)

if [[ -n "$USAGE_DATA" ]]; then
    # Parse z.ai API response
    # TIME_LIMIT (unit=5) is 5-hour limit
    FIVE_HOUR=$(echo "$USAGE_DATA" | jq -r '.data.limits[] | select(.type == "TIME_LIMIT" and .unit == 5) | .percentage // 0')
    FIVE_RESET=$(echo "$USAGE_DATA" | jq -r '.data.limits[] | select(.type == "TIME_LIMIT" and .unit == 5) | .nextResetTime // 0')

    # TOKENS_LIMIT is monthly token limit
    MONTHLY=$(echo "$USAGE_DATA" | jq -r '.data.limits[] | select(.type == "TOKENS_LIMIT") | .percentage // 0')
    MONTHLY_RESET=$(echo "$USAGE_DATA" | jq -r '.data.limits[] | select(.type == "TOKENS_LIMIT") | .nextResetTime // 0')

    FIVE_RESET_FMT=$(format_time_remaining_ms "$FIVE_RESET")
    MONTHLY_RESET_FMT=$(format_reset_day_ms "$MONTHLY_RESET")

    FIVE_COLOR=$(get_nord_gradient_color "$FIVE_HOUR")
    MONTHLY_COLOR=$(get_nord_gradient_color "$MONTHLY")

    FIVE_DISPLAY="${C_FROST_BLUE}5D${RESET} ${BOLD}\033[38;2;${FIVE_COLOR}m${FIVE_HOUR}%${RESET} (${FIVE_RESET_FMT})"
    MONTHLY_DISPLAY="${C_AURORA_YELLOW}MON${RESET} ${BOLD}\033[38;2;${MONTHLY_COLOR}m${MONTHLY}%${RESET} (${MONTHLY_RESET_FMT})"

    LINE2="${CTX_DISPLAY} | ${FIVE_DISPLAY} | ${MONTHLY_DISPLAY}"
else
    LINE2="${CTX_DISPLAY} | ${C_POLAR}Usage: N/A${RESET}"
fi

# ============================================================================
# Output (single line)
# ============================================================================
printf "%b | %b%b\n" "$LINE1" "$LINE2" "$CLR"
