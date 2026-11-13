# OC 교체와 worker 교체

OC가 판단만 하고 진본이 파일에 있으므로, 교체 때 넘길 것은 "어느 체인 폴더인지"뿐이다. 메시지는 고정 경로 받은편지함(`$RC/inbox.log`)과 처리 위치(`.cursor`)에 남으므로 별도 "미처리" 복사나 worker의 재전송이 필요 없다(0.1.2).

## 1. OC 교체 (옛 OC가 시작)

1. `merge.lock`이 없을 때 시작한다(병합 중이면 끝낸 뒤).
2. **동결**: `state.md` frontmatter `oc-status: 교체중`으로 바꾼다. 이 순간부터 옛 OC는 새 결정·병합·worker 답을 하지 않는다. (0.3.0, 4단계) 인계 순서: ① 진행 중 처리를 끝내거나 되돌리고 **실제로 처리한 마지막 번호까지만** `rc-watch.sh --ack $RC/inbox.log <n>`(답하지 않은 줄은 ack하지 않는다) ② `rc-watch.sh --unsubscribe $RC/inbox.log`(Monitor로 받고 있었으면 `TaskStop`도) ③ 인계 문서에 받은편지함 경로와 마지막 처리 번호 <n>을 적고 새 OC를 기동한다 ④ 새 OC는 `--subscribe` 뒤 `--pending`으로 n+1부터 처리한다. 동결 뒤 들어온 줄은 처리 위치 뒤에 그대로 남아 새 OC가 처리한다(표도 고치지 않는다). 옛 OC pane이 닫힐 때까지 이 상태를 유지한다.
3. 동결 직전까지의 `state.md` worker 표 `마지막 보고`, `queue.md` 상태, "## 결정"이 최신인지 본다. 머릿속에만 있는 판단(사용자와 방금 합의한 순서 등)은 "## 결정"에 한 줄로 적는다. 동결 전에 받았지만 아직 답하지 않은 줄은 `--ack`하지 않은 채 둔다(새 OC가 `--pending`으로 본다). 이미 처리한 줄은 반드시 `--ack`해 둔다(새 OC가 중복 처리하지 않게).
4. 짧은 인계 문서 `$RC/oc-handover-<n>.md`: 체인 폴더 절대경로, 리포, 옛 OC pane, 진행 중 사용자 대화 요지(OC 탭에서 하던 QC 흐름), 다음 첫 행동. 옛 인계 문서는 지우지 않는다.
5. 새 OC 기동(0.4.0) — **같은 탭의 새 pane**에 연다. 전역 `session-handoff` 스킬의 새 탭 규칙은 쓰지 않는다(그 규칙은 체인을 처음 시작하는 launch에만 쓰인다. 탭 하나가 체인 하나다):
   ```bash
   N=$("$AO" pane-open "[OC] <프로젝트 한글> QC <n>" --parent "$("$AO" whoami)" --cwd "$PWD")
   "$AO" agent-start rc-oc-<n> "$N" --kind claude -- <옛 OC와 같은 플래그>
   "$AO" agent-send rc-oc-<n> "review-chain 스킬로 <$RC>/oc-handover-<n>.md 를 읽고 OC를 이어받아. 옛 OC pane: $("$AO" whoami)" --confirm
   ```
   새 pane은 옛 OC의 오른쪽에 열린다. 출력 working|done이 인계 증거다(아니면 사용자에게 보고한다). 자리 바꾸기는 새 OC가 §2-7에서 옛 OC를 닫기 **직전에** 한다(옛 OC는 swap·close를 하지 않는다 — 두 세션이 같은 pane을 동시에 다루지 않게). 이름 규칙·재시도는 전역 `session-handoff` 스킬과 같다(기동은 1회).
6. 옛 OC는 새 OC가 pane을 닫을 때까지 2의 동결 규칙만 따른다(답하지 않고 `--ack`하지 않음). 사용자가 옛 OC pane(오른쪽)에서 말하면 "왼쪽 새 OC pane(`[OC] … QC <n>`)에서 말해 달라"고만 답한다.

## 2. 재개 (새 OC)

순서가 핵심이다(0.2.0): 받은편지함을 **구독**하고 → 상태를 다시 읽고 → `--pending`으로 미처리 줄을 처리한다. 받은편지함 경로가 고정이고 옛 OC가 `--ack`한 위치 뒤의 줄은 전부 남아 있으므로, 교체 순간 들어온 요청도 빠지지 않는다. `current-oc`는 기록·호환용이라 라우팅과 무관하다.

1. review-chain 스킬을 로드하고 `"$AO" session-init OC "<프로젝트 한글> QC"`(증거 줄의 `tab=`·`pane=`에 `[OC]` 확인).
2. 인계 문서 → `state.md` → `queue.md` 순으로 1차로 읽는다(맥락 파악용). worker 화면·report 전량은 읽지 않는다.
3. `"$AO" list --agents`로 worker 표의 이름이 살아 있는지 대조. 없는 이름은 상태 `막힘`(사유: 세션 없음) → §4로 교체 판단.
4. `current-oc` 갱신(기록·호환용): `printf '%s\n' "$("$AO" whoami)" > "$RC/current-oc.tmp" && mv "$RC/current-oc.tmp" "$RC/current-oc"`, `current-oc.log`에 한 줄. 이 값은 메시지 경로에 쓰이지 않는다.
   그다음 **자기 구독**을 켠다(0.2.0): `<SKILL 폴더>/scripts/rc-watch.sh --subscribe $RC/inbox.log`. 옛 OC가 `--ack`한 위치 뒤의 줄부터 이어서 들어온다(훅이 없는 도구면 `messages.md` §1 "훅이 없는 도구" 문단).
5. **재독**: `state.md`·`queue.md`를 다시 읽고 `rc-watch.sh --pending $RC/inbox.log`의 미처리 줄을 위에서부터 처리한다(처리할 때마다 `--ack <n>`). 깨움에 이미 처리한 `#n`이 다시 오면 `--ack`만 한다. 인계 문서의 "마지막 처리 번호 <n>" 뒤(n+1)부터 처리한다.
6. 살아 있는 worker에 `[OC변경] <새 pane>`을 보내는 것은 **선택**(알림용)이다: `rc-send.sh --to <name> $RC OC변경 "<새 pane>"`. worker는 아무것도 다시 보낼 필요가 없다.
7. 옛 OC pane 닫기(0.4.0 순서 고정): 먼저 `"$AO" pane-swap "$("$AO" whoami)" <옛 OC pane>`으로 왼쪽 자리를 이어받고(실패는 무시), 그다음 `"$AO" close <옛 OC pane>`(실패는 무시). 닫은 뒤 `--pending`을 한 번 더 보고(닫기 직전에 들어온 줄) 처리한다. 그다음 `oc-status: 활성`. 새 OC와 worker pane은 모두 같은 탭에 있으므로 탭은 그대로 남고(0.4.0), worker는 건드리지 않으며 표의 `탭` 칸도 바꾸지 않는다.
8. 사용자에게 한 줄: `[OC] 교체 완료 — 새 OC <pane>, worker n개 연결, 대기열 m건.`
9. 교체 전 옛 OC가 기다리던 것이 있었으면(`state.md` worker 표·`queue.md`·인계 문서의 대기 항목) 새 OC가 이어받아 "대기 목록과 끝맺음"(SKILL §6, 0.4.0)대로 항목마다 실제 상태를 확인하고 대기 목록으로 끝낸다.

## 3. 교체 직후 merge.lock이 남아 있으면

옛 OC가 병합 도중 끊긴 것이다. lock의 단계 칸(`references/state-files.md` merge.lock)을 위에서부터 보고 **비어 있는 첫 칸부터만** 이어 한다. 채워진 단계는 다시 하지 않는다(판올림·공용 파일 커밋·push·외부 반영 중복 방지).

1. 칸마다 실제 상태와 한 번 대조한다: `merged` 비었으면 `git -C <리포> merge-base --is-ancestor <sha> main`으로 이미 들어갔는지 본다(들어갔으면 main 머리를 적고 다음 칸). `version-bumped`·`shared-committed` 비었으면 `git log -3 main`·`git status --porcelain`으로 판올림 커밋·미커밋 공용 파일이 이미 있는지 본다. `pushed` 비었으면 `git ls-remote`로 원격이 이미 그 SHA인지 본다. `external-done` 비었으면 외부 시스템에 이미 반영됐는지 설정 `external` 절차의 조회로 본다.
2. 병합 전(`merged` 비었고 실제로도 안 들어감)이면 lock을 지우고 그 worker를 병합 순서 맨 앞에 둔다(SKILL §7을 처음부터).
3. `verified: fail`이면 이어 하지 않는다(SKILL §7-1 예외 — 사용자 결정 대기).
4. 대조 결과가 칸과 어긋나거나 판단이 안 서면 그 단계는 하지 않고 사용자 확인.
5. 모든 칸이 채워지면 SKILL §7-7 통지 → lock 삭제.

## 4. worker 교체

계기: worker 컨텍스트가 참(사용자가 말하거나 worker가 `[막힘] 컨텍스트`), 세션 소실, 반복 정지.

1. 살아 있으면 옛 worker에 `rc-send.sh --to <옛 이름> $RC 답 'report.md "## 인계"를 쓰고 [완료] 대신 [막힘] 인계준비로 알려 줘'`. 소실이면 생략.
2. 새 이름(`<name>2`)으로 같은 worktree·브랜치에 기동(SKILL §4, 0.4.0 — 배치는 논의형·잡수정 모두 OC 탭의 pane). 지시서에 옛 `report.md` 경로와 "## 인계"부터 읽으라는 줄을 추가. 새 이름의 `workers/<name>2/inbox.log`와 구독 명령(`rc-watch.sh --subscribe …`, 0.2.0)을 지시서에 적는다(옛 worker 받은편지함은 쓰지 않는다).
3. 표: 옛 줄 `교체됨`, 새 줄은 범위·상태를 그대로 이어받는다. 선점은 이름 기준이므로 `rc-claim.sh --release $RC <옛 이름>` 뒤 새 worker가 같은 패턴을 `rc-claim.sh`로 다시 선점한다(옛 이름이 남아 있으면 새 worker가 자기 범위와 충돌한다). 옛 worker 선점은 옛 pane 닫기(4) 뒤에 해제해 편집 소유자가 둘인 시간이 없게 한다.
4. 순서: 옛 worker의 1단계 보고 → 옛 pane 닫기 → 2단계 새 worker 기동. 같은 worktree에 편집 소유자가 둘인 시간을 두지 않는다. 새 worker 기동 증거(working|done)를 표에 적는다.
