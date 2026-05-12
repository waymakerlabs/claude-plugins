---
name: classify
description: |
  LLM Wiki inbox 자동 분류기. `00. Inbox/`에 던져진 새 자료를 카파시 LLM Wiki 4계층(Sources/Topics/Entities/Syntheses) 구조에 따라 자동 분류해 적절한 폴더로 이동한다. 매일 KST 01:00 home-macmini schedule에서 무인 호출 또는 사용자 수동 호출. dry-run 모드는 plan만 daily에 기록(파일 변경 0건), live 모드는 실제 분류·이동·archive·다이제스트 수행. 마이그레이션 계획 §8 + classification rules v1.1 + classification prompt v1.1 정책 그대로 구현.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
argument-hint: "[--mode dry-run|live] (기본: dry-run, 안전)"
---

# /llm-wiki:classify — LLM Wiki inbox 자동 분류기

## 발동 조건

- 명시 호출: `/llm-wiki:classify` 또는 `/llm-wiki:classify --mode live`
- 자연어 트리거: "inbox 분류해줘" / "오늘 inbox 처리해줘" / "ingest 돌려줘"
- **무인 자동**: home-macmini schedule이 매일 KST 01:00에 `claude --print "/llm-wiki:classify --mode dry-run"` 호출

## 핵심 원칙 (이 분류기가 절대 어기지 않는 것)

1. **archive-first**: inbox 원본은 절대 자동 삭제하지 않음. 처리 후 `90. Archive/inbox-processed/{YYYY-MM-DD}/`로 이동.
2. **Topic / Synthesis 자동 생성 금지**: 후보 신호만 `promotion candidates.md`에 append.
3. **atomic write**: 모든 새 파일은 `.tmp` 작성 후 `mv`. iCloud 부분 동기화 사고 방지.
4. **mode=dry-run이 기본값**: 인자 미지정 시 dry-run. live는 명시 지정해야 작동.
5. **wikilink alias 형식**: `[[전체경로/파일|표시]]`만. 백틱 감싸기 금지.
6. **frontmatter enum 신규 값 금지**: classification rules v1.1에 정의된 값만 사용.

## 실행 흐름 (마이그레이션 계획 §8 + §8.4 안전 정책 그대로)

### Step 1 — 환경 로드 (read-only)

설정 파일: `~/.claude/wrap-up-config.json`.

```json
{
  "obsidianVault": "/Users/peter/Library/Mobile Documents/iCloud~md~obsidian/Documents/Peter's 2nd Brain",
  "llmWikiWorkspace": "006. 레제 작업장"
}
```

`llmWikiWorkspace` 없으면 vault 안에서 `60. Topics / 70. Entities / 80. Syntheses` 모두 있는 폴더 자동 탐색 (search.md와 동일 정책). **자동 저장하지 않음**.

### Step 2 — Mode 확인

- `$ARGUMENTS` 파싱:
  - `--mode dry-run` 또는 미지정 → **dry-run** (안전 기본값)
  - `--mode live` → **live**
- 그 외 값은 거부하고 사용자에게 알림.

### Step 3 — Lock 검사 (Bash)

```bash
LOCK="{workspace}/99. Workspace Ops/.ingest.lock"
```

- Lock 존재 → 이전 실행이 비정상 종료된 가능성. ingest log에 기록 후 종료. 사용자 수동 해제 필요.
- Lock 없음 → 즉시 생성 (atomic write: `.tmp` → `mv`):
  ```yaml
  started_at: 2026-MM-DDTHH:MM:SS+09:00
  pid: $$
  host: $(hostname)
  mode: dry-run | live
  ```

### Step 4 — Inbox 스캔 + mtime 안전 검사

- `{workspace}/00. Inbox/` 내 모든 파일 목록 + 각 mtime 확인 (Bash `stat`)
- 5분 이내 수정된 파일이 있으면 → **iCloud 동기화 진행 중 가능성**. ingest log에 "30분 대기 후 재시도"로 기록 후 종료. 사용자가 다음 호출 시 재시도.
- 비어 있으면 → daily에 "처리 0건" 기록 후 Step 12로.

### Step 5 — iCloud lazy-download 강제 트리거

```bash
find "{workspace}/00. Inbox" -type f \( -name "*.icloud" -o -size 0 \) -exec brctl download {} \;
```

또는 각 파일을 `cat > /dev/null`로 한 번 읽어 강제 동기화. 5초 대기 후 실제 크기 재검증. 0이면 해당 파일은 `10. Triage/`로 이동(또는 dry-run plan 기록) + ingest log.

### Step 6 — 분류기 prompt 로드

```bash
PROMPT_PATH="{workspace}/99. Workspace Ops/classification prompt.md"
```

Read 도구로 본문을 로드. 이 문서의 `## SYSTEM` 블록이 분류 판정용 instruction. **이 본문이 단일 진실 원천**이며, 본 plugin instruction은 *흐름·정책*만 담음.

### Step 7 — 각 inbox 파일 분류 판정

각 파일에 대해:

1. **파일 내용 + URL 메타데이터 읽기** (Read 도구)
2. **분류기 prompt에 따라 JSON 결정** — Claude 자체가 prompt §"결정 알고리즘"의 10단계를 따라 판정:
   - `type` (source | entity, topic/synthesis는 금지)
   - `kind` (tool | skill | plugin | repo | site | tip | article | video | doc)
   - `tool` (배열, 정의된 enum만)
   - `medium` / `tags` / `title` / `url` / `summary`
   - `confidence` (0.0~1.0)
   - `target_folder` / `filename`
   - `related_topics` / `related_entities` (vault에 *실제 존재*하는 항목만, wikilink alias 형식)
   - `promotion_signals` (topic_candidate / synthesis_candidate / null)
   - `rationale` (1-2문장)
3. **confidence별 target_folder 조정**:
   - ≥ 0.90 → 정식 폴더, status: `ready`
   - 0.70 ~ 0.89 → 정식 폴더, status: `review-suggested`
   - < 0.70 → `15. Needs Review/`, status: `needs-review`
4. **거부 사례 처리**:
   - 빈 파일 / 바이너리 / URL 죽음 / lazy-download 실패 → `target_folder: "10. Triage"`, type: `reject`

### Step 8 — Mode별 처리

#### dry-run 모드 (기본값)

- **vault에 파일 변경 0건**.
- 모든 판정 결과를 daily 다이제스트에 plan 형식으로 기록:
  ```
  [plan] {filename} → {target_folder}/{new_filename}.md (conf {confidence})
    - type: {type}, kind: {kind}, tool: {tool}
    - 근거: {rationale}
    - 신규 wikilink: {related_topics 백링크 추가 예정 N건}
    - promotion_signals: {신호 또는 없음}
  ```
- inbox 원본은 inbox에 그대로.

#### live 모드

각 판정 결과에 대해:

1. **새 파일 작성** (atomic write):
   - frontmatter (마이그레이션 계획 §6 표준) + 본문 + 분류기 출력 summary
   - 작성 위치: `{workspace}/{target_folder}/{filename}.tmp` → `mv` → `{filename}.md`
   - status: `ready` | `review-suggested` | `needs-review` (confidence에 따라)
2. **관련 Topic의 백링크 자동 추가**:
   - 각 `related_topics` 항목의 본문 끝 "## 관련 Entity" 또는 "## 관련 Source" 섹션에 `- [[새 파일 경로|표시]]` append (Edit 도구).
   - 섹션이 없으면 생성.
3. **inbox 원본 → archive 이동**:
   ```bash
   ARCHIVE_DIR="{workspace}/90. Archive/inbox-processed/$(date +%Y-%m-%d)"
   mkdir -p "$ARCHIVE_DIR"
   mv "{원본}" "$ARCHIVE_DIR/"
   ```

### Step 9 — promotion candidates 누적

`promotion_signals` 있는 항목을:

```markdown
## {YYYY-MM-DD} (자동 분류기)

- **Topic 후보 신호**: `{키워드}` — 자료 `{새 파일 wikilink}` (5+번째 등장 시 정식 후보로 격상)
- **Synthesis 후보 신호**: `{A vs B}` — 자료 `{새 파일 wikilink}`
```

`{workspace}/99. Workspace Ops/promotion candidates.md`의 "## 진행 중" 섹션에 append.

### Step 10 — daily 다이제스트 작성

위치: `{workspace}/99. Workspace Ops/daily/{YYYY-MM-DD}.md`

```markdown
---
title: "Daily {YYYY-MM-DD} — inbox ingest ({mode})"
date: {YYYY-MM-DD}
type: daily
mode: dry-run | live
tags: [daily, ingest]
---

# {YYYY-MM-DD} — inbox ingest

## 처리 요약

- 총 입력: {N}건
- 확정 처리(≥0.90): {N1}건
- 보강 권장(0.70~0.89, review-suggested): {N2}건
- 사용자 검토 필요(<0.70, needs-review): {N3}건
- 거부(10. Triage): {N4}건

## 분류 결과 (kind별 분포)

| kind | 건수 |
|---|---|
| skill | ... |
| repo | ... |
| ... | ... |

## plan 또는 실제 변경 목록

(Step 8의 plan/실제 결과)

## promotion 후보 신호

(Step 9 누적분 — 없으면 "없음")

## 충돌·에러

(lock 잔류 / mtime 대기 / lazy-download 실패 / enum 위반 등)

## 통계

- 처리 시간: {초}
- confidence 평균: {값}
- 분포: ≥0.90 {N}건 / 0.70~0.89 {N}건 / <0.70 {N}건
```

### Step 11 — ingest log 1줄 append

`{workspace}/99. Workspace Ops/ingest log.md`에 append:

```
{YYYY-MM-DD HH:MM:SS} | mode={mode} | 처리 {N}건 | 확정 {N1} 보강 {N2} 검토필요 {N3} 거부 {N4} | 후보신호 {S}건 | 충돌 {E}건
```

### Step 12 — Lock 제거

`{workspace}/99. Workspace Ops/.ingest.lock` 삭제.

### Step 13 — 종료 보고

사용자(또는 schedule log)에게 짧은 한 문단:

```
✅ inbox ingest {mode} 완료

- 처리 {N}건 ({N1} 확정 / {N2} 보강 / {N3} 검토필요 / {N4} 거부)
- daily: {daily 파일 경로}
- 후보 신호: {S}건 (promotion candidates에 누적)
- 처리 시간: {초}
```

## Mode 비교 표 (요약)

| 단계 | dry-run | live |
|---|---|---|
| Step 1~7 (스캔·판정) | 동일 ✅ | 동일 ✅ |
| Step 8 새 파일 작성 | ❌ plan만 | ✅ atomic write |
| Step 8 백링크 추가 | ❌ plan만 | ✅ Edit |
| Step 8 inbox 원본 archive 이동 | ❌ (보류) | ✅ |
| Step 9 promotion candidates | ❌ plan만 | ✅ append |
| Step 10 daily | ✅ plan 형식 | ✅ 실제 결과 |
| Step 11 ingest log | ✅ `mode=dry-run` | ✅ `mode=live` |
| Step 12 Lock 해제 | ✅ | ✅ |

## 자연어 트리거 응답 톤

- 한글 존댓말.
- 결과 보고는 §Step 13 형식.
- ★ Insight 블록 사용 가능 (특이 사항·경고·후보 신호 강조 시).
- 마지막에 진행률 1줄.

## 절대 하지 않는 것

- **inbox 원본 자동 삭제** (archive-first 원칙)
- **Topic / Synthesis 자체 생성** (후보 신호만 promotion candidates에 누적)
- **frontmatter enum 신규 값 추가** (classification rules v1.1 정의값만)
- **wikilink 백틱 감싸기** / 짧은 `[[파일명]]` 형식
- **`~/.claude/wrap-up-config.json` 자동 수정** (search.md v1.0.1과 동일 원칙)
- **Lock 우회** — Lock 잔류 시 종료, 무리하게 진행하지 않음
- **dry-run에서 vault 파일 변경** (어떤 경우에도)

## 트러블슈팅

| 증상 | 원인 | 대응 |
|---|---|---|
| Lock 파일 잔류 | 이전 실행 비정상 종료 | 사용자가 수동으로 `.ingest.lock` 삭제 후 재실행 |
| Inbox mtime 5분 이내 변경 | iCloud 동기화 진행 중 | 30분 대기 후 schedule이 자동 재시도 (최대 3회) |
| lazy-download 실패 | iCloud 미동기화 | 파일을 `10. Triage/`로 이동(또는 plan 기록) |
| confidence 평균이 낮음 (예: <0.75) | 분류기 prompt 보완 필요 | 사용자가 `classification prompt.md` 갱신 후 재실행 |
| enum 위반 출력 | 분류기 prompt 미준수 | 해당 항목 거부 + Triage 이동. enum 검증 코드가 안전장치 |

## 관련 자료

- [[LLM Wiki 재구축 마이그레이션 계획]] §8 (자동화 흐름) / §8.4 (안전 정책)
- [[classification rules]] v1.1 (분류 규칙 정본)
- [[classification prompt]] v1.1 (LLM 시스템 프롬프트 정본)
- [[S6.5 dry-run 운영 설계]] (1주 검증 절차)
- [[promotion candidates]] (후보 신호 누적 위치)
- [[machines/home-macmini]] (자동화 호스트 정보)

## 확장 sub-command 후보 (다음 버전)

- `/llm-wiki:audit` — review-suggested 큐 일괄 점검 (v1.2 후보)
- `/llm-wiki:promote` — promotion candidates 검토·승격 안내 (v1.3 후보)
- `/llm-wiki:configure` — 설정 명시 호출 (v1.1 후보, search.md에서 분리 예고)
