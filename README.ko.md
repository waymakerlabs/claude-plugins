# WaymakerLabs Claude Plugins

**한국어** | [English](README.md)

WaymakerLabs에서 만든 유용한 Claude Code 플러그인 모음입니다.

## 마켓플레이스 추가

먼저 WaymakerLabs 마켓플레이스를 Claude Code에 추가하세요:

```bash
/plugin marketplace add waymakerlabs/claude-plugins
```

---

## 사용 가능한 플러그인

---

## ▶ minimal-statusline

> Nord Aurora 테마의 미니멀한 한 줄 상태표시줄.

**미리보기:**

![Minimal Statusline Preview](plugins/minimal-statusline/assets/preview.svg)

**레이아웃:**

| 위치 | 요소 | 설명 |
|------|------|------|
| 1 | Model | 현재 Claude 모델 (예: `Opus 4.5`) |
| 2 | Directory | 작업 디렉토리 경로 (예: `~/Dev`) |
| 3 | Git | 브랜치명 + 상태 (예: `(main)✓`) |
| 4 | Context | Auto-compact까지 남은 컨텍스트 |
| 5 | 5H | 5시간 API 사용량 % + 리셋 시간 (예: `8% (2h58m)`) |
| 6 | 7D | 7일 API 사용량 % + 리셋 요일 (예: `15% (Fri)`) |

**Git 상태 기호:**

| 기호 | 의미 |
|------|------|
| ✓ | Clean (변경사항 없음) |
| + | Staged 변경사항 있음 |
| ! | Unstaged 변경사항 있음 |
| ? | Untracked 파일 있음 |

**Context 상태:**

| 레이블 | 남은 % | 행동 |
|--------|--------|------|
| `Full` | > 50% | 여유 있음 |
| `Half` | 30-50% | 중간 지점 |
| `Low` | 15-30% | 마무리 고려 |
| `Compact` | 5-15% | `/compact` 권장 |
| `Compact!` | < 5% | `/compact` 즉시 필요 |

#### 설치

```bash
/plugin install minimal-statusline@waymakerlabs-claude-plugins
```

#### 설정

```bash
/minimal-statusline-start
```

그 다음 Claude Code를 재시작하세요.

#### 업데이트

플러그인 버전 변경 시 자동으로 업데이트됩니다:

1. 플러그인 업데이트:
```bash
/plugin marketplace update waymakerlabs-claude-plugins
/plugin update minimal-statusline@waymakerlabs-claude-plugins
```

2. Claude Code 재시작 - SessionStart hook을 통해 새 버전이 자동으로 적용됩니다.

#### 수동 설치

플러그인 시스템을 사용하지 않으려면:

**1. 스크립트 다운로드**
```bash
curl -o ~/.claude/minimal-statusline.sh \
  https://raw.githubusercontent.com/waymakerlabs/claude-plugins/main/plugins/minimal-statusline/scripts/minimal-statusline.sh
```

**2. 실행 권한 부여**
```bash
chmod +x ~/.claude/minimal-statusline.sh
```

**3. settings.json에 추가**

`~/.claude/settings.json`에 추가:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/minimal-statusline.sh"
  }
}
```

#### 크레딧

awesomejun의 [Awesome Statusline](https://github.com/awesomejun/awesome-claude-plugins) 기반

---

## ▶ wrap-up

> 작업 마무리 스킬 - Obsidian 문서화 + Git 커밋을 한 번에.

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

#### 설치

```bash
/plugin install wrap-up@waymakerlabs-claude-plugins
```

#### 사용법

```bash
/wrap-up              # 일반 실행
/wrap-up --reconfigure  # Obsidian vault 경로 재설정
```

#### 출력 예시

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

## 문제 해결

### Usage가 N/A로 표시됨

API 사용량 조회는 Claude Pro/Max 구독 + OAuth 인증이 필요합니다.

### 색상이 이상하게 보임

터미널이 True Color (24-bit)를 지원해야 합니다. iTerm2, Warp, Alacritty 등 모던 터미널을 권장합니다.

## 라이선스

MIT
