# 받은편지함 감시 끊김 방지 — S3 보고서 (바깥 점검 inbox-sweep + launchd)

작성 2026-11-11, 세션 `[OC] 받은편지함 S3`(pane w3:p65). 계획: `docs/plans/2026-11-11-inbox-reliability-plan.md` rev 5 §3 S3.

## 1. 결과 요약

- 계약 반영(S2 미룬 것 2건): 계획 §2-5 5번에 재통지 유예(`AO_INBOX_RENOTIFY_GRACE`, 기본 15초)와 통지 직전 `_aoiw_deliv` 재확인, 계약 진본 §1-4에 같은 내용. 계획 §2-9 표에 `wait-notify … [hook=SessionStart]`·`sub … [from=<옛 sid>]` 칸.
- 새 `lib/inbox-sweep.sh`, `bin/agent-orchestrator` 분기, launchd plist 틀, `launchd/install-sweep.sh`(기본 dry-run), `manifests/inbox-sweep.manifest`(kind `doc`), 가짜 herdr `notification show`. 계약 진본 §1-4에 `inbox-sweep`·`--register` 행.
- 커밋 `5189cea`(push 안 함).
- launchd: **설치하지 않는다**(§7, 주인님 결정). 코드는 리포에 남긴다.

## 2. 자동 시험

| 시점(HEAD) | 결과 |
|---|---|
| `5189cea`(S3 구현) | bash 300/300, `/bin/bash` 300/300 (S3 추가 29) |
| `34b500e`(1회차 수정) | bash 304/304, `/bin/bash` 304/304 |
| `e19b2ce`(2회차 수정) | bash 306/306, `/bin/bash` 306/306 |

- 끝의 `EXPECT` 총계 대조, `inbox-regress-all`(기존 122개), `inbox-real-state-untouched`(검사 이름에 `sweep/` 추가) 모두 PASS.
- 돌연변이 대조(자가 반증 ⓑ, 리포 사본에서): 1시간 규칙 제거 → FAIL 2(`repeat-30m`·`ack-keeps-alert`), 실패 전송에도 alerts 갱신 → FAIL 1(`no-herdr`), 본문 `≥` 제거 → FAIL 1(`legacy-backlog`). 회귀 시험은 고치기 전 코드에서 1회차 4건·2회차 2건이 정확히 FAIL(300/304·304/306).
- `plutil -lint` 틀·설치본 모두 OK(`inbox-sweep-plist-lint`·`-install-apply`).
- 실제 상태 dry-run(읽기 전용, 15:2x): `chain-grit-portal/coordinator.log 1 0 observed quiet` 한 줄. sweep·events 변경 0.
- `install-sweep.sh` dry-run(이 맥): plist 새로 만듦·등록 안 됨, 할 일 = sweep 폴더 생성·plist 쓰기·`launchctl bootstrap gui/501 …`. 아무것도 바꾸지 않음.

## 3. 계획과 다르게 정한 점

1. **열린 backlog 상태 파일 `sweep/open`** 추가(`<경로>\t<bl>\t<n>\t<arr>\t<exact>`). `backlog-open`을 받은편지함마다 한 번만 내고, cursor가 그 n을 넘은 sweep에서 `backlog-close`를 내기 위해서다. 계획 §2-1 표에는 obs·alerts만 있었다.
2. **`sweep/obs` 형식**: 계획의 `<경로>\t<줄 n>\t<첫 관측>`(줄마다 한 행) 대신 `<경로>\t<그때 줄 수 hi>\t<관측 epoch>`(줄 수가 늘었고 그 사이에 times 행이 빠진 줄이 있을 때만 한 행). 줄 m의 첫 관측 = `hi ≥ m`인 첫 행. 줄마다 행을 두면 옛 받은편지함(수백 줄) 첫 sweep에서 파일이 커지고, 같은 시각 정보를 더 적게 담을 수 있어서다. cursor ≥ hi인 행은 지운다(계획의 "cursor가 넘으면 지움"과 같은 뜻).
3. **`--dry-run`은 상태를 쓰지 않는다**: 잠금·obs·open·events 모두 건드리지 않는다(읽기 전용). 그래서 dry-run의 observed 나이는 앞선 실제 sweep이 남긴 obs가 있을 때만 0이 아니다.
4. **dry-run 출력은 미처리 줄이 있는 받은편지함만**(계획에는 범위가 없었다).
5. **알림 본문 표시 이름**: 상태 폴더 밖 받은편지함은 `<상위 폴더>/<파일>`(예: `c1/inbox`). 홈 경로를 넣지 않으면서 review-chain 체인 id가 보이게 했다.
6. **herdr 호출 보호**: `status server`로 서버 상태를 먼저 보고, 호출마다 `perl alarm` 10초 상한·stdin 막음·fd 6 닫음. 서버 자동 기동 자식이 sweep 잠금을 물려받으면 다음 sweep이 모두 "겹친 실행"으로 끝나기 때문이다.
7. **install-sweep.sh 추가 동작**: 같은 내용이 이미 있으면 유지(멱등), 다른 내용이면 `--apply`가 3으로 거부(덮어쓰지 않음, 먼저 `--uninstall`). `--uninstall --dry-run`도 둔다. 시험용 `AO_LAUNCHCTL`(가짜 launchctl)·`AO_TS`.
8. **plist**: `StandardOutPath=/dev/null`, `ProcessType=Background` 추가. PATH는 `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`.
9. **시험 추가**: 표의 케이스 외에 `inbox-sweep-register-bad`, `inbox-sweep-plist-lint`, `inbox-sweep-install-apply`·`-install-conflict`·`-uninstall-archive`(가짜 launchctl). `inbox-real-state-untouched` 검사 이름에 `sweep/` 추가.
10. **잘림·교체 판정 `sweep/seen`**(2회차 수정): `<경로>\t<지난 줄 수>\t<inode>\t<첫 줄 해시>`. 줄 수 감소·inode 변화·첫 줄 변화 중 하나면 그 받은편지함의 obs 전부를 버리고 열린 backlog를 `backlog-close … reset=1`로 닫는다. §2-9 표에 없던 칸 `reset=1`이다 — 지표 집계에서 reset 건은 따로 센다(S5 보고서에서 반영).

## 4. codex 크로스체크 (Sol high, 무거운 게이트)

범위: S3 전체(`87e3bf6..5189cea`) + S2 SHIP 뒤의 `94c3ffd`(concurrent-3 수정). 리뷰어는 매번 `-s read-only`·`--ephemeral`. 리뷰어는 /tmp 쓰기가 막혀 전체 시험을 못 돌렸고(메모리 내 대체 시험), 전체 시험은 메인이 돌렸다(§2).

| 회차 | 대상 | 판정 | finding | 반영 커밋 |
|---|---|---|---|---|
| 1 (`20261111-152821`) | `87e3bf6..5189cea` + `94c3ffd` | BLOCK | high 1·medium 3 | `34b500e` |
| 2 (`20261111-153827`) | `5189cea..34b500e` | BLOCK | medium 2 (1회차 #2 미해소 1, 그 수정의 새 결함 1) | `e19b2ce` |
| 3 (`20261111-154603`) | `34b500e..e19b2ce` | **SHIP** | 0 (알려진 한계 1, 비차단) | — |

1회차(모두 실제 결함으로 확인, 고치기 전 코드에서 회귀 시험 FAIL 확인):
1. high — herdr 호출의 `perl alarm`이 손자 프로세스를 못 끝내 stdout 파이프 대기로 sweep이 멈추고 fd 6을 쥠 → 새 프로세스 그룹 + 그룹 KILL, 출력은 임시 파일(`inbox-sweep-herdr-child-hang`).
2. medium — 잘린 파일의 옛 obs를 새 줄에 재사용(하한 위반) → inode 비교(`inbox-sweep-truncated-obs`). 2회차에서 같은 inode 절단이 남아 seen 판정으로 바꿈.
3. medium — `--dry-run --register`가 실제 등록 → 2로 거부(`inbox-sweep-dry-register`).
4. medium — `--uninstall` 보관 자리 충돌 시 덮어씀 → `.N` 접미·`mv -n`(`inbox-sweep-uninstall-no-clobber`).
- `94c3ffd`: 추가 결함 없음(정리 중 TERM 격리 시험에서 정리 완료·exit 2 보존). S2 보고서 §8의 "독립 리뷰 없음"은 이것으로 해소.

2회차: ① 같은 inode 10→1줄 절단에서 hi=1 obs 행이 남아 20분 alert → `sweep/seen`(`inbox-sweep-truncated-same-inode`). ② inode 칸 없는 옛 5칸 open 행을 교체로 오판 → inode 칸이 있을 때만 비교(`inbox-sweep-open-legacy-row`).

## 5. 남은 위험

- **같은 inode·같은 첫 줄로 예전 줄 수 이상 다시 쓰인 받은편지함**은 잘림으로 못 알아본다(3회차 리뷰어도 비차단 한계로 기록). 받은편지함은 append 전용이라 정상 경로에서는 생기지 않는다. 생기면 observed 나이가 하한이 아니게 될 수 있다.
- **launchd 미설치**(§7): R1(깨운 턴 중단 뒤 무입력)·R2(7000초 만료 뒤 쉬는 세션)에 들어온 메시지는 사람이 볼 때까지 남는다. 크기는 S5에서 events.log로 잰다.
- **~/.local/bin 판**: 링크가 마켓플레이스 사본(옛 판)을 가리켜 `inbox-sweep`을 모른다(실측 rc=2). push로 사본이 갱신되기 전 `--apply`만 하면 5분마다 rc=2로 끝나고 `launchd.err`에 한 줄씩 쌓인다.
- herdr 알림 표시 자체(화면에 뜨는가)는 가짜 herdr로만 시험했다 — launchd 실측에서 확인한다(UNVERIFIED).
- shellcheck 없음(미실행).

## 6. 미결·다음 할 일

- ~~launchd 설치·실측·외부 받은편지함 등록~~ — §7 결정으로 하지 않는다.
- **⑨ G5 통과**(15:58 확인): `why=timeout`이 시작 뒤 7001초(7000±5 안). S2 보고서 §4 ⑨ 줄에 옮겼다. S5 병합 조건 C3 충족. 시험 pane `w3:p64`는 이 세션 지시(닫지 말 것)에 따라 열어 둔다.

## 7. 주인님 결정 (2026-11-11, S3 마감 때)

**2026-11-11 주인님 결정(S3 마감 때)**: sweep 알림을 쓰지 않는다 — "메시지가 남아 있어도 따로 알릴 필요 없다". 이 방식(훅 대기자)이 안 되면 완전히 다른 방법으로 간다. 그래서 launchd는 설치하지 않고, `inbox-sweep`·`install-sweep.sh` 코드는 리포에 남긴다(필요해지면 `install-sweep.sh --apply` 한 번으로 켠다). 합의 결정 ②를 이것으로 바꾼다.

- 바뀐 문서: 계획 §3 S3 머리 인용·§3 S5 C5 삭제·병합 뒤 4번·§5-2 R1·§2-9 지표 사후 계산 줄.
- S5 판정 기준은 그대로다: 1주 동안 "사람이 물어서 발견한 미처리" 0건, 두 체인 모두 새 방식 인계 1회 이상. 이것이 깨지면 이 방식은 실패로 보고 다른 방법을 찾는다.
