---
name: math-exam
description: 수학 시험지/문제지 PDF 생성 (중1~고3, 학력평가/수능 형식)
---

# math-exam — 수학 시험지 PDF 생성 스킬

수학 수식을 포함한 **2열 문제지**를 PDF로 생성하는 스킬.
중학교 1학년 ~ 고등학교 3학년 범위의 수학 문제를 한컴 수식 스크립트로 작성하고,
LaTeX(xelatex)를 통해 PDF로 변환한다.

**두 가지 형식 지원:**
- **exam** (기본값, 학력평가/수능): 전국연합학력평가/수능 형식 시험지 (헤더, 가로 선택지, 배점 등)
- **worksheet** (`--exam-type worksheet` 명시 필요): 단순 2열 수학 문제지

## 환경

```
SKILL_DIR="이 SKILL.md가 위치한 디렉토리의 절대 경로"
```

### 전제 조건: TeX Live

```bash
# macOS
brew install --cask basictex
sudo tlmgr update --self
sudo tlmgr install collection-langkorean kotex-utf enumitem

# Linux
sudo apt install texlive-xetex texlive-lang-korean
```

## 디렉토리 구조

```
math-exam-skill/
├── SKILL.md                      # 이 파일
├── scripts/
│   ├── build_math_pdf.py         # CLI 엔트리포인트 (JSON → .tex → PDF)
│   ├── latex_generator.py        # JSON → .tex 문서 생성
│   ├── hancom_to_latex.py        # 한컴 수식 → LaTeX 변환기
│   └── graph_generator.py        # 그래프/도형 PNG 생성 (matplotlib)
└── examples/
    ├── sample_exam_2020_march.json   # 학력평가 형식 예시
    ├── sample_middle_school.json     # 중학교 워크시트 예시
    └── sample_high_school.json       # 고등학교 워크시트 예시
```

### 모듈 의존 구조

```
build_math_pdf.py (CLI + build 오케스트레이션)
  ├── latex_generator.py (generate_latex — exam/worksheet .tex 생성)
  │     └── hancom_to_latex.py (hancom_to_latex, convert_choice)
  └── graph_generator.py (도형/그래프 PNG, matplotlib 필요)
```

---

## 핵심 워크플로우: JSON → PDF

### 1. 문제 JSON 작성

**반드시 아래 형식을 따를 것.**

```json
{
  "exam_type": "학력평가",
  "year": 2025,
  "month": 3,
  "grade": "중2",
  "session": 2,
  "subject_area": "수학",
  "total_pages": 4,
  "question_type_label": "5지선다형",
  "problems": [
    {
      "text": "의 값은?",
      "equation": "2x + 3 = 7",
      "points": 4,
      "choices": ["1", "2", "3", "4", "5"]
    },
    {
      "text": "을 간단히 한 것은?",
      "equation": "sqrt 12 + sqrt 27",
      "points": 5,
      "choices": ["$3 sqrt 3$", "$4 sqrt 3$", "$5 sqrt 3$", "$6 sqrt 3$", "$7 sqrt 3$"]
    },
    {
      "section_label": "주관식",
      "text": "을 인수분해하시오.",
      "equation": "x^2 - 5x + 6",
      "points": 5
    }
  ]
}
```

### 2. PDF 빌드

```bash
# 학력평가 형식 (기본값)
python3 "$SKILL_DIR/scripts/build_math_pdf.py" \
    --problems problems.json \
    --output exam.pdf

# 단순 worksheet 형식
python3 "$SKILL_DIR/scripts/build_math_pdf.py" \
    --problems problems.json \
    --exam-type worksheet \
    --output worksheet.pdf

# .tex 파일도 함께 보존 (디버깅용)
python3 "$SKILL_DIR/scripts/build_math_pdf.py" \
    --problems problems.json \
    --keep-tex \
    --output exam.pdf
```

### 3. 검증

```bash
# 수식 변환기 단위 테스트
python3 "$SKILL_DIR/scripts/hancom_to_latex.py"
```

---

## 문제 JSON 필드

| 필드 | 필수 | 설명 |
|------|------|------|
| `exam_type` | **O** | **`"학력평가"` 지정** (worksheet 시 `"worksheet"`) |
| `year` | O | 학년도 (예: 2025) |
| `month` | O | 시행 월 (예: 3, 6, 9, 11) |
| `grade` | O | 학년 (예: "중1", "고1") |
| `session` | X | 교시 (기본: 2) |
| `subject_area` | X | 과목 영역 (기본: "수학") |
| `problems` | O | 문제 배열 |
| `problems[].text` | X | 문제 텍스트 |
| `problems[].equation` | X | 독립 수식 (한컴 수식 스크립트) |
| `problems[].points` | **O** | **배점** |
| `problems[].choices` | X | 객관식 5지선다 (`$...$`로 감싸면 수식) |
| `problems[].sub_problems` | X | 소문제 배열 [{text, equation}] |
| `problems[].section_label` | X | 섹션 구분 라벨 (예: "주관식") |
| `problems[].graph` | X | 도형/그래프 스펙 (graph_generator.py 참조) |

---

## 한컴 수식 스크립트 문법

수식은 LaTeX가 아닌 **한컴 수식 스크립트** 문법으로 작성한다. `hancom_to_latex.py`가 자동으로 LaTeX으로 변환한다.

### 기본 규칙

| 규칙 | 설명 |
|------|------|
| `{ }` | 그룹화 (여러 항을 하나로) |
| `~` | 공백 (1em) |
| `` ` `` | 1/4 공백 |
| `#` | 줄바꿈 (수식 내) |
| `&` | 열 정렬 (행렬, 연립방정식) |
| `"..."` | 텍스트 모드 |

### 분수와 루트

| 수식 | 스크립트 | 예시 |
|------|----------|------|
| 분수 | `a over b` | `{x+1} over {x-1}` |
| 제곱근 | `sqrt {x}` | `sqrt {b^2 - 4ac}` |
| n제곱근 | `root n of {x}` | `root 3 of {27}` |

### 위·아래 첨자

| 수식 | 스크립트 |
|------|----------|
| 위첨자 | `x^2` |
| 아래첨자 | `x_i` |
| 둘 다 | `x_i ^2` |

### 적분·합·곱·극한

| 수식 | 스크립트 |
|------|----------|
| 정적분 | `int _{a} ^{b} f(x) dx` |
| 급수 | `sum _{k=1} ^{n} a_k` |
| 곱 | `prod _{i=1} ^{n} x_i` |
| 극한 | `lim _{x -> 0} f(x)` |

### 괄호·행렬·연립방정식

| 수식 | 스크립트 |
|------|----------|
| 자동 크기 괄호 | `left ( {a over b} right )` |
| 절댓값 | `left \| x right \|` |
| 소괄호 행렬 | `pmatrix {a & b # c & d}` |
| 대괄호 행렬 | `bmatrix {1 & 0 # 0 & 1}` |
| 연립방정식 | `cases {2x+y=5 # 3x-2y=4}` |

### 장식

| 장식 | 스크립트 |
|------|----------|
| 벡터 | `vec v` |
| 모자 | `hat a` |
| 윗줄 | `bar x` |
| 물결 | `tilde a` |
| 점 | `dot a` |

### 그리스 문자

소문자: `alpha`, `beta`, `gamma`, `delta`, `epsilon`, `theta`, `lambda`, `mu`, `pi`, `sigma`, `phi`, `omega` 등
대문자: `GAMMA`, `DELTA`, `SIGMA` 등

### 특수 기호

| 기호 | 스크립트 |
|------|----------|
| 무한대 | `inf` |
| ± | `+-` 또는 `pm` |
| ≠ / ≤ / ≥ | `ne` / `le` / `ge` |
| → | `->` |
| ∈ / ⊂ | `in` / `subset` |
| ··· | `cdots` |
| 도(°) | `deg` |

### 내장 함수 (자동 로만체)

`sin`, `cos`, `tan`, `log`, `ln`, `exp`, `lim`, `max`, `min`, `det`, `gcd`, `arcsin`, `arccos`, `arctan`

---

## 학년별 수식 예시

### 중학교

```
2x + 3 = 7
{2x+1} over 3 = {x-2} over 5
cases {2x + y = 5 # 3x - 2y = 4}
sqrt 12 + sqrt 27 - sqrt 48
x^2 - 5x + 6 = 0
```

### 고등학교 수학 I

```
log _a xy = log _a x + log _a y
x = {-b +- sqrt {b^2 - 4ac}} over {2a}
left | x - 3 right | < 5
```

### 고등학교 수학 II

```
lim _{x -> 0} {sin x} over x = 1
f'(x) = lim _{h -> 0} {f(x+h) - f(x)} over h
int _{0} ^{pi} sin x dx = 2
sum _{k=1} ^{n} k = {n(n+1)} over 2
```

### 고등학교 확률·미적분·기하

```
{_n}C{_r} = {n!} over {r!(n-r)!}
{d} over {dx} x^n = n x^{n-1}
pmatrix {a & b # c & d} pmatrix {x # y}
{x^2} over {a^2} + {y^2} over {b^2} = 1
```

---

## 도형 그래프 (graph 필드)

`graph_generator.py`가 matplotlib으로 PNG를 생성한다. 문제 JSON의 `graph` 필드에 스펙을 지정.

**지원 타입**: `triangle`, `circle`, `quadrilateral`, `coordinate`, `solid3d`, `polynomial`, `quadratic`, `trig`, `exp_log`, `rational` 등

```json
{
  "text": "삼각형 ABC에서 ...",
  "equation": "...",
  "points": 4,
  "choices": ["1", "2", "3", "4", "5"],
  "graph": {
    "type": "triangle",
    "vertices": [[0, 0], [6, 0], [2, 5]],
    "labels": {"A": [2, 5], "B": [0, 0], "C": [6, 0]},
    "side_labels": {"AB": "5", "BC": "6"}
  }
}
```

---

## Critical Rules

1. **학력평가 형식 기본**: JSON에 `"exam_type": "학력평가"` 포함
2. **배점 필수**: 모든 문제에 `"points"` 필드
3. **선택지 수식**: `$...$`로 감싸면 수식. **한컴 수식 문법 사용** (`$3 sqrt 2$` ✓, `$3\sqrt{2}$` ✗)
4. **객관식 5지선다**: choices 5개 또는 `"section_label": "주관식"`
5. **TeX Live 필수**: xelatex + kotex 패키지 설치 필요
