# wrap-up

작업 마무리 스킬 - Obsidian 문서화 + Git 커밋을 한 번에.

## 기능

| 기능 | 설명 |
|------|------|
| **Daily Log** | 오늘 작업 내용을 daily log에 기록 |
| **Handoff** | 다음 세션을 위한 handoff 문서 생성 |
| **문서 업데이트** | 프로젝트 소개 등 관련 문서 자동 업데이트 |
| **Git Commit/Push** | 코드 변경사항 커밋 및 푸시 |

## 설치

```bash
/plugin install wrap-up@waymakerlabs-claude-plugins
```

## 사용법

### 기본 실행

```bash
/wrap-up
```

### 설정 재구성

```bash
/wrap-up --reconfigure
```

## 실행 흐름

```
/wrap-up 실행
    │
    ├─ 1. 설정 확인 (없으면 Obsidian vault 경로 물어봄)
    │
    ├─ 2. 프로젝트 폴더 확인 (없으면 생성 여부 물어봄)
    │
    ├─ 3. Daily log 생성/업데이트
    │
    ├─ 4. Handoff 문서 생성
    │
    ├─ 5. 관련 문서 업데이트 (필요시)
    │
    ├─ 6. Git commit & push
    │
    └─ 7. 다음 세션 시작 프롬프트 출력
```

## 출력 예시

```
✅ Wrap-up 완료!

📝 Daily log: Logos App/daily-logs/2026-01-21.md
📋 Handoff: Logos App/handoffs/HANDOFF-2026-01-21-1730.md
📦 Commit: abc1234 - feat: add vocabulary validation

---
🚀 다음 세션 시작 프롬프트:

/path/to/obsidian/001. 프로젝트/진행중/Logos App/handoffs/HANDOFF-2026-01-21-1730.md를 읽고 이어서 작업해줘.
```

## 생성되는 문서 구조

### Daily Log (`daily-logs/YYYY-MM-DD.md`)

```markdown
# 작업일지 - 2026-01-21

## 프로젝트 현황
| 항목 | 상태 | 비고 |
|------|------|------|
| 기능 A | ✅ | 완료 |
| 기능 B | 🔄 | 진행중 |

## 오늘 작업 내용
### 1. 기능 A 구현
- 상세 내용...

## 커밋 로그
| 커밋 | 메시지 |
|------|--------|
| `abc1234` | feat: add feature A |

## 다음 작업
- [ ] 기능 B 완료
```

### Handoff (`handoffs/HANDOFF-YYYY-MM-DD-HHMM.md`)

```markdown
# HANDOFF - 2026-01-21 17:30

## 현재 상태
| 항목 | 상태 | 설명 |
|------|------|------|
| 기능 A | ✅ 완료 | 구현 완료 |
| 기능 B | 🔄 진행중 | 50% 완료 |

## 다음 단계
1. 기능 B 마무리
2. 테스트 작성

## 다음 세션 시작 프롬프트
\`\`\`
handoffs/HANDOFF-2026-01-21-1730.md를 읽고 이어서 작업해줘.
\`\`\`
```

## 설정 파일

경로: `~/.claude/wrap-up-config.json`

```json
{
  "obsidianVault": "/Users/username/Documents/Obsidian Vault",
  "projectsPath": "001. 프로젝트/진행중"
}
```

## 새 프로젝트 시작 시

Obsidian에 프로젝트 폴더가 없으면 자동으로 기본 구조를 생성합니다:

```
{프로젝트명}/
├── 프로젝트 소개.md
├── daily-logs/
├── documents/
└── handoffs/
```

## 상태 아이콘

| 아이콘 | 의미 |
|--------|------|
| ✅ | 완료 |
| 🔄 | 진행중 |
| ⬜ | 시작 전 |
| ❌ | 차단됨 |

## License

MIT
