# Minimal Statusline for z.ai

Minimal single-line statusline for z.ai API with Nord Aurora theme.

## Preview

```
glm-5 | ~/Dev (main)✓ | Full | 5D 2% (126h7m) | MON 1% (02/23)
```

## Color Scheme (Nord Aurora)

| Element | Color | Hex |
|---------|-------|-----|
| Model | Frost Teal | #8FBCBB |
| Directory | Snow Storm | #D8DEE9 |
| Git Branch | Aurora Green | #A3BE8C |
| Git Dirty | Aurora Yellow | #EBCB8B |
| Context | Dynamic | See Context Status Labels |
| 5D | Frost Blue | #81A1C1 |
| MON | Aurora Yellow | #EBCB8B |

### Usage Gradient (5D, MON)

Percentage color changes based on usage:

```
0%  ───── 30% ───── 60% ───── 85% ───── 100%
Green    Yellow    Orange     Red
#A3BE8C  #EBCB8B   #D08770   #BF616A
```

## Features

- **Single Line**: All info displayed in one line
- **No Progress Bars**: Clean text labels and percentages
- **Nord Aurora Theme**: Unified Nord color palette
- **Smart Gradient**: Green → Yellow → Orange → Red based on usage
- **z.ai API**: Supports z.ai usage quota API

## Layout

```
Model | Directory (branch)status | CtxStatus | 5D % (time) | MON % (date)
```

### Layout Elements

| Position | Element | Description |
|----------|---------|-------------|
| 1 | Model | Current Claude model name |
| 2 | Directory | Working directory with git branch and status |
| 3 | Context Status | Remaining context until auto-compact (see below) |
| 4 | 5D | 5-day API usage % and reset time (z.ai TIME_LIMIT) |
| 5 | MON | Monthly token usage % and reset date (z.ai TOKENS_LIMIT) |

### Context Status Labels

Shows remaining context until auto-compact triggers (at 80%):

| Label | Remaining | Color | Meaning |
|-------|-----------|-------|---------|
| `Full` | > 50% | 🟢 Green | Plenty of context available |
| `Half` | 30-50% | 🟡 Yellow | Midway point |
| `Low` | 15-30% | 🟠 Orange | Consider wrapping up |
| `Compact` | 5-15% | 🔴 Red | Run `/compact` soon |
| `Compact!` | < 5% | 🔴 Red (Bold) | Run `/compact` now |

### Git Status Symbols

| Symbol | Meaning |
|--------|---------|
| ✓ | Clean (no changes) |
| + | Staged changes |
| ! | Unstaged changes |
| ? | Untracked files |

## Requirements

- z.ai API account with `ANTHROPIC_AUTH_TOKEN` configured
- `jq` for JSON parsing

## Installation

**1. Install plugin**
```bash
/plugin install minimal-statusline-zai@waymakerlabs-claude-plugins
```

**2. Setup statusline**
```bash
/minimal-statusline-zai-start
```

**3. Restart Claude Code**

> 💡 If statusline is not configured after installation, a setup prompt will appear on session start.

## Differences from Original

This version is modified for z.ai API:
- Uses z.ai `/api/monitor/usage/quota/limit` endpoint
- Shows **5D** (5-day limit) instead of 5H
- Shows **MON** (monthly tokens) instead of 7D
- Reads token from `~/.claude/settings.json`

## Credits

Based on [Minimal Statusline](../minimal-statusline) by WaymakerLabs.
Original based on [Awesome Statusline](https://github.com/awesomejun/awesome-claude-plugins) by awesomejun.
