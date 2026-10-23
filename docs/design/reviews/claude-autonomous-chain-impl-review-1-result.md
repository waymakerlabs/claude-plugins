<!-- Sol(review-sol, gpt-6.1-sol#high) 구현 1차 터미널 출력에서 마지막 판정 블록(로그 888–929행)을 옮김(2026-10-23). snapshot HEAD 7b01b51 일치 확인. 원문: claude-autonomous-chain-impl-review-1.log -->

# 판정: BLOCK

## BLOCK

- **[B1] `plugins/claude-autonomous-chain/skills/autonomous-chain/references/sol-review.md`:54,64–70 — 완료 표식이 로그에 기록되지 않아 정상 완료해도 대기가 끝나지 않습니다.**  
  `opencode … | tee "$LOG"; echo SOL-EXIT=$?`에서 `echo`는 파이프 밖에 있으므로 터미널에만 출력됩니다. 반면 대기 명령은 `$LOG`에서 `SOL-EXIT=`를 기다립니다. 동일한 구문을 파일 생성 없이 파이프로 재현한 결과, 터미널 출력에는 `SOL-EXIT=0`이 있었지만 로그에 해당하는 출력에는 없었습니다. 또한 `$?`는 `opencode`가 아니라 파이프라인의 상태여서, `false | tee /dev/null`도 현재 환경에서는 `SOL-EXIT=0`으로 기록됩니다.  
  **제안:** 실행 프로세스의 종료 상태를 보존하고 완료 표식을 실제 로그에도 기록하도록 기동 명령을 수정하십시오. 정상 종료·비정상 종료 모두에서 로그 기반 대기가 끝나는지 확인해야 합니다. 기존 설계 리뷰 로그에 표식이 있다는 사실은 새 기동 명령의 검증을 대신하지 못합니다.

- **[B2] `…/references/sol-review.md`:71–80 — 추출 명령이 ‘마지막 판정’이 아니라 ‘마지막으로 완결된 판정’을 반환합니다.**  
  제공된 `claude-autonomous-chain-review-2.log`에서는 최종 본문 54–85행을 정확히 추출했습니다. 그러나 뒤에 새로운 `# 판정: BLOCK`이 시작되고 종료 표식 전에 출력이 끊기면, `awk`가 기존 `last`를 지우지 않아 앞의 SHIP을 반환합니다. 실제 2차 로그에 이 잘린 판정을 **메모리에서만** 덧붙여 재현했으며, 추출 결과는 앞의 SHIP이고 기존 HEAD·대상 SHA도 그대로 남았습니다. 따라서 같은 snapshot에 대한 앞 판정이 있으면 78–80행 검사도 통과할 수 있습니다. 이는 설계 §10의 “잘린 결과는 통과로 인정하지 않는다”와 충돌합니다.  
  **제안:** 새로운 판정이 시작될 때 기존 결과를 무효화하고, 마지막 판정 블록이 완결되지 않았으면 추출 실패로 처리하십시오. 종료 표식도 정확한 한 줄로 확인하십시오.

- **[B3] `plugins/claude-autonomous-chain/agents/chain-planner-deep.md`:11 및 `…/references/planning.md` — 기본 planner의 금지 사항을 상속한다고 적었지만 실제로 전달되지 않습니다.**  
  `chain-planner.md`:26–27에는 제품 코드 수정, stage·commit·push, 허용 경로 밖 쓰기 금지가 있습니다. 깊이 planner는 “`chain-planner`와 같습니다”라고만 쓰고, 기본 정의를 읽는 경로나 절차가 없습니다. 공통 `planning.md`에도 이 금지가 없습니다. 기존 실측의 `agent-af74af7a26914103f.jsonl`:10에 기록된 실제 API system prompt를 확인한 결과, 깊이 planner 본문만 들어 있고 기본 planner 본문은 없었습니다. Claude Code는 이 문장을 에이전트 정의 상속으로 처리하지 않습니다. 따라서 Bash·Write·Edit를 가진 깊이 planner에 설계 §7의 조정자 단독 index 쓰기와 계획 담당의 쓰기 경계가 명시적으로 전달되지 않습니다.  
  **제안:** 기본·깊이 planner가 모두 읽는 `planning.md`에 공통 금지 사항을 넣거나, 깊이 정의에 직접 포함하십시오. 에이전트 간 문구 참조를 런타임 상속으로 간주하면 안 됩니다.

- **[B4] `…/references/task-brief.md`:44–58, `SKILL.md`:79–89 — 보고서 파일 계약이 실제 Claude Code 하니스 지시와 충돌하며, 실측은 이 경로를 실행하지 않았습니다.**  
  현재 계약은 worker가 보고서 파일을 쓰고 경로만 반환하며, 조정자는 그 파일의 변경 목록으로 커밋하도록 합니다. 그런데 기존 실측의 `agent-ae7334b87a3a81738.jsonl`:10에 기록된 실제 system prompt 끝에는 **“Do NOT Write report/summary/findings/analysis .md files. Return findings directly …”**가 추가됩니다. 같은 문구가 깊이 planner에도 있습니다. 기존 probe는 “파일을 읽거나 쓰지 말고 모델 ID만 답하라”는 호출이고 `totalToolUseCount: 0`이어서, 보고서 생성·회수 계약이 이 충돌을 견디는지는 확인하지 않았습니다.  
  **제안:** 이 보고서가 부모의 `Read` 도구 입력이라는 점을 명시하여 하니스가 허용하는 “다른 도구 입력 파일” 예외와 계약을 맞추거나, 지원되는 전달 방식으로 조정하십시오. 최소한 worker의 보고서 생성 → 경로 반환 → 조정자 읽기까지 실제 Claude Code에서 확인해야 합니다.

- **[B5] `SKILL.md`:88, `…/references/sol-review.md`:20–25,79–81 — 무커밋 실행 경로의 변경 범위와 snapshot을 검토 요청이 식별하지 못합니다.**  
  커밋 권한이 없으면 작업 트리 변경으로 통합 검증까지 진행하도록 구현했지만, Sol 요청 템플릿은 변경 범위를 `git diff <base>..<HEAD>` 또는 커밋 목록으로만 지정합니다. 이 범위에는 미커밋 변경과 신규 파일이 들어가지 않습니다. 파일 SHA도 문서 검토에만 제시되어 있고, 검토 전후 `HEAD`와 `git status --short` 비교만으로는 같은 경로의 내용 변경을 판별할 수 없습니다. 설계 2차에서 인정한 무커밋 경로 자체를 다시 다투는 것이 아니라, **이번에 작성된 검토 요청·snapshot 절차가 그 경로를 지원하지 않는다는 새 구현 근거**입니다.  
  **제안:** 무커밋 경로에서는 tracked 작업 트리 변경과 untracked 신규 파일을 포함하는 범위·내용 식별자를 요청에 기록하고, 결과 및 검토 전후 대조에도 사용하십시오. index를 쓰거나 강제로 커밋할 필요는 없습니다.

## NOTE

- **[N1] 설계 §17:278–279 — 모델·effort 증거를 더 정확히 기록할 수 있습니다.** 기존 probe 원자료에서 접두사 붙은 두 에이전트 호출, 실제 도구 목록 `Read, Write, Edit, Bash`, 모델 요청을 확인했습니다. 두 subagent JSONL의 13행에는 각각 `output_config.effort: high`와 `xhigh`도 있습니다. 따라서 “API 요청에 실린 effort 값은 로그에 나오지 않아 미확인”은 해당 원자료와 맞지 않습니다. **Claude Code가 요청에 실은 값은 확인**, 프록시·최종 모델이 그 effort를 실제 적용했는지는 여전히 미검증으로 구분하십시오.

- **[N2] 조정자 커밋 및 전역 변경 — 이 부분에서 새 BLOCK은 없습니다.** 새 파일의 경로 지정 `git add`도 조정자 단독 직렬 실행에 포함되므로 설계의 index 잠금 근거와 충돌하지 않습니다. 백업 대비 전역 diff는 설계 §16의 예외 범위에 머물며, memory의 `modified` 메타데이터 외에 무관한 변경은 없었습니다. 기존 규칙은 자율체인 밖에서 유지됩니다. 무거운 3회·가벼운 1회 규칙과 N5의 Opus 보조 검토 후 push 설명도 설계와 대응합니다.

## 검증 원장

- **snapshot:** HEAD `7b01b515f6ee990bd28d5871c5a0b64858eacd44`, 브랜치 `feat/claude-autonomous-chain`.
  - `~/.claude/CLAUDE.md` SHA-256: `b4c5b9e2a5f2f9ba5f20bfd5aa18100289d6ee217a7e6a88677a4e9bb9e494e2`
  - memory SHA-256: `08ec709aec54905e6251c20321081193869a4d69dbc7e05b5c8ce3a7e8f4a6f3`
  - 검토 전후 동일합니다. Git 상태는 요청 파일 하나만 미추적이며 tracked·staged 변경은 없습니다. 파일 수정이나 worker 기동은 하지 않았습니다.
- **확인:** 지정 diff 전체, 플러그인 11개 파일, 설계 revision 3, 설계 리뷰 1·2차 결과와 실제 2차 로그, 전역·memory 백업 diff를 대조했습니다. manifest·marketplace 이름/버전/경로가 일치합니다. 실제 로그 추출은 정상이며, 종료 표식 배선과 잘린 마지막 판정 실패는 파일 생성 없는 실행으로 재현했습니다.
- **런타임 원자료:** `~/.claude/projects/-private-tmp-chain-fm-probe/423670cc-16f6-478a-892e-00c97362e3a3/`의 부모 기록과 subagent `agent-ae7334b87a3a81738.jsonl`, `agent-af74af7a26914103f.jsonl`을 확인했습니다. Agent 도구가 실제 worker 도구 목록에서 제외됨은 확인했으나, Bash를 포함한 보안 샌드박스까지 보장한다는 판정은 아닙니다.
- **공개 자료 조회:** frontmatter·도구 제한·플러그인 접두사·독립 system prompt 계약 확인을 위해 [Claude Code 공식 subagent 문서](https://code.claude.com/docs/en/sub-agents)를, 터미널 출력 실행 계약 확인을 위해 [OpenCode V2 CLI 문서](https://opencode.ai/v2/docs/cli)를 읽었습니다. 설치된 Claude Code `2.1.309`와 OpenCode·Orca 관련 `--help`도 대조했습니다.
- **미검증·재사용 전제:** 실제 병렬 구현, 보고서 파일 회수, 수정된 기동 명령의 Orca 통합 실행, 마일스톤 인계, 프록시의 effort 적용은 검증하지 않았습니다. 기존 설계 B1–B4의 결정 자체는 재논쟁하지 않았으며, 위 BLOCK은 새 구현·런타임 근거에 한정합니다.

REVIEW-DONE
