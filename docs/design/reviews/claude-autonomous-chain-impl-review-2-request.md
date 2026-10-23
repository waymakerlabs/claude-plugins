# Sol 재검토 요청 — claude-autonomous-chain 구현 (round 2/3)

1차 구현 검토 세션을 재개한 것입니다. **읽기 전용**으로 작업합니다. 파일을 만들거나 고치지 않고 git 상태를 바꾸지 않습니다. 공개 자료 조회는 허용하며, 조회했다면 이유와 출처를 결과에 적습니다. 결과는 터미널에 출력합니다. 추론과 응답은 한국어로 합니다.

## 대상 snapshot

- 리포: `/Users/peter/Dev/claude-plugins`, 브랜치 `feat/claude-autonomous-chain`, HEAD `83dc9114577e1f9b99155d050c9d4c0ef3bb4b75`, `git status --short` 깨끗함(이 요청 파일만 미추적)
- 수정 커밋: `83dc911` (직전 검토 대상 `7b01b51`). 변경 범위: `git diff 7b01b51..83dc911`
- 리포 밖 파일(`~/.claude/CLAUDE.md`, memory)은 1차 이후 바뀌지 않았습니다. SHA는 1차 요청과 같습니다(`b4c5b9e2…`, `08ec709a…`).
- 1차 결과: `docs/design/reviews/claude-autonomous-chain-impl-review-1-result.md`

## 반영 내용 (1차 BLOCK → 위치)

| id | 반영 위치 | 요지 |
|---|---|---|
| B1 | `references/sol-review.md` §3·§4 | `{ opencode …; echo "SOL-EXIT-$NONCE=$?"; } \| tee LOG` — 표식이 로그에 기록되고 opencode 종료 코드 보존. nonce = 요청 파일 SHA-256 앞 12자. 완료 신호는 nonce 표식 줄 전체 일치만 |
| B2 | `references/sol-review.md` §5 | awk가 nonce 표식 줄에서 멈추고, 새 `# 판정:` 시작 시 `last=""`, 끝에서 블록이 열려 있으면 빈 결과 |
| B3 | `references/planning.md` §0, `agents/chain-planner-deep.md` | 공통 금지를 두 planner가 모두 읽는 파일과 깊이 정의 본문에 직접 명시 |
| B4 | `references/task-brief.md` §6, `SKILL.md` §4 worker 기동 | 보고서를 조정자 도구 입력 파일로 명시, 파일 없으면 worker 실패. 실측 결과는 설계 §17 새 행 |
| B5 | `references/sol-review.md` §2·§5, `SKILL.md` §5 | 작업 트리 식별자(`git diff HEAD --binary` + untracked 파일 내용 해시)를 snapshot·검토 전후 대조에 사용 |
| N1 | 설계 §17 | effort가 API 요청까지 실렸음을 기록, 모델 적용은 미확인으로 구분 |

수정 전 셸 배선 시험(조정자가 실제 zsh로 실행): 실패 명령 → 로그에 `SOL-EXIT-<nonce>=1`, 1차 로그에서 BLOCK 블록 정확 추출, 잘린 마지막 판정 → 0바이트, 표식 뒤 잡음 무시, 인용된 다른 nonce 0건 매치, BSD `xargs -0` 빈 입력 시 shasum 미실행.

**이 2차 검토 자체가 새 배선으로 기동됐습니다.** 이 요청 파일의 SHA-256 앞 12자가 이번 nonce입니다.

## 검토 범위

1. 1차 BLOCK B1~B5가 각각 해소됐는지.
2. 그 수정의 영향. 특히:
   - §3 기동 명령: 중괄호 안 `2>&1`과 `$?`의 의미, Orca가 넘기는 `--command` 문자열 안의 따옴표·이스케이프가 실제 탭 셸에서 성립하는지
   - §5 awk: 표식 줄 이후를 버리는 것이 정상 판정 블록을 잃는 경우가 있는지
   - §2 작업 트리 식별자: 요청 파일을 식별자 계산 **후**에 만드는 순서가 지켜지는지, 계산 명령이 index를 쓰지 않는지
   - B4: "도구 입력 파일 예외" 해석이 하니스 지시와 맞는지, 실측이 그 판단을 뒷받침하는지
3. 새 근거로 확인한 요청 범위 안의 중대한 결함(이번 수정이 만든 것이 아니어도).

새 근거가 없으면 1차에서 이미 확인한 영역(N2: 조정자 커밋·전역 변경)은 다시 훑지 않습니다.

## 판정 기준

1차와 같습니다. BLOCK은 구체적 오동작, 요구 누락·모순, 중대한 회귀, 권한·데이터 오류, 핵심 검증 누락으로 한정합니다.

## 출력 형식

```
# 판정: SHIP | BLOCK

## 1차 BLOCK 해소
- B1: 해소 | 미해소 — 근거
- B2 … B5

## 새 BLOCK
- [B6] <파일:줄> — <결함> / 근거 / 제안

## NOTE

## 검증 원장
- snapshot: HEAD `<SHA>`, 검토 전후 동일 여부
- 확인한 것 / 미검증으로 남긴 것
```

마지막 줄에 `REVIEW-DONE`을 출력하고 종료합니다.
