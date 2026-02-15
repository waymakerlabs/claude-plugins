# verify-skills

자가 유지보수형 코드 검증 프레임워크입니다. 프로젝트 코드 변경을 분석하여 검증 스킬을 자동 생성하고, 등록된 모든 검증 스킬을 일괄 실행합니다.

> 원본: [codefactory-co/kimoring-ai-skills](https://github.com/codefactory-co/kimoring-ai-skills)

## 스킬

| 스킬 | 설명 |
|------|------|
| `/manage-skills` | 세션 변경사항을 분석하여 verify 스킬을 생성/업데이트 |
| `/verify-implementation` | 등록된 모든 verify 스킬을 순차 실행하여 통합 검증 보고서 생성 |

## 사용 흐름

```
1. 코드 작업 완료
2. /manage-skills 실행
   → git diff 분석 → verify 스킬 생성/업데이트 제안
   → 승인하면 .claude/skills/verify-*/SKILL.md 자동 생성
3. /verify-implementation 실행
   → 등록된 모든 verify 스킬 순차 실행
   → 통합 보고서 → 이슈 발견 시 자동 수정 제안
4. PR 생성
```

## 설치

```bash
/plugin install verify-skills@waymakerlabs-claude-plugins
```

## 동작 방식

### `/manage-skills`

1. `git diff`로 현재 세션에서 변경된 파일 수집
2. 기존 verify 스킬과 변경 파일 매핑
3. 커버리지 갭 분석 (누락 파일, 오래된 패턴, 새 규칙)
4. CREATE vs UPDATE 결정 후 사용자 확인
5. 스킬 생성/업데이트 및 연관 파일 동기화

### `/verify-implementation`

1. 등록된 모든 verify 스킬 목록 확인
2. 각 스킬의 Workflow 검사를 순차 실행
3. PASS/FAIL 결과를 통합 보고서로 출력
4. 이슈 발견 시 수정 옵션 제공 (전체/개별/건너뛰기)
5. 수정 후 자동 재검증
