# llm-wiki

> LLM Wiki 회상·분류 도우미. Obsidian vault에 누적한 4계층 LLM Wiki(Topics / Entities / Syntheses / Sources)에서 키워드로 자료를 회상하고 비교 정리합니다.

## Sub-commands

| 명령 | 동작 |
|---|---|
| `/llm-wiki:search <키워드>` | 4계층 회상 검색 + 자기점검 리포트 |

(추가 sub-command는 다음 버전에서: `promote`, `audit`, `classify`)

## 자연어 트리거 예시

이 plugin이 활성화되어 있으면 슬래시 명령 없이도 다음과 같은 표현에 반응합니다:

- "vault에서 하네스 도구 관련 자료 보여줘"
- "Codex와 Claude Code 협업 자료 비교해줘"
- "AI Browser Agent 관련 스크랩 인벤토리"
- "레제 작업장에서 Antigravity 검색"

## 출력 형식

1. 매칭 건수 한 줄 요약
2. 의미 그룹별 표 (Synthesis → Topic → Entity → derived/Archive 4계층)
3. 추천 진입 순서 (3-5단계)
4. ★ 회상 품질 자기점검 (누락 / 노이즈 / 광의 후보 / tag 보강 제안)

## 설정

`~/.claude/wrap-up-config.json`을 obsidian-documents / wrap-up plugin과 공유:

```json
{
  "obsidianVault": "/Users/peter/Library/Mobile Documents/iCloud~md~obsidian/Documents/Peter's 2nd Brain",
  "llmWikiWorkspace": "006. 레제 작업장"
}
```

`llmWikiWorkspace`가 없으면 첫 호출 시 vault 안의 `60. Topics / 70. Entities / 80. Syntheses` 3개 폴더가 모두 있는 위치를 자동 탐색해 채택합니다.

## 검색 범위

```
{vault}/{llmWikiWorkspace}/
├── 60. Topics/                ← 1순위 (운영 관점)
├── 70. Entities/              ← kind별 sub-grouping
│   ├── tools, plugins, skills, repos, sites, tips
├── 80. Syntheses/             ← 결론·비교
├── 20. Raw Sources/derived/   ← 정제 노트
├── 30. Briefs/                ← legacy (매칭 시만)
├── 40. Research/              ← legacy (매칭 시만)
└── 90. Archive/               ← 원문 1차 자료
```

## 절대 하지 않는 것

- 자동 분류 정정 (회상만 — vault 파일 변경 0건)
- frontmatter 임의 수정
- 매칭 자료의 위치 변경

## 설계 원칙

- **회상의 본질 = 카파시 LLM Wiki 4계층 정렬** (Sources → Topics → Entities → Syntheses).
- **노이즈 검출 가시화**: 단순 단어 매칭으로 잘못 들어온 자료를 사용자가 즉시 알 수 있도록.
- **광의 후보 명시**: 단어는 안 잡혔지만 구조적으로 같은 영역인 entity를 별도로 알림 → tag 보강 후보 식별.

## 라이선스

MIT (waymakerlabs).
