# Minimal Statusline

깔끔한 미니멀 스테이터스라인 - Nord Aurora 테마, 프로그레스 바 없이 그라데이션 컬러 퍼센트만 표시.

## Preview

```
Opus 4.5 | Explanatory | ~/Dev (main)✓
Context 4% | 5H 0% (3h43m) | 7D 14% (Fri)
```

## Color Scheme (Nord Aurora)

| 요소 | 색상 | Hex |
|------|------|-----|
| Model | Frost Teal | #8FBCBB |
| Style | Aurora Orange | #D08770 |
| Directory | Snow Storm | #D8DEE9 |
| Git Branch | Aurora Green | #A3BE8C |
| Git Dirty | Aurora Yellow | #EBCB8B |
| Context | Aurora Purple | #B48EAD |
| 5H | Frost Blue | #81A1C1 |
| 7D | Aurora Yellow | #EBCB8B |

### Usage Gradient

사용량에 따른 퍼센트 색상 변화:

```
0%  ━━━━━ 30% ━━━━━ 60% ━━━━━ 85% ━━━━━ 100%
Green    Yellow    Orange     Red
#A3BE8C  #EBCB8B   #D08770   #BF616A
```

## Features

- **No Progress Bars**: 바 없이 숫자만 깔끔하게
- **Nord Aurora Theme**: 통일된 Nord 팔레트
- **Smart Gradient**: 사용량에 따라 Green → Yellow → Orange → Red
- **2-Line Layout**:
  - Line 1: 모델 | 스타일 | 경로 (브랜치) 상태
  - Line 2: Context % | 5H % (남은시간) | 7D % (리셋요일)

## Installation

```bash
/minimal-statusline-start
```

## Credits

Based on [Awesome Statusline](https://github.com/awesomejun/awesome-claude-plugins) by awesomejun.
