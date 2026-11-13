검토 결과, **규칙의 양보다 ‘기억해야만 실행되는 규칙’, 조건부 참조에 숨은 공통 규칙, 서로 다른 진본이 더 큰 문제입니다.** 탭 이름 누락은 이 구조로 설명할 수 있습니다. auto-chain은 이름 규칙을 pane 전용 참조에 두고, 실행기는 호출하지 않은 `self-name`을 대신 실행하지 않습니다. [auto-chain 참조:3·47](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/pane-worker.md:3), [어댑터:235–265](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/adapters/herdr.sh:235)

파일·Git·HTTP 쓰기 없이 검토했습니다. 최근 40개 커밋도 확인했으며, 아래 판단은 실행 시험을 하지 않은 정적 설계 검토입니다.

**1. 왜 기본 규칙이 빠지는가**

| 진단 | 근거와 영향 |
|---|---|
| 공통 의무가 선택적 읽기 경로에 있습니다. | auto-chain은 `pane-worker.md`를 ③ 전용으로 소개하고, 참조 문서도 “③을 쓸 때만 읽는다”고 합니다. 그런데 조정자 자신의 탭·pane 이름 규칙은 그 문서 47행에 있습니다. ① worker를 사용하는 조정자가 건너뛰기 쉽습니다. [SKILL:18–28](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:18), [참조:3·47](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/pane-worker.md:47) |
| 시작 절차가 하나로 모이지 않았습니다. | backend 확인은 22행, 받은편지함 구독은 56행, 권한은 99행, 마일스톤 착수는 127행에 흩어져 있습니다. 인계받은 첫 응답의 진행 보드 의무는 471행입니다. [SKILL:22](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:22), [56](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:56), [99](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:99), [471](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:471) |
| 사고 대응이 기존 절차 위에 계속 더해집니다. | 완료 알림 외에 받은편지함 완료 줄, 진행 감시, 재기동 직후 직접 확인이 추가되어 있습니다. pane에는 보조 대기와 정지 감시도 있습니다. 각각 합리적인 보완이지만 조정자가 배선과 회수 여부를 기억해야 합니다. [SKILL:152](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:152), [527–543](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:527), [pane 참조:91–99](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/pane-worker.md:91) |
| 설명 문구가 실행 프로토콜이 되었습니다. | 훅은 마지막 답의 `대기 목록`, `대기 없음`과 한국어 약속·질문 표현을 정규식으로 읽어 깨움 여부를 결정합니다. 보고 형식을 잊는 일이 실행 지속성에도 영향을 줍니다. [inbox-wait.sh:161–200](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/lib/inbox-wait.sh:161) |
| 문서의 최신 규칙을 에이전트가 다시 판별해야 합니다. | README의 “worker 코드를 읽지 않는다”는 문장은 본문의 “diff 본문을 직접 연다”와 다릅니다. README에는 현재 기본이 아닌 Sol 원인 조사 사다리와 옛 Orca 경로도 핵심 규칙 아래 남아 있습니다. [README:29–40](/Users/peter/Dev/claude-plugins/plugins/auto-chain/README.md:29), [SKILL:168](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:168), [381–387](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:381) |

중요 규칙의 위치와 강제 수준은 다음과 같습니다. 깊이는 해당 스킬 본문을 1단계로 계산했습니다.

| 규칙 | 위치·읽는 시점 | 현재 기억 의존 / 자동화 가능성 |
|---|---|---|
| 첫 응답 전 역할 이름 | 전역 CLAUDE → 전역 pane-worker 「아」. auto-chain에서는 조건부 참조 2단계, review-chain은 시작 2번에 직접 명시됩니다. [전역:47](/Users/peter/.claude/CLAUDE.md:47), [전역 pane-worker:61–68](/Users/peter/.claude/skills/pane-worker/SKILL.md:61), [review SKILL:30](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:30) | 호출과 확인 모두 에이전트 책임입니다. 시작 훅·실행기로 자동 처리할 수 있습니다. |
| 실행 수단·모델 선택 | auto-chain 초반 §1-1·§2, 전역 CLAUDE·pane-worker에도 반복됩니다. [auto SKILL:20–34](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:20), [74–94](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:74), [전역:39–46](/Users/peter/.claude/CLAUDE.md:39) | 판단은 에이전트에 남기되, 선택한 역할의 실행 인자는 스크립트가 만들 수 있습니다. |
| 첫 지시 1회, 이후 받은편지함 | auto-chain 38행, review-chain 82행, 전역 pane-worker 34·40행에 반복됩니다. [auto:38](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:38), [review:82](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:82), [전역 pane-worker:34–40](/Users/peter/.claude/skills/pane-worker/SKILL.md:34) | spawn 스크립트는 한 번 보내지만, 저수준 `agent-send` 자체에는 첫 지시 제한이 없습니다. [spawn:191–195](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/scripts/spawn-pane-worker.sh:191), [어댑터:268–281](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/adapters/herdr.sh:268) |
| 권한·소유 범위·커밋 주체 | auto 계획 2번·조정자 규율, review 시작 6번·D5, worker 지시서에 분산되어 있습니다. [auto:99·172–175](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:172), [review:35·209–210](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:209) | 권한 해석은 판단입니다. 선점 충돌은 이미 자동화되어 있으나 실제 편집 차단까지 하지는 않습니다. [rc-claim:87–126](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/scripts/rc-claim.sh:87) |
| 완료는 보고서·diff로 확인 | auto §5, review §7. 판정 시점에 읽습니다. [auto:168](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:168), [review:137–143](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:137) | 내용 판단은 남겨야 합니다. SHA·파일 범위·dirty 여부는 기계 검사로 옮길 수 있습니다. |
| 리뷰 증거 유효성 | auto §6 → `sol-review.md` §5의 2단계 경로입니다. [auto:290](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:290), [Sol 참조:157–174](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/sol-review.md:157) | done은 자동 생성하지만 유효 조건과 snapshot 대조는 수동입니다. 별도 검사 명령으로 옮길 수 있습니다. |
| 인계의 ack·구독 해제·재개 | auto 본문·pane 참조, review 본문·교체 참조, 전역 인계에 반복됩니다. [auto:445](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:445), [review:161](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:161), [전역 인계:30–32](/Users/peter/.claude/skills/session-handoff/SKILL.md:30) | 순서 대부분이 기계적입니다. 인계 실행기에 묶는 편이 적합합니다. |
| 대기 직전 실제 상태 확인 | auto 496행, review 125행입니다. [auto:496](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:496), [review:125](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:125) | `wait-status`는 이미 있지만 호출·회수 여부를 기억해야 하며, 백그라운드 셸은 관측하지 못합니다. [wait-status:6–12](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/lib/wait-status.sh:6) |

탭 이름 규칙의 전체 경로는 다음과 같습니다.

- **auto-chain 조정자:** 전역의 “첫 응답 전” 의무 → 전역 pane-worker 64행의 실행법 → auto-chain의 ③ 전용 참조 → 참조 47행의 조정자 `self-name`. 정작 계획·마일스톤 착수 순서에는 이름 확인이 없습니다. [전역:47](/Users/peter/.claude/CLAUDE.md:47), [전역 pane-worker:64](/Users/peter/.claude/skills/pane-worker/SKILL.md:64), [auto pane 참조:47](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/pane-worker.md:47), [auto SKILL:98–105·127](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:98)
- **실제 실행:** `self-name`을 호출하면 탭·pane을 각각 처리합니다. 그러나 `backend`와 `agent-start`에는 이름 확인이 없고, `pane-open`은 새 pane만 이름 붙입니다. 따라서 worker를 정상 기동해도 기존 탭의 누락은 남습니다. [진입점:289–293](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/bin/agent-orchestrator:289), [어댑터:196·235–265](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/adapters/herdr.sh:235)
- **나중에 pane만 바뀌는 경로:** 대기 절차의 명령은 `self-name --force - "[OC] …"`라서 탭을 명시적으로 건너뜁니다. **최초 이름 단계를 빠뜨리고 대기 단계만 수행했다면 최근 증상이 그대로 나타납니다—추정입니다.** [auto SKILL:500](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:500), [어댑터:239–245](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/adapters/herdr.sh:239)
- **review-chain:** 기존 세션은 기본적으로 launcher가 되어 이름이 포함된 새 탭을 만들고, 새 OC는 시작 2번에서 탭·pane에 `self-name`을 실행합니다. 재개 시에도 교체 참조의 첫 행동이 `self-name`입니다. auto-chain보다 직접적입니다. 다만 launcher 자신의 이름은 여전히 전역 의무에 의존합니다. [review SKILL:28–30](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:28), [launch:18–35](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/references/launch.md:18), [교체 참조:24](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/references/oc-handover.md:24)
- **보장 한계:** 현재 이름에 아무 `[XX]` 접두어가 있으면 유지합니다. `[OC]`가 맞는 역할인지 검사하지는 않습니다. pane 생성의 이름 변경 실패도 경고 후 성공으로 진행합니다. [어댑터:196·200–213](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/adapters/herdr.sh:200)

실제 충돌·불일치는 우선 정리해야 합니다.

| 항목 | 서로 다른 규정 |
|---|---|
| 리뷰 규칙 우선순위 | 전역 CLAUDE와 auto-chain은 auto-chain 게이트를 우선시하지만, 전역 review-protocol은 auto-chain의 명시적 `stop` 사다리보다 자신이 우선한다고 합니다. **직접적인 우선순위 충돌입니다.** [전역:37](/Users/peter/.claude/CLAUDE.md:37), [auto:72](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:72), [review-protocol:42](/Users/peter/.claude/skills/review-protocol/SKILL.md:42) |
| 리뷰 무게 | review-protocol은 자율체인 마일스톤 최종 검토를 무거운 게이트로 열거합니다. auto-chain은 화면은 생략, 데이터는 기본 가벼움입니다. override를 놓치면 다른 절차가 됩니다. [review-protocol:35](/Users/peter/.claude/skills/review-protocol/SKILL.md:35), [auto:279–283](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:279) |
| 미감시 전송 기록 | review 본문은 보낸 쪽이 직접 기록하라고 하지만, 참조와 스크립트는 자동 기록합니다. 중복 기록을 유도합니다. [review:110](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:110), [messages:18](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/references/messages.md:18), [rc-send:80–95](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/scripts/rc-send.sh:80) |
| 구독·인계 순서 | 전역 pane-worker는 일반 수신을 Monitor로 설명하고 구독 해제→ack 순서입니다. auto-chain은 구독 기본, ack→구독 해제입니다. 전역 session-handoff도 구독 승계와 Monitor 승계를 함께 서술합니다. [전역 pane-worker:46–49](/Users/peter/.claude/skills/pane-worker/SKILL.md:46), [auto:43·57](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:57), [인계:30–31](/Users/peter/.claude/skills/session-handoff/SKILL.md:30) |
| 배치·관측 | 전역 pane-worker는 오른쪽 최대 5개, 현재 어댑터는 기본 999개입니다. review §13은 사용자가 물을 때만 보고서를 본다고 하지만 §4·§6은 대기 점검 때도 보라고 합니다. [전역 pane-worker:21](/Users/peter/.claude/skills/pane-worker/SKILL.md:21), [어댑터:12–15](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/adapters/herdr.sh:12), [review:87·188](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:188) |
| 역할 접두어 복사 | review 대기 절은 OC·worker 모두에게 적용되는데 예제는 `[OC]`입니다. worker 참조의 같은 예제는 `[WO]`입니다. [review:118–129](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:118), [messages:68](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/references/messages.md:68) |
| 실패 사다리 | 본문은 원인 불명 실패→바로 xhigh이지만 worker·deep 정의는 실패→deep 경로를 계속 안내합니다. xhigh 설명에도 옛 Sol 후 재시도 경로가 남습니다. [auto:381–387](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:381), [worker:3](/Users/peter/Dev/claude-plugins/plugins/auto-chain/agents/chain-worker.md:3), [xhigh:3](/Users/peter/Dev/claude-plugins/plugins/auto-chain/agents/chain-worker-xhigh.md:3) |

**2. 복잡도 목록과 정리 판단**

행 수는 빈 줄·예제를 포함한 대략적인 본문 비용입니다. 아래의 “이동”은 실제 작업 제안입니다.

| auto-chain 본문 | 행 비용 | 판단 |
|---|---:|---|
| 도입·실행 단계·통신·역할 §1-1~§2 | 약 95 | **단순화·통합.** 시작 체크와 선택표만 남기고 통신 계약은 공통 참조로 옮깁니다. 현재 통신이 적용 범위보다 먼저 나옵니다. [20–94행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:20) |
| 계획·롤링 분해 §3 | 28 | **유지·단순화.** 최초 두 마일스톤 분해와 한 단계 앞 계획은 유지합니다. 마감 후 시작 규정과 마지막 웨이브 직후 시작 규정을 하나로 합칩니다. [96–122행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:96) |
| 실행 루프·조정자 규율 §4~§5 | 53 | **핵심 유지.** 지시서 필드·마감 체크·pane 정리는 템플릿·명령으로 옮깁니다. [124–175행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:124) |
| build/harden·30분 상한 §6-0 | 48 | **정책 유지, 상세 이동.** 본문에는 모드별 차이표만 둡니다. 예외와 이월 처리 전문을 상시 읽힐 필요는 없습니다. [177–223행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:177) |
| 검증 예산·BLOCK 지시서 | 29 | **단순화.** 검증 시점·snapshot 고정은 유지하고 worktree 격리 명령은 참조로 옮깁니다. [225–252행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:225) |
| breaker | 19 | **본문에서 제거.** 기본 off이며 본문 자체도 기동·병합 비용을 근거로 듭니다. 선택 기능 참조로 충분합니다. [254–270행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:254) |
| Sol 게이트·수렴·사다리 | 49 | **게이트표 유지, 중복 통합.** 유효성 검사는 스크립트로, 재검토 정책은 한 문서로 모읍니다. [273–320행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:273) |
| 계열 원장·시각 확인 | 33 | **단순화·조건부 이동.** 재발 방지와 사용자 확인은 유지하되 SWEEP 상세는 harden 진입 때만 읽힙니다. [322–353행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:322) |
| 결정·멈춤·실패 §7 | 40 | **핵심 유지·사다리 통합.** 실패 정의·예외·역사를 분리하고 “다음 행동” 표로 줄입니다. [355–393행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:355) |
| 상태 파일 §8 | 48 | **템플릿·계산을 스크립트로.** 전체 양식과 시간 9개 칸을 조정자가 매번 작성할 필요는 없습니다. [395–441행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:395) |
| 인계 §9 | 10 | **판단만 유지, 실행 자동화.** 짧지만 참조 안의 4단계·자리 교체·부모 정리가 실제 비용입니다. [443–451행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:443), [pane 참조:156–173](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/pane-worker.md:156) |
| 보고·대기·감시 §10 | 91 | **가장 큰 축소 대상.** 보고 예시는 참조, 인라인 감시 코드는 스크립트, 대기 판정은 명시적 상태로 옮깁니다. [453–543행](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:453) |

| review-chain 본문 | 행 비용 | 판단 |
|---|---:|---|
| 도입·시작 §0~§1 | 36 | **유지·단순화.** launch/current/resume 분기는 유지하고 초기화를 한 명령으로 묶습니다. [18–35행](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:18) |
| 상태 파일 §2 | 22 | **참조 이동.** 소유자·진본 구분만 남깁니다. claims의 수동 거울 표는 생성 대상으로 바꿉니다. [37–57행](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:37) |
| 분류·기동 §3~§4 | 29 | **핵심 유지·기동 통합.** 논의형의 수동 기동과 잡수정의 auto-chain 스크립트 호출을 같은 인터페이스로 만듭니다. [59–87행](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:59) |
| 선점 §5 | 15 | **메커니즘 유지.** 종료 코드별 행동만 본문에 남기고 패턴 비교 알고리즘 설명은 스크립트에 둡니다. [88–101행](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:88) |
| 메시지·대기 §6 | 29 | **공통화·스크립트 이동.** 메시지 종류표와 수신 내부 절차를 본문에서 반복하지 않습니다. [103–130행](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:103) |
| 병합·공용 파일 §7~§8 | 25 | **안전 조건 유지·검사 자동화.** SHA 고정, 범위, 검증 실패 시 중지는 보존합니다. [132–156행](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:132) |
| OC·worker 교체 §9~§10 | 10 | **공통 실행기로 통합.** 편집 소유자 하나와 재개 책임만 본문에 남깁니다. [157–165행](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:157) |
| 승격·정리 §11~§12 | 16 | **정책 유지·정리 자동화.** 승격 후 기존 작업만 마무리하는 규칙과 ignored 데이터 보관은 유지합니다. [167–181행](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:167) |
| 한계·멈춤 §13~§14 | 18 | **멈춤 조건 유지, 운영 설명 이동.** [183–199행](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:183) |
| 설계 결정 §15 | 18 | **본문에서 삭제하고 ADR로 이동.** 앞 절의 정책·사고 이력을 다시 설명합니다. [201–218행](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:201) |

참조·전역 계층도 함께 정리해야 합니다.

- auto의 **planning 130행·task-brief 102행·profile 89행**은 역할별 참조로 유지할 가치가 있습니다. 다만 모델·권한·통신 전문은 각 문서에서 반복하지 않도록 줄여야 합니다. [planning:3–9](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/planning.md:3), [task-brief:11–27](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/task-brief.md:11), [profile:38–59](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/profile.md:38)
- **Sol 참조 221행·pane 참조 173행**에는 정책·실행 명령·장애 복구가 섞여 있습니다. 공통 실행과 체인 정책을 나누되, 새 거대 프로토콜 문서를 만드는 것은 피해야 합니다. [Sol:112–187](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/sol-review.md:112), [pane:28–153](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/pane-worker.md:28)
- 에이전트 정의의 **짧은 금지 규칙 복제는 유지**할 만합니다. 역할마다 따로 읽히기 때문입니다. 다만 공통 지시서를 읽으라는 안내 뒤에 파일 크기·완료 통신 전문을 반복하는 부분은 축약할 수 있습니다. [worker:11–23](/Users/peter/Dev/claude-plugins/plugins/auto-chain/agents/chain-worker.md:11), [deep:11–21](/Users/peter/Dev/claude-plugins/plugins/auto-chain/agents/chain-worker-deep.md:11), [planner-deep:11–27](/Users/peter/Dev/claude-plugins/plugins/auto-chain/agents/chain-planner-deep.md:11)
- review-chain이 **auto-chain의 pane 참조·spawn 스크립트에 의존**하지만 플러그인 의존성에는 inbox-hooks만 선언되어 있습니다. 공통 실행 도구로 옮기거나 의존성을 명시해야 합니다. [review SKILL:24·81](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:24), [plugin.json:9](/Users/peter/Dev/claude-plugins/plugins/review-chain/.claude-plugin/plugin.json:9)
- 옛 스크립트 래퍼는 각각 5~6행입니다. **지금 삭제할 우선순위는 낮습니다.** 오래된 인계를 깨뜨릴 위험에 비해 줄어드는 부담이 작습니다. [호환 래퍼:2–6](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/scripts/herdr-spawn-worker.sh:2)

**3. 우선 개선안 — 8개**

비용·위험은 구현 전 **추정**이며 소/중으로 표시했습니다.

1. **P0 — 역할 이름을 시작 실행기가 자동 보장하도록 바꾸십시오.**  
   `session-start --role OC|WO|RV --title … --inbox …` 같은 멱등 명령에 이름 적용·읽기 확인·구독을 묶고, 명시적 역할 정보를 받은 동기 시작 훅에서도 호출하는 안입니다. OC만 공유 탭을 이름 붙이고 WO/RV는 자기 pane만 처리해야 합니다. 사용자 제목 본문은 보존합니다. 효과는 이름 규칙의 기억 의존 제거입니다.  
   비용 중 / 위험 중. 대상: AO 진입점·어댑터, 시작 훅, 두 SKILL. 검증에는 최초 실행·재개·사용자 제목·공유 탭·이름 변경 실패를 포함합니다. 현재 훅은 inbox-wait만 실행하며 이름 검사는 없습니다. [hooks:4–14](/Users/peter/Dev/claude-plugins/plugins/inbox-hooks/hooks/hooks.json:4), [래퍼:16–21](/Users/peter/Dev/claude-plugins/plugins/inbox-hooks/scripts/inbox-hook.sh:16)

2. **P0 — 첫 20행 안에 6개 체크를 두고, 공통 규칙의 진본을 하나로 정하십시오.**  
   `역할·이름 / 상태·권한 / 소유 범위 / 통신 / 완료 근거 / 다음 행동`만 상단에 둡니다. 공통 실행은 AO, 체인 정책은 각 SKILL, 전역 문서는 포인터로 정리합니다. 우선 review-protocol의 역방향 override와 README의 옛 규칙부터 제거합니다. 체크리스트는 자동화 보조이며 강제 수단으로 보지는 않습니다.  
   비용 소 / 위험 소. 대상: 두 SKILL·README, 전역 CLAUDE·pane-worker·review-protocol·session-handoff. [우선순위 충돌:review-protocol 42](/Users/peter/.claude/skills/review-protocol/SKILL.md:42), [전역 37](/Users/peter/.claude/CLAUDE.md:37), [README 29](/Users/peter/Dev/claude-plugins/plugins/auto-chain/README.md:29)

3. **P1 — 리뷰의 기계적 유효성 검사를 한 명령으로 만드십시오.**  
   done의 exit·sandbox·RUN_ID·snapshot·결과 헤더 검사를 `review-check`로 옮깁니다. 일반 review-protocol도 같은 실행기를 재사용하고, 게이트 무게·finding 채택 판단만 정책으로 남깁니다.  
   비용 중 / 위험 중. 대상: `review-run.sh`, Sol 참조, 전역 review-protocol, 신규 검사 명령. 현재 자동 실행기 뒤에 수동 검사 목록이 남아 있습니다. [runner:108–140](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/scripts/review-run.sh:108), [Sol:157–174](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/sol-review.md:157), [전역 실행:19–29](/Users/peter/.claude/skills/review-protocol/SKILL.md:19)

4. **P1 — 대기 상태를 자연어에서 분리하고, 감시 기동·재기동을 도구로 옮기십시오.**  
   작은 `waiting/done/needs-user` 상태와 대상 목록을 명령으로 기록하고 훅이 이를 읽게 하는 안입니다. 사용자에게는 이유·병목·다음 확인을 계속 설명하되, 문장의 물음표나 표현이 깨움 정책을 결정하지 않게 합니다. 기존 인라인 진행 감시도 스크립트로 추출합니다. 새로운 감시 계층을 추가하지 않고 기존 문구 판정을 대체해야 합니다.  
   비용 중 / 위험 중. 대상: `wait-status.sh`, `inbox-wait.sh`, auto §10, review §6. 백그라운드 셸 관측 누락은 별도 보완이 필요합니다. [문구 판정:161–200](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/lib/inbox-wait.sh:161), [감시 코드:511–529](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:511), [관측 한계:11](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/lib/wait-status.sh:11)

5. **P1 — 인계·pane 정리의 기계적 순서를 묶으십시오.**  
   ack→구독 해제→인계 기록→새 세션 기동, 새 세션의 구독·pending·자리 교체·부모 정리를 공통 실행기로 옮깁니다. 실패하면 “새 작업 중지, pending 확인, 기존 세션 보존”처럼 짧은 복구 규칙을 둡니다. 새로운 세대·선출·다단계 잠금은 추가하지 않는 편이 좋습니다.  
   비용 중 / 위험 중. 대상: 두 체인의 인계 참조, 전역 session-handoff, AO. planner를 남겨 넘기는 예외는 명시적 인자로 유지합니다. [auto 인계:445–449](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:445), [review 교체:8–31](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/references/oc-handover.md:8)

6. **P1 — review-chain은 선점을 유지하고 병합 전 검사를 자동화하십시오.**  
   `merge-check <worker> <SHA>`로 clean 상태·보고 SHA·선점 범위·공용 파일을 검사하게 합니다. diff 의미 판단과 승인 판단은 OC에 남깁니다. `merge.lock`의 기존 진행 기록을 활용하고 별도 경쟁 방지 체계는 만들지 않습니다.  
   비용 중 / 위험 중. 대상: review §7·상태 참조·scripts. claims 거울 표도 스크립트 출력으로 대체할 수 있습니다. [병합 검사:137–145](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:137), [진행 기록:76–93](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/references/state-files.md:76)

7. **P2 — 선택 기능·역사·양식을 상시 읽기 경로에서 빼십시오.**  
   breaker, 선택적 Sol 원인 조사, OpenCode 사다리, 구버전 이관은 해당 조건에서만 읽힙니다. 상태 양식은 템플릿으로 생성하고 시간 집계는 실측 가능한 값 중심으로 줄입니다. README는 현재 사용법과 변경 이력을 분리합니다.  
   비용 소~중 / 위험 소. 대상: auto SKILL·references·agents·README, review §15. 기능 삭제보다 **본문에서 제거**하는 작업이 먼저입니다. [선택 breaker:256](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:256), [선택 원인 조사:189–191](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/references/sol-review.md:189), [시간 집계:438–441](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:438)

8. **P2 — 전달 보장 초안은 ‘추가’보다 기존 점검의 ‘대체’ 범위로 다시 좁히십시오.**  
   초안은 기존 구독·대기자·notified·held를 유지하면서 메시지별 프로세스, 최신 것만 생존, 최대 3회 재전송, blocked 분기, 여러 승격 출력을 더합니다. **현재 방향은 과설계 위험이 큽니다.** 한 받은편지함의 미처리 여부를 보는 기존 점검을 확장하고, 제한된 복구 알림 후 사람에게 올리는 방식부터 권합니다.  
   비용 재설계 소 / 구현 중 / 위험 중. 대상: 초안, `inbox-wait.sh`, 이후 통신 문서. 초안의 계약·동작·시험·되돌림은 아직 TODO이고 기준 버전도 현재 저장소보다 이전입니다. [초안:3–5·13–27](/Users/peter/Dev/claude-plugins/docs/plans/2026-11-13-inbox-delivery-guarantee-plan.md:3), [TODO:42–68](/Users/peter/Dev/claude-plugins/docs/plans/2026-11-13-inbox-delivery-guarantee-plan.md:42), [현재 auto 버전:3](/Users/peter/Dev/claude-plugins/plugins/auto-chain/.claude-plugin/plugin.json:3)

**4. 얇아진 SKILL.md의 목표 형태**

아래 행 수는 제안 목표입니다. 참조 문서는 조건이 성립한 시점에만 읽도록 연결해야 합니다.

| auto-chain 목표 | 행 |
|---|---:|
| frontmatter·적용 범위 | 12 |
| 시작 명령·6개 필수 체크 | 15 |
| 계획/재개 경로 선택 | 10 |
| 실행 수단·역할 선택표 | 10 |
| 계획·롤링 분해 요약 | 10 |
| 웨이브 실행·통합 루프 | 20 |
| 게이트·검증 예산 표 | 18 |
| 실패·권한·멈춤 규칙 | 14 |
| 인계·정리 | 12 |
| 조건별 참조 색인 | 9 |
| **합계 목표** | **130** |

계획 양식은 planning, worker 계약은 task-brief, 리뷰 실행은 공통 도구로 보냅니다. 모드 예외·SWEEP·breaker·상태 양식·보고 예시는 조건별 참조에 둡니다. 현재 분리 기반은 이미 있습니다. [참조 목록:18](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:18), [모드 상세:177–223](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:177), [상태 양식:395–436](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:395)

| review-chain 목표 | 행 |
|---|---:|
| frontmatter·적용 범위 | 8 |
| launch/current/resume·시작 체크 | 16 |
| OC/WO 권한·소유 규칙 | 10 |
| 대기열·분류 | 9 |
| worker 기동·선점 결과별 행동 | 12 |
| 병합·검증·통지 루프 | 15 |
| 교체·승격·정리·멈춤 | 10 |
| 조건별 참조 색인 | 10 |
| **합계 목표** | **90** |

상태 양식·메시지 종류·worker 지시서·복구 절차는 기존 참조를 활용하고, §15의 설계 이력은 ADR로 옮깁니다. [참조 목록:23](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:23), [설계 결정:201–218](/Users/peter/Dev/claude-plugins/plugins/review-chain/skills/review-chain/SKILL.md:201)

**5. 불확실성**

- **추정:** 최근 이름 누락이 “시작 단계 누락→대기 단계에서 pane만 변경” 경로였는지는 해당 세션 transcript를 대조해야 확정할 수 있습니다. 문서와 구현에는 그 경로가 존재합니다. [auto:500](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:500)
- **추정:** 규칙 밀도·분산이 누락 확률을 높인다는 진단은 구조적 추론입니다. 본문 자체도 긴 컨텍스트와 실수의 인과를 `UNVERIFIED`로 표시합니다. [auto:450](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:450)
- 정상 인계에서 새 세션의 구독이 미처리 줄을 `held`로 표시할 수 있습니다. “n+1부터 처리”와 “이전 세션 줄은 사용자 확인 후 release”가 만나는 경계의 실제 운영 영향은 **추정**이며 재현 확인이 필요합니다. [inbox.sh:231–242](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/lib/inbox.sh:231), [auto:43·57](/Users/peter/Dev/claude-plugins/plugins/auto-chain/skills/autonomous-chain/SKILL.md:43)
- 시작 자동화의 효과는 **추정**입니다. 현재 시험은 `self-name`을 호출했을 때의 동작을 검증합니다. “에이전트가 호출을 잊어도 첫 응답 전에 이름이 보장된다”는 경로는 별도로 검증해야 합니다. [이름 시험:178–220](/Users/peter/Dev/claude-plugins/tools/agent-orchestrator/test/run-tests.sh:178)