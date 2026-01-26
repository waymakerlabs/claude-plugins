---
name: wrap-up
description: Session wrap-up - Obsidian documentation (daily log, handoff) + Git commit/push
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
argument-hint: "[--reconfigure]"
---

# Wrap-up: 작업 마무리 스킬

현재 세션의 작업 내용을 Obsidian에 문서화하고 Git에 커밋합니다.

## 실행 흐름

### Step 1: 설정 확인

설정 파일 경로: `~/.claude/wrap-up-config.json`

```json
{
  "obsidianVault": "/path/to/obsidian/vault",
  "projectsPath": "001. 프로젝트/진행중"
}
```

**설정 파일이 없거나 `--reconfigure` 인자가 있는 경우:**

AskUserQuestion으로 물어봅니다:

```
Obsidian vault 경로를 입력해주세요.
예: /Users/username/Documents/Obsidian Vault
```

입력받은 경로를 `~/.claude/wrap-up-config.json`에 저장합니다.

### Step 2: 현재 프로젝트 확인

1. 현재 작업 디렉토리에서 git root 찾기:
```bash
git rev-parse --show-toplevel
```

2. 프로젝트 이름 추출 (git root의 폴더명)

3. Obsidian vault에서 해당 프로젝트 폴더 찾기:
   - 경로: `{obsidianVault}/{projectsPath}/`
   - 프로젝트 폴더명은 대소문자 무시, 하이픈/언더스코어 무시하고 매칭
   - 예: `logos-app` → `Logos App` 매칭

**프로젝트 폴더가 없는 경우:**

AskUserQuestion으로 물어봅니다:

```
Obsidian에 프로젝트 폴더가 없습니다. 생성할까요?

[생성하기] - 기본 구조로 프로젝트 폴더 생성
[직접 지정] - 기존 폴더 경로 직접 입력
[취소] - 작업 취소
```

**생성하기 선택 시 기본 구조:**

```
{프로젝트명}/
├── 프로젝트 소개.md    ← 템플릿으로 생성
├── daily-logs/
├── documents/
└── handoffs/
```

### Step 3: 현재 세션 작업 내용 파악

현재 대화에서 수행한 작업을 분석합니다:
- 어떤 파일들을 수정/생성했는지
- 어떤 기능을 구현했는지
- 발생한 문제와 해결 방법
- 남은 작업

### Step 4: Daily Log 생성/업데이트

파일 경로: `{프로젝트폴더}/daily-logs/YYYY-MM-DD.md`

**파일이 없으면 새로 생성:**

```markdown
# 작업일지 - YYYY-MM-DD

## 프로젝트 현황

| 항목 | 상태 | 비고 |
|------|------|------|
| {작업1} | ✅/🔄/⬜ | 설명 |

---

## 오늘 작업 내용

### 1. {작업 제목}
- 상세 내용
- 관련 파일: `path/to/file.py`

---

## 실수 및 교훈

(해당 사항 있으면 작성)

---

## 커밋 로그

| 커밋 | 메시지 |
|------|--------|
| `{hash}` | {message} |

---

## 다음 작업

### 필수
- [ ] 작업 1
- [ ] 작업 2

### 선택적
- [ ] 작업 3
```

**파일이 있으면 업데이트:**
- "오늘 작업 내용" 섹션에 새 작업 추가
- "커밋 로그" 섹션 업데이트
- "다음 작업" 섹션 업데이트

### Step 5: Handoff 문서 생성 (단일 파일 유지)

**기존 handoff 삭제 후 새로 생성:**

1. handoffs 폴더에서 기존 `HANDOFF-*.md` 파일 삭제
2. 새 파일 생성: `{프로젝트폴더}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md`

> 💡 항상 하나의 handoff 파일만 유지합니다. 타임스탬프로 마지막 작업 시점을 알 수 있습니다.

```markdown
# HANDOFF - YYYY-MM-DD HH:MM

## 현재 상태

| 항목 | 상태 | 설명 |
|------|------|------|
| {기능1} | ✅ 완료 | 설명 |
| {기능2} | 🔄 진행중 | 설명 |
| {기능3} | ⬜ 예정 | 설명 |

## 이번 세션 작업 요약

- {작업 내용 1}
- {작업 내용 2}

## 다음 단계

1. {다음 할 일 1}
2. {다음 할 일 2}

## 주의사항

- {주의할 점}
- {기억해야 할 컨텍스트}

## 관련 파일

- `path/to/modified/file1.py` - 설명
- `path/to/modified/file2.ts` - 설명

## 다음 세션 시작 프롬프트

\`\`\`
{obsidianVault}/{projectsPath}/{프로젝트폴더}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md를 읽고 이어서 작업해줘.
\`\`\`
```

### Step 6: 프로젝트 버전 업데이트

프로젝트 타입에 따라 패치 버전을 1 올립니다:

#### 6-1. Claude 플러그인 프로젝트

**조건**: `plugin.json` 또는 `marketplace.json`이 있는 경우

1. `plugin.json`의 패치 버전을 1 올립니다 (예: 1.0.2 → 1.0.3)
2. `marketplace.json`의 해당 플러그인 버전도 동기화합니다

#### 6-2. Flutter 앱 프로젝트

**조건**: `pubspec.yaml`이 있는 경우

`pubspec.yaml`의 `version` 필드를 업데이트합니다:
- 형식: `X.Y.Z+BUILD` (예: 0.6.1+119)
- 패치 버전(Z)과 빌드 번호(BUILD) 둘 다 1씩 증가

```yaml
# 변경 전
version: 0.6.1+119

# 변경 후
version: 0.6.2+120
```

**주의사항**:
- 프로젝트 루트 또는 `apps/` 하위의 Flutter 앱을 찾습니다
- 여러 앱이 있으면 AskUserQuestion으로 어떤 앱의 버전을 올릴지 물어봅니다
- 메인 앱만 버전 업데이트 (예: `apps/logos_one/pubspec.yaml`)

> 💡 wrap-up 실행 시 항상 패치 버전이 1 증가합니다.

### Step 7: 관련 문서 업데이트

**버전이 명시된 모든 문서를 찾아 업데이트합니다:**

1. **코드 저장소 문서** (README.md, README.ko.md 등)
   - 버전 번호가 명시된 곳 업데이트
   - 변경된 기능 설명 업데이트

2. **Obsidian 프로젝트 문서**
   - 프로젝트 개요: 버전, 기능 테이블, 타임라인 업데이트
   - 사용법: 변경된 기능 설명 업데이트
   - 마지막 업데이트 날짜 갱신

> 💡 "버전이 명시된 곳"을 기준으로 검색하면 업데이트가 필요한 문서를 쉽게 찾을 수 있습니다.

### Step 8: Git Commit & Push

1. 코드 저장소에서:
```bash
git add .
git status
```

2. 변경사항이 있으면 커밋:
```bash
git commit -m "feat/fix/docs: {변경 내용 요약}

- {상세 변경 1}
- {상세 변경 2}

Co-Authored-By: Claude <noreply@anthropic.com>"
```

3. Push:
```bash
git push
```

### Step 9: 완료 메시지 출력

```
✅ Wrap-up 완료!

📝 Daily log: {프로젝트}/daily-logs/YYYY-MM-DD.md
📋 Handoff: {프로젝트}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md
📦 Commit: {hash} - {message}

---
🚀 다음 세션 시작 프롬프트:

{obsidianVault}/{projectsPath}/{프로젝트}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md를 읽고 이어서 작업해줘.
```

## 상태 아이콘

| 아이콘 | 의미 |
|--------|------|
| ✅ | 완료 |
| 🔄 | 진행중 |
| ⬜ | 시작 전 |
| ❌ | 차단됨/문제 |

## 인자 처리

| 인자 | 동작 |
|------|------|
| (없음) | 일반 실행 |
| `--reconfigure` | Obsidian vault 경로 재설정 |

## 프로젝트 소개.md 템플릿

새 프로젝트 폴더 생성 시 사용:

```markdown
# {프로젝트명}

## 프로젝트 개요

{한 줄 설명}

## 📍 프로젝트 위치

\`\`\`
{git root 경로}
\`\`\`

## 🎯 현재 상태

| 영역 | 상태 | 설명 |
|------|------|------|
| 개발 | 🔄 진행중 | - |

## 🏗️ 프로젝트 구조

\`\`\`
(프로젝트 구조 작성 필요)
\`\`\`

## 🛠️ 기술 스택

| 분류 | 기술 |
|------|------|
| 언어 | - |
| 프레임워크 | - |

## 📁 Obsidian 문서 구조

\`\`\`
{프로젝트명}/
├── 프로젝트 소개.md    ← 이 파일
├── daily-logs/
├── documents/
└── handoffs/
\`\`\`

## 🔧 주요 명령어

\`\`\`bash
# 빌드
# 테스트
# 실행
\`\`\`

## 🗓️ 개발 타임라인

| 기간 | 주요 작업 |
|------|----------|
| {오늘 날짜} | 프로젝트 시작 |

## 🎯 향후 계획

- [ ]

## ⚠️ 주의사항

-
```

## 중요 사항

1. **Obsidian vault 경로**는 사용자마다 다르므로 반드시 설정 파일에서 읽어옵니다.
2. **프로젝트 폴더 매칭**은 유연하게 처리합니다 (대소문자, 하이픈/언더스코어/공백 무시).
3. **Daily log는 누적**됩니다. 같은 날 여러 번 실행하면 기존 내용에 추가합니다.
4. **Handoff는 단일 파일만 유지**됩니다. 새로 생성 시 기존 파일을 삭제하고, 타임스탬프로 마지막 작업 시점을 표시합니다.
5. **Git 작업**은 코드 저장소에서만 수행합니다 (Obsidian vault가 아님).
6. **프로젝트 버전**은 wrap-up 실행 시 패치 버전이 1 증가합니다:
   - Claude 플러그인: plugin.json + marketplace.json 동기화
   - Flutter 앱: pubspec.yaml의 version 필드 (패치 + 빌드 번호 증가)
7. **문서 업데이트**는 버전이 명시된 곳을 기준으로 찾아서 업데이트합니다.
