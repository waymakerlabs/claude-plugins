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

Nord Aurora 테마의 미니멀 스테이터스라인 - 한 줄 레이아웃.

**Preview:**
```
Opus 4.5 | ~/Dev (main)✓ | Context 4% | 5H 7% (3h18m) | 7D 14% (Fri)
```

**Features:**
| 기능 | 설명 |
|------|------|
| Single Line | 한 줄에 모든 정보 표시 |
| Nord Aurora Theme | 통일된 Nord 팔레트 |
| No Progress Bars | 바 없이 숫자만 깔끔하게 |
| Smart Gradient | 사용량에 따라 Green → Yellow → Orange → Red |
| Git Status | 브랜치명 + 상태 (✓ clean, +staged, !modified, ?untracked) |

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

### Usage가 N/A로 표시되는 경우

API 사용량 조회에는 Claude Pro/Max 구독과 OAuth 인증이 필요합니다.

### 색상이 이상하게 보이는 경우

터미널이 True Color (24-bit)를 지원해야 합니다. iTerm2, Warp, Alacritty 등 모던 터미널 사용을 권장합니다.

---

## Credits

- **minimal-statusline**: Based on [Awesome Statusline](https://github.com/awesomejun/awesome-claude-plugins) by awesomejun

## License

MIT
