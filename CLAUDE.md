# CLAUDE.md

Claude Code 플러그인 마켓플레이스 프로젝트 가이드.

## 프로젝트 구조

```
waymakerlabs-plugins/
├── .claude-plugin/
│   └── marketplace.json       # ⚠️ 마켓플레이스 플러그인 목록 (필수 등록)
├── plugins/
│   ├── minimal-statusline/    # statusline 플러그인
│   └── wrap-up/               # Obsidian 문서화 플러그인
├── README.md
└── CLAUDE.md
```

## ⚠️ 필수 규칙: 새 플러그인 추가 시

**새로운 플러그인을 만들 때 반드시 두 곳에 등록해야 합니다:**

### 1. 플러그인 폴더 생성

```
plugins/{plugin-name}/
├── .claude-plugin/
│   └── plugin.json           # 플러그인 메타데이터
├── commands/
│   └── {skill-name}.md       # 슬래시 명령어 (스킬)
└── README.md
```

### 2. marketplace.json에 등록 (필수!)

`.claude-plugin/marketplace.json`의 `plugins` 배열에 새 플러그인 추가:

```json
{
  "plugins": [
    // ... 기존 플러그인들 ...
    {
      "name": "새-플러그인-이름",
      "version": "1.0.0",
      "description": "플러그인 설명",
      "author": {
        "name": "waymakerlabs",
        "email": "peter@waymakerlabs.com"
      },
      "source": "./plugins/새-플러그인-이름",
      "category": "workflow",
      "keywords": ["keyword1", "keyword2"],
      "homepage": "https://github.com/waymakerlabs/claude-plugins"
    }
  ]
}
```

> **중요**: `marketplace.json`에 등록하지 않으면 `/plugin browse`에서 플러그인이 보이지 않습니다!

## 플러그인 개발 체크리스트

새 플러그인 추가 시 확인:

- [ ] `plugins/{name}/.claude-plugin/plugin.json` 생성
- [ ] `plugins/{name}/commands/{skill}.md` 생성 (스킬이 있는 경우)
- [ ] `plugins/{name}/README.md` 생성
- [ ] **`.claude-plugin/marketplace.json`에 플러그인 등록** ⚠️
- [ ] 루트 `README.md`에 플러그인 문서 추가
- [ ] Git commit & push

## 스킬 (Slash Command) 작성법

`commands/{skill-name}.md` 파일 형식:

```markdown
---
name: skill-name
description: 스킬 설명
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
argument-hint: "[optional-args]"
---

# 스킬 제목

스킬이 수행할 작업에 대한 상세 지침을 마크다운으로 작성합니다.
Claude가 이 지침을 따라 작업을 수행합니다.
```

## 버전 관리

- `plugin.json`과 `marketplace.json`의 버전을 동기화
- 변경 시 두 파일 모두 버전 업데이트

## 주요 명령어

```bash
# 마켓플레이스 업데이트 (변경사항 반영)
/plugin marketplace update waymakerlabs-claude-plugins

# 플러그인 설치
/plugin install {plugin-name}@waymakerlabs-claude-plugins

# 플러그인 목록 확인
/plugin browse
```
