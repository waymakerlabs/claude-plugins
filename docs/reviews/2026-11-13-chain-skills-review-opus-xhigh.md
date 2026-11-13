# auto-chain · review-chain 설계 검토 (읽기 전용)

주인님, 읽기 전용 검토이며 파일은 고치지 않았습니다. 경로 기준은 `/Users/peter/Dev/claude-plugins`이고, 전역 파일은 `~/.claude/...`로 적었습니다. 조정자가 보탠 사고 증거(탭을 건너뛴 이름 변경)를 대조해 반영했습니다.

결론: 탭 이름 규칙이 빠진 데에는 구조적 원인이 있습니다. ① auto-chain 본문 착수 절차에 이름 붙이기 단계가 없습니다. ② 전역 규칙은 "자율체인이면 이 절 대신 스킬을 따르라"는 절 안에 있습니다. ③ 실제로 실행된 대기 표시 명령은 탭을 일부러 건너뜁니다. 문장을 더 쓰기보다 착수 명령에 묶어 자동화해야 합니다.

## 1. 진단

### 1-1. 사고 경로 (조정자 증거로 확정)

사고 세션의 auto-chain 조정자는 pane 이름만 `[OC] 컨플 이관 신청 · 대기 1 (최초 계획)`으로 바꿨습니다. 탭 이름(주인님이 붙인 `GIKI 마이그레이션 페이지`)은 주인님이 지적한 뒤에야 `[OC]`가 붙었습니다.

| 위치 | 내용 | 판정 |
|---|---|---|
| `plugins/auto-chain/skills/autonomous-chain/SKILL.md:500` | 대기 표시 `"$AO" self-name --force - "[OC] <이름> · 대기 <N> (…)"` | 사고 때 실행된 형식과 일치. 첫 인자 `-`는 탭을 건너뜀(`tools/agent-orchestrator/bin/agent-orchestrator:14`, `tools/agent-orchestrator/adapters/herdr.sh:237-240`) |
| 같은 파일 §3(:96-105)·§4 착수(:126-127) | 착수 때 self-name 단계 없음. 543줄 중 `self-name`은 :500 한 곳뿐 | 확인함 |
| `.../autonomous-chain/references/pane-worker.md:47` | "조정자는 착수 때 `self-name`을 한 번 실행한다" | 유일한 착수 지시. 그런데 문서 머리(:3)에 "③ pane worker를 쓸 때만 읽는다"고 적혀 있고, :47은 §2 「기동 — `spawn-pane-worker.sh`」(:28-49) 안 환경 변수 설명과 `--cwd` 사이의 글머리 하나라 조정자 자신에게 하는 지시로 읽히지 않음 |
| `~/.claude/CLAUDE.md:37` / `:47` | :37 "자율체인 적용 중에는 이 절의 병렬·모델 선택·실행 수단 … 대신 그 스킬의 규칙", :47 이름 규칙(방법은 `pane-worker` 「아」) | 같은 「작업 분담과 서브에이전트」 절. 이름 규칙이 대체 대상(실행 수단)의 일부로 읽히기 쉬움 |
| `~/.claude/skills/pane-worker/SKILL.md:61-68` | 실제 명령과 접두어 정의 | 이 스킬을 불러야 보이는데, 체인 진행 중에는 부를 계기가 없음 |
| `plugins/review-chain/skills/review-chain/SKILL.md:30` | §1의 2단계에 `self-name` | 이 세션이 OC가 될 때만 실행. 기본 경로 launch(:28)에서 부른 세션은 0단계에서 손을 떼고, `references/launch.md` §2(:17-37)에도 자기 이름 단계가 없음. 새 OC 탭은 `tab-open "[OC] … QC"`(launch.md:28)로 이름이 함께 붙으므로 launcher 탭만 이름 없이 남음 |
| `references/oc-handover.md:24` | 새 OC는 "스킬 로드 후 `self-name`" | 교체 때만 해당 |

**직접 메커니즘**: `self-name`을 `--force` 없이 실행하면 주인님이 붙인 이름은 지우지 않고 `[OC] `만 앞에 붙입니다(`adapters/herdr.sh:209-213` `label_plan` 사용자 이름 보존 가드). 착수 때 한 번만 실행했어도 탭은 `[OC] GIKI 마이그레이션 페이지`가 됐을 것입니다. 실제로 실행된 것은 :500의 `--force -` 형태뿐이었고, 이 형태는 규칙대로 탭을 건너뛰므로 대기 표시를 몇 번 반복해도 탭은 바로잡히지 않습니다.

스크립트가 연 세션은 이름이 붙습니다. `spawn-pane-worker.sh:58-59`, 인계 `pane-open "[OC] … M<n+1>"`(`references/pane-worker.md:161`), `tab-open "[OC] … QC"`(`launch.md:28`)입니다. 장치가 없는 쪽은 사람이 직접 연 첫 세션입니다. auto-chain 계획 세션, "자율체인으로"라고 부른 세션, review-chain launcher가 여기에 해당합니다.

### 1-2. 놓친 이유

1. **착수 단계가 본문에 없음**(위 표). 규칙이 ③ 전용 문서의 기동 절에 숨어 있습니다.
2. **범위 무효화로 읽힘**: `~/.claude/CLAUDE.md:37`의 대체 문장이 :47을 함께 덮는다고 읽힐 수 있습니다(추정, 가능성 높음).
3. **첫 응답 규칙이 두 개**: auto-chain `SKILL.md:471` "인계 직후 … 첫 응답은 반드시 진행 보드다"(굵게)가 전역 "첫 응답 전에 이름"과 경쟁합니다.
4. **간접 참조**: :47은 방법을 다른 스킬(`pane-worker` 「아」)로 넘깁니다.
5. **분량에 묻힘**: auto-chain 본문 543줄 중 `(2.x.x)`류 판 표식이 붙은 줄 99개, "근거" 단락 36개입니다(grep 집계).
6. **검사 장치 없음**: SessionStart 훅은 `herdr-agent-state.sh`(상태 보고)와 inbox-hooks 대기자뿐이고(`~/.claude/settings.json:32-58`, `plugins/inbox-hooks/hooks/hooks.json`), 이름을 보는 훅은 없습니다. `rex … --feature-session-naming=false`(`settings.json:45`)는 다른 도구의 이름 기능을 일부러 끈 것이라 대신해 주는 것도 없습니다.
7. **안전 장치가 누락을 가림**: :500의 `-`(탭 건너뜀)가 정확히 지켜졌기 때문에, 겉보기에는 이름 규칙을 지킨 것처럼 보였습니다.

### 1-3. 같은 구조의 다른 어긋남

- **받은편지함 수신 방식**: auto-chain `SKILL.md:43`은 "Monitor를 켜지 않는다, `inbox-subscribe`"입니다. 반면 `~/.claude/skills/pane-worker/SKILL.md:46-47`(Monitor, worker는 착수 직후 Monitor)과 `~/.claude/skills/session-handoff/SKILL.md`의 "받은편지함 동결"(Monitor 중지 → ack)은 옛 방식입니다.
- **pane 개수 상한**: `pane-worker/SKILL.md:21`은 "최대 5개, 넘치면 넘침 탭"입니다. `tools/agent-orchestrator/docs/herdr.md:29`(기본 999)와 review-chain `SKILL.md:79`·D3(:207)는 "제한 없음"입니다.
- **회차 상한의 우선순위**: `~/.claude/skills/review-protocol/SKILL.md` §2는 "`escalation`이 `stop`에 닿아도 이 절차가 우선"이라고 하고, auto-chain `SKILL.md:305-320`은 사다리를 진본으로 둡니다. 두 문서가 서로 자기를 우선이라고 적었습니다.
- **실패 사다리 중복**: auto-chain `SKILL.md:381-385`와 `~/.claude/CLAUDE.md:59-66`(:381이 "같은 사다리"라고 밝힘).
- **기억에 맡긴 규칙**: 대기 목록 쓰기 직전 `wait-status`(:496), 감시 재기동 직후 보고서 직접 읽기(:529), 마감 체크 4항(:142). 이 규칙들 자체가 기억에 의존한 실패의 사후 대책으로 추가된 것입니다(:496·:529의 근거 단락).

## 2. 복잡도 목록

### 2-1. auto-chain `SKILL.md`(543줄)

| 절 (줄) | 분량 | 판정 | 이유 |
|---|---|---|---|
| 머리·참조 (1-18) | 18 | 줄임 | :18 한 줄에 경로 9개가 몰려 있음 |
| §1-1 실행 단계 (20-35) | 16 | 유지·줄임 | 표는 핵심. :31 근거와 :33 옛 스크립트 호환은 reference로 |
| 세션 간 메시지 (36-59) | 24 | 합침 → 공용 계약 문서 | review-chain §6, pane-worker 「마」, session-handoff, task-brief §1-1과 5중 중복 |
| §1 적용 범위 (60-73) | 14 | 줄임 | :70-71 실측 근거는 설계 문서로 |
| §2 역할과 모델 (74-95) | 22 | 유지 | 표가 진본 |
| §3·§3-1 계획·롤링 분해 (96-123) | 28 | reference로 | 계획 세션에서만 필요 → `planning.md`. 단 착수 체크리스트는 남김 |
| §4 마일스톤 세션 (124-165) | 42 | 유지(핵심 흐름) | :141-144 pane 정리·사람 알림은 체크리스트 한 줄씩으로 |
| §5 조정자 규율 (166-176) | 11 | 줄임 | :170 쓰기 크기는 전역 `CLAUDE.md:70`과 중복 |
| §6-0 모드·출시 검토·30분 (177-224) | 48 | reference로 | 출시 검토(harden)는 사용자 요청 때만 씀(:197) |
| §6 검증·Sol 게이트 (225-321) | 97 | 줄이고 일부 지움 | 파괴 검토(:254-272, 19줄)는 기본 끔(:256) → 지우거나 reference로. 수렴(:295-303)·사다리(:305-320)는 `sol-review.md`로 |
| §6-1 결함 계열 (322-344) | 23 | reference로 | 전수 점검은 harden 전용(:340) |
| §6-2 시각 확인 (345-354) | 10 | 유지 | 짧고 자주 씀 |
| §7 멈춤·실패 (355-394) | 40 | 줄임 | 멈춤 조건 6개는 유지, 실패 사다리는 전역 규칙 참조 한 줄로 |
| §8 상태 파일 틀 (395-442) | 48 | reference로 | 틀은 처음 만들 때만 필요 |
| §9 인계 (443-452) | 10 | 스크립트로 | 순서가 고정된 절차라 명령 하나로 묶을 수 있음 |
| §10 진행 보고 (453-544) | 92 | 줄이고 스크립트로 | 감시 루프(:511-522)는 :529가 "고쳐 쓰지 않는다"고 할 만큼 고정 코드라 파일로 빼야 함. 대기 목록(:484-503)은 review-chain과 중복. :500 대기 표시는 탭을 건너뛰어 사고의 직접 원인(§1-1) |

### 2-2. review-chain `SKILL.md`(218줄)

| 절 (줄) | 분량 | 판정 | 이유 |
|---|---|---|---|
| §0 용어·참조 (18-24) | 7 | 유지 | |
| §1 시작 (26-35) | 10 | 스크립트로 | backend 확인·self-name·폴더·구독은 기계적 순서. launcher 경로에도 이름 단계 필요 |
| §2 상태 파일 (37-57) | 21 | 줄임 | 표만 남기고 나머지는 `references/state-files.md`로 |
| §3·§4·§5 분류·기동·선점 (59-101) | 43 | 유지(핵심) | 선점은 이미 `scripts/rc-claim.sh`로 자동화됨. 좋은 사례 |
| §6 메시지·대기 목록 (103-130) | 28 | 공용 문서와 합침 | auto-chain과 같은 규칙. :129 대기 표시도 탭을 건너뜀 |
| §7 병합 (132-146) | 15 | 유지 | 위험 구간 |
| §8-§14 (148-199) | 52 | 대부분 유지 | §9·§10 교체는 이미 reference에 있음 |
| §15 설계 결정 (201-218) | 18 | reference로 | 이력·근거라 실행 중에는 필요 없음. D5 대안 경로(:210)는 과잉 설계 후보 |

### 2-3. 계층 사이 중복

| 주제 | 나오는 곳 |
|---|---|
| 첫 지시 1회·재전송 금지 | auto-chain :38·:58, `references/pane-worker.md` §8, `~/.claude/skills/pane-worker/SKILL.md:34`, `session-handoff`, review-chain :82 |
| 받은편지함 구독·ack·pending | auto-chain :42-57, review-chain :33·:109, `references/messages.md`, `references/task-brief.md:23`, `pane-worker` 「마」, `session-handoff` |
| 대기 목록 형식 | auto-chain :484-503, review-chain :116-130, `messages.md:68`, `task-brief.md:24` |
| 이름 규칙 | 전역 `CLAUDE.md:47`, `pane-worker` 「아」(:61-68), `references/pane-worker.md:47`, `docs/herdr.md:26-27`, review-chain :30, 대기 표시 auto-chain :500·review-chain :129·`messages.md:68` |
| 회차·사다리 | auto-chain §6, `review-protocol` §2 |
| 실패 사다리 | auto-chain §7, 전역 `CLAUDE.md:59-66` |
| 150줄·8KB 쓰기 | 전역 `CLAUDE.md:70`, auto-chain :162·:170, `task-brief.md` §3 |

## 3. 개선 제안 (우선순위순)

1. **착수 명령 `agent-orchestrator session-init --role OC --name "<한글>" [--inbox <경로>]`.** 이 명령이 한 번에 하는 일:
   - 탭과 pane 모두 `--force` 없이 `self-name`을 실행합니다. 주인님이 붙인 이름에는 접두어만 붙습니다.
   - backend 확인, `mkdir -p`, `inbox-subscribe`를 합니다.
   - `whoami --field tab-label|pane-label`로 확인한 결과를 증거 한 줄로 출력합니다.

   그다음 SKILL.md의 착수 단계를 이 명령 하나로 대신합니다. 대상은 auto-chain §3의 1단계, §4 착수 줄(:127), §9 인계 뒤 child 착수, review-chain §1의 1·2·4단계, launcher 절차(`launch.md` §2)입니다.
   - 효과: 이번 사고 경로를 직접 막습니다. 이름 붙이기가 기억할 일에서 명령을 실행하면 따라오는 결과로 바뀝니다.
   - 비용: 진입점에 함수 하나(약 40줄), SKILL.md 4곳 수정. 위험: 낮음.
   - 바뀌는 파일: `tools/agent-orchestrator/bin/agent-orchestrator`, 두 SKILL.md, `launch.md`.
2. **대기 표시가 탭도 확인하게 하기(가장 쌈).** :500을 "탭은 force 없이 판정, pane만 force"로 바꿉니다. `self-name --force-pane "[OC] <탭 본문>" "[OC] … · 대기 N"` 같은 옵션을 두거나, 비강제 탭 `self-name "[OC] <본문>" -`를 먼저 실행합니다.
   - 효과: 착수 단계를 빠뜨려도 첫 대기 턴에서 탭이 바로잡힙니다.
   - 바뀌는 파일: auto-chain `SKILL.md:500`, review-chain `SKILL.md:129`, `references/messages.md:68`, 필요하면 `adapters/herdr.sh` `op_self_name`.
3. **Stop 훅 이름 검사(최종 그물).** herdr 안에서 턴이 끝날 때 탭이나 pane label에 `[XX] ` 접두어가 없으면 exit 2로 "self-name 필요" 한 줄을 냅니다. 세션당 1회만 냅니다. 판정은 접두어 유무로 해야 합니다. 빈 값과 숫자만 보면 이번 사례(사용자 이름 탭)를 놓칩니다.
   - 비용: 약 30줄. `whoami --field`와 `label_plan`은 이미 있습니다.
   - 위험: inbox-hooks의 `asyncRewake` Stop 대기자와 같은 이벤트에서 충돌하지 않는지 실측이 필요합니다.
   - 바뀌는 파일: `plugins/inbox-hooks/hooks/hooks.json` 또는 `~/.claude/hooks/` 새 파일 + `settings.json`.
4. **전역 CLAUDE.md 정리.** :47을 「작업 분담」 절 밖의 독립 줄로 옮기고 `session-init` 명령을 직접 적습니다. :37의 대체 범위에는 "이름 규칙·착수 명령은 대체 대상이 아님"을 덧붙입니다. 비용은 2줄 수정입니다.
5. **SKILL.md 맨 위에 착수 체크리스트 5~7줄.** frontmatter 바로 다음에 둡니다: ① `session-init` ② 상태 파일 읽기 ③ 첫 응답은 진행 보드 ④ 턴 끝은 `wait-status` 뒤 대기 목록 ⑤ 입력창에 치지 않음. 그리고 `references/pane-worker.md:47`의 조정자 자기 이름 문장은 지우거나 체크리스트를 가리키게 합니다(③ 전용 문서의 worker 기동 절은 진본 위치로 맞지 않음).
6. **판 표식과 근거 단락 걷어내기.** `(2.x.x)` 표식 99줄과 "근거" 단락 36개를 `docs/design/claude-autonomous-chain.md`나 CHANGELOG로 옮기고 규칙 문장만 남깁니다. 본문이 약 30% 줄어들 것으로 봅니다(추정). 위험은 근거가 안 보이면 같은 논의를 반복할 수 있다는 점으로, 설계 문서 링크 하나로 받칩니다.
7. **세션 간 메시지 계약을 한 문서로.** `tools/agent-orchestrator/docs/inbox.md`를 진본으로 두고 auto-chain·review-chain·pane-worker·session-handoff·task-brief는 한 줄 참조로 바꿉니다. 이때 1-3의 Monitor/구독 불일치와 pane 상한 불일치를 함께 고칩니다.
8. **`wait-status --list`가 대기 목록 틀과 이름 갱신까지.** 측정값으로 `대기 목록 (N):` 틀을 출력하고 제안 2의 이름 갱신도 함께 합니다. 에이전트는 이유·병목만 채웁니다. :496·:500의 "쓰기 직전에 X를 실행" 규칙이 사라집니다. 바뀌는 파일: `tools/agent-orchestrator/lib/wait-status.sh`, 두 SKILL.md.
9. **진행 감시 루프와 인계 순서를 스크립트로.** :511-522를 `scripts/progress-watch.sh`로 옮기고 재기동 직후 직접 읽기(:529)를 첫 동작에 넣습니다. 인계 4단계(:57, `references/pane-worker.md` §8)는 `scripts/handoff-coordinator.sh`로 묶습니다. 위험은 낮고, 지금처럼 고정 코드를 손으로 옮겨 쓰는 것보다 오히려 안전합니다.
10. **잘 쓰지 않는 분기는 reference로, 받은편지함 전달 보장 계획은 보류.**
    - reference로 옮길 것: 파괴 검토(기본 끔), 출시 검토, 전수 점검, 상태 파일 틀, 롤링 분해 세부, review-chain §15.
    - `docs/plans/2026-11-13-inbox-delivery-guarantee-plan.md`(68줄, §3-§9 TODO)는 입력창 알림, ack까지 최대 3회 재전송, 메시지마다 프로세스 하나, `escalations.log`·`events.log`를 새로 넣습니다. 이는 auto-chain :38("예외도 두지 않는다")과 review-chain D11(:216)을 뒤집고, 멈춤 점검(review-chain :130)·`notify`(auto-chain :46)·`wait-status`와 겹칩니다. 헤더의 예정 판(auto-chain 2.10.0·review-chain 0.4.0)은 이미 다른 기능에 쓰였습니다(git `f60a4e2`).
    - 대안: "대기 점검이 깨웠을 때 `wait-status`에 미처리 줄이 N분 넘게 남아 있으면 `notify` 1회" 규칙 하나면 사람에게 올라가는 경로가 확보됩니다.

**과잉 설계로 보이는 것**: 파괴 검토 절 전체(기본 끔인데 19줄), 사다리의 `worker:opencode-*` 칸(:313), review-chain D5 대안 경로(:210), 위 전달 보장 계획. 받은편지함 S1~S5에 크로스체크 BLOCK 수정 커밋이 10개 넘게 이어진 것(git `59449dc`~`212b3cb`)도 경합 방지가 비용에 비해 정교해졌다는 신호로 봅니다(추정).

## 4. 목표 모양

### auto-chain `SKILL.md` 목표 약 200줄

```
frontmatter (10)
0. 착수 체크리스트 (8)       ← session-init(탭·pane 이름·구독) · 상태 읽기 · 첫 응답 보드 · 턴 끝 wait-status · 입력창 금지
1. 실행 단계 표 + 내려감 (15)
2. 역할·모델 표 (18)
3. 마일스톤 세션 흐름 블록 + 마감 체크 (35)
4. 조정자 규율 (10)
5. 게이트 표 + BLOCK 범위 6항 (30)   ← 수렴·사다리 세부는 sol-review.md
6. 시각 확인 (10)
7. 멈춤 조건 6 + 실패는 전역 규칙 참조 (15)
8. 인계 = handoff-coordinator.sh (8)
9. 보고: 보드 형식 · 한 줄 보고 · 대기 목록은 wait-status --list (30)
10. reference 지도 — 언제 무엇을 여는지 (10)
```
reference로 옮길 것: `planning.md`(+롤링 분해), `modes.md`(구현·출시·30분·계열·전수 점검), `sol-review.md`(+사다리·수렴·파괴 검토), `state-file.md`(틀), `pane-worker.md`(조정자 자기 이름 문장 제거), 공용 `docs/inbox.md`. 판 표식과 근거는 설계 문서로 옮깁니다.

### review-chain `SKILL.md` 목표 약 130줄

```
frontmatter (12)
0. 착수 체크리스트 (6)        ← launch 판정 → session-init(launcher 탭 포함) → 설정 → 구독
1. 용어·폴더 (8)
2. 분류 표 (12)
3. worker 기동 (15)
4. 선점 = rc-claim.sh 종료 코드 표 (12)
5. 메시지 종류 표 + 공용 inbox.md 참조 (12)
6. 병합 7단계 (16)
7. 공용 파일 (8)
8. 교체·승격·정리 각 3줄 + reference (15)
9. 한계·멈춤 (14)
```
§15 설계 결정은 `references/design.md`로 옮기고, 대기 목록은 공용 문서를 참조합니다.

## 5. 확실하지 않은 것 (추정)

- 사고 세션이 `references/pane-worker.md`를 열었는지는 모릅니다. pane 이름의 `(최초 계획)`으로 보아 시점은 §3 계획 세션의 `chain-planner-deep` 대기 중입니다. §1-1 표(:28)는 최초 계획을 ③ pane으로 돌리므로 그 경우라면 문서를 열고도 :47을 worker 기동 세부로 넘긴 것이고, ①로 내려갔다면 아예 읽지 않은 것입니다.
- `CLAUDE.md:37`의 범위 문장이 실제로 :47을 덮어쓴 것으로 읽혔는지는 추정입니다. 컨텍스트 길이가 원인일 수도 있습니다.
- Stop 훅 exit 2가 inbox-hooks `asyncRewake` 대기자와 충돌하지 않는지는 실측이 필요합니다.
- 본문 30% 감소는 판 표식 줄 수로 낸 어림값입니다.
- `~/.claude/skills/pane-worker/SKILL.md.bak-20261113-…` 백업으로 보아 2026-11-13에 갱신이 있었습니다. 그때 「나」(상한 5)와 「마」(Monitor)가 갱신에서 빠진 것인지 의도한 것인지는 판단하지 못했습니다.

★ Insight: 사고가 날 때마다 "근거"를 붙인 문장 한 줄을 추가하는 방식이 쌓여, 문서 분량 자체가 기본 규칙을 잊게 만드는 원인이 되었습니다. 이번 사고는 규칙이 아예 없어서 생긴 일도 아닙니다. 대기 표시 규칙이 "탭은 건드리지 말라"는 안전 장치를 정확히 지켰기 때문에 착수 단계가 빠진 것이 끝까지 드러나지 않았습니다. `rc-claim.sh`처럼 판정을 스크립트에 넘긴 부분은 문서가 짧고 사고 보고도 없습니다. 착수(제안 1)와 대기 표시(제안 2)를 명령에 묶는 것이 가장 효과가 클 것으로 봅니다.
