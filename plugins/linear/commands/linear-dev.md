---
name: linear-dev
description: Dev cycle automation - ready, omc-run, review, done
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
  - mcp__plugin_linear_linear__list_issues
  - mcp__plugin_linear_linear__get_issue
  - mcp__plugin_linear_linear__update_issue
  - mcp__plugin_linear_linear__list_issue_statuses
  - mcp__plugin_linear_linear__list_teams
  - mcp__plugin_linear_linear__get_team
  - mcp__plugin_linear_linear__list_users
  - mcp__plugin_linear_linear__get_user
  - mcp__plugin_linear_linear__create_comment
argument-hint: "<ready|omc-run|review|done|next> [이슈ID]"
---

# Linear Dev: 개발 사이클 자동화

Linear 이슈 기반 개발 워크플로우를 자동화하는 스킬입니다.

**핵심 원칙: 1 이슈 = 1 브랜치 = 1 PR**

---

## 워크플로우 개요

```
ready → (omc-run) → review → done
  │         │         │        │
  │         │         │        └── 머지, 브랜치 삭제
  │         │         └── PR 생성
  │         └── OMC 팀 병렬 개발 (선택)
  └── 브랜치 생성, 작업 준비
```

---

## 사전 조건 체크

**모든 액션 실행 전에 반드시 확인:**

```bash
# Git 사용 가능한지 확인
git rev-parse --show-toplevel 2>/dev/null

# gh CLI 사용 가능한지 확인
gh auth status 2>/dev/null
```

- git이 없으면: "Git 저장소에서 실행해주세요" 안내 후 중단
- gh가 없거나 미인증이면: "gh auth login을 먼저 실행해주세요" 안내 후 중단

---

## 액션 라우팅

| 인자 | 액션 | 설명 |
|------|------|------|
| `ready {이슈ID}` | Ready | 브랜치 생성, 작업 준비 |
| `omc-run` | OMC Run | OMC 팀 병렬 개발 (선택) |
| `review` | Review | PR 생성 |
| `done` | Done | 머지, 브랜치 삭제, 정리 |
| `next` | Next | 다음 할 일 목록 |
| (없음) | 대화형 | AskUserQuestion으로 액션 선택 |

인자가 없으면 AskUserQuestion으로 물어봅니다:

```
어떤 작업을 할까요?

[ready] - 브랜치 생성, 작업 준비
[omc-run] - OMC 팀 병렬 개발
[review] - PR 생성
[done] - 머지 & 정리
[next] - 다음 할 일 확인
```

---

## 액션 1: Ready — 작업 준비

### Step 1. 이슈 조회

```
get_issue(id: "{이슈ID}", includeRelations: true)
```

이슈 정보를 확인하고 요약합니다:

```
## {이슈ID}: {제목}

| 항목 | 값 |
|------|-----|
| 상태 | {state} |
| 우선순위 | {priority} |
| 담당자 | {assignee} |
| 프로젝트 | {project} |

### 체크리스트
- [ ] {항목 1}
- [ ] {항목 2}
...
```

### Step 2. 안전 체크

```bash
# 현재 브랜치 상태 확인
git status --short
git branch --show-current
```

- 커밋되지 않은 변경이 있으면 경고:
  "커밋되지 않은 변경사항이 있습니다. 먼저 커밋하거나 stash해주세요."
- 이미 해당 이슈의 브랜치가 있으면:
  "이미 브랜치가 존재합니다. 체크아웃할까요?" (AskUserQuestion)

### Step 3. 브랜치 생성

이슈의 `branchName` 필드를 사용하여 브랜치를 생성합니다.

```bash
# main 최신화
git checkout main
git pull origin main

# 브랜치 생성 (Linear이 제공하는 브랜치명 사용)
git checkout -b {branchName}
```

**브랜치명 규칙:**
- Linear의 `get_issue` 응답에 `branchName`이 포함됨
- 형식: `{팀키소문자}-{이슈번호}-{제목-kebab-case}`
- 예: `log-101-user-settings-feature`

### Step 4. 상태 업데이트

```
update_issue(id: "{이슈ID}", state: "In Progress")
```

### Step 5. 완료 메시지

```
## 작업 준비 완료

| 항목 | 값 |
|------|-----|
| 이슈 | {이슈ID}: {제목} |
| 브랜치 | {branchName} |
| 상태 | In Progress |

### 다음 단계
- 직접 개발: 코딩을 시작하세요
- OMC 병렬 개발: `/linear-dev omc-run`

작업이 끝나면 `/linear-dev review`로 PR을 생성합니다.
```

---

## 액션 2: OMC Run — 팀 병렬 개발

OMC(oh-my-claudecode)의 팀 기능을 활용해 병렬로 개발을 진행합니다.

### Step 1. 이슈 분석

현재 브랜치에서 이슈 ID를 추출하고 이슈 내용을 확인합니다:

```bash
git branch --show-current
```

브랜치명에서 이슈 ID 추출: `{팀키}-{번호}-...` → `{팀키대문자}-{번호}`

```
get_issue(id: "{이슈ID}")
```

### Step 2. 작업 분류

이슈의 체크리스트를 분석하여 작업을 분류합니다:

```
## 작업 분석

### Frontend (Gemini CLI)
- [ ] {UI 관련 작업}
- [ ] {컴포넌트 작업}
- [ ] {스타일 작업}

### Backend (Codex CLI)
- [ ] {API 작업}
- [ ] {데이터 모델}
- [ ] {비즈니스 로직}

### 기타 (Codex CLI)
- [ ] {테스트}
- [ ] {설정/환경}
```

### Step 3. OMC 팀 실행

작업을 병렬로 실행합니다:

**Frontend 작업이 있는 경우:**
```
Gemini CLI 팀원에게 frontend 작업 할당:
- UI 컴포넌트 구현
- 스타일링
- 사용자 인터랙션
```

**Backend/기타 작업이 있는 경우:**
```
Codex CLI 팀원에게 backend 작업 할당:
- API 구현
- 데이터 모델
- 비즈니스 로직
- 테스트 작성
```

### Step 4. 실행 프롬프트

OMC 팀을 스폰하여 병렬 작업을 지시합니다:

```
Skill: oh-my-claudecode:team

팀 구성:
- Frontend 작업: Gemini CLI (gemini)
- Backend 작업: Codex CLI (codex)

작업 내용:
{분류된 작업 목록}

각 팀원은 담당 영역의 체크리스트 항목을 완료하세요.
- Gemini: {frontend 작업들}
- Codex: {backend 작업들}

완료 후 변경사항을 보고하세요.
```

### Step 5. 진행상황 업데이트

완료된 작업을 체크리스트에 반영:

```
update_issue(id: "{이슈ID}", description: "{업데이트된 체크리스트}")
```

### Step 6. 완료 메시지

```
## OMC Run 완료

| 항목 | 상태 |
|------|------|
| Frontend (Gemini) | {완료/진행중} |
| Backend (Codex) | {완료/진행중} |

### 완료된 항목
- [x] {완료된 항목들}

### 남은 항목
- [ ] {미완료 항목들}

계속 진행하거나 `/linear-dev review`로 PR을 생성하세요.
```

---

## 액션 3: Review — PR 생성

### Step 1. 현재 브랜치에서 이슈 감지

```bash
git branch --show-current
```

브랜치명에서 이슈 ID를 추출합니다:
- 패턴: `{팀키}-{번호}-...` (예: `log-101-...` → `LOG-101`)
- 팀 키를 대문자로 변환하여 이슈 ID 구성

이슈 ID를 찾을 수 없으면 AskUserQuestion으로 물어봅니다.

### Step 2. 이슈 정보 조회

```
get_issue(id: "{이슈ID}")
```

### Step 3. 변경사항 확인

```bash
# 스테이징 안 된 변경 확인
git status --short

# 커밋 로그 (main 이후)
git log main..HEAD --oneline
```

- 커밋이 없고 변경사항도 없으면: "커밋할 내용이 없습니다" 안내 후 중단
- 스테이징 안 된 변경이 있으면: "커밋되지 않은 변경이 있습니다. 커밋 후 진행할까요?" (AskUserQuestion)

### Step 4. Push

```bash
git push -u origin {현재브랜치}
```

### Step 5. PR 생성

```bash
gh pr create \
  --title "{이슈ID}: {이슈 제목}" \
  --body "$(cat <<'EOF'
## Summary
{이슈 설명에서 핵심 내용 추출}

## Changes
{git log의 커밋 메시지 기반으로 변경사항 요약}

## Checklist
{이슈의 체크리스트 상태}

Resolves {이슈ID}
EOF
)"
```

**PR 제목 컨벤션:** `{이슈ID}: {설명}` (예: `LOG-101: Add user settings feature`)

### Step 6. 완료 메시지

```
## PR 생성 완료

| 항목 | 값 |
|------|-----|
| PR | {PR URL} |
| 이슈 | {이슈ID}: {제목} |
| 커밋 | {커밋 수}개 |

Linear 이슈 상태가 GitHub 연동을 통해 자동으로 전환됩니다.
리뷰가 필요하면 GitHub에서 리뷰어를 지정하세요.

리뷰 완료 후 `/linear-dev done`으로 머지하세요.
```

---

## 액션 4: Done — 머지 & 정리

### Step 1. 현재 PR 확인

```bash
gh pr view --json number,title,state,mergeable,url
```

- PR이 없으면: "현재 브랜치에 PR이 없습니다" 안내 후 중단
- PR이 머지 불가 상태면: 이유를 안내 (리뷰 미완료, 충돌 등)

### Step 2. 머지 확인

AskUserQuestion으로 확인:

```
PR을 머지할까요?

[Squash Merge] - 커밋을 하나로 합쳐서 머지 (추천)
[Merge] - 모든 커밋 유지하며 머지
[취소] - 머지하지 않음
```

### Step 3. 머지 실행

```bash
# 선택에 따라
gh pr merge --squash --delete-branch
# 또는
gh pr merge --merge --delete-branch
```

### Step 4. 로컬 정리

```bash
git checkout main
git pull origin main

# 머지된 브랜치 삭제 (로컬)
git branch -d {브랜치명}
```

### Step 5. 완료 메시지

```
## 작업 완료

| 항목 | 값 |
|------|-----|
| 머지된 PR | {PR URL} |
| 이슈 | {이슈ID} → Done (자동 전환) |
| 브랜치 | {브랜치명} (삭제됨) |

다음 작업은 `/linear-dev next`로 확인하세요.
```

---

## 액션 5: Next — 다음 할 일 확인

### Step 1. 내 Todo 이슈 조회

```
list_issues(assignee: "me", state: "Todo", includeArchived: false)
```

### Step 2. 우선순위 정렬 & 출력

```
## 내 할 일 목록

| # | 이슈 | 제목 | 우선순위 | 프로젝트 |
|---|------|------|---------|---------|
| 1 | {ID} | {제목} | Urgent | {프로젝트} |
| 2 | {ID} | {제목} | High | {프로젝트} |

`/linear-dev ready {이슈ID}`로 작업을 준비하세요.
```

정렬 기준: 우선순위(Urgent > High > Normal > Low) → 사이클 마감일 → 생성일

---

## 커밋 메시지 컨벤션

커밋 시 이슈 ID를 포함합니다:

```
{이슈ID}: {변경 내용}
```

예시:
- `LOG-101: Add user settings API endpoint`
- `LOG-101: Implement password change form`

---

## 상태 자동 전환 (GitHub 연동)

GitHub-Linear 연동이 설정되어 있으면 아래가 자동으로 일어납니다:

| GitHub 이벤트 | Linear 상태 |
|--------------|------------|
| PR 열림 / Draft PR | In Progress |
| Review 요청 | In Review |
| PR 머지 | Done |

따라서 `ready` 액션에서만 수동으로 상태를 변경하고, 이후는 자동 전환에 맡깁니다.

---

## 워크플로우 요약

| 단계 | 명령 | 설명 |
|------|------|------|
| 1 | `/linear-dev ready {이슈ID}` | 브랜치 생성, 작업 준비 |
| 2 | `/linear-dev omc-run` | OMC 팀 병렬 개발 (선택) |
| 3 | `/linear-dev review` | PR 생성 |
| 4 | `/linear-dev done` | 머지, 정리 |
| + | `/linear-dev next` | 다음 이슈 추천 |

**기본 워크플로우:** ready → review → done
**OMC 활용 워크플로우:** ready → omc-run → review → done
