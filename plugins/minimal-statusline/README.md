# Minimal Statusline

Minimal single-line statusline with Nord Aurora theme.

## Preview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Opus 4.5 | ~/Dev (main)✓ | Full | 5H 8% (2h58m) | 7D 15% (Fri)              │
│ ────────   ──────────────   ────   ───────────   ────────────               │
│ Teal       Snow    Green   Green  Blue          Yellow                      │
│ #8FBCBB    #D8DEE9 #A3BE8C        #81A1C1       #EBCB8B                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Color Scheme (Nord Aurora)

| Element | Color | Hex |
|---------|-------|-----|
| Model | Frost Teal | #8FBCBB |
| Directory | Snow Storm | #D8DEE9 |
| Git Branch | Aurora Green | #A3BE8C |
| Git Dirty | Aurora Yellow | #EBCB8B |
| Context | Dynamic | See Context Status Labels |
| 5H | Frost Blue | #81A1C1 |
| 7D | Aurora Yellow | #EBCB8B |

### Usage Gradient (5H, 7D)

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

## Layout

```
Model | Directory (branch)status | CtxStatus | 5H % (time) | 7D % (day)
```

Example:
```
Opus 4.5 | ~/Dev (main)✓ | Full | 5H 8% (2h58m) | 7D 15% (Fri)
```

### Layout Elements

| Position | Element | Description |
|----------|---------|-------------|
| 1 | Model | Current Claude model name |
| 2 | Directory | Working directory with git branch and status |
| 3 | Context Status | Remaining context until auto-compact (see below) |
| 4 | 5H | 5-hour API usage % and reset time |
| 5 | 7D | 7-day API usage % and reset day |

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

## Installation

**1. Install plugin**
```bash
/plugin install minimal-statusline@waymakerlabs-claude-plugins
```

**2. Setup statusline**
```bash
/minimal-statusline-start
```

**3. Restart Claude Code**

> 💡 If statusline is not configured after installation, a setup prompt will appear on session start.

## Credits

Based on [Awesome Statusline](https://github.com/awesomejun/awesome-claude-plugins) by awesomejun.
