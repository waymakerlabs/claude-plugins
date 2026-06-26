# Minimal Statusline

Minimal single-line statusline with Nord Aurora theme.

## Preview

![Minimal Statusline Preview](assets/preview.svg)

## Color Scheme (Nord Aurora)

| Element | Color | Hex |
|---------|-------|-----|
| Model | Frost Teal | #8FBCBB |
| Directory | Snow Storm | #D8DEE9 |
| Git Branch | Aurora Green | #A3BE8C |
| Git Dirty | Aurora Yellow | #EBCB8B |
| Context | Dynamic | See Context Usage Bands |
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
Model | Directory (branch)status | C % | 5H % (time) | 7D % (day)
```

Example:
```
Opus 4.8 | ~/Dev (main)✓ | C 33% | 5H 8% (2h58m) | 7D 15% (Fri)
```

### Layout Elements

| Position | Element | Description |
|----------|---------|-------------|
| 1 | Model | Current Claude model name |
| 2 | Directory | Working directory with git branch and status |
| 3 | Context (`C`) | Context window usage % — matches the Claude app's "used" figure (see below) |
| 4 | 5H | 5-hour API usage % and reset time |
| 5 | 7D | 7-day API usage % and reset day |

### Context Usage Bands

`C` shows how much of the context window is **used** (e.g. `C 33%` = 332.3k / 1.0M), the same number the Claude app reports. The color steps up in bands aligned to the ~90% auto-compact point:

| Used | Color | Meaning |
|------|-------|---------|
| 0–49% | 🟢 Green | Safe — plenty of room |
| 50–74% | 🟡 Yellow | "Dumb zone" — quality may start to degrade |
| 75–84% | 🟠 Orange | Warning — compaction approaching |
| 85%+ | 🔴 Red | Compact imminent (auto-compact ~90%) |

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
