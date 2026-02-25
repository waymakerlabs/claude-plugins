---
name: linear-dev
description: Dev cycle automation - start issues, create PRs, finish & clean up
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - mcp__plugin_linear_linear__list_issues
  - mcp__plugin_linear_linear__get_issue
  - mcp__plugin_linear_linear__update_issue
  - mcp__plugin_linear_linear__list_issue_statuses
  - mcp__plugin_linear_linear__list_teams
  - mcp__plugin_linear_linear__get_team
  - mcp__plugin_linear_linear__list_users
  - mcp__plugin_linear_linear__get_user
  - mcp__plugin_linear_linear__create_comment
argument-hint: "<start|pr|finish|next> [이슈ID]"
---

# Linear Dev: 개발 사이클 자동화

Linear 이슈 기반 개발 워크플로우를 자동화하는 스킬입니다.
**핵심 원칙: 1 이슈 = 1 브랜치 = 1 PR**

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

## 액션 라우팅

인자를 파싱하여 아래 액션으로 분기합니다:

| 인자 | 액션 | 설명 |
|------|------|------|
| `start {이슈ID}` | Start | 이슈 작업 시작 (브랜치 생성) |
| `pr` | PR | 현재 브랜치에서 PR 생성 |
| `finish` | Finish | PR 머지 후 정리 |
| `next` | Next | 다음 할 일 목록 |
| (없음) | 대화형 | AskUserQuestion으로 액션 선택 |

인자가 없으면 AskUserQuestion으로 물어봅니다:

```
어떤 작업을 할까요?

[start] - 이슈 작업 시작 (브랜치 생성)
[pr] - PR 생성
[finish] - PR 머지 & 정리
[next] - 다음 할 일 확인
```

---

## 액션 1: Start — 이슈 작업 시작

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
| 라벨 | {labels} |
| 상위 이슈 | {parent} |
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
- 예: `log-101-backend-favorites-data-model`

### Step 4. 상태 업데이트

```
update_issue(id: "{이슈ID}", state: "In Progress")
```

### Step 5. 완료 메시지

```
## 작업 시작 준비 완료

| 항목 | 값 |
|------|-----|
| 이슈 | {이슈ID}: {제목} |
| 브랜치 | {branchName} |
| 상태 | In Progress |

이제 코딩을 시작하세요. 작업이 끝나면 `/linear-dev pr`로 PR을 생성합니다.
```

---

## 액션 2: PR — Pull Request 생성

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

Resolves {이슈ID}
EOF
)"
```

**PR 제목 컨벤션:** `{이슈ID}: {설명}` (예: `LOG-101: Add favorites data model`)

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
```

---

## 액션 3: Finish — PR 머지 & 정리

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

### Step 5. 다음 이슈 제안

브랜치명에서 추출한 이슈의 상위 이슈(parent)를 확인하고, 같은 parent의 다음 Todo 이슈를 조회합니다:

```
list_issues(parentId: "{parentId}", state: "Todo", includeArchived: false)
```

```
## 머지 완료

| 항목 | 값 |
|------|-----|
| 머지된 PR | {PR URL} |
| 이슈 | {이슈ID} → Done (자동 전환) |
| 브랜치 | {브랜치명} (삭제됨) |

## 다음 할 일
| 이슈 | 제목 | 우선순위 |
|------|------|---------|
| {이슈ID} | {제목} | {priority} |

`/linear-dev start {이슈ID}`로 다음 작업을 시작하세요.
```

---

## 액션 4: Next — 다음 할 일 확인

### Step 1. 내 Todo 이슈 조회

```
list_issues(assignee: "me", state: "Todo", includeArchived: false)
```

### Step 2. 우선순위 정렬 & 출력

```
## 내 할 일 목록

| # | 이슈 | 제목 | 우선순위 | 프로젝트 | 사이클 |
|---|------|------|---------|---------|--------|
| 1 | {ID} | {제목} | Urgent | {프로젝트} | {사이클} |
| 2 | {ID} | {제목} | High | {프로젝트} | {사이클} |

`/linear-dev start {이슈ID}`로 작업을 시작하세요.
```

정렬 기준: 우선순위(Urgent > High > Normal > Low) → 사이클 마감일 → 생성일

---

## 커밋 메시지 컨벤션

커밋 시 이슈 ID를 포함합니다:

```
{이슈ID}: {변경 내용}
```

예시:
- `LOG-101: Add favorites table schema and migration`
- `LOG-101: Address review feedback - add index on word_id`

## 상태 자동 전환 (GitHub 연동)

GitHub-Linear 연동이 설정되어 있으면 아래가 자동으로 일어납니다:

| GitHub 이벤트 | Linear 상태 |
|--------------|------------|
| PR 열림 / Draft PR | In Progress |
| Review 요청 | In Review |
| PR 머지 | Done |

따라서 `start` 액션에서만 수동으로 상태를 변경하고, 이후는 자동 전환에 맡깁니다.
