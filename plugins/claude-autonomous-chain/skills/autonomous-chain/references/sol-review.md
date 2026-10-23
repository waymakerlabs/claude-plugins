# Sol 검토 절차 (OpenCode `review-sol` via Orca 탭)

계획 검토, 웨이브 고위험 검토, 마일스톤 최종 검토에 쓴다. 게이트 조건과 회차는 SKILL.md §6 Sol 게이트가 진본이다.

## 1. 전제

- Orca 런타임 ready(`orca status`), OpenCode CLI, `review-sol` 에이전트 정의(`~/.config/opencode/agent/review-sol.md`). 이 정의는 수정하지 않는다.
- `review-sol`은 읽기 전용 정의가 우선해 **결과 파일을 쓰지 않는다**. 결과는 터미널 출력으로 받는다.
- OpenCode 권한이 넓게 열려 있어 읽기 전용은 지시로만 지켜진다. 요청 파일에 금지를 명시하고, 검토 전후 snapshot을 대조한다.
- 리뷰어는 이전 회차 로그·결과를 읽고 그대로 출력하거나, 요청의 명령을 시험하려고 `# 판정:`·`REVIEW-DONE` 같은 문자열을 직접 만들기도 한다. 로그 안의 이런 줄은 **현재 판정이나 종료 신호가 아닐 수 있다**. 아래 nonce 표식과 snapshot 대조로만 구분한다.

## 2. snapshot과 요청 파일

### snapshot

요청 전에 다음을 기록한다(상태 파일과 요청 파일 모두).

- `HEAD`: `git -C <리포> rev-parse HEAD`
- 커밋된 변경 범위: `git diff <base>..<HEAD> -- <경로들>` 또는 커밋 목록
- **작업 트리 식별자**(무커밋 경로이거나 미커밋 변경이 검토 대상일 때 필수). tracked 변경과 untracked 신규 파일 내용을 모두 포함한다. index를 쓰지 않는다.

  ```bash
  cd <리포> && { GIT_OPTIONAL_LOCKS=0 git diff HEAD --binary; GIT_OPTIONAL_LOCKS=0 git ls-files --others --exclude-standard -z | xargs -0 shasum -a 256; } | shasum -a 256 | cut -c1-64
  ```

  같은 명령의 파일 목록(`GIT_OPTIONAL_LOCKS=0 git status --short`)도 함께 적고, 검토 범위를 "`HEAD` + 이 작업 트리 변경"으로 명시한다.
- 문서 검토면 대상 파일 SHA-256(`shasum -a 256 <경로>`).

### 요청 파일

`docs/chain/<chain-id>/reviews/<gate>-<n>-request.md`에 쓴다(`<gate>`: `plan`, `wave-M1-W2`, `final-M1` 등).

```markdown
# Sol 검토 요청 — <체인> <게이트> (round <k>/<상한>)

**읽기 전용**으로 작업합니다. 파일을 만들거나 고치지 않고 git 상태를 바꾸지 않습니다. 공개 자료(공식 문서·업스트림 소스) 조회는 허용하며, 조회했다면 이유와 출처를 결과에 적습니다. 결과는 터미널에 출력합니다. 추론과 응답은 한국어로 합니다.

## 대상 snapshot
- 리포: <절대 경로>, HEAD `<40자 SHA>`
- 커밋된 변경 범위: <git diff base..HEAD 또는 커밋 목록>
- 작업 트리 식별자: `<64자>` (미커밋 변경 포함 시). 변경 파일: <git status --short 목록>. 미커밋 변경은 `git diff HEAD`와 신규 파일 직접 읽기로 봅니다.
- 대상 파일 SHA-256: `<경로>` `<sha>` (문서 검토일 때)
- 요구·종료 조건: <계획 문서 경로와 절>
- 실행 증거: <상태 파일의 검증 포인터>

## 검토 범위
(재검토면) 1. 직전 BLOCK 각각의 해소 여부 2. 그 수정의 영향 3. 새 근거로 확인한 요청 범위 안의 중대한 결함(이번 수정이 만든 것이 아니어도). 새 근거가 없으면 이미 확인한 영역은 다시 훑지 않습니다.

## 판정 기준
BLOCK은 구체적 오동작, 요구 누락·모순, 중대한 회귀, 권한·데이터 오류, 핵심 검증 누락으로 한정합니다. 취향·문서 형식은 NOTE입니다.

## 출력 형식
# 판정: SHIP | BLOCK
## (재검토면) 직전 BLOCK 해소
## BLOCK
- [B<n>] <위치> — <결함> / 근거 / 제안
## NOTE
## 검증 원장
- snapshot: HEAD `<SHA>`, 작업 트리 식별자, 대상 SHA, 검토 전후 동일 여부

마지막 줄에 `REVIEW-DONE`을 출력하고 종료합니다.
```

요청 파일 자체는 검토 대상 snapshot에 넣지 않는다(커밋하지 않아도 되고, 작업 트리 식별자 계산 전에 만들면 식별자에 들어가므로 **식별자를 먼저 계산**한다).

## 3. 기동

Orca에 **등록된** worktree에 탭을 연다. 대상 리포가 등록되지 않았으면 `--worktree active`가 `selector_not_found`로 실패하므로, 등록된 worktree(`path:<등록 경로>`)에 열고 명령 안에서 `cd`한다.

```bash
REQ="<요청 파일 절대 경로>"
NONCE="$(shasum -a 256 "$REQ" | cut -c1-12)"   # 회차마다 요청이 다르므로 nonce도 다르다
TITLE="chain-<chain-id>-<gate>-<n>"            # 세션 식별용 고유 제목
LOG="<리포>/docs/chain/<chain-id>/reviews/<gate>-<n>.log"
CMD="cd '<리포>' && { opencode run --agent review-sol -m 'ai-gateway-openai/gpt-6.1-sol#high' --title '$TITLE' -f '$REQ' '첨부한 요청 파일을 읽고 그대로 검토해. 마지막 줄은 REVIEW-DONE.' 2>&1; echo \"SOL-EXIT-$NONCE=\$?\"; } | tee '$LOG'"
orca terminal create --worktree <active|path:등록경로> --title "$TITLE" --command "$CMD" --json
```

- 중괄호 묶음이 핵심이다. `echo`가 파이프 안에 있어야 표식이 **로그에 기록되고**, `$?`가 `tee`가 아니라 `opencode`의 종료 코드가 된다(`… | tee LOG; echo $?`는 둘 다 틀린다).
- `create`는 시도당 1회. 응답 전체에서 handle을 즉시 추출한다(잘라서 잃으면 `orca terminal list`로 title 기반 재확보, 재create 금지).
- 재검토는 같은 리뷰 세션을 재개한다: `opencode run -s <ses_id> --agent review-sol -m … -f '<round k 요청>' …` (같은 중괄호·nonce 배선). 세션 ID는 첫 회차 후 `cd <리포> && opencode session list --format json`에서 `$TITLE`과 같은 제목을 찾아 상태 파일에 기록한다. 찾지 못하면 새 세션으로 하되 요청에 직전 결과 파일 경로를 넣는다.
- **리뷰가 진행되는 동안 대상 문서·코드를 고치지 않는다.** 독립 작업(다른 웨이브의 비대상 파일 등)은 계속해도 된다.

## 4. 대기

- 완료 신호는 ANSI 코드를 지운 로그에서 **이번 nonce의 표식 줄 전체 일치** 하나다: `^SOL-EXIT-<NONCE>=[0-9]+$`. 값이 0이 아니면 검토 실패다.
- 로그의 `REVIEW-DONE`·`SOL-EXIT=`·`# 판정:` 단순 grep은 완료 신호로 쓰지 않는다(인용과 리뷰어 시험 문자열에 걸린다). Orca 터미널 status도 쓰지 않는다(명령이 끝나도 셸이 남아 `running`으로 보인다).
- `Bash run_in_background`로 기다리고 완료 알림을 받는다. 화면을 반복해서 읽지 않는다.

  ```bash
  until sed -E 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -qE "^SOL-EXIT-$NONCE=[0-9]+$"; do sleep 15; done
  ```

- 구현 검토는 30분 이상 걸릴 수 있다(리뷰어가 명령을 직접 시험한다). 시간만으로 실패로 보지 않는다. 60분을 넘기면 `orca terminal read --terminal <handle> --screen --json`으로 1회 상태를 보고, 권한 질문 등 입력 대기면 기록 후 탭을 닫고 1회 재시도한다.

## 5. 결과 추출과 판정

1. ANSI 색 코드를 지우고, **이번 nonce 표식 줄 앞까지만** 본다. 그 범위에서 새 `^# 판정:`이 시작될 때마다 이전 결과를 버리고, 마지막 판정 블록이 `^REVIEW-DONE$`으로 닫히지 않았으면 **빈 결과**로 둔다.

   ```bash
   sed -E 's/\x1b\[[0-9;]*m//g' "$LOG" | awk -v m="^SOL-EXIT-$NONCE=" '
     $0 ~ m {exit}
     /^# 판정:/ {buf=""; on=1; last=""}
     on {buf=buf $0 "\n"}
     /^REVIEW-DONE$/ {if(on){last=buf; on=0}}
     END {if(on) last=""; printf "%s", last}' > "$RESULT"
   ```

   저장할 때 맨 위에 출처 주석(리뷰어·세션 ID·로그 행 범위·snapshot 일치 여부)을 단다.
2. 추출 결과를 검사한다. 하나라도 어기면 `unverified`로 기록하고 1회 재시도한다.
   - 비어 있지 않고 `# 판정: SHIP` 또는 `# 판정: BLOCK`으로 시작
   - `## 검증 원장`(또는 동등한 snapshot 줄)에 요청한 HEAD SHA(앞 12자 이상)와 작업 트리 식별자·대상 SHA(요청에 있던 것)가 **그대로** 있다. 다르면 이전 회차 인용이거나 리뷰어의 시험 문자열이다.
3. 검토 전후 snapshot 대조: `HEAD`, 작업 트리 식별자(§2 명령 재실행), 대상 파일 SHA가 요청 때와 같은지 확인한다. `git status --short`만으로는 같은 경로의 내용 변경을 알 수 없으므로 식별자로 본다. 리뷰어가 파일을 바꿨으면 그 변경을 되돌리지 말고 기록한 뒤 질문 대기열에 올린다.
4. 상태 파일에 기록: 게이트, 회차, snapshot(HEAD·작업 트리 식별자·대상 SHA), 리뷰 세션 ID, nonce, 판정, 결과 파일 경로, BLOCK id 목록.
5. 탭 정리: `orca terminal close --terminal <handle> --tab --json`.

## 6. 장애 처리

- 기동 실패·표식 값 비0·빈 결과·snapshot 불일치: 1회 재시도.
- 그래도 안 되면:
  - **웨이브 고위험 검토**: `Agent`(model: opus, subagent_type: general-purpose, 읽기 전용 지시)로 같은 요청을 보조 검토한다. 그 결과로 push까지 진행할 수 있다. 해당 task를 상태 파일에 `sol-pending`으로 표시하고 마일스톤 최종 Sol 검토 범위에 반드시 넣는다.
  - **계획 검토·마일스톤 최종 검토**: 다른 리뷰어로 대체하지 않는다. 게이트를 `unverified`로 두고 멈춤 조건 5로 보고한다. Opus 보조 검토를 미리 해 둘 수는 있지만 통과 근거로 쓰지 않는다.
