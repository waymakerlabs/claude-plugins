# claude-organizer

> Organize CLAUDE.md into a modular, skill-based project structure.

---

## Overview

Transform a monolithic CLAUDE.md into organized, domain-specific skills that follow the **Progressive Disclosure** pattern.

**Before:**
```
CLAUDE.md (500+ lines)
├── Project overview
├── Build commands
├── UI guidelines
├── API documentation
├── Database schema
├── Deployment process
└── ... everything in one file
```

**After:**
```
CLAUDE.md (50 lines) - minimal entry point
.claude/skills/
├── frontend/SKILL.md
├── backend/SKILL.md
├── database/SKILL.md
└── deployment/SKILL.md
```

---

## Install

```bash
/plugin install claude-organizer@waymakerlabs-claude-plugins
```

## Usage

```bash
/claude-organizer
```

---

## What It Does

1. **Analyzes** your project structure and CLAUDE.md
2. **Detects** domains (UI, API, Pipeline, Database, etc.)
3. **Creates** modular skills in `.claude/skills/`
4. **Reorganizes** CLAUDE.md to minimal entry point
5. **Configures** Git to track skills

---

## Re-run Anytime

CLAUDE.md grew again? Just run `/claude-organizer` again:

- Detects new content
- Updates existing skills
- Keeps CLAUDE.md clean

---

## Benefits

| Aspect | Before | After |
|--------|--------|-------|
| Context Usage | All info loaded always | Only relevant skill loaded |
| Maintainability | One huge file | Modular, organized |
| Team Sync | Manual copy | Git-tracked skills |
| Discoverability | Scroll through everything | `/skill-name` to access |

---

## 한국어 설명

### 개요

CLAUDE.md를 스킬 기반 구조로 정리하는 플러그인입니다.

### 왜 필요한가?

기존 방식에서는 CLAUDE.md에 모든 프로젝트 정보를 담습니다:
- 프로젝트 개요, 빌드 명령어, UI 가이드, API 문서, DB 스키마, 배포 절차...
- 파일이 커질수록 **모든 정보가 항상 컨텍스트에 로드** → 토큰 낭비

스킬 기반 접근법:
- 영역별로 스킬 분리 (`.claude/skills/`)
- **필요한 스킬만 필요할 때 로드** → 컨텍스트 효율화
- **Progressive Disclosure**: 핵심만 SKILL.md에, 상세는 references/에

### 사용법

```bash
# 처음 실행 - 프로젝트 분석 후 스킬 생성
/claude-organizer

# 이후 CLAUDE.md가 다시 커지면 재실행
/claude-organizer
```

### 자동 감지 영역

| 감지 패턴 | 영역 | 스킬 이름 |
|-----------|------|-----------|
| `src/components/`, `*.tsx` | Frontend | `frontend`, `ui-*` |
| `src/api/`, `routes/` | Backend | `backend`, `api-*` |
| `pipeline/`, `scripts/` | Data Pipeline | `pipeline-*` |
| `prisma/`, `migrations/` | Database | `database` |
| `flutter/`, `lib/` | Mobile | `flutter-app` |
| `deploy/`, `docker/` | Deployment | `deployment` |

### 결과물

```
프로젝트/
├── CLAUDE.md                 # 간소화 (스킬 목록 + 핵심 규칙만)
├── .claude/
│   └── skills/
│       ├── frontend/
│       │   ├── SKILL.md      # 핵심 정보 (100줄 이하)
│       │   └── references/   # 상세 문서
│       ├── backend/
│       └── deployment/
└── .gitignore                # .claude/skills/ Git 포함 설정
```

### Git 동기화

`.claude/skills/`는 Git에 커밋되므로:
- 다른 컴퓨터에서 clone 시 스킬 자동 사용
- 팀 전체가 동일한 워크플로우 공유

---

## Related

- [Skill-based Project Management Guide](https://github.com/waymakerlabs/claude-plugins)
