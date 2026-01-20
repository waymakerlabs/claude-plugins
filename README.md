# WaymakerLabs Claude Plugins

A collection of useful Claude Code plugins by WaymakerLabs.

## Quick Start

```bash
# 1. Add marketplace
/plugin marketplace add waymakerlabs/claude-plugins

# 2. Install plugin
/plugin install minimal-statusline@waymakerlabs-claude-plugins

# 3. Setup statusline
/minimal-statusline-start

# 4. Restart Claude Code
```

---

## Available Plugins

### minimal-statusline

Minimal single-line statusline with Nord Aurora theme.

**Preview:**
```
Opus 4.5 | ~/Dev (main)✓ | Context 4% | 5H 7% (3h18m) | 7D 14% (Fri)
```

**Features:**
| Feature | Description |
|---------|-------------|
| Single Line | All info displayed in one line |
| Nord Aurora Theme | Unified Nord color palette |
| No Progress Bars | Clean percentage numbers only |
| Smart Gradient | Green → Yellow → Orange → Red based on usage |
| Git Status | Branch name + status (✓ clean, +staged, !modified, ?untracked) |

**Install:**
```bash
/plugin install minimal-statusline@waymakerlabs-claude-plugins
```

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
