---
name: obsidian-documents
description: 사용자가 "옵시디언에 저장해줘", "옵시디안에 정리해줘", "obsidian에 넣어줘" 등 Obsidian 관련 요청을 할 때 자동으로 사용하는 스킬. Obsidian vault에 마크다운 문서로 저장합니다.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
argument-hint: "[내용 또는 주제]"
---

# Obsidian Documents: Obsidian 문서화 스킬

사용자가 요청한 내용을 Obsidian vault에 마크다운 문서로 정리해서 저장합니다.

## 발동 조건

사용자 프롬프트에 다음과 같은 표현이 있을 때 이 스킬을 사용합니다:
- "옵시디언에 저장해줘"
- "옵시디안에 정리해줘"
- "obsidian에 넣어줘"
- "옵시디언에 기록해줘"
- "옵시디언으로 만들어줘"

## 실행 흐름

### Step 1: 설정 확인

설정 파일 경로: `~/.claude/wrap-up-config.json`

```json
{
  "obsidianVault": "/path/to/obsidian/vault",
  "projectsPath": "001. 프로젝트/진행중"
}
```

**설정 파일이 없는 경우:**

AskUserQuestion으로 Obsidian vault 경로를 물어봅니다:

```
Obsidian vault 경로를 입력해주세요.
예: /Users/username/Documents/Obsidian Vault
```

입력받은 경로를 `~/.claude/wrap-up-config.json`에 저장합니다. 이 설정은 wrap-up 스킬과 공유됩니다.

### Step 2: 프로젝트 컨텍스트 확인

현재 작업 디렉토리가 git 프로젝트인지 확인합니다:

```bash
git rev-parse --show-toplevel 2>/dev/null
```

**프로젝트 컨텍스트가 있는 경우:**
1. 프로젝트 이름 추출 (git root의 폴더명)
2. Obsidian vault에서 해당 프로젝트 폴더 찾기
   - 경로: `{obsidianVault}/{projectsPath}/`
   - 프로젝트 폴더명은 대소문자 무시, 하이픈/언더스코어 무시하고 매칭
3. 저장 위치: `{프로젝트폴더}/documents/`

**프로젝트 컨텍스트가 없는 경우:**
- 저장 위치: `{obsidianVault}/` (vault root)

### Step 3: 문서 내용 정리

사용자가 요청한 내용을 마크다운 문서로 정리합니다:

1. 문서화 대상 파악
   - 대화에서 논의된 특정 주제
   - 사용자가 요약해달라고 한 문서
   - 연구/조사 결과
   - 기타 요청된 내용

2. 적절한 구조로 정리
   - 제목
   - 요약
   - 상세 내용
   - 관련 링크/참고자료 (있는 경우)

### Step 4: 파일명 생성

내용을 분석하여 적절한 파일명을 자동 생성합니다:

- 핵심 키워드나 주제를 추출
- 한글/영문 모두 가능
- 공백은 하이픈으로 대체
- 예: `React-상태관리-정리.md`, `API-설계-가이드.md`

### Step 5: 문서 저장

1. 저장 경로 확인:
   - 프로젝트 있음: `{obsidianVault}/{projectsPath}/{프로젝트}/documents/{파일명}.md`
   - 프로젝트 없음: `{obsidianVault}/{파일명}.md`

2. 폴더가 없으면 생성

3. 파일 저장

### Step 6: 완료 메시지

```
문서가 저장되었습니다.

📄 파일: {저장 경로}
📁 위치: {프로젝트명}/documents/ 또는 vault root
```

## 문서 템플릿

저장되는 문서의 기본 구조:

```markdown
# {제목}

> 작성일: YYYY-MM-DD

## 요약

{핵심 내용 1-2문장}

## 상세 내용

{정리된 내용}

## 참고

- {관련 링크나 참고자료}
```

## 중요 사항

1. **설정 파일 공유**: wrap-up 스킬과 동일한 `~/.claude/wrap-up-config.json`을 사용합니다.
2. **프로젝트 매칭**: 대소문자, 하이픈/언더스코어/공백을 무시하고 유연하게 매칭합니다.
3. **자동 폴더 생성**: documents 폴더가 없으면 자동으로 생성합니다.
4. **파일명 충돌**: 같은 이름의 파일이 있으면 `-2`, `-3` 등 숫자를 붙입니다.
