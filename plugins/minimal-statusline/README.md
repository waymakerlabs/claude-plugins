# Minimal Statusline

미니멀 스테이터스라인 - Nord Aurora 테마, 한 줄 레이아웃.

## Preview

```
Opus 4.5 | ~/Dev (main)✓ | Context 4% | 5H 7% (3h18m) | 7D 14% (Fri)
```

## Color Scheme (Nord Aurora)

| 요소 | 색상 | Hex |
|------|------|-----|
| Model | Frost Teal | #8FBCBB |
| Directory | Snow Storm | #D8DEE9 |
| Git Branch | Aurora Green | #A3BE8C |
| Git Dirty | Aurora Yellow | #EBCB8B |
| Context | Aurora Orange | #D08770 |
| 5H | Frost Blue | #81A1C1 |
| 7D | Aurora Yellow | #EBCB8B |

### Usage Gradient

사용량에 따른 퍼센트 색상 변화:

```
0%  ───── 30% ───── 60% ───── 85% ───── 100%
Green    Yellow    Orange     Red
#A3BE8C  #EBCB8B   #D08770   #BF616A
```

## Features

- **Single Line**: 한 줄에 모든 정보 표시
- **No Progress Bars**: 바 없이 숫자만 깔끔하게
- **Nord Aurora Theme**: 통일된 Nord 팔레트
- **Smart Gradient**: 사용량에 따라 Green → Yellow → Orange → Red

## Layout

```
Model | Directory (branch)status | Context % | 5H % (time) | 7D % (day)
```

## Installation

```bash
# 1. Install plugin
/plugin install minimal-statusline@waymakerlabs-claude-plugins

# 2. Setup statusline
/minimal-statusline-start

# 3. Restart Claude Code
```

> 💡 플러그인 설치 후 statusline이 설정되지 않았으면, 세션 시작 시 자동으로 안내 메시지가 표시됩니다.

## Credits

Based on [Awesome Statusline](https://github.com/awesomejun/awesome-claude-plugins) by awesomejun.
