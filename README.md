# WaymakerLabs Claude Plugins

A collection of useful Claude Code plugins by WaymakerLabs.

## Add Marketplace

First, add the WaymakerLabs marketplace to Claude Code:

```bash
/plugin marketplace add waymakerlabs/claude-plugins
```

---

## Available Plugins

### minimal-statusline

Minimal single-line statusline with Nord Aurora theme.

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

### wrap-up

작업 마무리 스킬 - Obsidian 문서화 + Git 커밋을 한 번에.

**기능:**

| 기능 | 설명 |
|------|------|
| Daily Log | 오늘 작업 내용을 daily log에 기록 |
| Handoff | 다음 세션을 위한 handoff 문서 생성 |
| 문서 업데이트 | 프로젝트 소개 등 관련 문서 자동 업데이트 |
| Git Commit/Push | 코드 변경사항 커밋 및 푸시 |

**실행 흐름:**

```
/wrap-up 실행
    │
    ├─ 설정 확인 (없으면 Obsidian vault 경로 물어봄)
    ├─ 프로젝트 폴더 확인 (없으면 생성 여부 물어봄)
    ├─ Daily log 생성/업데이트
    ├─ Handoff 문서 생성
    ├─ 관련 문서 업데이트
    ├─ Git commit & push
    └─ 다음 세션 시작 프롬프트 출력
```

#### Install

```bash
/plugin install wrap-up@waymakerlabs-claude-plugins
```

#### Usage

```bash
/wrap-up              # 일반 실행
/wrap-up --reconfigure  # Obsidian vault 경로 재설정
```

#### Output Example

```
✅ Wrap-up 완료!

📝 Daily log: Logos App/daily-logs/2026-01-21.md
📋 Handoff: Logos App/handoffs/HANDOFF-2026-01-21-1730.md
📦 Commit: abc1234 - feat: add vocabulary validation

---
🚀 다음 세션 시작 프롬프트:

.../Logos App/handoffs/HANDOFF-2026-01-21-1730.md를 읽고 이어서 작업해줘.
```

---

## Troubleshooting

### Usage shows N/A

API usage requires Claude Pro/Max subscription with OAuth authentication.

### Colors look wrong

Your terminal must support True Color (24-bit). We recommend modern terminals like iTerm2, Warp, or Alacritty.

## License

MIT
