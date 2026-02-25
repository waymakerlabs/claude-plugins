---
name: math-exam
description: 수학 시험지/문제지 PDF 생성 (중1~고3, 학력평가/수능 형식)
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
argument-hint: "[학년/범위/문제수 등 요청사항]"
---

# Math Exam: 수학 시험지 PDF 생성 스킬

수학 수식을 포함한 **2열 문제지**를 PDF로 생성하는 스킬.
중학교 1학년 ~ 고등학교 3학년 범위의 수학 문제를 한컴 수식 스크립트로 작성하고,
LaTeX(xelatex)를 통해 PDF로 변환한다.

## 실행 흐름

### Step 1: 사용자 요청 파악

사용자의 요청에서 다음을 파악한다:
- 학년 (중1~고3)
- 시험 유형 (학력평가/워크시트)
- 문제 수
- 출제 범위/단원
- 난이도

### Step 2: 문제 JSON 생성

SKILL_DIR 경로를 확인한다:
```bash
SKILL_DIR="$(dirname "$(find ~/.claude -name 'math-exam.md' -path '*/math-exam/commands/*' 2>/dev/null | head -1)")/.."
```

예제 JSON 참조:
```bash
cat "$SKILL_DIR/examples/sample_exam_2020_march.json"
```

**학력평가 형식** (기본값)으로 JSON을 작성한다:

```json
{
  "exam_type": "학력평가",
  "year": 2025,
  "month": 3,
  "grade": "고1",
  "session": 2,
  "subject_area": "수학",
  "problems": [
    {
      "text": "의 값은?",
      "equation": "한컴 수식 스크립트",
      "points": 4,
      "choices": ["1", "2", "3", "4", "5"]
    }
  ]
}
```

**수식 문법 — 한컴 수식 스크립트 사용 (LaTeX 아님!):**

| 수식 | 스크립트 |
|------|----------|
| 분수 | `{x+1} over {x-1}` |
| 제곱근 | `sqrt {b^2 - 4ac}` |
| n제곱근 | `root 3 of {27}` |
| 적분 | `int _{a} ^{b} f(x) dx` |
| 급수 | `sum _{k=1} ^{n} a_k` |
| 극한 | `lim _{x -> 0} f(x)` |
| 행렬 | `pmatrix {a & b # c & d}` |
| 연립방정식 | `cases {2x+y=5 # 3x-2y=4}` |
| 자동괄호 | `left ( {a over b} right )` |
| 그리스문자 | `alpha`, `theta`, `pi` |
| 특수기호 | `inf`, `pm`, `ne`, `le`, `ge`, `->` |

**선택지 수식**: `$...$`로 감싸면 수식 처리. 예: `"$3 sqrt 2$"`, `"${1} over {2}$"`

### Step 3: PDF 빌드

```bash
python3 "$SKILL_DIR/scripts/build_math_pdf.py" \
    --problems problems.json \
    --output exam.pdf
```

워크시트 형식:
```bash
python3 "$SKILL_DIR/scripts/build_math_pdf.py" \
    --problems problems.json \
    --exam-type worksheet \
    --output worksheet.pdf
```

### Step 4: 결과 전달

생성된 PDF 경로를 사용자에게 알려준다.

## 전제 조건

xelatex이 필요하다. 설치 안내:
```bash
# macOS
brew install --cask basictex
sudo tlmgr update --self
sudo tlmgr install collection-langkorean kotex-utf enumitem

# Linux
sudo apt install texlive-xetex texlive-lang-korean
```

## 주의사항

1. 수식은 반드시 **한컴 수식 스크립트** 문법 사용 (LaTeX 문법 아님)
2. 학력평가 형식: 모든 문제에 `points` 필수, 객관식은 `choices` 5개
3. 선택지 수식: `$3 sqrt 2$` ✓ / `$3\sqrt{2}$` ✗
4. 주관식: `"section_label": "주관식"` 지정
