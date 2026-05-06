---
name: search
description: LLM Wiki 4계층 회상 검색. 사용자가 "vault에서 X 관련 자료 보여줘", "○○ 스크랩 리스트", "○○ 자료 비교"처럼 회상 요청을 할 때 호출. 키워드를 받아 Obsidian vault의 60. Topics / 70. Entities / 80. Syntheses / 20. Raw Sources/derived 등에서 검색하고 4계층 순으로 그룹핑해 보여줍니다.
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
argument-hint: "[검색 키워드 — 한글·영문 둘 다 가능, 콤마로 여러 개]"
---

# /llm-wiki:search — LLM Wiki 4계층 회상 검색

사용자가 던진 키워드로 Obsidian vault의 LLM Wiki 폴더를 회상해, 카파시 LLM Wiki 4계층(Sources / Topics / Entities / Syntheses) 순으로 정리합니다.

## 발동 조건

- 명시 호출: `/llm-wiki:search <키워드>`
- 자연어 트리거 (이 plugin이 활성화되어 있을 때):
  - "vault에서 ○○ 자료 보여줘"
  - "레제 작업장에서 ○○ 검색"
  - "○○ 관련 스크랩 리스트"
  - "○○ 자료 비교 정리"

## 실행 흐름

### Step 1: 설정 확인 — vault 위치 (read-only)

설정 파일: `~/.claude/wrap-up-config.json` (obsidian-documents / wrap-up plugin과 공유).

```json
{
  "obsidianVault": "/path/to/obsidian/vault",
  "llmWikiWorkspace": "006. 레제 작업장"
}
```

**중요**: 이 명령어는 **read-only**다. 어떤 경우에도 `~/.claude/wrap-up-config.json`을 자동으로 수정하지 않는다. 사용자 시스템 설정은 사용자가 직접 결정한다.

**`obsidianVault`만 있고 `llmWikiWorkspace`가 없으면**:

vault 안에서 다음 경로 패턴이 모두 존재하는 폴더를 *임시 메모리*에서만 자동 탐색:
- `*/60. Topics/`
- `*/70. Entities/`
- `*/80. Syntheses/`

위 3개가 모두 존재하는 폴더가 1개면 그것을 본 호출에 한해 LLM Wiki workspace로 사용. 여러 개면 AskUserQuestion으로 사용자에게 1회 선택 받기 (config 저장 안 함). 후보가 0개면 사용자에게 안내하고 종료.

응답 마지막에 다음 안내 1줄 추가:

> 💡 매번 자동 탐색을 피하려면 `~/.claude/wrap-up-config.json`에 다음 줄을 직접 추가하세요: `"llmWikiWorkspace": "{탐색된 폴더명}"`

**설정 파일 자체가 없으면**:

AskUserQuestion으로 vault 경로를 임시로 받아 본 호출만 처리. config 자동 생성하지 않음. 응답 마지막에 wrap-up 또는 obsidian-documents plugin 셋업을 권유.

**`llmWikiWorkspace`가 이미 설정되어 있으면**:

그 값을 그대로 사용. 자동 탐색·수정 일체 안 함.

### Step 2: 검색 키워드 정규화

- argument-hint로 받은 키워드를 정리.
- 한글 키워드면 영문 동의어도 함께 검색 (예: "하네스" → "harness", "회상" → "recall").
- 동의어 매핑이 모호하면 사용자가 입력한 그대로 단일 검색.

### Step 3: vault 검색 (Bash + Python)

검색 범위:
1. `60. Topics/`
2. `70. Entities/` (하위 tools / plugins / skills / repos / sites / tips 모두)
3. `80. Syntheses/`
4. `20. Raw Sources/derived/`
5. `30. Briefs/` (legacy 보존, 매칭되면 보여주기)
6. `40. Research/` (legacy 보존, 매칭되면 보여주기)
7. `90. Archive/` (원문 1차 자료)

권장 구현: Python 스크립트(공백 경로 안전 처리). 예시:

```python
import os, re, glob

base = "{vault}/{llmWikiWorkspace}"
search_dirs = ["60. Topics", "70. Entities", "80. Syntheses",
               "20. Raw Sources/derived", "30. Briefs", "40. Research",
               "90. Archive"]
keywords = [...]  # 정규화된 키워드 (한글 + 영문 동의어)

matches = []
for d in search_dirs:
    full = os.path.join(base, d)
    if not os.path.isdir(full): continue
    for path in glob.glob(f"{full}/**/*.md", recursive=True):
        if path.endswith("_Entity Map.md"): continue
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
        text_low = text.lower()
        if any(k.lower() in text_low for k in keywords):
            # frontmatter title 추출, 카테고리 분류
            ...
            matches.append((category, path, title, hit_keyword, snippet))
```

### Step 4: 결과 그룹핑 (4계층 순)

```
1. 80. Syntheses (결론·비교)
2. 60. Topics (운영 관점)
3. 70. Entities (제품 사실) — kind별 sub-grouping (tools / plugins / skills / repos / sites)
4. 20. Raw Sources/derived (정제 노트)
5. 30. Briefs / 40. Research (legacy, 매칭 시만)
6. 90. Archive (원문)
```

### Step 5: 출력 형식

```markdown
## {키워드} 회상 결과

매칭 건수: {N}건

### 그룹 1 — Synthesis (결론·비교)

| 자료 | 핵심 |
|---|---|
| [제목](상대경로) | 한 줄 요약 |

### 그룹 2 — Topic (운영 관점)
...

### 그룹 3 — Entity (제품 사실)
**tools (M건)** / **plugins** / **skills** / **repos** / **sites**
...

### 그룹 4 — derived / Archive (원문·해설)
...

## 추천 진입 순서

```
1차 (개념): {원문 핵심 자료}
2차 (결론): {Synthesis}
3차 (도구): {핵심 Entity 1-2개}
4차 (운영): {Topic의 운영 관점 섹션}
```

## ★ 회상 품질 자기점검

- **누락 후보**: (사용자가 떠올린 자료 중 안 잡혔을 가능성 — frontmatter `tags:` 부족 의심)
- **노이즈**: (단순 단어 매칭으로 들어온 무관 자료)
- **광의 후보**: (단어는 안 잡혔지만 구조적으로 같은 영역인 entity)
- **tag 보강 제안**: (자주 함께 떠오르는 키워드를 frontmatter에 추가하면 다음 회상이 더 정확해질 entity)
```

### Step 6: 결과가 30건 이상이면

핵심 그룹만 표로 보여주고, 나머지는 폴더별 카운트로 압축:

```
## 추가 매칭 (요약)

- 30. Briefs: 6건 (legacy 보존, 본문 검토 시 별도 요청)
- 90. Archive: 5건 (원문 1차 자료)
```

전체 리스트가 필요한지 사용자에게 묻기.

## 응답 톤

- 한글 존댓말.
- ★ Insight 블록 활용 (회상 품질 자기점검 + 광의 후보 + tag 보강 제안).
- 마크다운 링크는 클릭 가능한 형식으로 (vault 상대경로).

## 절대 하지 않는 것

- 자동 분류 정정 (회상만 — vault 파일 변경 0건).
- frontmatter 임의 수정.
- 매칭 자료를 다른 폴더로 이동.
- **`~/.claude/wrap-up-config.json` 자동 생성·수정** (read-only 원칙).
- 사용자 시스템 설정 파일 어떤 형태든 자동 수정.

설정 변경이 필요하면 사용자가 직접 편집하거나, 별도 `/llm-wiki:configure` sub-command(v1.1 후보)를 통해 명시 호출로만 진행.

## 확장 sub-command 후보 (다음 버전)

- `/llm-wiki:configure` — `~/.claude/wrap-up-config.json` 갱신을 사용자 명시 호출로만 진행 (자동 저장 금지 원칙)
- `/llm-wiki:promote` — promotion candidates 누적 후보 검토 + 승격 안내
- `/llm-wiki:audit` — review-suggested 큐 일괄 점검
- `/llm-wiki:classify` — inbox 새 자료 1건 분류 (수동 호출 PoC)

## 비고

- LLM Wiki 4계층 구조는 카파시 *"Obsidian is the IDE, LLM is the programmer, wiki is the codebase"* 모델 기반.
- 본 plugin은 vault 회상이 핵심이며, vault 변경은 별도 plugin으로 분리.
- workspace 안의 폴더 번호 prefix(60./70./80./20.)는 검색 시 그대로 처리.
