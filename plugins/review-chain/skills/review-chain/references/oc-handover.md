# OC 교체와 worker 교체

OC가 판단만 하고 진본이 파일에 있으므로, 교체 때 넘길 것은 "어느 체인 폴더인지"뿐이다.

## 1. OC 교체 (옛 OC가 시작)

1. `merge.lock`이 없을 때 시작한다(병합 중이면 끝낸 뒤).
2. **동결**: `state.md` frontmatter `oc-status: 교체중`으로 바꾼다. 이 순간부터 옛 OC는 새 결정·병합·worker 답을 하지 않는다. 그 뒤 받은 worker 메시지는 처리하지 않고 원문을 `state.md` "## 미처리"에 받은 순서대로 덧붙이기만 한다(표도 고치지 않는다). 옛 OC pane이 닫힐 때까지 계속한다.
3. 동결 직전까지의 `state.md` worker 표 `마지막 보고`, `queue.md` 상태, "## 결정"이 최신인지 본다. 머릿속에만 있는 판단(사용자와 방금 합의한 순서 등)은 "## 결정"에 한 줄로 적는다. 동결 전에 받았지만 아직 답하지 않은 요청도 "## 미처리"로 옮긴다.
4. 짧은 인계 문서 `$RC/oc-handover-<n>.md`: 체인 폴더 절대경로, 리포, 옛 OC pane, 진행 중 사용자 대화 요지(OC 탭에서 하던 QC 흐름), 다음 첫 행동. 옛 인계 문서는 지우지 않는다.
5. 새 OC 기동 — **이 경우에만** 전역 「후속 세션 인계 프로토콜」의 새 탭 방식을 쓴다:
   ```bash
   ROOT=$("$AO" tab-open "[OC] <프로젝트 한글> QC <n>" --cwd "$PWD")
   "$AO" agent-start rc-oc-<n> "$ROOT" --kind claude -- <옛 OC와 같은 플래그>
   "$AO" agent-send rc-oc-<n> "review-chain 스킬로 <$RC>/oc-handover-<n>.md 를 읽고 OC를 이어받아. 옛 OC pane: $("$AO" whoami)" --confirm
   ```
   출력 working|done이 인계 증거다. 이름 규칙·재시도는 전역 프로토콜과 같다(기동은 1회).
6. 옛 OC는 새 OC가 pane을 닫을 때까지 2의 동결 규칙만 따른다(답하지 않고 "## 미처리"에 덧붙이기만). 사용자가 옛 OC 탭에서 말하면 "새 OC 탭(`[OC] … QC <n>`)에서 말해 달라"고만 답한다.

## 2. 재개 (새 OC)

순서가 핵심이다: `current-oc`를 먼저 바꾸고 **그 뒤에** 상태를 다시 읽는다. 그래야 교체 순간 옛 OC로 간 요청이 "## 미처리"에 남거나, worker가 `[OC변경]` 뒤 다시 보내 새 OC로 온다.

1. review-chain 스킬을 로드하고 `self-name`.
2. 인계 문서 → `state.md` → `queue.md` 순으로 1차로 읽는다(맥락 파악용). worker 화면·report 전량은 읽지 않는다.
3. `"$AO" list --agents`로 worker 표의 이름이 살아 있는지 대조. 없는 이름은 상태 `막힘`(사유: 세션 없음) → §4로 교체 판단.
4. `current-oc` 교체: `printf '%s\n' "$("$AO" whoami)" > "$RC/current-oc.tmp" && mv "$RC/current-oc.tmp" "$RC/current-oc"`, `current-oc.log`에 한 줄. 이 뒤로 `rc-send.sh`는 새 OC로 보낸다(전송마다 파일을 다시 읽는다).
5. **재독**: `state.md`·`queue.md`를 다시 읽고 "## 미처리"를 위에서부터 처리한다(처리한 줄 끝에 ` → 처리 <시각>`, 줄은 지우지 않는다).
6. 살아 있는 worker 전부에 `[rc <id>] [OC] [OC변경] <새 pane>`. worker는 답을 못 받은 마지막 요청이 있으면 다시 보낸다 — "## 미처리"에서 이미 처리한 것과 같으면 같은 답을 한 번 더 보내면 된다(중복 무해).
7. 옛 OC pane 닫기: `"$AO" close <옛 OC pane>`(실패는 무시). 닫은 뒤 "## 미처리"를 한 번 더 보고(닫기 직전에 덧붙은 줄) 처리한다. 그다음 `oc-status: 활성`. 옛 OC 탭에 다른 pane(잡수정 worker)이 있으면 탭은 남는다 — 그 worker는 그대로 두고 표의 `탭` 칸은 바꾸지 않는다.
8. 사용자에게 한 줄: `[OC] 교체 완료 — 새 OC <pane>, worker n개 연결, 대기열 m건.`

## 3. 교체 직후 merge.lock이 남아 있으면

옛 OC가 병합 도중 끊긴 것이다. lock의 단계 칸(`references/state-files.md` merge.lock)을 위에서부터 보고 **비어 있는 첫 칸부터만** 이어 한다. 채워진 단계는 다시 하지 않는다(판올림·공용 파일 커밋·push·외부 반영 중복 방지).

1. 칸마다 실제 상태와 한 번 대조한다: `merged` 비었으면 `git -C <리포> merge-base --is-ancestor <sha> main`으로 이미 들어갔는지 본다(들어갔으면 main 머리를 적고 다음 칸). `version-bumped`·`shared-committed` 비었으면 `git log -3 main`·`git status --porcelain`으로 판올림 커밋·미커밋 공용 파일이 이미 있는지 본다. `pushed` 비었으면 `git ls-remote`로 원격이 이미 그 SHA인지 본다. `external-done` 비었으면 외부 시스템에 이미 반영됐는지 설정 `external` 절차의 조회로 본다.
2. 병합 전(`merged` 비었고 실제로도 안 들어감)이면 lock을 지우고 그 worker를 병합 순서 맨 앞에 둔다(SKILL §7을 처음부터).
3. `verified: fail`이면 이어 하지 않는다(SKILL §7-1 예외 — 사용자 결정 대기).
4. 대조 결과가 칸과 어긋나거나 판단이 안 서면 그 단계는 하지 않고 사용자 확인.
5. 모든 칸이 채워지면 SKILL §7-7 통지 → lock 삭제.

## 4. worker 교체

계기: worker 컨텍스트가 참(사용자가 말하거나 worker가 `[막힘] 컨텍스트`), 세션 소실, 반복 정지.

1. 살아 있으면 옛 worker에 `[rc <id>] [OC] [답] report.md "## 인계"를 쓰고 [완료] 대신 [막힘] 인계준비로 알려 줘`. 소실이면 생략.
2. 새 이름(`<name>2`)으로 같은 worktree·브랜치에 기동(SKILL §4, 배치는 옛 worker와 같은 종류). 지시서에 옛 `report.md` 경로와 "## 인계"부터 읽으라는 줄을 추가.
3. 표: 옛 줄 `교체됨`, 새 줄은 범위·상태를 그대로 이어받는다(범위 재제출 불필요).
4. 순서: 옛 worker의 1단계 보고 → 옛 pane 닫기 → 2단계 새 worker 기동. 같은 worktree에 편집 소유자가 둘인 시간을 두지 않는다. 새 worker 기동 증거(working|done)를 표에 적는다.
