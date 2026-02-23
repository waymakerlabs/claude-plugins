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
| Handoff | 다음 세션을 위한 handoff 문서 생성 (단일 파일 유지) |
| 문서 업데이트 | 프로젝트 소개 등 관련 문서 자동 업데이트 |
| Git Commit/Push | 코드 변경사항 커밋 및 푸시 |

> **참고**: Handoff는 항상 하나의 파일만 유지합니다. 이전 handoff는 삭제되고 타임스탬프가 포함된 새 파일이 생성되어, 마지막 세션 종료 시점을 확인할 수 있습니다.

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

## ▶ obsidian-documents

> Obsidian 문서 저장 - "옵시디언에 저장해줘"라고 말하면 Obsidian에 마크다운으로 저장.

**기능:**

| 기능 | 설명 |
|------|------|
| 자연어 발동 | "옵시디언에 저장해줘", "옵시디안에 정리해줘", "obsidian에 넣어줘" 등으로 자동 발동 |
| 슬래시 명령어 | `/obsidian-documents`로도 사용 가능 |
| 스마트 저장 | 프로젝트 `documents/` 폴더 또는 vault root에 저장 |
| 설정 공유 | wrap-up과 동일한 설정 사용 |

**저장 위치:**

| 상황 | 저장 위치 |
|------|----------|
| Git 프로젝트 내에서 실행 | `{프로젝트}/documents/{파일명}.md` |
| 프로젝트 외부에서 실행 | Obsidian vault root |

#### 설치

```bash
/plugin install obsidian-documents@waymakerlabs-claude-plugins
```

#### 사용법

자연어로:
```
이 내용 옵시디언에 저장해줘
방금 논의한 API 설계 정리해서 옵시디언에 넣어줘
```

슬래시 명령어:
```bash
/obsidian-documents [내용 또는 주제]
```

#### 설정

`~/.claude/wrap-up-config.json` 사용 (wrap-up과 공유):

```json
{
  "obsidianVault": "/path/to/obsidian/vault",
  "projectsPath": "001. 프로젝트/진행중"
}
```

---

## ▶ verify-skills

> 자가 유지보수형 코드 검증 프레임워크 - 프로젝트별 verify 스킬을 자동 생성하고 실행.

[codefactory-co/kimoring-ai-skills](https://github.com/codefactory-co/kimoring-ai-skills) 기반.

**스킬:**

| 스킬 | 설명 |
|------|------|
| `/manage-skills` | 세션 변경사항 분석 → verify 스킬 자동 생성/업데이트 |
| `/verify-implementation` | 등록된 모든 verify 스킬 순차 실행 → 통합 검증 보고서 |

**동작 방식:**

```
1. 코드 작업
2. /manage-skills 실행
   → git diff 분석 → verify 스킬 생성 제안
   → 승인 시 .claude/skills/verify-*/SKILL.md 자동 생성
3. /verify-implementation 실행
   → 모든 verify 스킬 실행 → 통합 보고서 → 자동 수정 제안
4. PR 생성
```

#### 설치

```bash
/plugin install verify-skills@waymakerlabs-claude-plugins
```

#### 사용법

```bash
/manage-skills                    # 변경사항 분석, verify 스킬 생성/업데이트
/verify-implementation            # 모든 verify 스킬 실행
/verify-implementation api        # 특정 verify 스킬만 실행
```

---

## ▶ plan-and-build

> 구조화된 개발 워크플로우 - Research → Plan → Annotation Cycle → Implementation.

Boris Tane의 "How I Use Claude Code" 블로그에서 영감을 받았습니다. AI에게 바로 코딩을 시키지 않고, **리서치, 계획, 구현**을 분리하여 의사결정은 사람이, 실행은 AI가 합니다.

**워크플로우:**

```
/plan-and-build {작업 설명}
    │
    ├─ Research: 코드베이스 심층 분석 → research.md
    ├─ Plan: 코드 스니펫 포함 구현 계획 → plan.md
    ├─ Annotation Cycle: plan.md에 인라인 주석 → AI가 반영
    │   └─ 만족할 때까지 반복
    ├─ Todo: plan.md에 체크리스트 추가
    ├─ Implementation: 계획대로 기계적 실행
    └─ 완료 보고
```

**핵심 원칙:** "구현 시작"이라고 할 때까지 코드를 건드리지 않습니다. 모든 문서는 `docs/plan-and-build/`에 보존되어 나중에 참고할 수 있습니다.

#### 설치

```bash
/plugin install plan-and-build@waymakerlabs-claude-plugins
```

#### 사용법

```bash
/plan-and-build 사용자 인증 시스템 추가
/plan-and-build 모놀리식 UserService를 도메인별로 분리
```

---

## 문제 해결

### Usage가 N/A로 표시됨

API 사용량 조회는 Claude Pro/Max 구독 + OAuth 인증이 필요합니다.

### 색상이 이상하게 보임

터미널이 True Color (24-bit)를 지원해야 합니다. iTerm2, Warp, Alacritty 등 모던 터미널을 권장합니다.

## 라이선스

MIT
