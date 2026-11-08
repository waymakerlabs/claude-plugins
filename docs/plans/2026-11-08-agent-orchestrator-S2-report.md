# agent-orchestrator S2 보고 — 설치 목록·배포 준비·Orca 플러그인 삭제 (2026-11-08)

- 세션: herdr pane `w2:p17`(탭 `w2:t8` "논의", pane 이름 "S2 설치 목록"). 부모 `w2:p14`(닫지 않음)
- 리포 `/Users/peter/Dev/waymakerlabs-claude-plugins`, branch `main`, HEAD `b5691fb` = origin/main(변경 없음)
- **commit·태그·push 안 함**. 메인(논의 pane)이 직접 한다(주인님 지시). 태그 `orca-codex-delegate-v1.0.3`도 만들지 않았다
- 상태: S2 종료 조건 충족(아래 표). codex 크로스체크는 생략(가역·저위험 — 새 폴더 추가와 미설치 플러그인 삭제)

## Orca 설치 재확인 (읽기만)

| 머신 | `installed_plugins.json` | `orca-codex-delegate` |
|---|---|---|
| 이 맥 | 있음 | 0건 |
| office-macmini | 1647 B, 11-08 15:24 | 0건 |
| home-macmini | 1240 B, 05-12 15:18 | 0건 |

## 실측: 실제 herdr pane 쓰기 동작 (herdr 0.9.5)

이 pane에서 진입점을 불렀다(응답 기록용 PATH shim → 실제 `/opt/homebrew/bin/herdr`, 끝난 뒤 shim 삭제).

```
pane-open "시험 pane" --cwd <리포>  → w2:p18  rc=0  (pane get: label "시험 pane")
close w2:p18                        → rc=0
tab-open "시험 탭" --cwd <리포>     → w2:p19  rc=0  (새 탭 w2:tB)
close w2:p19                        → rc=0  (탭도 사라짐, tab list에 논의 탭만 남음)
```

실제 응답 모양:
- `pane layout --pane w2:p17` → `result.layout.panes[].rect{x,y,width,height}`. 기준 pane `w2:p17`(x=100)보다 오른쪽이 없어 `right`가 선택됐다
- `pane split …` → `{"result":{"pane":{…,"pane_id":"w2:p18",…},"type":"pane_info"}}` — 어댑터 `result.pane.pane_id`와 맞음
- `tab create …` → `{"result":{"root_pane":{…,"pane_id":"w2:p19","tab_id":"w2:tB",…},"tab":{…,"label":"시험 탭","pane_count":1,…},"type":"tab_created"}}`
  - S1 어댑터의 "첫 `pane_id`" 추출도 `root_pane`이 먼저 나와 맞는 값이었다. 그래도 키 순서에 기대지 않게 **`root_pane.pane_id`를 먼저 읽고, 없으면 첫 `pane_id`로 내려가게** 바꿨다(`adapters/herdr.sh` `op_tab_open`). 계약은 바뀌지 않음
- `pane close` → `{"result":{"type":"ok"}}`

## 만든·바꾼 파일

| 경로 | 내용 |
|---|---|
| `tools/agent-orchestrator/manifests/core.manifest` | 계획 §2-4 내용 그대로(2항목) |
| `tools/agent-orchestrator/manifests/herdr.manifest` | 계획 §2-4 내용 그대로(14항목, 모든 줄 5칸 탭 구분 확인) |
| `tools/agent-orchestrator/lib/manifest.py` | manifest 해석·`check`(읽기 전용)·`uninstall`(기본 dry-run, `--apply` 때만 보관). Python 3.9 호환 |
| `tools/agent-orchestrator/install.sh` | `--check <backend>`(읽기 전용, core+backend), `<backend>`(링크·config 멱등 생성 — **S2에선 실제 HOME에 실행 안 함**) |
| `tools/agent-orchestrator/uninstall-backend.sh` | 기본 `--dry-run`, `--apply`. `core`는 백엔드로 받지 않음(2) |
| `tools/agent-orchestrator/docs/herdr.md` | S1 실측 사실 + 이번 응답 모양 + 계획 §3 특이사항 + D7 `--machine` 예외 |
| `tools/agent-orchestrator/adapters/herdr.sh` | `op_tab_open` `root_pane` 우선(위) |
| `tools/agent-orchestrator/test/run-tests.sh` | S2 시험 31건 추가, `EXPECT=123` |
| `CLAUDE.md`(리포) | 구조 절에 `tools/` 한 줄 |
| `README.md`·`README.ko.md` | 머리에 `tools/` 한 줄, `orca-codex-delegate` 절 삭제 |
| `.claude-plugin/marketplace.json` | `orca-codex-delegate` 항목만 제거(13개 남음, JSON 유효) |
| `plugins/orca-codex-delegate/` | 삭제(작업 트리). 사본은 `~/.claude/archive/orca-codex-delegate-20261108-170810/`(archive-first) |

설계 판단:
- `existing`은 owner 칸이 `-`·`rex`라 kind로 보존을 판정한다. `ours-core`는 owner로 판정. 둘 다 `uninstall`에서 "보존" 행만 출력하고 실행 함수가 없다.
- 리포 상대 항목(`adapter`·`doc`·리포 안 `rule`)은 파일을 옮기지 않고 "git 이력 보관(수동 git rm)"으로만 표시.
- `rule` grep은 대소문자 무시, 폴더면 `archive/`·`CHANGELOG*` 제외(계획 manifest note). `allow` 항목은 그 파일·패턴에 걸린 줄을 잔존에서 뺀다.
- macOS `/usr/bin/python3`는 기본으로 `~/Library/Caches/com.apple.python`에 바이트코드를 쓴다 → `--check`·dry-run이 HOME에 디렉터리를 만든다(시험 `check-readonly`가 잡음). 두 스크립트에서 `PYTHONDONTWRITEBYTECODE=1`로 막았고, 시험 지문은 제외 없이 전체 트리를 본다.

## 시험 결과

```
$ tools/agent-orchestrator/test/run-tests.sh
== 집계: PASS 123 / FAIL 0 / 총 123 (기대 123)   exit 0, 케이스 이름 중복 0
$ shellcheck -x bin/agent-orchestrator adapters/herdr.sh lib/common.sh test/run-tests.sh install.sh uninstall-backend.sh → 0건
$ python3 -m py_compile lib/manifest.py → ok (__pycache__ 정리함)
```

S1 92건은 그대로 PASS. S2 31건(사본 리포 + 가짜 HOME, PATH 격리 유지):
- `--check`: 필수 없음 → 1, 전후 HOME 트리 지문 같음(`check-readonly`), 개수(core 0/2, herdr 6/6, 잔존 4 = CLAUDE.md 2·AGENTS 1·SKILL 1, archive·CHANGELOG 제외), allow 따로 셈, existing 정보 행, 없는 백엔드 12·인자 2
- `install.sh`: 생성 → 두 번째 = 유지 2·지문 같음(멱등), 설치 뒤 `--check` 0, 링크로 `backend` → herdr, config 값만 교체·다른 줄 보존, 일반 파일 충돌 3·덮어쓰지 않음, 대상 없음 12
- `uninstall` dry-run: 전후 지문 같음·archive 없음, 보존 6(existing 4·ours-core 2), rule = 위치만, 실행 예정 4, `core` 2·잘못된 옵션 2·없는 백엔드 12
- 가드 제거 시 실패 증명(`neg-preserve-guard`): `GUARD:preserve` 줄을 지운 사본은 existing·ours-core를 보존으로 처리하지 않는다(grep으로 제거 먼저 확인)
- `--apply`(가짜 HOME만): 훅 2개 archive 이동, settings는 herdr 항목만 제거·rex·PreToolUse·다른 키 유지·원본 백업, rule·existing·ours-core 그대로

## 이 맥 실제 점검 (읽기 전용)

```
$ tools/agent-orchestrator/install.sh --check herdr            (exit 1 — core 미설치는 S3 대상이라 정상)
== core: 필수 0/2 있음, rule 잔존 0건(allow 제외)
== herdr: 필수 6/6 있음, rule 잔존 134건(allow 제외)          (CLAUDE.md 13 · AGENTS.md 1 · auto-chain 120, allow 2건 제외)
$ tools/agent-orchestrator/uninstall-backend.sh herdr          (exit 0, 보존 6행, 실행 예정 4)
실제 HOME 7파일(settings.json·hooks.json·config.toml·훅 2·CLAUDE.md·AGENTS.md) 전후 shasum 같음, ~/.claude/archive/agent-orchestrator 없음
```

## 종료 조건 (계획 §6 S2 행)

| 조건 | 결과 |
|---|---|
| `install.sh --check herdr` 이 맥 전부 존재 | herdr 6/6 있음. docs/herdr.md를 만든 뒤 6/6. core 0/2는 S3에서 설치 |
| uninstall dry-run이 existing·ours-core를 "보존", 파일 변경 0(shasum) | 보존 6행, shasum 같음 |
| 실제 herdr pane `pane-open "시험 pane"` → `close` 1회 | w2:p18 열고 닫음(+ `tab-open` 1회) |
| diff가 허용 목록 밖 0 | 아래 |
| `grep -n orca-codex-delegate README.md README.ko.md .claude-plugin/marketplace.json` 0 | 0건(rc=1) |

```
$ git status --short
 M .claude-plugin/marketplace.json
 M CLAUDE.md
 M README.ko.md
 M README.md
 D plugins/orca-codex-delegate/.claude-plugin/plugin.json
 D plugins/orca-codex-delegate/README.md
 D plugins/orca-codex-delegate/skills/orca-codex-delegate/SKILL.md
?? docs/plans/
?? tools/
$ git diff --stat → 7 files changed, 5 insertions(+), 354 deletions(-)
```

## 메인이 할 일 (commit·태그·push)

1. 태그(삭제 커밋 전에): `git tag orca-codex-delegate-v1.0.3 b5691fb` — `b5691fb`에 `plugins/orca-codex-delegate/` 3파일(plugin.json 1.0.3)과 marketplace 항목이 있음을 `git ls-tree`로 확인함
2. 스테이징할 경로(전부 명시):
   - `tools/agent-orchestrator/` 아래 12개: `adapters/README.md` `adapters/herdr.sh` `bin/agent-orchestrator` `docs/herdr.md` `install.sh` `lib/common.sh` `lib/manifest.py` `manifests/core.manifest` `manifests/herdr.manifest` `test/fake-herdr.py` `test/run-tests.sh` `uninstall-backend.sh`
   - `docs/plans/` 5개: `2026-11-08-agent-orchestrator-brief.md` `-decisions.md` `-plan.md` `-S1-report.md` `-S2-report.md`(이 파일). 리포 밖 S3 handoff는 대상 아님
   - `CLAUDE.md` `README.md` `README.ko.md` `.claude-plugin/marketplace.json`
   - 삭제 3개: `plugins/orca-codex-delegate/.claude-plugin/plugin.json` `plugins/orca-codex-delegate/README.md` `plugins/orca-codex-delegate/skills/orca-codex-delegate/SKILL.md`(`git rm` 또는 `git add` 경로 명시)
3. 커밋을 둘로 나누면(선택): ① `tools/`·`docs/plans/`·CLAUDE.md·README의 `tools/` 줄 ② Orca 삭제. README 두 파일은 두 변경이 섞여 있어 하나로 묶는 편이 간단하다
4. push(주인님 승인 뒤): 태그 먼저 `git push origin orca-codex-delegate-v1.0.3`, 그다음 `main`. push = 세 머신 배포(autoUpdate). 플러그인 버전 변경 0

## 남은 것

- S3: 세 머신 마켓플레이스 갱신 확인 → `install.sh herdr` → `--check herdr` → pane 안 `~/.local/bin/agent-orchestrator backend` = herdr, 비로그인 ssh에서 11. handoff `/Users/peter/Dev/HANDOFF-2026-11-08-agent-orchestrator-S3.md`
