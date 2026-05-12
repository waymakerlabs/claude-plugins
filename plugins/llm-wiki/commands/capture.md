---
name: capture
description: |
  외부 자료(URL / 메모 / URL+메모 / 여러 자료 묶음)를 받아 자료 단위로 분해·정규화·중복 검출·보안 검사·요약 후 `00. Inbox/`에 md로 적재한다. 분류는 별도(`/llm-wiki:classify`가 다음 schedule에서 처리). intake 계층 — **손실 없이 저장, 자동 판단은 보수적**. Telegram(openclaw 등) 어댑터에서 `claude --print "/llm-wiki:capture {원문}"` 형태로 호출 가능.
allowed-tools:
  - WebFetch
  - Read
  - Write
  - Bash
  - Glob
  - Grep
argument-hint: "[URL 또는 자유 텍스트 — 여러 줄·여러 URL 가능]"
---

# /llm-wiki:capture — 외부 자료 intake (vault 00. Inbox 적재)

## 발동 조건

- 명시 호출: `/llm-wiki:capture <URL 또는 텍스트>`
- 자연어 트리거: "이거 저장해줘 https://..." / "이거 inbox에 넣어줘" / "스크랩해줘 ..."
- 채널 어댑터 호출 (openclaw 등 telegram bot): `claude --print "/llm-wiki:capture {메시지 본문}"`

## 핵심 원칙 (이 intake 계층이 절대 어기지 않는 것)

1. **손실 없이 저장**: 사용자 메모·평가·명령·tracking source 모두 보존. 자동 폐기 금지.
2. **자동 판단 보수적**: 자료 단위 자동 병합 금지(같은 도구 여부는 `same_candidate` 라벨로 표시만, 분리 적재가 기본).
3. **분류 책임 분리**: capture는 *intake*. type/kind/tool/confidence 같은 분류 결정은 [[classify]]가 다음 단계에서 수행.
4. **보안 우선**: URL 안 토큰·인증 정보 redaction. SSRF·malicious URL 검사.
5. **archive-first**: inbox에 적재만. 자동 삭제·이동 금지.
6. **fetch 실패 ≠ 거부**: 사용자가 보낸 맥락 자체가 가치 → 부분 자료라도 inbox 적재 (status: needs-review). `10. Triage`는 명백한 쓰레기/빈 입력/위험 URL만.
7. **atomic write**: 모든 새 파일은 `.tmp` → `mv`. iCloud 부분 동기화 사고 방지.

## 실행 흐름 (Step 1 ~ 11)

### Step 1 — 환경 로드 (read-only)

설정: `~/.claude/wrap-up-config.json` (`obsidianVault`, `llmWikiWorkspace`).

`llmWikiWorkspace` 없으면 vault 안 `60. Topics / 70. Entities / 80. Syntheses` 모두 있는 폴더 자동 탐색 (search.md / classify.md와 동일). config 자동 수정 금지.

### Step 2 — 입력 파싱 (자료 단위 분해)

`$ARGUMENTS`를 다음으로 분해:

1. **URL 추출**: 정규식 `https?://[^\s\)\]\|<>"']+`로 모든 URL 발견. trailing 구두점(`.`, `,`, `;`, `)`) 제거.
2. **자료 단위 분해**:
   - 입력에서 URL 위치를 기준으로 *근접 텍스트 블록*을 그룹핑.
   - 한 자료 = (URL + 직전·직후 비-URL 텍스트). 빈 줄 이상 떨어지면 다른 자료로.
   - URL 없는 텍스트 블록은 *메모만* 자료 (type: tip 후보, classify가 결정).
3. **각 자료에 부여**:
   - `original_url` (URL 자료일 때)
   - `user_note` (URL 주변 메모)
   - `user_endorsement` 감지 키워드: "추천", "참고해보세요", "인상적", "도움", "괜찮은", "좋은" / 영어 "recommend", "great", "useful", "interesting" 등 → `true`. 없으면 `false`.
   - `install_command` 감지: `npx ...`, `npm install`, `pip install`, `brew install`, `git clone`, `curl ... | bash` → 본문에 코드블록으로 보존.
4. **여러 URL이 한 자료인가? 판별**:
   - 기본은 **분리**(URL 1개 = 자료 1개).
   - 강한 근거가 있을 때만 *제안*하고 `same_candidate` 라벨로 표시 (자동 병합 X):
     - repo명/프로젝트명/도메인이 일치 (예: `youtube.com/...BlueKiwi` + `github.com/dandacompany/bluekiwi`)
     - 영상 제목에 repo명 포함
     - 본문 메모가 한 도구를 가리킴 (예: "...블루키위를 소개...")
   - 약한 근거(같은 줄에 메모 + URL 등)는 분리. 사용자가 묶고 싶으면 vault에서 수동 통합.

### Step 3 — 보안 검사 (URL redaction + 위험 패턴)

각 자료의 URL에 대해:

1. **민감 query 감지 + redaction**:
   - 감지 키: `token=`, `key=`, `code=`, `auth=`, `session=`, `access_token=`, `refresh_token=`, `email=`, `phone=`, `password=`, `secret=`, `api_key=`
   - 발견 시 해당 query 값을 `<redacted>`로 치환. 원본도 저장하지 않음.
   - `redaction_applied: true` + `redacted_keys: [token, email, ...]` 메타에 기록.

2. **SSRF/내부 IP 검사**:
   - `localhost`, `127.0.0.1`, `0.0.0.0`, RFC1918 private IP(`10.*`, `172.16~31.*`, `192.168.*`), `.local` 도메인 → **fetch 거부**, inbox 적재도 거부, 사용자에게 경고 회신.

3. **위험 파일 확장자**:
   - URL 끝이 `.exe`, `.bat`, `.scr`, `.com`, `.dmg`(서명 미검증) 등 → fetch 안 함, 사용자 경고 후 메모 형태로만 적재 (`fetch_status: blocked_extension`).

4. **malicious URL heuristics** (간단):
   - 알려진 URL shortener에서 *최종 destination이 unknown*인 경우 → fetch는 시도하되 `unverified_redirect` 메타.
   - typosquatting 의심(`g00gle.com`, `clauded.ai` 등) → 경고 메타.

### Step 4 — URL 정규화 + 중복 검출 (4단계 키)

각 자료에 대해 4단계 키 산출:

1. **`original_url`**: 사용자가 던진 그대로 (redaction 적용 후).
2. **`normalized_url`**:
   - tracking 파라미터 제거: `utm_*`, `?si=`, `?s=`, `fbclid`, `gclid`, `mc_*`, `_ga`, `ref=`
   - `youtu.be/{id}` ↔ `youtube.com/watch?v={id}` 통일 (canonical 형태로)
   - `m.cafe.naver.com` ↔ `cafe.naver.com` 모바일/데스크톱 통일
   - trailing `/` 제거, `http` → `https`, 대소문자 호스트 → 소문자
   - fragment(`#...`) 제거
3. **`canonical_url`**: WebFetch 시 응답의 `<link rel="canonical">` 또는 `<meta property="og:url">`를 사용.
4. **`content_fingerprint`**: `sha256(title + canonical_domain)` 짧은 해시(앞 12자).

**중복 검출**:
- 검색 범위: `00. Inbox/`, `70. Entities/**`, `90. Archive/inbox-processed/**`
- 매칭 전략 (우선순위):
  - `canonical_url` 일치 → **duplicate**
  - `normalized_url` 일치 → **duplicate**
  - `content_fingerprint` 일치 + 도메인 같음 → **possible_duplicate**
  - 그 외 → **new**
- **자동 skip은 `duplicate`(강한 매칭)만**. `possible_duplicate`는 적재하되 frontmatter에 표시 + 결과 회신에 알림.

### Step 5 — Fetch + 메타데이터 수집

각 자료 (new 또는 possible_duplicate)에 대해:

1. **GitHub URL**:
   - 가능하면 `gh api repos/<owner>/<repo>` + README fetch (`gh api repos/<owner>/<repo>/readme`로 base64 → decode).
   - release/issue/PR URL이면 해당 객체 직접 fetch (`gh api`).
   - 실패 시 WebFetch fallback.
2. **YouTube URL**:
   - WebFetch로 페이지 메타 (`og:title`, `og:description`, `og:image`, `og:url`, 채널명).
   - **transcript 추출은 본 sub-command 범위 외** (v1.3 후보). 본문은 OG description으로 시작.
3. **일반 web (news/blog/wiki)**:
   - WebFetch로 본문 + OG 태그.
   - 본문 길이가 500자 미만이면 OG description 보강.
4. **로그인 필요 (m.cafe.naver.com 등)**:
   - fetch 실패 또는 본문이 로그인 페이지 키워드("로그인", "Sign in", 로그인 폼 HTML) 감지.
   - `fetch_status: login_required`, 본문은 *사용자 메모 + URL만* 보존.
   - `summary_source: user_note_only`.

**`fetch_status` enum**:
- `ok`: 본문 정상 추출
- `partial`: 본문 짧음 (OG 보강 사용)
- `og_only`: 본문 추출 실패, OG만 사용
- `login_required`: 로그인 페이지로 리디렉트
- `failed`: 모든 시도 실패 (네트워크/404/timeout)
- `redacted`: 민감 토큰 감지 → fetch 안 함
- `blocked_extension`: 위험 확장자 → fetch 거부
- `blocked_ssrf`: 내부 IP/SSRF 의심 → fetch 거부

### Step 6 — 요약 생성

각 자료마다:

- **제목 결정** (우선순위): canonical title → og:title → fetch한 `<title>` → URL의 last path segment → 사용자 메모 첫 20자.
- **요약 본문 1-2문단** (3-5문장):
  - `fetch_status: ok | partial`이면 본문 기반 (LLM 자체 추출).
  - `og_only`면 OG description 기반.
  - `login_required | failed | blocked`면 사용자 메모만 + 정황 설명.
- **summary_source** 메타에 출처 표시 (`body | og | user_note | mixed`).
- 길이 가이드: 300~600자. 너무 짧으면 OG로 보강, 너무 길면 핵심만.

### Step 7 — 파일명 생성 (충돌 처리)

표준 형식: `{YYYY-MM-DD} {짧은 식별자}.md`

**짧은 식별자**:
- GitHub: repo명 (예: `bluekiwi`, `gstack-codex`). 소유자 다른 동명 repo는 `{owner}-{repo}`.
- YouTube: 영상 title의 첫 핵심 단어들 (3-5어, 한국어/영어 그대로).
- 뉴스/블로그: 기사 제목 첫 30-40자, 특수문자 제거.
- 메모만: 메모 첫 20-30자.

**충돌**:
- `{기본명}.md` 존재 → `{기본명} (2).md`, `(3).md` ...
- `00. Inbox/` + `70. Entities/**` + `90. Archive/inbox-processed/**` 모두 검색.

### Step 8 — frontmatter 작성 (intake 메타)

inbox 단계 frontmatter는 *intake 메타만*. type/kind/tool/confidence는 classify가 채움.

```yaml
---
captured_at: 2026-MM-DDTHH:MM:SS+09:00
captured_by: /llm-wiki:capture v1.2.0
captured_via: cli | openclaw | unknown   # 인입 채널 (인자/환경에서 추정)
original_url: https://...
normalized_url: https://...
canonical_url: https://...               # null 가능
content_fingerprint: <12자 해시>
fetch_status: ok | partial | og_only | login_required | failed | redacted | blocked_extension | blocked_ssrf
dedupe_status: new | duplicate | possible_duplicate
duplicate_of: "[[기존 파일 wikilink]]"   # duplicate 또는 possible_duplicate일 때만
source_type: github | youtube | blog | news | community | wiki | docs | release | other
user_note: |                             # 사용자가 같이 던진 메모
  ...
user_endorsement: true | false           # 추천·평가 키워드 감지
install_command: |                       # 사용자 메모에 명령 있을 때만
  ...
summary_source: body | og | user_note | mixed
same_candidate: "[[다른 자료 wikilink]]" # 강한 근거의 묶음 후보일 때만
redaction_applied: false                 # true면 redacted_keys 함께
redacted_keys: [token, email, ...]       # redaction_applied true일 때만
tags: [intake]
lifecycle: new
---
```

### Step 9 — 본문 작성

```markdown
# {제목}

> 원본 URL: {original_url (redaction 후)}
> {canonical_url과 다르면 canonical도 표시}
> 캡처 일시: {YYYY-MM-DD HH:MM KST}
> 출처 채널: {captured_via}

## 요약

{1-2문단 요약 — summary_source에 따라 본문/OG/메모 기반}

## 사용자 메모

{user_note이 있으면}

## 설치/사용 명령

{install_command이 있으면 코드블록}

## 메타

- fetch_status: {값}
- dedupe_status: {값}
- source_type: {값}
- user_endorsement: {값}
- same_candidate: {있으면 wikilink}

## 비고

{redaction / login_required / SSRF 거부 등 운영 정보}
```

### Step 10 — Atomic write + 결과 누적

```bash
# 각 자료
TMP="{workspace}/00. Inbox/.{filename}.tmp"
DEST="{workspace}/00. Inbox/{filename}.md"

# Write 도구로 TMP 작성 → Bash mv
mv "$TMP" "$DEST"
```

처리 결과를 다음 카운터로 누적:
- `captured_new`: dedupe_status=new 적재 수
- `captured_dup`: duplicate (skip)
- `captured_possible_dup`: possible_duplicate 적재
- `captured_needs_review`: login_required / failed / og_only 등 보강 필요
- `captured_blocked`: SSRF/blocked_extension 등 거부
- `captured_tip`: URL 없는 메모만 자료

### Step 11 — 결과 회신 (간결 운영 신호)

기본 1줄:
```
Captured: {new}건 적재, {dup}건 중복skip, {possible_dup}건 의심중복, {needs_review}건 보강필요, {blocked}건 거부
```

자료 수가 ≥2이거나 *예외 상황(중복/실패/거부)* 있으면 짧은 목록 추가:
```
- ✅ new      → 00. Inbox/{file1}.md
- ⚠️  needs-review → 00. Inbox/{file2}.md  (login_required)
- 🔁 duplicate    → skip (matches [[기존 파일]])
- 🚫 blocked      → SSRF 의심 (URL 미저장)
```

**Telegram 회신 (openclaw에서 호출 시)**: 본 1줄 + 목록만. 본문 요약 X — 사용자는 vault에서 확인.

## Mode 비교 (capture는 단일 모드)

capture는 *intake*라 dry-run 모드 없음. inbox에 적재가 본질. 다만 다음 안전 장치:

| 상황 | 동작 |
|---|---|
| 동일 URL 다중 입력 (한 호출에 같은 URL 2회) | 1번만 처리, 나머지 silent skip |
| 사용자 명시적 강제 재적재 요청 | `--force` 인자 v1.3 후보 (현재는 미지원) |
| Lock 충돌 (classify가 도는 중) | capture는 lock 사용 안 함 (inbox 적재만, classify와 비충돌). 단 `.classify.lock`이 있으면 잠시 대기는 안 함, 그대로 적재. classify가 다음 사이클에 잡음. |
| 빈 입력 | 즉시 종료 + "입력 없음" 회신 |

## 응답 톤

- 한글 존댓말.
- 기본 회신은 §Step 11 형식 (간결).
- 보안 redaction 발생 시 ★ Insight로 강조.
- 마지막에 진행률 1줄 (사용자 호출 시).

## 절대 하지 않는 것

- **사용자 메모·평가·명령 자동 폐기** (손실 없이 저장)
- **자료 단위 자동 병합** (`same_candidate` 라벨만, 분리 적재가 기본)
- **민감 토큰 query 그대로 저장** (redaction 필수)
- **SSRF/internal IP fetch 시도** (블록)
- **`~/.claude/wrap-up-config.json` 자동 수정** (search.md와 동일 원칙)
- **inbox 외 폴더 자동 쓰기** (classify의 책임)
- **dedupe possible_duplicate를 자동 skip** (적재 + 알림)
- **로그인 페이지를 본문으로 잘못 저장** (login_required 분기 필수)

## 트러블슈팅

| 증상 | 원인 | 대응 |
|---|---|---|
| 모든 fetch가 실패 | 네트워크 / iCloud 동기화 문제 | 사용자 메모만으로라도 적재, needs-review |
| 같은 자료 반복 적재 | normalization 정책 미반영 | 4단계 키 재계산 후 dedupe_status 재산정 |
| Telegram 회신이 너무 김 | 결과가 N건 다수 | 1줄 요약 + 핵심 예외만 (전체 목록은 vault daily에) |
| Redaction이 과민 | 정상 query를 토큰으로 오인 | 알려진 키 목록(§Step 3.1)만 redaction. 추가 false positive 시 사용자가 vault 수동 보정 |
| URL 추출 실패 (이상한 형식) | 정규식 한계 | 입력 텍스트 전체를 메모만 자료로 적재 (URL 없음) |

## 입력 패턴 16개 매트릭스 (참조)

| 패턴 | 처리 |
|---|---|
| A. 단순 URL 1개 | fetch + 1 inbox md |
| B. 메모 + URL | user_note 보존, 1 inbox md |
| C. URL + 메모 | 동일 |
| D. 한 줄 URL + 메모 | URL 추출 + 잔여 텍스트 메모 |
| E. 묶음 — 같은 도구 여러 URL | **분리 적재 + same_candidate 라벨** (자동 병합 X) |
| F. 묶음 — 설치 명령 포함 | install_command 본문 코드블록 보존 |
| G. 사용자 평가·추천 | user_endorsement: true |
| H. tracking 파라미터 | 정규화 시 제거, 원본은 본문 보존 |
| I. 중복 (이미 vault) | duplicate → skip, possible_duplicate → 적재+알림 |
| J. 스크린샷 + 메모 | 이미지는 처리 외, 메모만 → tip 후보 (URL 없음) |
| K. 코드 스니펫 복붙 | URL 없음 → tip 후보 |
| L. X/Twitter/Reddit thread | 단일 URL로 처리, og:description 기반 |
| M. Discord/Slack 복붙 | URL 없음 → 본문 그대로 메모 적재 |
| N. PDF 논문 링크 | URL 단일 처리. PDF 본문 추출은 v1.3 후보 |
| O. 긴 터미널 로그 | URL 없음 → tip 또는 reject(`10. Triage`로는 안 보냄) |
| P. 여러 URL이 *비교/대안* 관계 | 분리 적재가 기본 (E와 같은 처리, same_candidate 표시 안 함) |

## 관련 자료

- [[LLM Wiki 재구축 마이그레이션 계획]] §1.4 (사용자 명시 요구), §2 (입력 자료 6유형)
- [[classification rules]] v1.1 — type/kind/tool/medium enum
- [[classification prompt]] v1.1 — classify가 사용하는 정본
- [[machines/home-macmini]] — 자동 호출 호스트
- [[promotion candidates]] — 후보 신호 누적 (classify 책임)

## 확장 후보 (다음 버전)

- v1.3: YouTube transcript 추출 (별도 CLI 통합)
- v1.3: PDF 본문 추출
- v1.3: `--force` 인자 (중복 강제 재적재)
- v1.3: 이미지 OCR (Tesseract 또는 Claude vision)
- v1.4: 사용자별 인입 채널 통계 (telegram / cli / slack 등)
