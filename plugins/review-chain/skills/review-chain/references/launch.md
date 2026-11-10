# 새 세션으로 시작 (launch)

review-chain은 보통 auto-chain이 끝난 무거운 세션에서 불린다. 그 세션이 OC가 되면 지난 개발 맥락이 OC 컨텍스트를 처음부터 차지한다. 그래서 **기본은 새 탭에 깨끗한 OC를 여는 것**이고, 부른 세션(launcher)은 시작 메모만 쓰고 넘긴다.

## 1. 어느 경로인가

| 상황 | 경로 |
|---|---|
| 첫 지시가 시작 메모(`launch-*.md`)를 가리킴 | **OC로 시작** — SKILL §1-1부터 |
| 첫 지시가 OC 인계 문서(`oc-handover-*.md`)를 가리킴 | **재개** — `oc-handover.md` §2 |
| 사용자가 "이 세션에서", "여기서 바로"라고 명시 | **OC로 시작** — 이 세션이 OC |
| 그 밖 전부("리뷰체인으로 해줘", "리뷰체인으로 새 세션 열어줘", 자율체인 끝난 세션에서 호출) | **launch** — 아래 §2 |

## 2. launcher 절차

launcher는 체인 폴더·worktree·worker를 만들지 않는다. 대기열 등록도 하지 않는다(새 OC가 한다).

1. `"$AO" backend`가 0인지 본다. 아니면 SKILL §1-1처럼 멈춘다.
2. 리포 = `git rev-parse --show-toplevel`. 리포가 아니면 멈추고 묻는다.
3. 넘길 사실만 모은다(새로 조사하지 않는다 — 이 세션이 이미 아는 것만):
   - 방금 끝난 작업(마일스톤·버전·마지막 커밋 `git log -1 --oneline`), `git status --short` 요지(미커밋이 있으면 경고 한 줄)
   - QC 대상(화면·URL·실행 명령)과 이미 알려진 수정사항(사용자가 이 세션에서 말한 것 원문)
   - 공용 파일 위치(VERSION·릴리즈 노트·진행 원장), 외부 시스템(JIRA 등), 프로젝트 설정 `.claude/review-chain.md` 유무
   - 이 세션에서 사용자가 준 상시 권한(push·외부 쓰기)이 있으면 그대로, 없으면 "없음"
4. `.git/info/exclude`에 `/.review-chain/`가 없으면 한 줄 추가하고, 시작 메모를 `<리포>/.review-chain/launch-<YYYYMMDD-HHMM>.md`에 쓴다(§3 틀, 60줄 이하).
5. 새 탭에 OC를 연다(전역 `session-handoff` 스킬(후속 세션 인계 프로토콜)의 새 탭 방식 — 순차 대체이므로 맞는 쓰임):
   ```bash
   ROOT=$("$AO" tab-open "[OC] <프로젝트 한글> QC" --cwd "<리포>")
   "$AO" agent-start rc-oc "$ROOT" --kind claude -- <이 세션과 같은 플래그 — ps -o args= -p $PPID>
   "$AO" agent-send rc-oc "review-chain 스킬로 <메모 절대경로>를 읽고 OC로 시작해. 부모 pane: $("$AO" whoami)" --confirm
   ```
   - `--cwd`는 리포 루트(이미 신뢰된 폴더). 이름 `rc-oc`가 살아 있으면(3) `rc-oc-2`처럼 바꾼다. 기동은 1회.
   - 출력 working|done이 인계 증거다. 5·6·그 밖 실패면 메모 경로와 함께 사용자에게 보고하고 멈춘다.
   - 이 `agent-send` 한 줄이 launcher가 새 OC에 보내는 유일한 입력이다(세션을 여는 첫 지시). 이후 launcher↔OC 사이에 메시지는 없다.
6. 사용자에게 한 줄: `[OC] <프로젝트> QC — 새 탭에서 시작했습니다(<pane> · working). 그 탭에서 수정사항을 말씀해 주세요.`
7. 그 뒤 launcher는 review-chain 일을 하지 않는다. 사용자가 이 탭에서 수정사항을 말하면 "새 OC 탭에서 말해 달라"고만 답한다.

## 3. 시작 메모 틀

```markdown
# review-chain 시작 메모 <YYYYMMDD-HHMM>

- 리포: <절대경로> · main <짧은 해시> <제목>
- 작업 트리: 깨끗 | 미커밋 n개(<요지>) — 체인 시작 전에 사용자 확인
- 방금 끝난 작업: <마일스톤·버전·요지 한두 줄>
- QC 대상: <화면·URL·실행 명령>
- 알려진 수정사항: <사용자 원문, 한 줄씩 | 없음>
- 공용 파일: <VERSION·노트·원장 경로 | 미확인>
- 외부 시스템: <JIRA 프로젝트 키 등 | 없음>
- 프로젝트 설정: .claude/review-chain.md 있음 | 없음
- 상시 권한: push <ask|...> · 외부 쓰기 <none|...> (launcher 세션에서 사용자가 준 것만)
- 부모 pane: <launcher pane> · 머신: <이 머신>
- 부모 닫기: 허용 | 금지(<사유 — 다른 머신, 살아 있는 worker pane, 사용자 요청>)
```

## 4. 새 OC의 첫 행동

1. SKILL §1-1~§1-6을 진행한다(§1-4 새 체인, 메모의 사실로 `state.md` frontmatter·`queue.md` 초기 항목을 채운다). §1-4의 `inbox.log`·`shared-files` 생성과 받은편지함 Monitor 시작도 여기서 한다(첫 worker 기동 전).
2. 메모의 "부모 닫기"가 허용이면 첫 착수 전에 `"$AO" close <부모 pane>`(실패는 무시). 금지면 닫지 않는다. launcher 탭에 다른 pane이 남아 있으면 탭은 닫히지 않는다.
3. launcher는 부모 닫기를 이렇게 정한다: 같은 머신이고, launcher 탭에 살아 있는 worker pane·백그라운드 작업이 없고, 사용자가 남기라고 하지 않았으면 허용.
4. 메모는 지우지 않는다(체인 폴더 `state.md` "## 결정"에 메모 경로 한 줄).
