# Sol 검토 절차 (리뷰어 공통 — 실행기 `scripts/review-run.sh`)

계획 검토, 웨이브 고위험 검토, 마일스톤 최종 검토에 쓴다. 게이트 조건·회차·수렴 규칙은 SKILL.md §6 Sol 게이트가 진본이다.

(2.2.0) 요청 파일 형식·snapshot·판정 규칙은 리뷰어와 무관하다. 리뷰어별로 다른 것은 실행 명령 하나이고, 그것은 실행기가 감춘다. 완료 근거는 실행기가 쓰는 **done 파일 하나**다. 근거: helpai M1-10에서 `리뷰 | tee 로그; echo EXIT=$?` 배선이 `tee`의 종료 코드를 읽고 표식이 로그 밖에 찍혀, 4분 만에 끝난 리뷰를 약 3시간 뒤에 회수했다.

## 1. 전제와 리뷰어 고정

- 리뷰어는 프로파일 `reviewer`(`references/profile.md`) 값이다: `opencode-sol`(기본) · `opencode-build` · `codex-cli`. 모델은 셋 다 GPT-6.1 Sol high다(`REVIEW_MODEL`·`REVIEW_EFFORT`로 바꿀 수 있다).
  - `opencode-sol`: OpenCode `review-sol` 에이전트(`~/.config/opencode/agent/review-sol.md`, 수정하지 않는다).
  - `opencode-build`: 쓰기 가능한 `build` 에이전트에 `review-sol.md`를 첨부한 우회(`REVIEW_AGENT_FILE`). 읽기 전용은 지시와 전후 snapshot 대조로만 지켜진다.
  - (2.2.1) opencode 공통: 실행 파일은 `~/.opencode/bin/opencode`를 우선한다(`REVIEW_OPENCODE_BIN`으로 바꿈). 게이트웨이 키가 필요한 환경은 실행기 호출 **전에** 키를 export한다(예: `AIGW_OPENCODE_KEY=$(~/.claude/ai-router-refresh.sh | head -1)`, 값은 로그·상태 파일에 적지 않는다). herdr pane에서 실행할 때도 같다.
  - `codex-cli`: `codex exec … -s read-only`. 샌드박스가 읽기 전용을 강제한다.
- 실행기·대기 스크립트: `scripts/review-run.sh`, `scripts/review-wait.sh`(SKILL.md와 같은 디렉터리 기준, 인자는 §3·§4).
- **착수 드라이런**(체인 착수 때, 이어받은 세션도 첫 리뷰 전 1회): 짧은 요청 파일(`# 판정: SHIP` 한 줄과 `## 검증 원장`에 HEAD 12자, 마지막 줄 `REVIEW-DONE`만 출력하라는 내용)을 §3 명령으로 돌린다. §5-1 유효 조건을 통과하면 그 리뷰어로 고정한다. 실패하면 `reviewer` 값 → `opencode-build` → `codex-cli` 순서로 다음을 시도한다(이미 시도한 값은 건너뛴다). 동작한 값과 실패 사유를 상태 파일 `## 결정`에 적고, 이후 모든 회차가 그 값을 쓴다. 근거: office 체인에서 `--agent review-sol`이 거부돼 7회 시도·약 10분을 썼다.
- 읽기 전용 primary 에이전트(예: `review-sol-primary`)를 opencode에 따로 두는 것이 `opencode-build`보다 안전하다. 사용자 환경 변경이므로 **권장(사용자 확인)**으로만 제안한다.
- 리뷰어는 이전 회차 결과를 인용하거나 `# 판정:` 같은 문자열을 시험 삼아 만들기도 한다. 결과의 판정 줄은 §5의 snapshot 대조를 통과해야 현재 판정이다.

## 2. snapshot과 요청 파일

### snapshot

요청 전에 다음을 기록한다(상태 파일과 요청 파일 모두).

- `HEAD`: `git -C <리포> rev-parse HEAD`
- 커밋된 변경 범위: `git diff <base>..<HEAD> -- <경로들>` 또는 커밋 목록
- **작업 트리 식별자**(무커밋 경로이거나 미커밋 변경이 검토 대상일 때 필수). tracked 변경과 untracked 신규 파일 내용을 모두 포함하되, **검토 절차가 스스로 쓰는 체인 메타데이터는 제외**한다. index를 쓰지 않는다.

  ```bash
  # 제외 대상: 체인의 reviews 폴더, 상태 파일, 질문 대기열. 프로파일 state가 다른 경로면 그 파일과 옆의 questions.md로 바꾼다.
  META=( ":(exclude)docs/chain/<chain-id>/reviews" ":(exclude)docs/chain/<chain-id>/state.md" ":(exclude)docs/chain/<chain-id>/questions.md" )
  cd <리포> && { GIT_OPTIONAL_LOCKS=0 git diff HEAD --binary -- . "${META[@]}"; GIT_OPTIONAL_LOCKS=0 git ls-files --others --exclude-standard -z -- . "${META[@]}" | xargs -0 shasum -a 256; } | shasum -a 256 | cut -c1-64
  ```

  검토 전후 같은 `META`로 계산한다. worker 보고서(`reports/`)와 제품 파일은 제외하지 않는다. 같은 명령의 파일 목록(`GIT_OPTIONAL_LOCKS=0 git status --short`)도 함께 적고, 검토 범위를 "`HEAD` + 이 작업 트리 변경"으로 명시한다.
  - 실행기의 `tree_before/after`는 이와 별개인 실행 중 변경 검사다(메타데이터를 빼지 않는다). 그래서 리뷰가 도는 동안에는 조정자가 리포에 아무것도 쓰지 않는다(§3).
- 문서 검토면 대상 파일 SHA-256(`shasum -a 256 <경로>`).

### 요청 파일

`docs/chain/<chain-id>/reviews/<gate>-<n>-request.md`에 쓴다(`<gate>`: `plan`, `wave-M1-W2`, `final-M1` 등).

```markdown
# 검토 요청 — <체인> <게이트> (round <k>/<상한>)

**읽기 전용**으로 작업합니다. 파일을 만들거나 고치지 않고 git 상태를 바꾸지 않습니다. 공개 자료(공식 문서·업스트림 소스) 조회는 허용하며, 조회했다면 이유와 출처를 결과에 적습니다. 결과는 최종 응답으로 출력합니다. 추론과 응답은 한국어로 합니다.

## 대상 snapshot
- 리포: <절대 경로>, HEAD `<12자 SHA>`
- 커밋된 변경 범위: <git diff base..HEAD 또는 커밋 목록>
- 작업 트리 식별자: `<64자>` (미커밋 변경 포함 시). 변경 파일: <git status --short 목록>. 미커밋 변경은 `git diff HEAD`와 신규 파일 직접 읽기로 봅니다.
- 대상 파일 SHA-256: `<경로>` `<sha>` (문서 검토일 때)
- 요구·종료 조건: <계획 문서 경로와 절>
- 실행 증거: <상태 파일의 검증 포인터>(전수 점검 task가 있었으면 그 보고서의 위치 표)

## 모드
`build` | `harden` (SKILL.md §6-0). `build`이면 BLOCK은 다음 6개로만 한정합니다: 주 흐름 미동작, 기존 기능 회귀, 데이터 손실·권한·보안 오류, 크래시·빌드 실패, 되돌리기 어려운 대상, 사용자 시각검증 지적. 그 밖의 경계 조건(화면 폭·긴/빈 데이터·입력 방식 차이·접근성 세부·시각 다듬기·드문 경로)은 `NOTE [backlog]`로 적습니다.

## 알려진 결함 계열
원장: <defect-classes.md 절대 경로>. 이번 범위에 해당하는 계열: <C<n> 목록 | 없음>.
이 계열들은 지적된 한 위치만 보지 말고 같은 패턴의 다른 호출자까지 이번 회차에 한꺼번에 찾아 나열합니다(다음 회차로 미루지 않습니다).

## 판정 기준
BLOCK은 구체적 오동작, 요구 누락·모순, 중대한 회귀, 권한·데이터 오류, 핵심 검증 누락으로 한정합니다. 취향·문서 형식은 NOTE입니다. finding마다 심각도를 BLOCK / MAJOR / MINOR / NOTE 중 하나로 붙입니다. 데이터 손실·권한 우회·비가역 변경 위험인 finding에는 심각도와 함께 태그 `[안전]`을 붙입니다(MAJOR여도 차단으로 다룹니다).

## 출력 형식
# 판정: SHIP | BLOCK
## BLOCK
- [B<n>] [BLOCK|MAJOR] [안전]? [계열: C<n> | 새: <한 줄 패턴>] <위치> — <결함> / 근거(재현 입력) / 제안
## NOTE
- [MINOR|NOTE] [backlog] <위치> — <한 줄>
## 검증 원장
- snapshot: HEAD `<12자 SHA>`, 작업 트리 식별자, 대상 SHA, 검토 전후 동일 여부

마지막 줄에 `REVIEW-DONE`을 출력하고 종료합니다.
```

- (2.1.0) 요청·결과에 적는 커밋 SHA는 **12자리**(작업 트리 식별자 64자와 대상 SHA-256은 그대로). 판정 검사(§5)는 앞 12자 일치로 본다.
- (1.6.1) 증거 이미지(PNG)는 첨부하지 않고 경로만 적는다. 계획 문서는 전문 대신 해당 절 위치를 적는다.

### delta 요청 (재검토 기본 — 무거운 게이트만)

r2 이후 재검토는 위 형식 대신 아래처럼 짧게 쓴다. 범위 규칙의 진본은 SKILL.md §6 "게이트 수렴 규칙"(2.2.0)이다. 가벼운 게이트는 프로파일 `light-gate-rereview: delta`일 때만 이 형식으로 1회 재검토한다.

```markdown
# 검토 요청 — <체인> <게이트> round <k>/<상한>[+<사다리 칸>] (delta)

**읽기 전용**. (위 형식의 금지·조회 규칙 한 줄)

## 범위 (delta 만)
- HEAD `<12자>`. 직전 snapshot `<12자>`, 직전 결과 `<결과 파일 경로>`.
- 제품 변경 커밋 `<12자>`(<파일 수>파일 +a/−b): `git show <sha>`.
- 확인할 것:
  1. 직전 finding 각각의 해소 여부 — B<n>(<계열>): <한 줄 요약> · 직전 재현 입력이 이제 <기대 결과>인지 …
  2. 이번 수정 diff가 직접 만든 회귀(정상 경로의 새 오판·중복 등)
  (breaker를 썼으면 `K<n>` 해소도 1에 넣는다)
- **범위 밖에서 새로 찾은 finding은 심각도와 관계없이 `NOTE [backlog]`로만 적습니다.** 예외: 데이터 손실·권한 우회·비가역 변경 위험을 **재현으로 확인**한 경우만 `[범위 밖·재현]`을 붙여 BLOCK으로 올립니다(재현 입력 필수). 범위 안 finding도 데이터·권한·비가역 위험이면 태그 `[안전]`을 붙입니다.
- 이미 확인한 영역은 다시 훑지 않습니다.

## 출력 형식
# 판정: SHIP | BLOCK
## 직전 finding 해소
- B<n>: 해소 | 부분 해소(<남은 반례 한 줄>) | 미해소
## BLOCK
## NOTE
## 검증 원장
- snapshot: HEAD `<12자>`, 검토 전후 동일 여부

마지막 줄에 `REVIEW-DONE`.
```

요청 파일은 `reviews/` 아래에 두므로 작업 트리 식별자의 `META` 제외에 걸린다. 요청 파일은 기동 **전에** 쓴다(실행기 snapshot보다 먼저).

## 3. 기동

```bash
S=<SKILL.md 디렉터리 절대 경로>; D=/tmp/chain-<chain-id>/reviews; mkdir -p "$D"
REQ="<요청 파일 절대 경로>"; RES="$D/<gate>-<n>-result.md"; DONE="$D/<gate>-<n>.done"; RUNF="$DONE.run"
REVIEWER=<고정한 reviewer>; REPO="<리포 절대 경로>"
CMD=$(printf '%q ' bash "$S/scripts/review-run.sh" "$REVIEWER" "$REQ" "$RES" "$DONE" "$REPO")
# 실행: herdr는 backend-herdr.md §7(명령 pane), orca는 backend-orca.md §2, agent는 Bash run_in_background로 bash -c "$CMD"
```

- (2.2.0) 경로를 따옴표로 감싸 문자열에 끼우지 않는다. 인자마다 `printf %q`로 quote한 `CMD` 하나를 만들고, 세 백엔드 모두 이 `CMD`를 그대로 넘긴다(`herdr pane run`·`orca terminal create --command`는 명령을 셸 문자열로 받는다). 경로에 `'`·공백·`$(…)`가 있어도 인자 그대로 전달된다.
- `<n>`은 회차·재시도마다 새 값이다(`final-M1-2`, 재시도 `final-M1-2b`). 실행기도 같은 경로의 이전 결과·done·로그를 `*.stale-<RUN_ID>`로 옮기지만 경로를 재사용하지 않는다.
- **RUN 기록은 `<done>.run` 하나다**(`tee` 없음). `review-run.sh`가 직접 `RUN <RUN_ID> pid=<PID> start=<시작 시각>` 한 줄을 쓰고 stdout에도 같은 줄을 낸다. 기동 직후 이 줄에서 RUN_ID·PID를 읽어 상태 파일에 적는다(구동 증거). 이 파일이 생기기 전에는 §4 대기를 띄우지 않는다. `start`는 `review-wait.sh`가 PID 재사용을 가려내는 신원이다.
- 로그·결과·done 파일은 `/tmp/chain-<chain-id>/`에 둔다. **리뷰가 진행되는 동안 조정자는 리포에 파일을 쓰지 않는다**(실행기 `ro` 검사가 깨진다). 판정을 기록한 뒤 결과 파일을 `reviews/`로 옮긴다.
- 기동은 시도당 1회. 응답을 잃었으면 `RUNF`·done 파일을 먼저 확인한다(재기동 금지).
- (1.6.1) 재검토는 항상 새 리뷰 세션이다(세션 재개 금지 — 맥락이 200k를 넘으면 응답이 오지 않는 경우가 있었다). delta 요청은 그 자체로 완결되게 쓴다.

## 4. 대기

```bash
PID=$(sed -n 's/^RUN [^ ]* pid=\([0-9]*\).*/\1/p' "$RUNF")
bash "$S/scripts/review-wait.sh" "$DONE" "$PID" 3600   # Bash run_in_background, 완료 알림을 기다린다
```

- 종료 코드: `0` = done 파일 있음(내용 출력) → §5. `3` = 실행기가 done 없이 사라짐(`exit=lost` — pid가 살아 있어도 `<done>.run`의 `start`와 시작 시각이 다르면 PID 재사용으로 보고 lost) → `unverified`, §6 재시도. `4` = timeout — 실패가 아니다. 같은 명령으로 다시 대기한다.
- 로그 grep, 결과 파일 존재, pane·터미널 상태로 완료를 판단하지 않는다. done 파일이 유일한 완료 근거다.
- 진행 보고(선택): 10분마다 경과 한 줄과 무응답 검사가 필요하면 `Monitor`로 아래를 띄운다. 알림일 뿐 완료 판정에 쓰지 않는다.

  ```bash
  LOG="$DONE.log"; T0=<기동 epoch초>; last=-1
  while [ ! -f "$DONE" ]; do
    m=$(( ($(date +%s) - T0) / 60 )); sz=$(wc -c < "$LOG" 2>/dev/null | tr -d ' '); sz=${sz:-0}
    [ "$sz" != "${psz:-}" ] && { psz=$sz; ts=$(date +%s); }
    [ $((m / 10)) -gt $last ] && { last=$((m / 10)); echo "검토 중 ${m}분 · 로그 ${sz}B"; }
    [ $(( $(date +%s) - ${ts:-$(date +%s)} )) -ge 900 ] && { echo "REVIEW-STALL 로그 ${sz}B 15분 정체"; exit 3; }
    sleep 15
  done
  ```

  `REVIEW-STALL`이면 백엔드의 화면 읽기로 1회 보고(권한 질문·입력 대기인지 기록) 실행기 PID를 끝낸다. done 파일이 `exit=signal`로 남으면 §6 "무응답 재시도"로 간다.
- 실측(giki-parity M3, 9회): 리뷰 실행은 회당 1.5~6분. 소요를 말할 때는 done 파일 `started`·`ended`로 잰다.

## 5. 판정

1. **done 파일 유효 조건**(모두 만족해야 판정을 읽는다): `exit=0` · `verdict≠none` · `ro=same` · `codex-cli`면 `sandbox=read-only` · `run_id`가 `<done>.run`의 RUN_ID와 같음. 하나라도 어기면 `unverified` → §6. (`ro=unverified` = snapshot의 git 명령이 실패해 전후 비교를 못 했다는 뜻 — `same`이 아니므로 통과하지 못한다.)
2. **결과 파일 검사**: 첫 판정 줄이 `# 판정: SHIP|BLOCK`(codex의 맨 앞 `SHIP`/`BLOCK` 한 줄도 같은 뜻), `## 검증 원장`에 요청한 HEAD 12자와 작업 트리 식별자·대상 SHA가 그대로 있음, done `head_before`가 요청 HEAD와 같음. 다르면 이전 회차 인용이거나 시험 문자열이다 → `unverified`.
3. **snapshot 대조**: 작업 트리 식별자(§2 명령, 같은 `META`)와 대상 파일 SHA가 요청 때와 같은지 본다. 리뷰어가 파일을 바꿨으면 되돌리지 말고 기록한 뒤 질문 대기열에 올린다.
4. **심각도 매핑과 `block-on`**(프로파일, 기본 `block`). 리뷰어의 원 판정과 별개로 조정자가 **실효 판정**을 정한다.

   | finding | `block-on: block` | `block-on: major` |
   |---|---|---|
   | BLOCK | 차단 | 차단 |
   | MAJOR 범위 안, `[안전]` 없음 | NOTE로 회수(백로그·후속 task) | 차단 |
   | MAJOR 범위 안, `[안전]` | 차단 | 차단 |
   | MINOR·NOTE | NOTE | NOTE |
   | delta 범위 밖, `[범위 밖·재현]` | 차단 | 차단 |
   | delta 범위 밖, 그 밖(`[안전]`만 있고 재현 없음 포함) | `NOTE [backlog]` + 다음 게이트 확인 항목 | `NOTE [backlog]` + 다음 게이트 확인 항목 |

   **안전 예외**(SKILL.md §6 "게이트 수렴 규칙" 1과 같은 규칙): 범위 **안**은 `[안전]` 태그만으로 차단, 범위 **밖**은 재현 근거가 있는 `[범위 밖·재현]`일 때만 차단한다. 판정은 태그로 한다(조정자가 내용을 다시 분류해 태그를 지우지 않는다). 범위 판정이 먼저이고, 그 다음 태그를 본다.

   차단 finding이 하나도 없으면 실효 판정은 SHIP이다. 구현 모드에서는 §6-0 BLOCK 범위 밖 finding도 차단하지 않는다. 상태 파일에는 `원 판정 → 실효 판정`을 함께 적는다(예: `BLOCK→SHIP (MAJOR 2 → NOTE, block-on block)`).
5. 상태 파일 기록: 게이트, 회차, reviewer, RUN_ID, snapshot(HEAD·작업 트리 식별자·대상 SHA), 원/실효 판정, 결과 파일 경로, 차단 finding id와 계열(`B8:C1`), delta면 각 finding의 해소 상태(`B8 부분 해소`). 원장에는 발생 줄 한 줄만 덧붙인다.
6. pane·탭 정리: 백엔드 문서의 Sol 절.

## 6. 장애 처리

- `unverified`(유효 조건 위반·`exit=lost`·snapshot 불일치): 새 `<n>`(새 RUN_ID)으로 1회 재시도.
- (1.6.1) **무응답 재시도**(`REVIEW-STALL`, 또는 `exit≠0`이면서 결과가 비어 있음): 같은 요청을 그대로 다시 보내지 않고 맥락을 줄여 1회 다시 보낸다.
  - 재검토(delta)였으면 첨부 이미지를 빼고 경로로 바꾼다.
  - 첫 회차(r1)였으면 요청을 영역 2개로 나눠(예: 제품 코드 / 시험·증거) 동시에 띄운다. 둘 다 SHIP이어야 SHIP이고 차단 finding은 합친다. 회차는 1회로 센다.
  - 무응답은 BLOCK이 아니라 `unverified`다.
- 고정한 리뷰어가 재시도 뒤에도 `unverified`면 §1 순서의 다음 리뷰어를 드라이런하고, 통과하면 그 리뷰어로 같은 요청을 1회 보낸다. 바꾼 사실을 `## 결정`에 적는다. 이 전환은 **실행 장애에만** 쓴다(BLOCK을 받았다고 리뷰어를 바꾸지 않는다).
- 그래도 안 되면:
  - **웨이브 고위험 검토**: `Agent`(model: opus, 읽기 전용 지시)로 같은 요청을 보조 검토하고 그 결과로 진행할 수 있다. 해당 task를 `sol-pending`으로 표시하고 마일스톤 최종 검토 범위에 넣는다.
  - **계획 검토·마일스톤 최종 검토**: Claude 리뷰로 대체하지 않는다. 게이트를 `unverified`로 두고 멈춤 조건 5로 보고한다.

## 7. Sol 원인 조사 (`root-cause: sol`일 때만)

프로파일 `root-cause: sol`일 때 SKILL.md §7 실패 사다리에서 쓴다(기본 `none`이면 쓰지 않는다). 게이트가 아니므로 회차·판정에 넣지 않는다. 기동·대기·장애 처리는 §3~§6과 같고, 요청 파일은 `reviews/cause-<task-id>-<n>-request.md`다. 실행기는 `# 판정:` 줄을 찾으므로 출력 첫 줄을 `# 판정: SHIP`(형식상 표식 — 판정 아님)으로 두게 한다.

```markdown
# Sol 원인 조사 — <체인> <task-id> (판정 아님)

**읽기 전용**. 파일을 만들거나 고치지 않고 git 상태를 바꾸지 않습니다. 재현·시험 실행은 허용하되 출력은 `/tmp`에만 둡니다. 추론과 응답은 한국어로 합니다.

## 사실
- 리포 <절대 경로>, HEAD `<12자>` (실패 커밋), 통과하던 커밋 `<sha | 없음>`
- 증상: <한 줄>
- 재현 명령: `<명령>` → <실패 출력 핵심 2~5줄 또는 로그 경로>

## 반박된 가설 (이미 틀림)
- H1: <첫 시도의 가설> — <고친 내용> 뒤에도 <증상>

## 의심 지점 (검증 대상, 확정 아님)

## 출력 형식
# 판정: SHIP   ← 형식상 첫 줄(판정 아님)
# 원인
- 위치·메커니즘·확신도(높음|중간|낮음 — 근거)
# 근본 수정안
# 수정을 가르는 최소 관찰
# 증상만 맞추는 수정 (하지 말 것)
## 검증 원장
- HEAD `<12자>`

마지막 줄에 `REVIEW-DONE`.
```

- 결과는 `reviews/cause-<task-id>-<n>-result.md`에 저장하고 `## 결정`에 원인·채택 근거를 한 줄 남긴다. 확신도가 낮음이면 최소 관찰을 먼저 실행한다(실패 횟수에 넣지 않는다).
