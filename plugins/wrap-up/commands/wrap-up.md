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

현재 세션의 작업 내용을 Obsidian에 문서화하고, Git 프로젝트의 경우 커밋합니다.

## 실행 흐름

### Step 1: 설정 확인

설정 파일 경로: `~/.claude/wrap-up-config.json`

```json
{
  "obsidianVault": "/path/to/obsidian/vault",
  "projectsPath": "001. 프로젝트/진행중",
  "areasPath": "002. 관리 영역"
}
```

**설정 파일이 없거나 `--reconfigure` 인자가 있는 경우:**

AskUserQuestion으로 물어봅니다:

```
Obsidian vault 경로를 입력해주세요.
예: /Users/username/Documents/Obsidian Vault
```

입력받은 경로를 `~/.claude/wrap-up-config.json`에 저장합니다.

### Step 2: 작업 유형 확인 및 폴더 찾기

1. 현재 작업 디렉토리에서 git root 찾기 시도:
```bash
git rev-parse --show-toplevel 2>/dev/null
```

2. **결과에 따라 분기:**

#### Case A: Git 프로젝트인 경우 (git root 있음)

- 프로젝트 이름 추출 (git root의 폴더명)
- `{obsidianVault}/{projectsPath}/`에서 해당 프로젝트 폴더 찾기
- 프로젝트 폴더명은 대소문자 무시, 하이픈/언더스코어/공백 무시하고 매칭
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

#### Case B: Git 프로젝트가 아닌 경우 (git root 없음)

- 현재 폴더명 추출 (cwd의 basename)
- `{obsidianVault}/{areasPath}/`에서 해당 폴더 찾기
- 폴더명은 대소문자 무시, 하이픈/언더스코어/공백 무시하고 매칭

**폴더가 없는 경우:**

자동으로 `{obsidianVault}/{areasPath}/{폴더명}/` 생성

**폴더 내 daily-logs 또는 handoffs 폴더가 없는 경우:**

자동으로 `daily-logs/` 및 `handoffs/` 폴더 생성

### Step 3: 현재 세션 작업 내용 파악

현재 대화에서 수행한 작업을 분석합니다. 다음 세션이 탐색 없이 바로 작업을 시작할 수 있도록 충분한 맥락을 추출합니다.

**관련 파일 자동 수집 (Git 프로젝트인 경우):**

```bash
# 이번 세션에서 변경된 파일 (커밋 전 + 스테이징)
git diff --name-only
git diff --cached --name-only

# 최근 커밋에서 변경된 파일 (이번 세션 커밋 포함)
git log --oneline --name-only -5
```

수집된 파일을 3단계로 분류:

| 분류 | 기준 |
|------|------|
| **편집 대상** | git diff에 나타난 파일 (실제 수정됨) |
| **참조 필수** | 대화에서 Read했지만 수정하지 않은 파일 |
| **설정 & 의존성** | config, package.json, .env.example 등 |

**반드시 추출 (다음 세션의 삽질 방지):**
- 확정된 결정사항과 그 이유 (예: "JWT 대신 세션 방식 선택 — 보안 요구사항")
- 사용자가 언급한 선호/제약조건 (예: "컴포넌트는 PascalCase", "한국어 에러 메시지")
- 시도했지만 실패한 접근과 실패 이유 (예: "Redis 시도 → Docker 의존성 문제로 포기")

> 💡 **핵심 원칙**: 다음 세션의 "파일 고고학"(file archaeology)을 방지하는 것이 목표. 이전 세션에서 이미 파악한 정보를 프론트로딩하여, 다음 세션이 즉시 구현을 시작할 수 있게 합니다.

### Step 4: Daily Log 생성/업데이트

파일 경로: `{대상폴더}/daily-logs/YYYY-MM-DD.md`

**4-0. 이전 Daily Log 연속성 체크:**

오늘 날짜의 daily log가 아직 없는 경우, 가장 최근 daily log를 찾아 읽습니다:

1. `daily-logs/` 폴더에서 가장 최근 날짜 파일 찾기
2. "다음 작업" 섹션의 체크리스트 항목 확인
3. 이번 세션에서 완료된 항목은 `- [x]`로 변경
4. 미완료 항목은 오늘 daily log의 "다음 작업"으로 이월
5. 오늘 daily log 상단 "프로젝트 현황" 테이블에 이전 계획 대비 진행 상태 반영

> 💡 이전 daily log가 없거나, 오늘 daily log가 이미 존재하면 이 단계를 건너뜁니다.

#### Git 프로젝트용 Daily Log 템플릿

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

#### 관리 영역용 Daily Log 템플릿 (Git 아닌 경우)

**파일이 없으면 새로 생성:**

```markdown
# 업무일지 - YYYY-MM-DD

## 오늘 작업 내용

### 1. {작업 제목}
- 상세 내용

---

## 메모 및 참고사항

(해당 사항 있으면 작성)

---

## 다음 작업

- [ ] 작업 1
- [ ] 작업 2
```

**파일이 있으면 업데이트:**
- "오늘 작업 내용" 섹션에 새 작업 추가
- "다음 작업" 섹션 업데이트
- (Git 프로젝트인 경우) "커밋 로그" 섹션 업데이트

### Step 5: Handoff 문서 생성

**5-0. 이전 핸드오프 연속성 체크:**

handoffs 폴더에 기존 `HANDOFF-*.md`가 있으면 **삭제 전에 먼저 읽습니다:**

1. 이전 핸드오프의 "다음 단계" 항목을 확인
2. 이번 세션에서 완료된 항목은 "현재 상태" 테이블에 ✅로 반영
3. 미완료 항목은 새 핸드오프의 "다음 단계"로 자동 이월
4. 이전 핸드오프의 "결정사항 & 제약조건" 중 여전히 유효한 내용은 유지

> 💡 이전 핸드오프가 없으면 이 단계를 건너뜁니다.

**5-1. 기존 handoff 삭제 후 새로 생성:**

1. handoffs 폴더에서 기존 `HANDOFF-*.md` 파일 삭제
2. 새 파일 생성

- **Git 프로젝트**: `{프로젝트폴더}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md`
- **비 Git**: `{영역폴더}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md`

> 💡 항상 하나의 handoff 파일만 유지합니다. 타임스탬프로 마지막 작업 시점을 알 수 있습니다.

#### Git 프로젝트용 핸드오프 템플릿

```markdown
# HANDOFF - YYYY-MM-DD HH:MM

## 현재 상태

| 항목 | 상태 | 설명 |
|------|------|------|
| {기능1} | ✅ 완료 | 설명 |
| {기능2} | 🔄 진행중 | 설명 |
| {기능3} | ⬜ 예정 | 설명 |

## 작업 맥락

{현재 구현 상태를 서술형으로 작성. 단순 나열이 아닌, 이어서 작업하기 위해 필요한 맥락을 제공.}

{예시: "인증 시스템의 로그인/로그아웃은 완료. 토큰 갱신 로직이 미완성으로, `src/auth/refresh.ts`의 `handleRefresh()` 함수에서 에러 핸들링 추가 필요."}

## 결정사항 & 제약조건

### 확정된 결정
- {결정 내용} — {이유}

### 사용자 선호/제약
- {선호 또는 제약 내용}

### 시도했지만 실패한 접근 (Dead Ends)
- {시도한 내용} → {실패 이유}

(해당 사항 없으면 "없음"으로 기록)

## 다음 단계

1. {다음 할 일 1}
2. {다음 할 일 2}

## 주의사항

- {주의할 점}
- {기억해야 할 컨텍스트}

## 관련 파일

### 편집 대상 (수정이 필요한 파일)
- `path/to/file` - 설명

### 참조 필수 (맥락 이해에 필요)
- `path/to/file` - 설명

### 설정 & 의존성
- `path/to/file` - 설명

> 💡 넉넉하게 포함할 것. 파일 하나를 더 넣는 비용은 낮지만, 빠뜨리면 다음 세션에서 다시 탐색해야 함. 8~15개 목표.

## 다음 세션 시작 프롬프트

\`\`\`
{obsidianVault}/{projectsPath}/{프로젝트폴더}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md를 읽고 이어서 작업해줘.
관련 파일 섹션에 나열된 파일들을 먼저 읽은 후 작업을 시작해. 새로운 파일 탐색은 최소화하고, 핸드오프 문서의 맥락을 기반으로 진행해.
\`\`\`
```

#### 비 Git 작업용 핸드오프 템플릿 (간소화)

```markdown
# HANDOFF - YYYY-MM-DD HH:MM

## 작업 맥락

{이번 세션에서 수행한 작업과 현재 상태를 서술형으로 작성.}

## 결정사항

- {결정 내용} — {이유}

(해당 사항 없으면 "없음"으로 기록)

## 다음 단계

1. {다음 할 일 1}
2. {다음 할 일 2}

## 참고 자료

- {참조한 문서, URL, 파일 경로 등}

## 다음 세션 시작 프롬프트

\`\`\`
{obsidianVault}/{areasPath}/{영역폴더}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md를 읽고 이어서 작업해줘.
\`\`\`
```

### Step 6: 프로젝트 버전 업데이트 (Git 프로젝트만)

> ⚠️ **Git 프로젝트가 아닌 경우 이 단계를 건너뜁니다.**

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

#### 6-3. Node.js 프로젝트

**조건**: `package.json`이 있는 경우 (단, plugin.json이 없는 경우에만)

`package.json`의 `version` 필드를 업데이트합니다:
- 형식: `X.Y.Z` (SemVer)
- 패치 버전(Z)만 1 증가

**주의사항**:
- Claude 플러그인 프로젝트는 6-1로 처리 (plugin.json 우선)
- 모노레포의 경우 루트 package.json만 업데이트

### Step 7: 관련 문서 업데이트 (Git 프로젝트만)

> ⚠️ **Git 프로젝트가 아닌 경우 이 단계를 건너뜁니다.**

**버전이 명시된 모든 문서를 찾아 업데이트합니다:**

1. **코드 저장소 문서** (README.md, README.ko.md 등)
   - 버전 번호가 명시된 곳 업데이트
   - 변경된 기능 설명 업데이트

2. **Obsidian 프로젝트 문서**
   - 프로젝트 개요: 버전, 기능 테이블, 타임라인 업데이트
   - 사용법: 변경된 기능 설명 업데이트
   - 마지막 업데이트 날짜 갱신

### Step 8: Git Commit & Push (Git 프로젝트만)

> ⚠️ **Git 프로젝트가 아닌 경우 이 단계를 건너뜁니다.**

**8-0. 안전 체크 (git add 전에 반드시 실행):**

```bash
git status --short
```

아래 패턴에 해당하는 파일이 스테이징 대상에 있으면 **경고 후 제외**합니다:

| 패턴 | 위험 |
|------|------|
| `.env`, `.env.*` (`.env.example` 제외) | API 키, 시크릿 노출 |
| `credentials*.json`, `*secret*`, `*token*` | 인증 정보 노출 |
| `*.pem`, `*.key`, `*.p12` | 인증서/키 파일 노출 |
| 10MB 이상 파일 | 대용량 바이너리가 repo에 포함 |

```bash
# 위험 파일이 감지된 경우
git add --all -- ':!.env' ':!.env.local' ':!credentials.json'
```

> 💡 .gitignore에 이미 포함된 파일은 git status에 나타나지 않으므로 별도 체크 불필요. 여기서는 .gitignore에 누락된 위험 파일을 잡는 것이 목적.

**8-1. 스테이징 및 커밋:**

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

#### Git 프로젝트인 경우:

```
✅ Wrap-up 완료!

📝 Daily log: {프로젝트}/daily-logs/YYYY-MM-DD.md
📋 Handoff: {프로젝트}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md
📦 Commit: {hash} - {message}

---
🚀 다음 세션 시작 프롬프트:

{obsidianVault}/{projectsPath}/{프로젝트}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md를 읽고 이어서 작업해줘.
관련 파일 섹션에 나열된 파일들을 먼저 읽은 후 작업을 시작해. 새로운 파일 탐색은 최소화하고, 핸드오프 문서의 맥락을 기반으로 진행해.
```

#### Git 프로젝트가 아닌 경우:

```
✅ Wrap-up 완료!

📝 Daily log: {영역폴더}/daily-logs/YYYY-MM-DD.md
📋 Handoff: {영역폴더}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md

---
🚀 다음 세션 시작 프롬프트:

{obsidianVault}/{areasPath}/{영역폴더}/handoffs/HANDOFF-YYYY-MM-DD-HHMM.md를 읽고 이어서 작업해줘.
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

새 프로젝트 폴더 생성 시 사용 (Git 프로젝트만):

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
2. **폴더 매칭**은 유연하게 처리합니다 (대소문자, 하이픈/언더스코어/공백 무시).
3. **Daily log는 누적**됩니다. 같은 날 여러 번 실행하면 기존 내용에 추가합니다.
4. **Git 프로젝트**: Handoff 생성, 버전 업데이트, Git commit/push 수행
5. **Git 아닌 경우**: Daily log + 간소화 Handoff 생성 (관리 영역에 저장)
6. **Git 작업**은 코드 저장소에서만 수행합니다 (Obsidian vault가 아님).
7. **프로젝트 버전**은 wrap-up 실행 시 패치 버전이 1 증가합니다:
   - Claude 플러그인: plugin.json + marketplace.json 동기화
   - Flutter 앱: pubspec.yaml의 version 필드 (패치 + 빌드 번호 증가)
   - Node.js: package.json의 version 필드 (패치 버전 증가)
8. **문서 업데이트**는 버전이 명시된 곳을 기준으로 찾아서 업데이트합니다.
