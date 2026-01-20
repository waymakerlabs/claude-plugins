# WaymakerLabs Claude Plugins

A collection of useful Claude Code plugins by WaymakerLabs.

## Quick Start

**1. Add marketplace**
```bash
/plugin marketplace add waymakerlabs/claude-plugins
```

**2. Install plugin**
```bash
/plugin install minimal-statusline@waymakerlabs-claude-plugins
```

**3. Setup statusline**
```bash
/minimal-statusline-start
```

**4. Restart Claude Code**

---

## Available Plugins

### minimal-statusline

Minimal single-line statusline with Nord Aurora theme.

**Preview:**

![Minimal Statusline Preview](plugins/minimal-statusline/assets/preview.svg)

**Features:**
| Feature | Description |
|---------|-------------|
| Single Line | All info displayed in one line |
| Nord Aurora Theme | Unified Nord color palette |
| Context Labels | `Full` → `Half` → `Low` → `Compact` → `Compact!` |
| Smart Gradient | Green → Yellow → Orange → Red based on usage |
| Git Status | Branch name + status (✓ clean, +staged, !modified, ?untracked) |

**Context Status:**
| Label | Remaining | Action |
|-------|-----------|--------|
| `Full` | > 50% | Plenty of context |
| `Half` | 30-50% | Midway point |
| `Low` | 15-30% | Consider wrapping up |
| `Compact` | 5-15% | Run `/compact` soon |
| `Compact!` | < 5% | Run `/compact` now |

---

## Manual Installation

```bash
# 1. Download script
curl -o ~/.claude/minimal-statusline.sh \
  https://raw.githubusercontent.com/waymakerlabs/claude-plugins/main/plugins/minimal-statusline/scripts/minimal-statusline.sh

# 2. Make executable
chmod +x ~/.claude/minimal-statusline.sh

# 3. Add to settings.json (~/.claude/settings.json)
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/minimal-statusline.sh"
  }
}
```

---

## Troubleshooting

### Usage shows N/A

API usage requires Claude Pro/Max subscription with OAuth authentication.

### Colors look wrong

Your terminal must support True Color (24-bit). We recommend modern terminals like iTerm2, Warp, or Alacritty.

---

## Credits

- **minimal-statusline**: Based on [Awesome Statusline](https://github.com/awesomejun/awesome-claude-plugins) by awesomejun

## License

MIT
