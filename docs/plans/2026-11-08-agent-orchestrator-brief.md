# 계획 초안 지시서 — agent-orchestrator (오케스트레이션 툴 추상화)

너는 계획 초안 작성자다. **파일 수정·커밋·push·원격 쓰기 금지.** 읽기·조사만 하고, 결과는 아래 경로 하나에만 쓴다.

- 출력: `/Users/peter/Dev/waymakerlabs-claude-plugins/docs/plans/2026-11-08-agent-orchestrator-plan.md` (한국어, 존댓말 불필요, 간결하게)
- 반환: `<계획 파일 경로> — <세션 수> 세션, <핵심 위험 1줄>` 한 줄만.
- 금지 표현: 전역 CLAUDE.md의 금지어 목록을 따른다. 대신 기재/명시/추가/반영 등을 쓴다.

## 배경 (사용자와 합의된 사실)

사용자는 세 머신을 쓴다: 이 맥(`/Users/peter`), office 맥미니(`ssh office-macmini`), 홈 맥미니(`ssh home-macmini`). 오늘 Orca → herdr로 오케스트레이션 툴을 바꿨는데, Orca 흔적이 6개 CLI 훅·스킬 링크·codex 신뢰 항목·규칙 문서·메모리 34곳에 남아 정리에 큰 비용이 들었다. herdr도 나중에 Rex(현재 개발 중) 등으로 바뀔 수 있다. 같은 일이 반복되지 않게 하려는 것이 목표다.

합의된 결정:
1. **동작 이름 추상화**: 규칙·스킬은 툴 이름 대신 동작 이름만 쓴다. 명령 하나 `agent-orchestrator <동작> …` + 툴별 어댑터(`adapters/herdr.sh`). 백엔드는 설정 한 줄(`backend=herdr`), 없으면 환경 변수로 자동 판단(`HERDR_ENV=1` 등). 출력은 JSON이 아니라 필요한 값 한 줄(예: pane id). 지원하지 않는 동작은 정해진 종료 코드로 "unsupported"를 알리고 호출자가 아래 단계로 내려간다.
   - 동작 후보: `tab-open <한글 이름>`, `pane-open <한글 이름>`(herdr는 split에 이름 옵션이 없어 split 직후 rename), `self-name <한글>`, `agent-start`, `agent-send`, `agent-wait`, `agent-read`, `close`, `list`, `whoami`. 최종 목록은 실제 사용처를 조사해 정한다.
2. **이번 범위는 herdr 어댑터만.** Rex 어댑터는 만들지 않되 들어올 자리는 구조에 둔다. 기존 Rex 시작 훅(`rex __internal session-start`, Claude `~/.claude/settings.json`·codex `~/.codex/hooks.json` SessionStart)은 건드리지 않고 설치 목록에 "기존 항목"으로만 기재.
3. **설치 목록(manifest)**: 어댑터마다 자기가 바깥에 설치하는 것(훅·설정 항목·링크·스킬)을 목록으로 둔다. 툴 제거 시 그 목록으로 정리한다(archive-first: 삭제 대신 `~/.claude/archive/` 등으로 보관).
4. **위치**: 마켓플레이스 리포(`/Users/peter/Dev/waymakerlabs-claude-plugins`) 안에 두고 `~/.local/bin/agent-orchestrator`로 링크. codex도 같은 경로로 부른다. 확인된 사실: 홈 맥미니는 비로그인 ssh 셸 PATH에 `~/.local/bin`이 없고 로그인 셸(`zsh -lc`)에는 있다. office는 비로그인 PATH에 없음(로그인 셸 미확인). 위치를 플러그인 안으로 할지 리포 최상위 별도 폴더로 할지는 네가 근거를 들어 정한다(플러그인 업데이트 경로 `~/.claude/plugins/cache/...`는 버전마다 폴더가 바뀐다는 점 고려).
5. **worker 실행 3단계 규칙**(같은 작업에서 함께 반영): ① 기본 = 메인 CLI 내장 서브에이전트(Claude `Agent`) — 결과는 파일로, 반환은 한 줄 ② worker가 다른 CLI여야 하면 headless 일회성 실행 + done 파일(기존 `review-run.sh`/`review-wait.sh` 방식 확장) ③ pane worker는 사용자가 지켜보며 끼어들 작업·작업 도중 메인과 대화가 필요한 작업·메인보다 오래 살아야 하는 작업(세션 인계)만. 근거: pane 방식은 회수 지연(M1-10 리뷰 179분), 정지 오판, 기동 실패(신뢰 확인 `agent_not_ready`) 비용이 컸다.
6. **탭·pane 이름은 항상 한글**(오늘 반영 완료 — auto-chain 2.2.2, 세 머신 CLAUDE.md/AGENTS.md). 추상화 뒤에도 유지.
7. codex 메인 오케스트레이터는 당장 안 한다(장기 고민). 다만 규칙이 CLI 중립이 되게 쓴다.

## 조사 대상 (herdr 이름 분포, grep 실측)

- `~/.claude/CLAUDE.md` 28곳(특히 43번째 줄 herdr 규칙 ①~⑨, 「후속 세션 인계 프로토콜」 herdr 절), `~/.claude/CLAUDE_HISTORY.md`
- `~/.codex/AGENTS.md` 7곳 (office·홈에도 같은 규칙 절 있음. 홈 맥미니 `~/.claude/CLAUDE.md`는 오늘 새로 만든 herdr 이름 규칙 한 절뿐)
- auto-chain: `plugins/auto-chain/skills/autonomous-chain/` — `references/backend-herdr.md` 53, `SKILL.md` 26, `scripts/herdr-spawn-worker.sh` 26, `scripts/test/run-tests.sh` 13, `README.md` 10, `scripts/herdr-stall-watch.sh` 9, `references/task-brief.md` 6, `references/sol-review.md` 4, `references/backend-orca.md`(Orca 잔재 — 처리 방안 포함)
- 메모리: `~/.claude/projects/*/memory/` 중 herdr 언급 파일 8개
- herdr가 설치한 훅: `~/.claude/hooks/herdr-agent-state.sh`, `~/.codex/herdr-agent-state.sh` ("managed by herdr" — 재설치 시 덮어씀, 편집 금지)
- herdr CLI: `herdr <그룹> --help` (맨 `herdr`는 TUI라 실행 금지). 버전 0.9.5.

## 계획에 반드시 포함할 것

1. 동작 목록과 각 동작의 입출력·종료 코드 계약, herdr 어댑터 매핑 표.
2. 파일 배치(리포 경로·링크·설정 파일 위치), 세 머신 배포·PATH 처리, 설치 목록 형식.
3. 문서 이관 방식: 규칙 문서에는 동작 이름 + 3단계 기준만, 툴별 특이사항은 어댑터 참고 문서 한 곳에.
4. auto-chain 버전 계획(2.3.0 예상): 웨이브 기본을 ① `Agent`로, ②는 review-run 확장, 계획 planner-deep만 pane 유지 여부 판단, stall-watch는 pane worker가 있을 때만. `herdr-spawn-worker.sh`의 위치(어댑터 위로 올릴지).
5. 진행 중인 helpai 자율체인 M1-11(2.2.x로 실행 중)을 깨지 않는 전환 순서. helpai 프로젝트 가이드(`/Users/peter/Dev/helpai`의 체인 가이드·CLAUDE.md)에 herdr/pane 고정 문구가 있는지 확인하고 충돌 처리 포함.
6. 시험: 가짜 백엔드로 어댑터 계약 시험, 음성 대조(어댑터 없을 때 unsupported 코드), 기존 시험 56건 유지.
7. 되돌리기 방법, 고위험 지점(전역 규칙·훅 변경은 codex 크로스체크 대상) 표시.
8. **세션 단위로 쪼갠 단계 목록**: 각 단계의 종료 조건·검증·다음 세션 첫 착수 지점. 구현은 이 계획 세션이 아닌 새 세션에서 시작한다.
9. 사용자 결정이 필요한 항목은 따로 모은다(추측으로 정하지 말 것).
