---
name: orca-codex-delegate
description: >-
  Tracked Orca Run/Task로 Codex에게 실제 review 또는 implementation을 수행시킬 때 사용. 트리거:
  "codex한테 시켜/맡겨", "codex로 크로스체크해줘", "codex로 구현위임", 사용자가 명시적으로 review/구현을
  Codex로 시킬 때, 또는 Claude Code 전역 CLAUDE.md의 "서브에이전트 엔진 우선순위" 자기점검(Agent 도구
  호출 직전)·"고위험 plan/작업완료 codex 크로스체크 의무" 게이트가 발동했을 때. 이 스킬은 Run/Task/dispatch
  명령 순서, worker 프로필(orca-review 읽기전용 / orca-implement 쓰기), 대기·수신 규율, 실측 함정,
  finding 보고 형식을 담은 절차 문서다. `orca-cli`/`orchestration` skill 위에 있는 Codex 특화 정책
  레이어이며, 저 두 스킬은 Orca CLI 자체의 사용법을 다룬다. 사용하지 않는 경우: 일반적인 Orca CLI/프로필
  설명 질문, 다른 Claude Code 세션으로의 full handoff(그건 별도 탭 인계 절차).
---

# Orca-Codex 위임 절차

> 이 문서를 실제로 열었다면 — 이미 트리거가 켜졌다는 뜻이다. 절차를 시작하기 전에 임의로 `codex exec`나
> 일반 서브에이전트로 대체하지 말고, 아래 순서를 그대로 따른다. CLAUDE.md의 자기점검 문구는 "언제 이
> 스킬을 부를지"만 판단하고, 부른 뒤의 모든 실행 세부는 여기 있다.

## 1. 역할 경계

| | 크로스체크 프로토콜 (읽기전용) | 구현위임 프로토콜 (쓰기) |
|---|---|---|
| 방향 | Claude가 만든 것을 → codex가 외부 검토 | codex가 만든 것을 → Claude가 직접 검토 |
| worker 프로필 | `orca-review` (workspace-write이지만 정책상 읽기전용) | `orca-implement` (실제 파일 수정 허용) |
| 완료 후 재검토 | (해당 없음 — 검토가 곧 결과물) | codex 자체 재검토 요구 안 함, **Claude가 직접** diff·근거코드 대조 |
| 트리거 문구 | "Orca로 codex한테 크로스체크해줘", 고위험 plan/완료 게이트 | "이 작업 codex한테 시켜", "실작업은 codex로" |

Claude(coordinator) = 계획·분해·Task 작성·결과 검토·최종 판단·사용자 보고.
Codex(worker) = 코드/문서 조사, 파일 수정·구현, 테스트 작성·실행, 재현, 결과 보고.

## 2. 사전 점검 (처음 쓰기 전에만, 세션당 1회)

- `orca status --json` — 런타임 가용성. 미가용이면 `codex:codex-rescue` subagent로 폴백하고 폴백 사실을
  보고에 명시.
- `orca skills get orchestration --full` — 최신 계약 확인(세션 2회차부터는 재확인 불요).
- codex CLI 준비상태: `node <codex-companion.mjs 경로> setup --json`, 없으면 `codex --version`/
  `codex login`으로 대체 확인.
- `~/.codex/config.toml`의 실제 모델·effort·service_tier — **이 값은 계속 바뀐다.** 문서·narration에
  적을 때 그때그때 확인해서 적고, 예전 세션 값을 그대로 옮겨 적지 않는다. 사용자가 특정 모델/effort/
  "fast" 같은 설정을 요청하면 그게 이미 base config 기본값인지 먼저 확인하고, 존재하지 않는 필드는
  가장 가까운 대응(예: `service_tier=priority`)을 찾아 설명한다 — 지어내지 않는다.
- 프로필 존재 확인: `~/.codex/orca-review.config.toml`(읽기전용 정책), `~/.codex/orca-implement.config.toml`
  (쓰기 허용). 둘 다 모델/effort는 base config를 상속하고 `approval_policy=never`+network 허용만
  덮어쓴다(대칭 구조).

## 3. worktree 선택 (교정 — 2026-08-12 codex 크로스체크로 확정)

두 방식이 있고, 상황에 따라 다르다 — 무조건 한쪽으로 치환하지 않는다:

- **대상 리포가 task 계약상 명확할 때** (예: "이 리포에서 크로스체크해줘") → `--worktree
  path:<repo-절대경로>`로 명시. `--worktree active`는 Orca의 현재 활성 워크트리가 다른 프로젝트를
  가리키고 있어도 그쪽에 worker가 생기는 실측 사고가 있었다(2026-08-04, `path:` 미명시로 legacy-lens에
  리뷰 워커가 생성됨).
- **"지금 사용자가 보고 있는 worktree"가 계약 자체일 때** → `--worktree current`(또는 low-level
  경로에서 `active`)가 맞는 선택이다. 이 경우 `path:`로 바꾸면 오히려 사용자 의도와 다른 고정 경로를
  참조하게 된다.
- 확실하지 않으면 worker 생성 직후 실제 대상이 맞는지 확인한다(워커의 cwd 또는 `orca terminal list
  --json`의 worktree 필드 대조).

## 4. 크로스체크 절차 (읽기전용)

0. **세션 첫 크로스체크에서만** `orca status --json` + `orca skills get orchestration --full`로 런타임
   가용성과 현재 버전 지침을 확인한다. 같은 세션 2회차부터는 재확인하지 않는다.
1. **리뷰 단위마다 전용 Run을 만든다.** `orca orchestration run-create --objective "<범위> 읽기 전용
   크로스체크" --json`으로 coordinator를 Run에 bind하고, `orca orchestration check --run <run_id>
   --peek --format --json`으로 자기 Run의 미확인 메일만 점검한다. `--all`은 이력 조회일 뿐 배수가
   아니고, 이전 Run의 결과를 새 리뷰 결과로 해석하지 않는다. **`run-create`를 프로브로 재호출하지
   않는다** — 코디네이터 바인딩이 새 Run으로 옮겨간다(실측). run id는 `run-create` 응답에서 바로 잡는다.
2. `orca orchestration task-create --run <run_id> --spec "..." --json`으로 task를 만든다. spec에는
   범위·읽기 전용 여부·검증할 주장/파일/테스트·시작/종료 snapshot(HEAD, branch, `git status --short`,
   대상 diff 또는 commit)·독립 oracle 또는 negative control 1개를 구체적으로 적는다. 리뷰 요청이면
   기본값은 읽기 전용:
   - 파일 수정·stage·commit·reset·외부 시스템 mutation 금지
   - 진행 중인 변경 또는 snapshot 불일치는 즉시 보고하고, 결론을 섞지 말고 재기준화한다
   - **출력 형식 강제**: finding 1건 = 1블록, 접두사 `[BLOCK]`/`[WARN]`/`[NIT]` + `파일:라인` + 한
     문장 주장 + 제안 1줄. 마지막 줄은 `BLOCK=n WARN=n NIT=n`. 문제 없으면 명시적으로 `no finding`.
3. **현재 미커밋 diff를 검토해야 하면 같은 worktree에서 순차적으로** worker를 연다. 별도 worktree는
   실제 checkout 또는 파일 충돌 때문에 공유가 불가능한 경우만 쓴다. worker 기동은 §3 기준으로 worktree를
   고르고 `orca-review` 프로필로: `orca terminal create --worktree <path:.../current> --title "<작업명>"
   --command "codex --profile orca-review" --json` → `tui-idle` 대기 → `orca orchestration dispatch
   --task <task_id> --to <handle> --inject --json`.
4. `orca-review`의 `workspace-write`는 **읽기 전용의 기술적 보장이 아니라 task spec의 정책 보장**이다.
   전용 read-only 프로필을 별도 검증하기 전까지 이 한계를 최종 보고에 명시한다.
5. 자기 handle을 모르면 **임의의 기존 agent terminal을 `--from`으로 사칭하지 않는다.** 전용
   coordinator terminal을 만들거나 현재 handle을 확인한 뒤 Run을 bind한다.
6. **대기·수신 규율**:
   - `check --wait`는 자기 Run의 가장 오래된 Delivery를 `--ack <delivery_id>` 전까지 재전달한다.
     Delivery 전체를 처리하고 `taskId`·`dispatchId` 일치를 확인한 뒤에만 ack한다.
   - `check --wait` 출력은 JSON 객체 여러 개다(keepalive 다수 + 마지막에 실제 Delivery). 단일
     `json.load`는 `Extra data`로 실패한다 → 파일로 받아 `JSONDecoder().raw_decode` 루프로 파싱하고
     **마지막 객체**의 `result`를 본다. keepalive를 결과로 오독하면 `count=None`을 "결과 없음"으로
     오인한다.
   - `--wait` 타임아웃·`count:0`은 실패가 아니라 체크포인트다. `orca orchestration worker-show
     --dispatch <id> --json`으로 상태를 확인하고, 활동 중이면 계속 기다린다. 코딩·리뷰 작업은 15~60분이
     정상이다.
   - worker는 `worker_done`을 정확히 한 번, 명시적 `--outcome succeeded|failed`와 함께 보내야 한다.
7. 완료 후 `task-list --run <run_id>`와 `dispatch-show --task <id>`(또는 `worker-show`)로 실제
   tracked 결과를 검증한다. **리뷰 worker의 완료는 finding 보고일 뿐 수정 권한이 아니다** — 수정은
   승인 시 별도 task로 배정한다.
8. **finding을 그대로 수용하지 않는다** — 특히 BLOCK은 해당 파일·라인과 종료 snapshot을 직접 열어
   사실을 확인한 뒤 반영한다.
9. 리뷰가 끝나면 worker terminal을 정리한다: `orca terminal close --terminal <handle>`(탭째 정리는
   `--tab`). 쌓이면 다음 크로스체크에서 handle 혼동을 부른다.
10. `orca orchestration reset`은 다른 진행 중 작업까지 지울 수 있으므로, 전체 orchestration 상태 폐기를
    명시 요청받지 않는 한 실행 금지.

최종 보고에 짧게 포함: Run/task/dispatch ID·worker 종류 / 검토 범위와 snapshot / 읽기 전용 준수 여부와
기술적 한계 / 집계(BLOCK/WARN/NIT)와 확정 finding 또는 no finding / 직접 확인한 항목과 근거(파일:라인) /
oracle·검증 명령과 결과 / 다음 수정 task 필요 여부.

## 5. 구현위임 절차 (쓰기)

크로스체크의 반대 방향 — codex가 구현하는 것을 Claude가 오케스트레이션하고 직접 크로스체크한다.

0. **처음 쓰기 전에 가능성부터 테스트한다** — §2 사전 점검을 실행하고 결과를 짧게 보고한다.
1. **세션 첫 위임에서만** `orca skills get orchestration --full`로 최신 계약을 확인한다. 사용자가
   "직접 크로스체크하겠다"고 명시했으므로 **감독형(coordinated subtask)**으로 분류한다 — full handoff가
   아니라 Run→Task→dispatch --inject→check --wait→worker_done 경로를 그대로 따른다.
2. **워커는 §3 기준으로 worktree를 고르고** `orca terminal create --command "codex --profile
   orca-implement"`로 띄운다(low-level 경로). `worker-start --agent codex` 조합형이 codex CLI 업데이트
   프롬프트로 막히는 경우가 있으니, 막히면 low-level 경로로 폴백한다.
3. **task spec은 구체적으로 쓴다** — 수정 대상 파일 경로(정확히 그 파일만, 범위 밖 수정 금지 명시)·
   근거가 되는 실제 코드 위치(함수명·대략 라인, "grep으로 재확인" 지시)·요구사항 각 항목·해당 리포의
   금지 표현/스타일 가이드가 있으면 명시·**git commit은 하지 않는다(조정자가 리뷰 후 처리)**를 매번
   명시한다. 인용부호가 복잡한 heredoc은 커밋위생 훅에 토큰화 실패로 막힐 수 있으므로, spec이 길면
   임시 파일에 쓰고 `$(cat 파일)`로 전달한 뒤 즉시 삭제한다.
4. `worker_done` 수신 후 **codex 자체 재검토를 요구하지 않는다** — 대신 Claude(조정자)가 직접:
   ① `git diff --stat`/`git status --short`로 변경 범위가 spec대로인지 확인
   ② 변경 내용이 근거로 든 실제 코드·자산과 사실적으로 일치하는지 그 코드를 직접 열어 대조
   ③ 해당 리포의 금지 표현·문서 톤 일치 여부 확인.
   §4의 finding 형식(BLOCK/WARN/NIT)을 그대로 써도 되고, 간단한 변경이면 서술형으로 대체해도 된다 —
   핵심은 "codex가 잘했다고 보고했다"를 그대로 받지 않고 직접 확인하는 것이다.
5. **되돌리기 어려운 고위험 변경**(스키마·배포/보안 설정·계약 문서·비가역 런타임 동작)이면 Claude
   직접 리뷰에 더해 별도 codex 리뷰 워커(§4 크로스체크 절차)를 추가로 돌린다 — 고위험 판단 기준은 이
   skill이 정의하지 않는다. 호출한 세션의 `~/.claude/CLAUDE.md` 운영 규칙을 참조한다(같은 기준을 두
   곳에 중복 정의하면 드리프트가 재발한다 — 2026-08-12에 이 skill을 분리하며 실제로 발견한 문제와
   같은 종류).
6. **정리**: `orca orchestration worker-release --dispatch <id>`가 `dispatch_not_found`를 반환할 수
   있다(이 Orca 버전은 `worker_done` 처리 시점에 capability를 이미 자동 회수하는 것으로 보인다 —
   `capability_revoked_at`이 완료 시각과 동일한 것으로 실측). 에러로 취급하지 말고 `orca terminal
   close --terminal <handle>`로 대체 정리한다.
7. 이 절차로 이미 Claude가 직접 크로스체크를 마쳤다면, 별도 wrap-up류 codex 크로스체크 게이트는 그
   라운드에서 생략해도 된다 — 단, §5의 고위험 기준에 해당하면 생략하지 않는다.

최종 보고에 짧게 포함: Run/task/dispatch ID·codex 프로필과 실제 모델/effort(확인한 값)·위임한 변경
범위·**Claude가 직접 확인한 항목과 근거(파일:라인)**·추가 codex 리뷰 필요 여부(고위험이면 실행
결과까지).

## 6. 공통 실측 함정 (두 절차 모두 적용)

1. **`--worktree active` 오조준** — §3 참조. 대상이 명확하면 `path:`로 명시.
2. **`check --wait` replay** — 이전 Delivery를 ack하지 않으면 같은 메일이 계속 replay된다. 수신 메일의
   `payload.taskId`·`dispatchId`가 이번 라운드 것과 일치하는지 매번 확인.
3. **`check --wait` 다중 JSON** — keepalive 다수 + 마지막 실제 Delivery. `raw_decode` 루프로 파싱,
   마지막 객체만 결과로 취급.
4. **`run-create` 재호출이 바인딩 이동** — 프로브 목적으로 다시 부르면 코디네이터 바인딩이 새 Run으로
   옮겨간다. `run-use --id <원래 run>`으로 되돌린다.
5. **`worker-read --dispatch <id>`는 워커 종료 후 `dispatch_not_found`** — agent terminal이 이미
   소멸했기 때문. finding 전문은 `orca terminal read --terminal <handle>`의 `result.terminal.tail`
   (문자열 배열)에서 읽고 ANSI 이스케이프를 지운다. 워커 handle을 기록해두면 편하다.
6. **`worker-release`의 `dispatch_not_found`** — §5-6 참조. 완료 시점에 capability가 이미 자동
   회수된 것으로 보임. 에러로 취급 말고 `terminal close`로 대체.

## 7. 적용 범위

이 skill은 **이 Mac의 로컬 Claude Code 세션**에 적용된다(전역 `~/.claude/skills/`에 있으므로 로컬
프로젝트 전체에서 발견됨). Cloud/Cowork 등 원격 세션에는 자동으로 전파되지 않는다 — 그런 세션에서
같은 절차가 필요하면 계정 skill 업로드 또는 repo-level skill/plugin 배포를 별도로 검토한다.

## 8. 명령·경로 표기 원칙

여기 실린 명령은 예시이며 사용자·리포별 절대경로, 인증정보, 고정 handle/worktree ID를 담지 않는다.
실행 시 Orca가 반환한 JSON 값(handle, task_id, dispatch_id, run_id)을 그대로 쓴다. 리포 경로는
`<repo-root>`처럼 자리표시자로 두고, 실제 실행 시 그 세션의 실제 경로로 채운다.
