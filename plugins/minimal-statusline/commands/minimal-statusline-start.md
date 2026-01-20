---
name: minimal-statusline-start
description: Install Minimal Statusline - clean statusline without progress bars
allowed-tools:
  - Read
  - Write
  - Bash
---

# Minimal Statusline Installation

WaymakerLabs의 Minimal Statusline을 설치합니다.

## 특징

- 프로그레스 바 없이 깔끔한 퍼센트 표시
- Catppuccin 테마 그라데이션 컬러 (사용량에 따라 색상 변화)
- 2줄 구성: 모델/스타일/경로 | Context/5H/7D 사용량

## 설치 절차

1. 기존 statusline 백업:
```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
[[ -f ~/.claude/statusline.sh ]] && cp ~/.claude/statusline.sh ~/.claude/statusline-backup-${TIMESTAMP}.sh
```

2. 스크립트 설치:
```bash
cp "${CLAUDE_PLUGIN_ROOT}/scripts/minimal-statusline.sh" ~/.claude/minimal-statusline.sh
chmod +x ~/.claude/minimal-statusline.sh
```

3. settings.json 업데이트:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/minimal-statusline.sh"
  }
}
```

## 설치 완료 메시지

```
✅ Minimal Statusline이 설치되었습니다!

📁 스크립트: ~/.claude/minimal-statusline.sh
🎨 특징: 프로그레스 바 없이 깔끔한 퍼센트 표시

🔄 Claude Code를 재시작하면 적용됩니다.
```
