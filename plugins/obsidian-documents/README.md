# Obsidian Documents Plugin

Obsidian에 문서를 저장하는 Claude Code 스킬입니다.

## 개요

"옵시디언에 저장해줘"라고 요청하면 대화 내용을 Obsidian vault에 마크다운 문서로 저장합니다.

## 특징

- **자연어 발동**: "옵시디언에 저장해줘", "옵시디안에 정리해줘", "obsidian에 넣어줘" 등으로 자동 발동
- **수동 실행**: `/obsidian-documents` 명령어로도 실행 가능
- **스마트 저장**: 프로젝트 컨텍스트에 따라 적절한 위치에 저장
- **설정 공유**: wrap-up 스킬과 동일한 설정 파일 사용

## 설치

```bash
/plugin install obsidian-documents@waymakerlabs-claude-plugins
```

## 사용법

### 자연어로 요청

```
이 내용 옵시디언에 저장해줘
```

```
방금 논의한 API 설계 정리해서 옵시디언에 넣어줘
```

### 슬래시 명령어

```
/obsidian-documents [내용 또는 주제]
```

## 저장 위치

| 상황 | 저장 위치 |
|------|----------|
| Git 프로젝트 내에서 실행 | `{프로젝트폴더}/documents/` |
| 프로젝트 외부에서 실행 | Obsidian vault root |

## 설정

`~/.claude/wrap-up-config.json` 파일을 사용합니다:

```json
{
  "obsidianVault": "/path/to/obsidian/vault",
  "projectsPath": "001. 프로젝트/진행중"
}
```

> wrap-up 스킬과 설정을 공유합니다. 한쪽에서 설정하면 양쪽에서 사용 가능합니다.

## 버전

- **1.0.0**: 초기 릴리즈
