# Linear Plugin

Linear 이슈 관리, 개발 사이클 자동화, 기획 워크플로우를 위한 Claude Code 플러그인입니다.

## Prerequisites

- Linear MCP가 연결되어 있어야 합니다 (Claude Code 환경에 기본 포함)
- `/linear-dev` 사용 시: `git`, `gh` CLI 필요

## Install

```bash
/plugin install linear@waymakerlabs-claude-plugins
```

## Skills

| Skill | Description |
|-------|-------------|
| `/linear` | 일반 Linear 관리 - 이슈 조회/생성/수정, 버그 Triage, 팀 워크로드 분석 |
| `/linear-dev` | 개발 사이클 자동화 - 이슈 시작, PR 생성, 머지 & 정리, 다음 할 일 |
| `/linear-plan` | 기획 & 구조화 - Epic 분해, 스프린트 계획, 릴리즈 계획 |

---

## `/linear` - 이슈 & 프로젝트 관리

Linear의 이슈, 프로젝트, 팀 워크플로우를 자연어로 관리합니다.

### 사용 예시

```bash
# 이슈 조회
/linear 내 이슈 보여줘
/linear 이번 주 할 일
/linear LOG-101 상세 정보

# 이슈 생성 & 수정
/linear "로그인 버그 수정" 이슈 만들어줘
/linear LOG-101 우선순위 High로 변경해줘
/linear LOG-101 상태 In Progress로 변경

# 버그 Triage
/linear 버그 이슈 정리해줘
/linear 크리티컬 이슈 뭐 있어?

# 팀 워크로드
/linear 팀원별 작업량 분석해줘
/linear 누가 여유 있어?

# 스프린트 회고
/linear 지난 사이클 리뷰
/linear 완료율 보여줘

# 라벨링
/linear 라벨 없는 이슈 찾아서 정리해줘

# 문서 감사
/linear 문서 현황 보여줘
```

### 워크플로우

```
목표 확인 → 컨텍스트 수집 (팀/프로젝트 결정) → MCP 도구 실행 → 결과 요약
```

팀이 하나면 자동 선택되고, 여러 개면 어느 팀인지 물어봅니다.

---

## `/linear-dev` - 개발 사이클 자동화

**핵심 원칙: 1 이슈 = 1 브랜치 = 1 PR**

Linear 이슈 기반으로 브랜치 생성부터 PR 머지까지 전체 개발 사이클을 자동화합니다.

### 액션 목록

| 액션 | 명령어 | 설명 |
|------|--------|------|
| Start | `/linear-dev start {이슈ID}` | 이슈 조회 → main 최신화 → 브랜치 생성 → 상태 In Progress |
| PR | `/linear-dev pr` | 현재 브랜치의 이슈 감지 → Push → PR 생성 |
| Finish | `/linear-dev finish` | PR 머지 → main 복귀 → 브랜치 삭제 → 다음 이슈 제안 |
| Next | `/linear-dev next` | 나에게 할당된 Todo 이슈를 우선순위 순으로 표시 |

인자 없이 `/linear-dev`만 실행하면 대화형으로 액션을 선택합니다.

### Start — 이슈 작업 시작

```bash
/linear-dev start LOG-101
```

**수행 동작:**

1. Linear에서 이슈 정보 조회 (제목, 상태, 담당자, 브랜치명)
2. 커밋되지 않은 변경이 있으면 경고
3. `main` 브랜치 최신화 (`git pull`)
4. Linear이 제공하는 브랜치명으로 새 브랜치 생성
5. 이슈 상태를 `In Progress`로 변경

**결과:**

```
## 작업 시작 준비 완료

| 항목 | 값 |
|------|-----|
| 이슈 | LOG-101: 즐겨찾기 데이터 모델 설계 |
| 브랜치 | log-101-backend-favorites-data-model |
| 상태 | In Progress |

이제 코딩을 시작하세요. 작업이 끝나면 `/linear-dev pr`로 PR을 생성합니다.
```

### PR — Pull Request 생성

```bash
/linear-dev pr
```

**수행 동작:**

1. 현재 브랜치명에서 이슈 ID 자동 추출 (예: `log-101-...` → `LOG-101`)
2. Linear에서 이슈 정보 조회
3. 커밋되지 않은 변경이 있으면 커밋 여부 확인
4. `git push -u origin {브랜치}`
5. `gh pr create` — 제목: `{이슈ID}: {이슈 제목}`, 본문: 이슈 설명 + 변경사항 요약

**PR 컨벤션:**

```
제목: LOG-101: Add favorites data model and migration
본문:
  ## Summary
  - favorites 테이블 스키마 추가
  - 마이그레이션 스크립트 작성

  Resolves LOG-101
```

### Finish — PR 머지 & 정리

```bash
/linear-dev finish
```

**수행 동작:**

1. 현재 브랜치의 PR 상태 확인 (머지 가능 여부)
2. 머지 방식 선택 (Squash Merge 추천 / Merge / 취소)
3. PR 머지 + 리모트 브랜치 삭제
4. `main`으로 체크아웃 + pull
5. 로컬 브랜치 삭제
6. 같은 Epic의 다음 Todo 이슈 제안

**결과:**

```
## 머지 완료

| 항목 | 값 |
|------|-----|
| 머지된 PR | #42 |
| 이슈 | LOG-101 → Done (자동 전환) |
| 브랜치 | log-101-... (삭제됨) |

## 다음 할 일
| 이슈 | 제목 | 우선순위 |
|------|------|---------|
| LOG-102 | [Backend] API 엔드포인트 | High |

`/linear-dev start LOG-102`로 다음 작업을 시작하세요.
```

### Next — 다음 할 일 확인

```bash
/linear-dev next
```

나에게 할당된 Todo 이슈를 우선순위 순으로 보여줍니다:
- 정렬: Urgent > High > Normal > Low → 사이클 마감일 → 생성일

### 전체 개발 흐름

```
/linear-dev start LOG-101    이슈 시작 (브랜치 생성)
        │
        ▼
     코딩 작업
        │
        ▼
/linear-dev pr               PR 생성
        │
        ▼
     코드 리뷰
        │
        ▼
/linear-dev finish            머지 + 정리
        │
        ▼
/linear-dev start LOG-102    다음 이슈로 반복
```

### 커밋 메시지 컨벤션

```
{이슈ID}: {변경 내용}
```

예시:
- `LOG-101: Add favorites table schema and migration`
- `LOG-101: Address review feedback - add index on word_id`

### 자동 상태 전환 (GitHub-Linear 연동)

| GitHub 이벤트 | Linear 상태 |
|--------------|------------|
| PR 열림 / Draft PR | In Progress |
| Review 요청 | In Review |
| PR 머지 | Done |

`start`에서만 수동 상태 변경, 이후는 GitHub 이벤트에 의한 자동 전환에 맡깁니다.

---

## `/linear-plan` - 기획 & 구조화

기능 분해, 스프린트 계획, 릴리즈 계획을 위한 기획 워크플로우입니다.

### 워크플로우 1: 기능 분해

```bash
/linear-plan 기능 분해
/linear-plan 즐겨찾기 기능을 태스크로 나눠줘
/linear-plan 이 기능 이슈로 쪼개줘
```

큰 기능을 PR 리뷰 가능한 크기(200~400줄)의 서브태스크로 분해합니다.

**수행 동작:**

1. 기능 요구사항 확인 (사용자 설명 또는 대화형 질문)
2. 코드베이스 구조 분석 (git 프로젝트인 경우)
3. 상위 이슈(Epic) 생성
4. 서브태스크 설계 & 사용자 확인
5. 확인 후 일괄 이슈 생성 (의존성 관계 포함)

**분해 기준:**

| 기준 | 권장 |
|------|------|
| PR 크기 | 200~400줄 변경 |
| 리뷰 시간 | 30분 이내 |
| 작업 시간 | 반나절~하루 |
| 테스트 | 독립적으로 테스트 가능 |

**예시 결과:**

```
## 기능 분해: 즐겨찾기 단어장

| # | 이슈 | 제목 | 영역 | 예상 크기 |
|---|------|------|------|----------|
| 1 | LOG-101 | [Backend] 데이터 모델 설계 | Backend | ~150줄 |
| 2 | LOG-102 | [Backend] API 엔드포인트 | Backend | ~300줄 |
| 3 | LOG-103 | [Frontend] 즐겨찾기 버튼 UI | Frontend | ~250줄 |
| 4 | LOG-104 | [Frontend] 즐겨찾기 화면 | Frontend | ~200줄 |
| 5 | LOG-105 | [Test] 통합 테스트 | Test | ~200줄 |
```

### 워크플로우 2: 스프린트 계획

```bash
/linear-plan 스프린트 계획
/linear-plan 이번 사이클 계획 세워줘
/linear-plan 다음 주 작업 계획
```

현재/다음 사이클의 작업을 분석하고 계획합니다.

**수행 동작:**

1. 현재 사이클 이슈 현황 조회 (Done/In Progress/Todo 비율)
2. 팀원별 워크로드 분석 (과부하/여유 식별)
3. 백로그에서 다음 사이클 추가 이슈 제안
4. 확인 후 사이클 배정 + 담당자 배정

**예시 결과:**

```
## 현재 사이클: Sprint 12
기간: 2/17 ~ 2/28

| 상태 | 이슈 수 |
|------|---------|
| Done | 8 |
| In Progress | 3 |
| Todo | 4 |
| 완료율 | 53% |

## 팀원별 워크로드
| 팀원 | 진행중 | Todo | 상태 |
|------|--------|------|------|
| Peter | 2 | 3 | 적정 |
| Alex | 4 | 5 | 과부하 |
```

### 워크플로우 3: 릴리즈 계획

```bash
/linear-plan 릴리즈 계획
/linear-plan v2.0 릴리즈 계획 세워줘
/linear-plan 3월 말 출시 로드맵 만들어줘
```

프로젝트, 마일스톤, 이슈를 한번에 생성합니다.

**수행 동작:**

1. 릴리즈 범위 파악 (이름, 목표일, 주요 기능)
2. 프로젝트 생성
3. 마일스톤 설정 (Feature Freeze → Beta → Documentation → Launch)
4. 각 마일스톤에 이슈 생성
5. 전체 요약 출력

**예시 결과:**

```
## 릴리즈 계획: v2.0
목표일: 2026-03-31

| 마일스톤 | 기한 | 이슈 수 |
|---------|------|---------|
| Feature Freeze | 3/14 | 8 |
| Beta | 3/21 | 3 |
| Documentation | 3/28 | 4 |
| Launch | 3/31 | 2 |
```

---

## Core Principles

| 원칙 | 설명 |
|------|------|
| **1 이슈 = 1 브랜치 = 1 PR** | 하나의 이슈는 하나의 브랜치에서 작업하고 하나의 PR로 머지 |
| **PR 리뷰 가능한 크기** | 200~400줄 변경이 적당 |
| **자동 상태 전환** | GitHub-Linear 연동으로 PR 이벤트에 따라 이슈 상태 자동 변경 |
| **커밋 컨벤션** | `{이슈ID}: {메시지}` (예: `LOG-101: Add favorites model`) |
| **수동 상태 변경 최소화** | `start`에서만 수동 변경, 이후는 GitHub 자동 전환 |

## 상태 워크플로우

```
Backlog → Todo → In Progress → In Review → Done
```

## 우선순위

| 숫자 | 의미 |
|------|------|
| 1 | Urgent |
| 2 | High |
| 3 | Normal |
| 4 | Low |
