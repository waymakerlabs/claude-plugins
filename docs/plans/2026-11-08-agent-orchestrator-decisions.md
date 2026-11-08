# agent-orchestrator 계획 — 사용자 결정 (2026-11-08)

계획 `2026-11-08-agent-orchestrator-plan.md` §8 D1~D8에 대한 결정. codex 크로스체크가 끝난 뒤 계획 본문에 반영한다(리뷰 중에는 계획 파일을 고치지 않는다).

| 항목 | 결정 | 근거 |
|---|---|---|
| D1 리뷰 실행 화면 | **headless 기본**(`review_view: headless`, `run_in_background` + `review-wait.sh`). `review_view: pane`은 선택지로 남김. helpai는 기존 지시(codex 오른쪽 pane)대로 프로파일에서 `pane` 유지, S6에서 helpai가 다시 판단 | 사용자: 어느 쪽이든 무관, 추천대로. 완료 판정은 done 파일이라 화면 유무와 무관 |
| D2 `chain-planner-deep` | **pane ③ 유지**. 10·11이면 ① Agent로 내려감 | 사용자 선호(pane) + 초안 권장 일치 |
| D3 홈 PATH | **추가하지 않음**. 규칙·스크립트는 `~/.local/bin/agent-orchestrator` 절대 경로 | 셸 설정을 늘리지 않는다. 재측정: 홈 로그인 셸에도 `~/.local/bin` 없음, office는 로그인 셸에만 있음 |
| D4 2.3.0 반영 시점 | **helpai M1-11 마감 뒤** | 진행 중 체인 보호 |
| D5 Orca 잔재 | **삭제**: `orca-codex-delegate` 플러그인 폴더와 marketplace.json 항목, auto-chain `references/backend-orca.md`와 SKILL.md orca 분기 제거. 제거 전 태그 `orca-codex-delegate-v1.0.3`를 만들어 복원 경로를 남긴다(auto-chain 쪽은 기존 태그 `auto-chain-v1.7.1-orca`). 세 머신 설치 여부 확인 후 설치돼 있으면 uninstall | 사용자 지시. git 이력·태그로 복원 가능하므로 archive-first 위반 아님 |
| D6 링크 대상 | **세 머신 모두 마켓플레이스 사본**(`~/.claude/plugins/marketplaces/waymakerlabs-claude-plugins/tools/...`). 개발 중 시험은 개발 리포 경로를 직접 호출 | 세 머신 동일. 편집 중인 미완성 코드가 실제 세션에 바로 쓰이지 않는다(push+update 뒤에만 반영) |
| D7 원격 조작 `--machine` | **이번 범위에서 제외**. gchat-g-on 메모리의 원격 prompt는 `docs/herdr.md`의 알려진 예외로 기재하고 `install.sh --check`의 잔존 허용 목록에 넣는다 | S1 계약을 작게 유지. 사용처 1곳 |
| D8 helpai 대리 보고 ID | **helpai 쪽에서 S6에 결정**. 제안값: Agent worker는 `agent:<agentId>`, pane worker는 기존 `session:<UUID>` | helpai 체인 소유 규칙(Q24) |
| D9 office gira 메모리 `herdr-parallel-agents.md`("구현은 `Agent` 대신 herdr 패널", 2026-11-06) | **새 3단계 기준으로 변경**(2026-11-08 주인님 결정 — 추천안). 옛 문구는 지우지 않고 "2026-11-08 변경: 3단계 기준으로 대체" 이력으로 남긴다. S6 전역 규칙 적용 때 메모리 3파일과 함께 반영(office 원격 쓰기, 백업 먼저) | S5 보고 §4-3. 프로젝트 메모리가 전역 규칙보다 구체적인 지시로 읽혀 옛 방식을 계속 따를 수 있다 |
