---
name: minimal-statusline-zai-start
description: Install Minimal Statusline for z.ai - clean statusline without progress bars
allowed-tools:
  - Read
  - Write
  - Bash
---

# Minimal Statusline for z.ai Installation

z.ai API용 Minimal Statusline을 설치합니다.

## 특징

- 프로그레스 바 없이 깔끔한 퍼센트 표시
- Nord Aurora 테마 그라데이션 컬러 (사용량에 따라 색상 변화)
- z.ai API 사용량 표시: 5D (5일 제한) / MON (월간 토큰)

## 설치 절차

1. 기존 statusline 백업:
```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
[[ -f ~/.claude/minimal-statusline-zai.sh ]] && cp ~/.claude/minimal-statusline-zai.sh ~/.claude/minimal-statusline-zai-backup-${TIMESTAMP}.sh
```

2. 스크립트 설치:
```bash
cp "${CLAUDE_PLUGIN_ROOT}/scripts/minimal-statusline-zai.sh" ~/.claude/minimal-statusline-zai.sh
chmod +x ~/.claude/minimal-statusline-zai.sh
```

3. settings.json 업데이트:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/minimal-statusline-zai.sh"
  }
}
```

## 설치 완료 메시지

```
✅ Minimal Statusline for z.ai가 설치되었습니다!

📁 스크립트: ~/.claude/minimal-statusline-zai.sh
🎨 특징: z.ai API 사용량 (5D / MON) 표시

🔄 Claude Code를 재시작하면 적용됩니다.
```
