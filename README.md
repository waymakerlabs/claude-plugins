# WaymakerLabs Claude Plugins

[한국어](README.ko.md) | **English**

A collection of useful Claude Code plugins by WaymakerLabs.

## Add Marketplace

First, add the WaymakerLabs marketplace to Claude Code:

```bash
/plugin marketplace add waymakerlabs/claude-plugins
```

---

## Available Plugins

---

## ▶ minimal-statusline

> Minimal single-line statusline with Nord Aurora theme.

**Preview:**

![Minimal Statusline Preview](plugins/minimal-statusline/assets/preview.svg)

**Layout:**

| Position | Element | Description |
|----------|---------|-------------|
| 1 | Model | Current Claude model (e.g., `Opus 4.5`) |
| 2 | Directory | Working directory path (e.g., `~/Dev`) |
| 3 | Git | Branch name + status (e.g., `(main)✓`) |
| 4 | Context | Remaining context until auto-compact |
| 5 | 5H | 5-hour API usage % + reset time (e.g., `8% (2h58m)`) |
| 6 | 7D | 7-day API usage % + reset day (e.g., `15% (Fri)`) |

**Git Status Symbols:**

| Symbol | Meaning |
|--------|---------|
| ✓ | Clean (no changes) |
| + | Staged changes |
| ! | Unstaged changes |
| ? | Untracked files |

**Context Status:**

| Label | Remaining | Action |
|-------|-----------|--------|
| `Full` | > 50% | Plenty of context |
| `Half` | 30-50% | Midway point |
| `Low` | 15-30% | Consider wrapping up |
| `Compact` | 5-15% | Run `/compact` soon |
| `Compact!` | < 5% | Run `/compact` now |

#### Install

```bash
/plugin install minimal-statusline@waymakerlabs-claude-plugins
```

#### Setup

```bash
/minimal-statusline-start
```

Then restart Claude Code.

#### Update

Updates are applied automatically when plugin version changes:

1. Update the plugin:
```bash
/plugin marketplace update waymakerlabs-claude-plugins
/plugin update minimal-statusline@waymakerlabs-claude-plugins
```

2. Restart Claude Code - the new version is automatically applied via SessionStart hook.

#### Manual Installation

If you prefer not to use the plugin system:

**1. Download script**
```bash
curl -o ~/.claude/minimal-statusline.sh \
  https://raw.githubusercontent.com/waymakerlabs/claude-plugins/main/plugins/minimal-statusline/scripts/minimal-statusline.sh
```

**2. Make executable**
```bash
chmod +x ~/.claude/minimal-statusline.sh
```

**3. Add to settings.json**

Add to `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/minimal-statusline.sh"
  }
}
```

#### Credits

Based on [Awesome Statusline](https://github.com/awesomejun/awesome-claude-plugins) by awesomejun

---

## ▶ wrap-up

> Session wrap-up skill - Obsidian documentation + Git commit in one go.

**Features:**

| Feature | Description |
|---------|-------------|
| Daily Log | Record today's work in daily log |
| Handoff | Generate handoff document (single file, overwrites previous) |
| Doc Update | Auto-update related docs (project overview, etc.) |
| Git Commit/Push | Commit and push code changes |

> **Note**: Handoff maintains only one file. Previous handoff is deleted and a new timestamped file is created, so you can see when the last session ended.

**Execution Flow:**

```
/wrap-up
    │
    ├─ Check config (ask for Obsidian vault path if not set)
    ├─ Find project folder (ask to create if not found)
    ├─ Create/update daily log
    ├─ Generate handoff document
    ├─ Update related documents
    ├─ Git commit & push
    └─ Output next session prompt
```

#### Install

```bash
/plugin install wrap-up@waymakerlabs-claude-plugins
```

#### Usage

```bash
/wrap-up              # Normal execution
/wrap-up --reconfigure  # Reconfigure Obsidian vault path
```

#### Output Example

```
✅ Wrap-up complete!

📝 Daily log: Logos App/daily-logs/2026-01-21.md
📋 Handoff: Logos App/handoffs/HANDOFF-2026-01-21-1730.md
📦 Commit: abc1234 - feat: add vocabulary validation

---
🚀 Next session prompt:

.../Logos App/handoffs/HANDOFF-2026-01-21-1730.md - read and continue working.
```

---

## Troubleshooting

### Usage shows N/A

API usage requires Claude Pro/Max subscription with OAuth authentication.

### Colors look wrong

Your terminal must support True Color (24-bit). We recommend modern terminals like iTerm2, Warp, or Alacritty.

## License

MIT
