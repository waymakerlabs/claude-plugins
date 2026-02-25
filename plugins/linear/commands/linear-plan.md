---
name: linear-plan
description: Planning & structuring - Epic decomposition, sprint & release planning
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - mcp__plugin_linear_linear__list_issues
  - mcp__plugin_linear_linear__get_issue
  - mcp__plugin_linear_linear__create_issue
  - mcp__plugin_linear_linear__update_issue
  - mcp__plugin_linear_linear__list_issue_statuses
  - mcp__plugin_linear_linear__list_issue_labels
  - mcp__plugin_linear_linear__create_issue_label
  - mcp__plugin_linear_linear__list_projects
  - mcp__plugin_linear_linear__get_project
  - mcp__plugin_linear_linear__save_project
  - mcp__plugin_linear_linear__list_teams
  - mcp__plugin_linear_linear__get_team
  - mcp__plugin_linear_linear__list_users
  - mcp__plugin_linear_linear__get_user
  - mcp__plugin_linear_linear__list_cycles
  - mcp__plugin_linear_linear__list_milestones
  - mcp__plugin_linear_linear__get_milestone
  - mcp__plugin_linear_linear__save_milestone
  - mcp__plugin_linear_linear__create_comment
argument-hint: "[기능 분해|스프린트 계획|릴리즈 계획]"
---

# Linear Plan: 기획 & 구조화

기능 분해, 스프린트 계획, 릴리즈 계획을 위한 스킬입니다.

## 워크플로우 라우팅

인자 또는 대화 맥락에서 워크플로우를 식별합니다:

| 트리거 | 워크플로우 |
|--------|-----------|
| "기능 분해", "태스크 나눠줘", "이슈 쪼개줘" | 기능 분해 |
| "스프린트 계획", "사이클 계획", "이번 주 계획" | 스프린트 계획 |
| "릴리즈 계획", "프로젝트 생성", "로드맵" | 릴리즈 계획 |
| (불명확) | AskUserQuestion으로 확인 |

---

## 워크플로우 1: 기능 분해 (Epic → 서브태스크)

큰 기능을 PR 리뷰 가능한 크기의 서브태스크로 분해합니다.

### Step 1. 기능 파악

사용자에게 기능 요구사항을 확인합니다. 이미 설명이 있으면 그대로 사용합니다.

필요시 AskUserQuestion:

```
어떤 기능을 분해할까요? 기능의 목표와 범위를 설명해주세요.
```

**코드베이스 분석** (git 프로젝트인 경우):

현재 프로젝트의 구조를 파악하여 태스크 분해에 반영합니다:

```bash
# 프로젝트 구조 파악
ls -la
```

관련 파일/디렉토리를 읽어 아키텍처를 이해합니다.

### Step 2. 팀/프로젝트 결정

```
list_teams
```

팀이 여러 개면 AskUserQuestion으로 선택. 프로젝트도 필요시 확인합니다.

### Step 3. 상위 이슈 (Epic) 생성

```
create_issue(
  title: "{기능명}",
  team: "{팀}",
  description: "## 목표\n{기능 설명}\n\n## 범위\n{포함/제외 사항}",
  priority: {우선순위},
  labels: ["feature"]
)
```

### Step 4. 서브태스크 설계

기능을 아래 기준으로 분해합니다:

| 기준 | 설명 |
|------|------|
| **PR 리뷰 크기** | 각 태스크가 200~400줄 변경으로 리뷰 가능한 크기 |
| **독립적 테스트** | 각 태스크가 독립적으로 테스트 가능 |
| **의존성 순서** | 데이터 모델 → API → UI → 테스트 순서 |
| **영역 분리** | [Backend], [Frontend], [Test], [Infra] 등 접두어 사용 |

**분해 결과를 사용자에게 확인:**

```
## 기능 분해 제안

상위 이슈: {Epic 제목}

| # | 제목 | 영역 | 의존성 | 예상 크기 |
|---|------|------|--------|----------|
| 1 | [Backend] 데이터 모델 설계 | Backend | - | ~150줄 |
| 2 | [Backend] API 엔드포인트 | Backend | 1 | ~300줄 |
| 3 | [Frontend] UI 컴포넌트 | Frontend | 2 | ~250줄 |
| 4 | [Frontend] 화면 통합 | Frontend | 3 | ~200줄 |
| 5 | [Test] 통합 테스트 | Test | 1,2 | ~200줄 |

이대로 이슈를 생성할까요? 수정이 필요하면 말씀해주세요.
```

AskUserQuestion으로 확인 후 진행합니다.

### Step 5. 서브태스크 생성

확인 후 일괄 생성:

```
create_issue(
  title: "[Backend] 데이터 모델 설계",
  team: "{팀}",
  parentId: "{Epic 이슈 ID}",
  description: "## 목표\n{상세 설명}\n\n## 작업 내용\n- [ ] {체크리스트}",
  priority: {우선순위},
  labels: ["backend"]
)
```

의존성이 있는 이슈는 `blockedBy`로 관계를 설정합니다.

### Step 6. 완료 요약

```
## 기능 분해 완료

### {Epic 제목}
| 이슈 | 제목 | 상태 |
|------|------|------|
| {ID} | {제목} | Todo |

총 {N}개 서브태스크가 생성되었습니다.
`/linear-dev start {첫번째이슈ID}`로 작업을 시작하세요.
```

---

## 워크플로우 2: 스프린트 계획

현재/다음 사이클의 작업을 계획합니다.

### Step 1. 현재 사이클 검토

```
list_teams
list_cycles(teamId: "{팀ID}", type: "current")
```

현재 사이클의 이슈 현황 조회:

```
list_issues(cycle: "{사이클}", team: "{팀}")
```

### Step 2. 현황 분석

```
## 현재 사이클: {사이클 이름}
기간: {시작일} ~ {종료일}

| 상태 | 이슈 수 |
|------|---------|
| Done | {N} |
| In Progress | {N} |
| In Review | {N} |
| Todo | {N} |
| 완료율 | {%} |
```

### Step 3. 팀 용량 분석

팀원별 현재 할당량을 파악합니다:

```
list_users(team: "{팀}")
```

각 팀원별 진행 중 이슈 수를 조회하여 여유 인원을 식별합니다.

```
## 팀원별 워크로드

| 팀원 | In Progress | Todo | 총 할당 | 상태 |
|------|------------|------|---------|------|
| {이름} | 2 | 3 | 5 | 적정 |
| {이름} | 4 | 5 | 9 | 과부하 |
| {이름} | 1 | 1 | 2 | 여유 |
```

### Step 4. 스코프 제안

백로그에서 다음 사이클에 추가할 만한 이슈를 제안합니다:

```
list_issues(team: "{팀}", state: "Backlog")
```

우선순위와 팀 용량을 고려하여 추천 목록을 만들고, AskUserQuestion으로 확인합니다.

### Step 5. 사이클 배정

확인된 이슈들을 사이클에 추가합니다:

```
update_issue(id: "{이슈ID}", cycle: "{사이클}")
update_issue(id: "{이슈ID}", assignee: "{담당자}")
```

---

## 워크플로우 3: 릴리즈 계획

프로젝트와 마일스톤 기반의 릴리즈를 계획합니다.

### Step 1. 릴리즈 범위 파악

AskUserQuestion으로 확인:

```
릴리즈에 대해 알려주세요.

- 릴리즈 이름/버전 (예: v2.0, Beta Release)
- 목표 날짜
- 주요 기능/목표
```

### Step 2. 프로젝트 생성

```
save_project(
  name: "{릴리즈명}",
  team: "{팀}",
  description: "## 목표\n{릴리즈 목표}",
  targetDate: "{목표일}",
  state: "started"
)
```

### Step 3. 마일스톤 설정

릴리즈를 단계별 마일스톤으로 나눕니다:

```
save_milestone(project: "{프로젝트}", name: "Feature Freeze", targetDate: "{날짜}")
save_milestone(project: "{프로젝트}", name: "Beta", targetDate: "{날짜}")
save_milestone(project: "{프로젝트}", name: "Documentation", targetDate: "{날짜}")
save_milestone(project: "{프로젝트}", name: "Launch", targetDate: "{날짜}")
```

사용자에게 마일스톤 구성을 확인받습니다.

### Step 4. 이슈 생성

각 마일스톤에 해당하는 이슈를 생성합니다:

```
create_issue(
  title: "{이슈 제목}",
  team: "{팀}",
  project: "{프로젝트}",
  milestone: "{마일스톤}",
  description: "{상세 설명}",
  priority: {우선순위}
)
```

### Step 5. 완료 요약

```
## 릴리즈 계획 완료

### {릴리즈명}
목표일: {날짜}

| 마일스톤 | 기한 | 이슈 수 |
|---------|------|---------|
| Feature Freeze | {날짜} | {N} |
| Beta | {날짜} | {N} |
| Documentation | {날짜} | {N} |
| Launch | {날짜} | {N} |

총 {N}개 이슈가 생성되었습니다.
```

---

## 태스크 분해 가이드라인

### 좋은 분해 예시

```
기능: 사용자 인증 시스템

[Backend] 사용자 모델 & 마이그레이션      (~150줄)
[Backend] 인증 API (회원가입/로그인)      (~300줄)
[Backend] JWT 토큰 발급 & 갱신            (~200줄)
[Frontend] 로그인/회원가입 폼 UI          (~250줄)
[Frontend] 인증 상태 관리 & 라우트 가드    (~200줄)
[Test] 인증 E2E 테스트                    (~200줄)
```

### 나쁜 분해 예시

```
기능: 사용자 인증 시스템

인증 시스템 구현                          (~2000줄, 리뷰 불가)
```

### 분해 기준

| 기준 | 권장 |
|------|------|
| PR 크기 | 200~400줄 변경 |
| 리뷰 시간 | 30분 이내 |
| 작업 시간 | 반나절~하루 |
| 테스트 | 독립적으로 테스트 가능 |
| 의존성 | 최소화, 명시적 |
