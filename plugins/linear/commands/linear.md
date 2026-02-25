---
name: linear
description: Manage Linear issues, projects & team workflows
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
  - mcp__plugin_linear_linear__list_comments
  - mcp__plugin_linear_linear__create_comment
  - mcp__plugin_linear_linear__list_projects
  - mcp__plugin_linear_linear__get_project
  - mcp__plugin_linear_linear__save_project
  - mcp__plugin_linear_linear__list_teams
  - mcp__plugin_linear_linear__get_team
  - mcp__plugin_linear_linear__list_users
  - mcp__plugin_linear_linear__get_user
  - mcp__plugin_linear_linear__list_documents
  - mcp__plugin_linear_linear__get_document
  - mcp__plugin_linear_linear__search_documentation
  - mcp__plugin_linear_linear__list_cycles
  - mcp__plugin_linear_linear__list_milestones
  - mcp__plugin_linear_linear__get_milestone
argument-hint: "[자연어 요청]"
---

# Linear: 이슈 & 프로젝트 관리

Linear MCP 도구를 사용하여 이슈, 프로젝트, 팀 워크플로우를 관리하는 스킬입니다.

## 필수 워크플로우

**반드시 순서대로 진행합니다. 단계를 건너뛰지 마세요.**

### Step 1: 목표 확인

사용자의 요청을 분석하여 아래 중 해당하는 워크플로우를 식별합니다:

| 워크플로우 | 트리거 예시 |
|-----------|------------|
| 이슈 조회 | "내 이슈 보여줘", "이번 주 할 일", "팀 이슈 현황" |
| 이슈 생성/수정 | "이슈 만들어줘", "상태 변경해줘", "우선순위 올려줘" |
| 버그 Triage | "버그 정리해줘", "크리티컬 이슈 뭐 있어?" |
| 팀 워크로드 | "팀원별 작업량", "누가 여유 있어?" |
| 스프린트 회고 | "지난 사이클 리뷰", "완료율 보여줘" |
| 라벨링 | "라벨 정리해줘", "라벨 없는 이슈 찾아줘" |
| 문서 감사 | "문서 현황", "업데이트 필요한 문서" |

필요하면 팀/프로젝트, 우선순위, 라벨, 사이클, 기한 등을 확인합니다.

### Step 2: 컨텍스트 수집

실행에 필요한 식별자(팀 ID, 프로젝트 ID, 이슈 ID 등)를 먼저 조회합니다.

**팀 결정 순서:**

1. 사용자가 명시한 경우 → 그대로 사용
2. 명시하지 않은 경우 → `list_teams`로 팀 목록 조회
3. 팀이 1개면 자동 선택, 여러 개면 AskUserQuestion으로 확인

**프로젝트 결정 순서 (이슈 생성/수정 시):**

1. 사용자가 명시한 경우 → 그대로 사용
2. 명시하지 않은 경우 → `list_projects(team: "{팀명}")`로 프로젝트 목록 조회
3. 프로젝트가 0개면 생략, 1개면 자동 선택, 여러 개면 AskUserQuestion으로 확인 ("프로젝트 없음" 옵션 포함)

**"내 이슈" 조회 시:**

```
list_issues(assignee: "me", includeArchived: false)
```

**이슈 리스트 조회 시 (프로젝트 우선):**

1. 현재 작업 중인 로컬 프로젝트 이름 파악:
   ```bash
   # git remote에서 리포지토리 이름 추출
   git remote get-url origin 2>/dev/null | sed 's/.*\///' | sed 's/.git$//'
   # 또는 디렉토리 이름 사용
   basename $(git rev-parse --show-toplevel 2>/dev/null)
   ```
2. `list_projects(team: "{팀명}")`로 Linear 프로젝트 목록 조회
3. 로컬 프로젝트명과 매칭되는 Linear 프로젝트가 있으면:
   ```
   list_issues(team: "{팀명}", project: "{매칭된프로젝트}", includeArchived: false)
   ```
4. 매칭되는 프로젝트가 없으면 팀 전체 이슈 조회:
   ```
   list_issues(team: "{팀명}", includeArchived: false)
   ```

**중요:** 아카이브된 이슈는 제외하려면 항상 `includeArchived: false`를 사용합니다.

### Step 3: 실행

Linear MCP 도구를 논리적 순서로 호출합니다:

1. **읽기 먼저** — list/get/search로 현재 상태 파악
2. **생성/수정** — 필요한 필드를 모두 채워서 실행
3. **대량 작업** — 그룹핑 로직을 설명한 후 적용

### Step 4: 결과 요약

실행 결과를 정리하고, 남은 작업이나 블로커를 안내합니다.

**요약 형식:**

```
## 결과

| 이슈 | 상태 | 담당자 | 우선순위 |
|------|------|--------|---------|
| PRJ-42 제목 | In Progress | @이름 | High |

## 다음 액션
- 추가 필요한 작업
- 확인이 필요한 사항
```

## 워크플로우별 상세 가이드

### 이슈 조회

- `list_issues` — 필터: assignee, state, priority, label, project, team, cycle
- `get_issue` — 단일 이슈 상세 (includeRelations: true로 블로킹 관계 확인)
- "내 이슈": `list_issues(assignee: "me")`
- "팀 이슈": `list_issues(team: "{팀명}")`

### 이슈 생성

최소 필수 필드: `title`, `team`

추가 권장 필드:
- `description` — 마크다운 형식
- `priority` — 1(Urgent), 2(High), 3(Normal), 4(Low)
- `assignee` — 담당자 (이름, 이메일, "me")
- `labels` — 라벨 이름 배열
- `project` — 프로젝트명
- `parentId` — 상위 이슈 (Epic의 서브태스크인 경우)
- `estimate` — 이슈 추정치

### 이슈 수정

- 상태 변경: `update_issue(id, state: "In Progress")`
- 담당자 변경: `update_issue(id, assignee: "이름")`
- 우선순위 변경: `update_issue(id, priority: 2)`
- 라벨 추가: `update_issue(id, labels: ["bug", "urgent"])`

### 버그 Triage

1. `list_issues(state: "triage")` 또는 `list_issues(label: "bug")`로 버그 목록 조회
2. 영향도/심각도 기준으로 분류
3. 우선순위 설정 + 담당자 배정 + 사이클 추가

### 팀 워크로드 분석

1. `list_users(team: "{팀명}")`로 팀원 목록 조회
2. 각 팀원별 `list_issues(assignee: "{이름}", state: "started")`로 진행 중 이슈 파악
3. 과부하/여유 팀원 식별 후 재분배 제안

### 스프린트 회고

1. `list_cycles(teamId: "{팀ID}", type: "previous")`로 지난 사이클 조회
2. 해당 사이클의 이슈 조회: `list_issues(cycle: "{사이클}", team: "{팀}")`
3. 완료/미완료 비율 분석, 패턴 파악
4. 회고 이슈 생성 (선택사항)

### 스마트 라벨링

1. 라벨 없는 이슈 조회
2. 이슈 제목/설명 분석하여 라벨 제안
3. 확인 후 일괄 적용

### 문서 감사

1. `list_documents`로 문서 목록 조회
2. 오래된 문서 또는 누락된 주제 식별
3. 업데이트가 필요한 문서에 대해 이슈 생성

## 팁

- **배치 처리**: 관련 변경은 묶어서 처리합니다
- **자연어 질의**: "이번 주 존이 뭐 하고 있는지 보여줘" 같은 자연어도 OK
- **맥락 활용**: 이전 이슈를 참조하여 새 요청에 활용합니다
- **대량 작업**: Rate limit를 고려하여 작은 배치로 나눕니다

## 우선순위 번호

| 숫자 | 의미 |
|------|------|
| 0 | None |
| 1 | Urgent |
| 2 | High |
| 3 | Normal |
| 4 | Low |

## 상태 워크플로우

```
Backlog → Todo → In Progress → In Review → Done
                                         → Cancelled
```
