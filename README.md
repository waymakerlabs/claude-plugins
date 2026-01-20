# WaymakerLabs Claude Plugins

A collection of useful Claude Code plugins by WaymakerLabs.

## Quick Start

### 1. Add Marketplace

```bash
/plugin marketplace add waymakerlabs/claude-plugins
```

### 2. Install Plugin

```bash
/plugin install minimal-statusline@waymakerlabs-claude-plugins
```

### 3. Restart Claude Code

설치 후 Claude Code를 재시작하면 새 statusline이 적용됩니다.

---

## Available Plugins

### minimal-statusline

프로그레스 바 없이 깔끔한 퍼센트만 표시하는 미니멀 스테이터스라인.

**Preview:**
```
Opus 4.5 | Explanatory | ~/Dev (main)✓
Context 4% | 5H 0% (3h43m) | 7D 14% (Fri)
```

**Features:**
| 기능 | 설명 |
|------|------|
| No Progress Bars | 바 없이 숫자만 깔끔하게 표시 |
| Gradient Colors | 사용량에 따라 색상 변화 (낮음: 핑크/라벤더 → 높음: 레드) |
| Git Status | 브랜치명 + 상태 표시 (✓ clean, +staged, !modified, ?untracked) |
| API Usage | 5시간/7일 사용량 및 리셋 시간 표시 |

**Line 1 구성:**
- 모델명 (Opus 4.5, Sonnet 등)
- Output Style (있는 경우)
- 현재 디렉토리 경로
- Git 브랜치 및 상태

**Line 2 구성:**
- `Context`: 현재 대화의 컨텍스트 윈도우 사용률
- `5H`: 5시간 API 사용량 + 리셋까지 남은 시간
- `7D`: 7일 API 사용량 + 리셋 요일

---

## Manual Installation

플러그인 마켓플레이스 없이 수동으로 설치하려면:

```bash
# 1. 스크립트 다운로드
curl -o ~/.claude/minimal-statusline.sh \
  https://raw.githubusercontent.com/waymakerlabs/claude-plugins/main/plugins/minimal-statusline/scripts/minimal-statusline.sh

# 2. 실행 권한 부여
chmod +x ~/.claude/minimal-statusline.sh

# 3. settings.json에 추가 (~/.claude/settings.json)
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
