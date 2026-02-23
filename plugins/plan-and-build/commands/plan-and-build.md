---
name: plan-and-build
description: Structured workflow - Research → Plan → Annotation Cycle → Implementation
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
  - TaskCreate
  - TaskUpdate
  - TaskList
  - AskUserQuestion
argument-hint: "<task description>"
---

# Plan & Build: 구조화된 개발 워크플로우

AI에게 바로 코딩을 시키지 않고, **Research → Plan → Annotation Cycle → Todo → Implementation** 단계를 분리하여 의사결정은 사람이, 실행은 AI가 하는 구조화된 워크플로우입니다.

문서는 프로젝트 루트의 `docs/plan-and-build/` 폴더에 생성됩니다.

## 실행 흐름

### Step 1: 작업 확인 & 폴더 준비

1. **작업 설명 확인**: 인자로 받은 작업 설명을 확인합니다. 인자가 없으면 AskUserQuestion으로 물어봅니다:
   > "어떤 작업을 계획하고 구현할까요?"

2. **프로젝트 루트 탐지**: git root를 찾거나, 현재 작업 디렉토리를 프로젝트 루트로 사용합니다:
   ```bash
   git rev-parse --show-toplevel 2>/dev/null || pwd
   ```

3. **문서 폴더 준비**: `{프로젝트 루트}/docs/plan-and-build/` 폴더가 없으면 생성합니다.

4. **기존 문서 확인**: `research.md` 또는 `plan.md`가 이미 존재하면 AskUserQuestion으로 확인합니다:
   - "새로 시작" — 기존 문서를 삭제하고 처음부터 시작
   - "이어서 하기" — 기존 문서를 유지하고 이전 단계부터 재개

5. **작업 안내 출력**:
   ```
   🚀 Plan & Build 시작!

   📝 작업: {task description}
   📁 문서 위치: docs/plan-and-build/

   Step 1: ✅ 작업 확인 완료
   Step 2: 🔄 리서치 진행중...
   ```

### Step 2: Research (리서치)

코드베이스를 **깊이 있게** 탐색하고 `docs/plan-and-build/research.md`를 생성합니다.

**탐색 방법:**
- Task 도구의 Explore 에이전트를 활용하여 깊이 있는 코드베이스 분석 수행
- "deeply", "in great detail", "intricacies" 수준의 깊은 탐색
- 관련된 모든 파일, 패턴, 의존성을 빠짐없이 조사

**research.md 내용 구성:**

```markdown
# Research: {task description}

> 생성일: {YYYY-MM-DD}
> 작업: {task description}

## 관련 코드 구조 및 아키텍처

{프로젝트 구조, 주요 모듈, 데이터 흐름 등}

## 기존 패턴 및 컨벤션

{코딩 스타일, 네이밍 규칙, 디자인 패턴, 에러 처리 방식 등}

## 의존성 및 영향 범위

{변경 시 영향받는 파일/모듈, 외부 의존성 등}

## 주의사항 및 잠재적 충돌

{기존 코드와의 충돌 가능성, 엣지 케이스, 기술적 제약 등}

## 참고 파일

| 파일 | 역할 |
|------|------|
| `path/to/file` | 설명 |
```

**완료 후 사용자에게 리뷰 요청:**

```
📖 리서치 완료! `docs/plan-and-build/research.md`를 확인해주세요.
수정사항이 있으면 파일에 직접 주석을 달고 알려주세요.
괜찮으면 '계획 시작'이라고 말씀해주세요.
```

**여기서 멈추고 사용자 응답을 기다립니다.**

### Step 3: Plan (계획 수립)

사용자가 '계획 시작'이라고 하면, research.md를 기반으로 `docs/plan-and-build/plan.md`를 생성합니다.

**plan.md 내용 구성:**

```markdown
# Plan: {task description}

> 생성일: {YYYY-MM-DD}
> 작업: {task description}
> 기반: [research.md](./research.md)

## 구현 전략 개요

{전체적인 접근 방식과 이유를 서술형으로 설명}

## 수정할 파일 목록

| 순서 | 파일 경로 | 변경 유형 | 설명 |
|------|----------|----------|------|
| 1 | `path/to/file` | 생성/수정/삭제 | 설명 |

## 상세 변경 계획

### Phase 1: {phase 이름}

#### 1-1. {파일 또는 작업}

**변경 내용:**
{무엇을 왜 변경하는지}

**코드 스니펫:**
\`\`\`{lang}
// 변경 전 (해당하는 경우)
// 변경 후
\`\`\`

### Phase 2: {phase 이름}
...

## 트레이드오프 고려사항

| 선택지 | 장점 | 단점 | 결정 |
|--------|------|------|------|
| A 방식 | ... | ... | ✅ 선택 |
| B 방식 | ... | ... | ❌ |

## 구현 순서

1. Phase 1: {이유와 함께}
2. Phase 2: {이유와 함께}
...
```

**완료 후 Annotation Cycle 안내:**

```
📋 계획 작성 완료! `docs/plan-and-build/plan.md`를 확인해주세요.

**주석 사이클을 시작합니다:**
1. plan.md를 에디터에서 열어주세요
2. 수정/추가/거부할 내용에 인라인 주석을 달아주세요
3. '주석 반영해줘'라고 말씀하면 반영합니다
4. 만족할 때까지 반복합니다
5. '구현 시작'이라고 말씀하면 구현을 시작합니다
```

**여기서 멈추고 사용자 응답을 기다립니다.**

### Step 4: Annotation Cycle (주석 사이클)

사용자가 plan.md에 인라인 주석을 추가한 후 "주석 반영해줘"라고 요청하면:

1. `docs/plan-and-build/plan.md`를 다시 읽습니다
2. 사용자가 추가한 모든 주석/코멘트를 찾습니다
3. 주석 내용을 반영하여 plan.md를 업데이트합니다
4. 변경 사항을 요약하여 보고합니다

**핵심 가드레일:**
- 이 단계에서는 **절대 코드를 구현하지 않습니다**
- plan.md 문서만 수정합니다
- 반복 가능합니다 (사용자가 만족할 때까지)

**반영 완료 후:**

```
✏️ 주석 반영 완료! 변경사항:
- {변경 1}
- {변경 2}

plan.md를 다시 확인해주세요.
추가 수정이 있으면 '주석 반영해줘', 괜찮으면 '구현 시작'이라고 말씀해주세요.
```

**여기서 멈추고 사용자 응답을 기다립니다.**

### Step 5: Todo List 생성

사용자가 "구현 시작"이라고 하면, plan.md 끝에 세부 작업 체크리스트를 추가합니다.

**plan.md에 추가되는 체크리스트:**

```markdown
---

## 구현 체크리스트

### Phase 1: {phase 이름}
- [ ] Task 1-1: {구체적인 작업 설명}
- [ ] Task 1-2: {구체적인 작업 설명}

### Phase 2: {phase 이름}
- [ ] Task 2-1: {구체적인 작업 설명}
- [ ] Task 2-2: {구체적인 작업 설명}

### 검증
- [ ] 타입 체크 통과
- [ ] 린트 통과
- [ ] 기존 테스트 통과
```

이 체크리스트는 Step 6에서 구현 진행상황 추적에 사용됩니다.

### Step 6: Implementation (구현)

계획을 기계적으로 실행합니다.

**구현 규칙:**
- plan.md의 상세 변경 계획을 **그대로** 따릅니다
- 각 task 완료 시 plan.md의 체크박스를 `- [x]`로 업데이트합니다
- 모든 task와 phase를 완료할 때까지 멈추지 않습니다
- 불필요한 주석이나 JSDoc을 추가하지 않습니다
- `any`/`unknown` 타입을 사용하지 않습니다
- 기존 패턴과 컨벤션을 준수합니다

**진행 방식:**
1. Phase 순서대로 진행
2. 각 Phase 내 Task를 순서대로 실행
3. Task 완료 시마다 plan.md 체크박스 업데이트
4. 가능하면 typecheck/lint를 주기적으로 실행하여 문제를 조기에 발견

### Step 7: 완료 보고

모든 구현이 완료되면 최종 보고를 출력합니다:

```
✅ Plan & Build 완료!

📖 Research: docs/plan-and-build/research.md
📋 Plan: docs/plan-and-build/plan.md
🔨 구현된 파일: {수정된 파일 목록}

문서는 docs/plan-and-build/에 보존되어 있어 나중에 참고할 수 있습니다.
```

## 상태 아이콘

| 아이콘 | 의미 |
|--------|------|
| ✅ | 완료 |
| 🔄 | 진행중 |
| ⬜ | 시작 전 |

## 중요 사항

1. **의사결정은 사람이 합니다**: AI는 리서치하고, 계획을 세우고, 실행하지만 — 계획 승인은 반드시 사용자가 합니다.
2. **주석 사이클이 핵심입니다**: 사용자가 plan.md에 직접 주석을 달아 피드백하는 과정이 이 워크플로우의 핵심 가치입니다.
3. **구현 전까지 코드를 건드리지 않습니다**: Step 5에서 사용자가 "구현 시작"이라고 할 때까지 코드 파일을 수정하지 않습니다.
4. **문서는 보존됩니다**: research.md와 plan.md는 구현 후에도 삭제하지 않습니다. 나중에 왜 이렇게 구현했는지 참고할 수 있습니다.
5. **기존 문서 재사용**: 이전 세션의 research.md/plan.md가 있으면 이어서 작업할 수 있습니다.
