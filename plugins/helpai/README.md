# helpai

프로젝트 작업을 돕는 스킬 모음입니다. 모든 스킬은 `helpai:` namespace로 호출합니다.

## 스킬

### `/helpai:project-setup`

현재 폴더를 프로젝트로 초기화합니다. 이미 되어 있는 단계는 건너뛰므로 여러 번 실행해도 됩니다.

1. **GitHub** — git repo가 아니거나 remote가 없으면, 활성 `gh` 계정으로 `<계정>/<폴더명>` private repo를 만들지 한 번 묻고 생성합니다. 초기 커밋은 파일 목록을 확인받은 뒤 만들고, 비밀값으로 보이는 파일은 제외합니다.
2. **docs** — 고정 폴더 세트와 `docs/index.md`를 만듭니다. docs가 이미 있으면 기존 파일을 옮기지 않고 index를 소급해 작성합니다.
3. **마일스톤 원장** — `docs/milestones/README.md`를 만듭니다. ID는 `M{플랜}-{순번}`(예: `M1-01`)입니다.
4. **규칙** — 프로젝트 `CLAUDE.md`(있으면 `AGENTS.md`도)에 문서·마일스톤 규칙 섹션을 추가합니다. 마커로 감싸서 다시 실행하면 그 구간만 갱신합니다.

#### docs 고정 폴더

| 폴더 | 용도 |
|---|---|
| `product/` | 제품 정의, 요구사항, 원칙 |
| `architecture/` | 구조, 설계, ADR |
| `design/` | UI·디자인 시스템 |
| `plans/` | 로드맵, 여러 플랜에 걸친 계획 |
| `milestones/` | 플랜별 마일스톤 계획·진행 기록·결과 |
| `operations/` | 배포·운영 절차 |
| `archive/` | 역사적 baseline, 폐기 문서 |

폴더를 추가하려면 `skills/project-setup/references/docs-layout.md` 표에 한 줄을 추가하고 버전을 올리면 됩니다. 스킬을 다시 실행하면 기존 프로젝트에도 반영됩니다.

## 설치

```
/plugin install helpai@waymakerlabs-claude-plugins
```

## 요구 사항

- `git`
- `gh` (GitHub 연결 단계에만 필요. 로그인돼 있지 않으면 그 단계만 건너뜁니다)
- `python3` (index 검증용)
