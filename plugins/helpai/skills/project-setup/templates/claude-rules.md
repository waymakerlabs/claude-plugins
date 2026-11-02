<!-- helpai:docs-rules:start v1 -->
## 문서 규칙 (helpai project-setup)

- `docs/index.md`는 `docs/` 아래 모든 문서와 자료의 단일 색인입니다. 작업을 시작할 때 먼저 확인합니다.
- `docs/` 아래 파일을 추가·이동·이름 변경·폐기하면 **같은 변경(같은 커밋)에서** `docs/index.md`를 갱신합니다.
- 문서는 고정 폴더 중 맞는 곳에 둡니다: `product/`(제품 정의·요구사항) · `architecture/`(구조·설계·ADR) · `design/`(UI·디자인 시스템) · `plans/`(로드맵·플랜 간 계획) · `milestones/`(마일스톤 기록) · `operations/`(배포·운영) · `archive/`(폐기·역사 기록). 맞는 폴더가 없으면 새 최상위 폴더를 만들기 전에 사용자에게 확인합니다.
- index 항목은 `문서 | 목적 | 상태` 표 형식이고, 목적은 1~2문장으로 씁니다. 날짜별 진척이나 변경 이력은 index가 아니라 각 문서 안에 둡니다.
- index 상태 값은 `current` / `draft` / `historical`만 씁니다.
- 문서를 폐기할 때는 삭제하지 않고 `archive/`로 옮긴 뒤 상태를 `historical`로 바꿉니다.
- 비밀번호, API key, 토큰 같은 민감 정보는 문서에 기록하지 않습니다.

### 마일스톤 규칙

- ID는 `M{플랜번호}-{순번}`입니다(예: `M1-01`). 새 플랜마다 플랜 번호를 1 올리고 순번은 `01`부터 시작합니다. 부여한 번호는 바꾸거나 재사용하지 않습니다.
- 플랜을 세우면 `docs/milestones/M{n}-<slug>/README.md`에 그 플랜의 마일스톤 전체를 `planned`로 등재하고, `docs/milestones/README.md` 원장에 플랜 한 줄을 추가합니다.
- 마일스톤을 시작할 때 `M{n}-{nn}-<slug>/plan.md`를 작성하고 상태를 `in-progress`로 바꿉니다. 원장의 진행 위치(예: `03/05 (M1-03 진행 중)`)도 함께 갱신합니다.
- 의미 있는 단위를 끝낼 때마다 `progress.md` 아래에 기록을 이어 씁니다(날짜·한 일·검증 명령과 결과·다음 착수 지점). 기존 기록은 고치지 않습니다.
- 종료할 때 `result.md`를 쓰고 상태를 갱신합니다. 종료 조건을 근거와 함께 채우지 못했으면 `done`으로 바꾸지 않습니다.
- 마일스톤 상태 값은 `planned` / `in-progress` / `blocked` / `done` / `dropped`만 씁니다.
- 문서 형식은 `docs/milestones/README.md`의 「문서 형식」 절을 따릅니다.
<!-- helpai:docs-rules:end -->
