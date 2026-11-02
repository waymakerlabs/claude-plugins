---
name: project-setup
description: >-
  Bootstrap the current folder as a project. Creates a private GitHub repo with gh when the folder is not a
  git repo or has no remote (asks once to confirm owner), sets up docs/ with a fixed folder set and
  docs/index.md as the single index of every document (back-fills the index when docs/ already exists),
  creates the milestone ledger docs/milestones/README.md (IDs M{plan}-{nn}), and adds an idempotent
  docs/milestone rules section to the project CLAUDE.md (and AGENTS.md if present). Triggers: "/helpai:project-setup",
  "프로젝트 셋업해줘", "프로젝트 초기화", "project init", "docs 구조 잡아줘". Not for: global ~/.claude settings,
  creating a project's CLAUDE.md content from scratch (use /init), or planning milestones (only the ledger is created).
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
---

# helpai: project-setup

현재 작업 폴더(이하 "프로젝트")를 다음 상태로 만든다. 각 단계는 **이미 되어 있으면 건너뛰고**, 다시 실행해도
결과가 같아야 한다(idempotent).

1. git repo이고 GitHub private remote가 연결돼 있다.
2. `docs/`에 고정 폴더 세트와 `docs/index.md`가 있고, index가 docs 안의 모든 문서를 가리킨다.
3. `docs/milestones/README.md` 원장이 있다.
4. 프로젝트 `CLAUDE.md`(있으면 `AGENTS.md`도)에 문서 규칙 섹션이 있다.

이 스킬과 같은 폴더의 파일:
- `references/docs-layout.md` — 고정 폴더 세트·상태 enum의 **진본**. 폴더 목록을 여기서 읽는다(이 문서에 하드코딩하지 않는다).
- `templates/index.md` — `docs/index.md` 템플릿
- `templates/milestones-ledger.md` — `docs/milestones/README.md` 템플릿
- `templates/claude-rules.md` — CLAUDE.md에 넣을 규칙 섹션(마커 포함)

## 금지 사항

- 기존 파일을 삭제하거나 옮기지 않는다. 고정 세트에 맞지 않는 폴더도 그대로 두고 index 「기타」에 등재한다.
- `git add -A` / `git add .` / `git add -u` / `git commit -a`를 쓰지 않는다. 항상 경로를 명시해 스테이징한다.
- 비밀값으로 보이는 파일을 커밋하지 않고, 그 내용을 출력하지 않는다(파일 이름만 보고한다).
- public repo를 만들지 않는다. 항상 `--private`.
- 사용자 확인 없이 GitHub repo 생성·commit·push를 하지 않는다.

## 0. 상태 점검

다음을 한 번에 확인하고 결과를 짧게 표로 보고한다.

```bash
pwd
basename "$PWD"
git rev-parse --is-inside-work-tree 2>/dev/null && git rev-parse --show-toplevel
git remote -v 2>/dev/null
git log --oneline -1 2>/dev/null
git status --short 2>/dev/null | head -50
gh auth status 2>&1 | head -6
ls -la docs 2>/dev/null; ls CLAUDE.md AGENTS.md 2>/dev/null
```

- 현재 폴더가 다른 repo의 **하위 폴더**이면(`show-toplevel`이 `pwd`와 다름) 멈추고 사용자에게 알린다.
  상위 repo 안에 새 repo를 만들지 않는다.
- `gh`가 없거나 로그인돼 있지 않으면 1단계는 건너뛰고, 사용자에게 `! gh auth login`을 안내한 뒤 2단계부터 진행한다.

## 1. Git / GitHub

### 1-1. 판정

| 상태 | 할 일 |
|---|---|
| git repo 아님 | 1-2 → 1-3 → 1-4 |
| git repo, remote 없음 | 1-2 → (커밋이 없으면 1-3) → 1-4 |
| remote 있음 | 건너뛰고 remote URL만 보고 |

### 1-2. owner·이름 확인 (질문은 한 번)

- 이름은 폴더명을 그대로 쓴다. GitHub에서 허용하지 않는 문자(공백 등)가 있으면 `-`로 바꾼 이름을 제안한다.
- owner 후보: 현재 활성 `gh` 계정(`gh api user --jq .login`)이 기본값, 그 외 `gh api user/orgs --jq '.[].login'`.
- 이미 같은 이름의 repo가 있는지 확인한다: `gh repo view <owner>/<name> --json visibility,url 2>/dev/null`.
- `AskUserQuestion`으로 **한 번만** 묻는다. 기본 선택지(첫 번째, Recommended)는
  "`<활성계정>/<폴더명>`으로 private repo 생성". 다른 owner가 있으면 선택지로 추가하고, "GitHub 연결 건너뛰기"도 둔다.
  같은 이름 repo가 이미 있으면 선택지를 "기존 repo를 origin으로 연결"로 바꾼다(그 repo가 public이면 그 사실을 질문에 적는다).

### 1-3. 초기 커밋 (커밋이 하나도 없을 때만)

1. git repo가 아니면 `git init -b main`.
2. `.gitignore`가 없으면 만든다. 스택 파일(`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml` 등)을 보고
   해당 언어의 일반 항목을 넣고, 항상 다음을 포함한다:
   `.DS_Store`, `.env`, `.env.*`(단 `!.env.example`), `*.pem`, `*.key`, `.idea/`, `.vscode/`(설정 공유가 필요하면 사용자가 뺀다).
   `.gitignore`가 이미 있으면 위 비밀값 항목 중 빠진 것만 추가할지 물어본다.
3. 후보 목록: `git ls-files --others --exclude-standard`.
4. 비밀값 의심 파일을 걸러 낸다(이름 기준: `.env*`(`.env.example` 제외), `*.pem`, `*.key`, `*.p12`, `id_rsa*`,
   `credentials*`, `*secret*`, `*.keystore`, `service-account*.json`). 걸린 파일은 `.gitignore`에 추가하고 이름만 보고한다.
5. 커밋할 파일 목록을 보여 주고(100개가 넘으면 상위 폴더별 개수로 요약) 확인을 받는다.
6. 경로를 명시해 스테이징한다. 목록이 길면 파일로 넘긴다:
   ```bash
   git ls-files --others --exclude-standard > /tmp/helpai-initial-files.txt
   git add --pathspec-from-file=/tmp/helpai-initial-files.txt && rm /tmp/helpai-initial-files.txt
   git commit -m "chore: initial commit"
   ```
   폴더가 비어 있으면 `.gitignore`만 커밋한다.

### 1-4. repo 생성·연결

- 새로 만들 때: `gh repo create "<owner>/<name>" --private --source . --remote origin --push`
- 기존 repo에 연결할 때: `git remote add origin <url>` 후, 원격이 비어 있을 때만 `git push -u origin HEAD`.
  원격에 이미 커밋이 있으면 push하지 않고 사용자에게 알린다(강제 push 금지).
- 결과 URL과 visibility를 `gh repo view --json url,visibility`로 확인해 보고한다.

## 2. docs 폴더

`references/docs-layout.md`를 읽어 고정 폴더 목록·index 섹션 제목·순서를 얻는다.

### 2-1. 폴더 만들기

- 고정 폴더 중 없는 것만 만든다. git은 빈 폴더를 추적하지 않으므로, 비어 있는 고정 폴더에는 빈 `.gitkeep`을 둔다.
  나중에 그 폴더에 문서가 생기면 `.gitkeep`은 그대로 둬도 된다(index에는 넣지 않는다).

### 2-2. index 작성 — docs가 새로 생긴 경우

`templates/index.md`를 복사해 `{{PROJECT_NAME}}`을 폴더명으로 바꾸고, 생성 지침 주석을 지운다.
섹션 순서가 `docs-layout.md` 표와 다르면 표를 따른다(표에 폴더가 추가됐으면 섹션도 추가한다).

### 2-3. index 소급 작성 — docs가 이미 있던 경우

1. 목록 수집: `find docs -type f ! -name '.gitkeep' ! -name '.DS_Store' ! -path 'docs/index.md' | sort`.
2. 문서마다 목적 한두 문장을 쓴다. 파일 제목(첫 `#` 줄)과 앞부분만 읽는다. 문서가 **30개를 넘으면** 폴더 단위로
   나눠 `Agent` 서브에이전트(model: sonnet) 여러 개에 **병렬로** 맡긴다. 각 프롬프트에 담당 폴더 목록과 회수 형식
   `경로 | 목적(1~2문장) | 상태 후보 | 근거 한 줄`을 명시하고, 파일을 수정하지 말라고 적는다.
3. 상태: `archive/` 아래이거나 문서가 스스로 폐기·대체·historical을 밝히면 `historical`, "초안/draft/WIP"이면 `draft`,
   그 외 `current`. 판단이 애매한 항목은 최종 보고에 모아 사용자에게 확인을 요청한다.
4. 배치: 고정 폴더 아래 문서는 해당 섹션에, 그 밖의 폴더·`docs/` 바로 아래 파일은 「기타」 섹션에 등재한다.
   한 폴더가 하나의 묶음(README + 하위 문서)이면 README 한 줄에 주요 하위 문서를 ` · `로 이어 적어도 된다.
   이미지·데이터 같은 자료 파일도 빠뜨리지 않는다(같은 폴더 문서 줄에 함께 적거나 별도 줄).
5. 기존 `docs/index.md`가 있으면 **덮어쓰지 않는다.** 기존 항목은 그대로 두고 빠진 파일만 해당 섹션에 추가한다.
   기존 index 형식이 다르면(목록형 등) 형식을 바꾸지 않고 그 형식으로 추가한 뒤, 표 형식으로 바꿀지 사용자에게 묻는다.
6. 다른 파일이 index 역할을 하고 있으면(예: gira처럼 `docs/README.md`) 그 파일은 그대로 두고, `docs/index.md`를 만들어
   그 파일도 항목으로 등재한다. 어느 쪽을 진입점으로 둘지는 보고에서 사용자에게 묻는다.

### 2-4. index 검증 (항상 실행)

docs 안의 모든 파일이 index에 링크돼 있고, index의 링크가 모두 실제 파일을 가리키는지 확인한다.

```bash
python3 - <<'PY'
import re, pathlib, urllib.parse
docs = pathlib.Path("docs"); idx = docs / "index.md"
text = idx.read_text(encoding="utf-8")
links = {urllib.parse.unquote(m.split("#")[0]) for m in re.findall(r"\]\(([^)\s]+)\)", text)}
links = {l for l in links if l and not re.match(r"^[a-z]+:", l)}
files = {p.relative_to(docs).as_posix() for p in docs.rglob("*")
         if p.is_file() and p.name not in {".gitkeep", ".DS_Store"} and p != idx}
linked = {l.removeprefix("./") for l in links}
dirs = {l.rstrip("/") + "/" for l in linked if (docs / l).is_dir()}
missing = sorted(f for f in files if f not in linked and not any(f.startswith(d) for d in dirs))
broken = sorted(l for l in linked if not (docs / l).exists())
print("unindexed:", len(missing)); [print("  -", f) for f in missing]
print("broken:", len(broken)); [print("  -", l) for l in broken]
PY
```

`unindexed`와 `broken`이 모두 0이 될 때까지 index를 고친다. 폴더 단위 링크(예: `[ADR 모음](architecture/adr/)`)는
그 아래 파일 전체를 등재한 것으로 본다. 파일이 많은 자료 폴더(이미지·데이터)에만 쓰고, 문서는 가능하면 개별로 등재한다.

## 3. 마일스톤 원장

- `docs/milestones/README.md`가 없으면 `templates/milestones-ledger.md`를 그대로 복사한다.
- 이미 있으면 건드리지 않는다. 형식이 템플릿과 다르면 보고에 "기존 원장 유지"라고만 적는다.
- 플랜·마일스톤 폴더는 만들지 않는다. 실제로 플랜을 세울 때 규칙에 따라 만든다.

## 4. CLAUDE.md 규칙 섹션

`templates/claude-rules.md`의 내용(마커 `<!-- helpai:docs-rules:start ... -->` ~ `<!-- helpai:docs-rules:end -->` 포함)을 적용한다.

| 대상 파일 상태 | 처리 |
|---|---|
| 파일 없음 | `# CLAUDE.md` 제목 한 줄 + 빈 줄 + 규칙 섹션으로 새로 만든다 |
| 마커 없음 | 파일 끝에 빈 줄 하나를 두고 규칙 섹션을 추가한다 |
| 마커 있음 | start~end 사이만 템플릿 내용으로 교체한다. 마커 밖은 건드리지 않는다 |

- 대상: 프로젝트 루트 `CLAUDE.md`는 항상. `AGENTS.md`는 **이미 있을 때만** 같은 방식으로 적용한다.
- 기존 CLAUDE.md에 docs 규칙과 충돌하는 문장(예: 다른 index 파일을 진입점으로 지정)이 있으면 고치지 말고 보고에 적는다.
- 적용 후 `grep -c 'helpai:docs-rules:start' CLAUDE.md`가 1인지 확인한다(중복 삽입 방지).

## 5. 마무리

1. 변경 내역을 보고한다: `git status --short` 결과와 단계별 결과(생성 / 건너뜀 / 사용자 확인 필요).
2. 커밋 여부를 묻는다. 동의하면 **이번에 만들거나 바꾼 경로만** 스테이징한다:
   ```bash
   git add -- docs/index.md docs/milestones/README.md CLAUDE.md <생성한 .gitkeep 경로들> [AGENTS.md] [.gitignore]
   git commit -m "docs: set up docs index, milestone ledger and docs rules (helpai project-setup)"
   ```
   remote가 연결돼 있으면 push할지도 함께 묻는다.
3. 보고 마지막에 다음을 적는다: 사용자 확인이 필요한 항목(애매한 상태 판정, 기존 index와의 관계, 충돌 문장),
   그리고 "새 폴더가 필요하면 `references/docs-layout.md`에 추가한 뒤 이 스킬을 다시 실행하면 된다"는 안내.
