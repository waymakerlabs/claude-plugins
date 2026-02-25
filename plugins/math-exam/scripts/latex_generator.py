#!/usr/bin/env python3
"""Generate LaTeX documents from problem JSON data.

This is the PDF-pipeline equivalent of section_generators.py.
It takes the same JSON format and produces a complete .tex file
suitable for compilation with xelatex.

Two formats are supported:
- exam (학력평가/수능): Full standardized Korean exam paper layout
- worksheet: Simple 2-column math worksheet

Usage:
    from latex_generator import generate_latex
    tex_source = generate_latex(data, image_paths)
"""

from __future__ import annotations

import platform
from pathlib import Path

from hancom_to_latex import hancom_to_latex, convert_choice


# ═══════════════════════════════════════════════════════════════════════
#  Constants
# ═══════════════════════════════════════════════════════════════════════

CHOICE_LABELS = ["①", "②", "③", "④", "⑤"]


# ═══════════════════════════════════════════════════════════════════════
#  Font detection
# ═══════════════════════════════════════════════════════════════════════

def _detect_korean_font() -> str:
    """Detect an available Korean font for the current platform."""
    system = platform.system()
    if system == "Darwin":
        # macOS: try common Korean fonts
        candidates = ["AppleGothic", "Apple SD Gothic Neo", "NanumGothic"]
    elif system == "Windows":
        candidates = ["Malgun Gothic", "NanumGothic", "Batang"]
    else:
        # Linux
        candidates = ["NanumGothic", "UnBatang", "Noto Sans CJK KR"]

    # Try to detect which fonts are available via fc-list
    try:
        import subprocess
        result = subprocess.run(
            ["fc-list", ":lang=ko", "family"],
            capture_output=True, text=True, timeout=5,
        )
        available = result.stdout
        for font in candidates:
            if font in available:
                return font
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # Fallback
    if system == "Darwin":
        return "AppleGothic"
    elif system == "Windows":
        return "Malgun Gothic"
    return "NanumGothic"


# ═══════════════════════════════════════════════════════════════════════
#  LaTeX preamble
# ═══════════════════════════════════════════════════════════════════════

def _make_preamble(korean_font: str | None = None) -> str:
    """Generate the LaTeX preamble with all required packages."""
    if korean_font is None:
        korean_font = _detect_korean_font()

    return rf"""\documentclass[10pt, a4paper]{{article}}

% ── Fonts ──
\usepackage{{fontspec}}
\usepackage{{kotex}}
\setmainhangulfont{{{korean_font}}}

% ── Math ──
\usepackage{{amsmath, amssymb, amsthm}}

% ── Layout ──
\usepackage[left=20mm, right=20mm, top=15mm, bottom=15mm]{{geometry}}
\usepackage{{multicol}}
\setlength{{\columnsep}}{{8mm}}
\setlength{{\columnseprule}}{{0pt}}

% ── Graphics ──
\usepackage{{graphicx}}

% ── Page numbering ──
\usepackage{{fancyhdr}}
\pagestyle{{fancy}}
\fancyhf{{}}
\renewcommand{{\headrulewidth}}{{0pt}}
\fancyfoot[C]{{\thepage}}

% ── Misc ──
\usepackage{{enumitem}}
\usepackage{{tabularx}}
\usepackage{{setspace}}

% ── Custom commands ──
\newcommand{{\examrule}}{{\noindent\rule{{\textwidth}}{{0.8pt}}}}
\newcommand{{\points}}[1]{{\hfill\textnormal{{[#1점]}}}}
\newcommand{{\sectionbox}}[1]{{\fbox{{\small #1}}}}
"""


# ═══════════════════════════════════════════════════════════════════════
#  Equation helpers
# ═══════════════════════════════════════════════════════════════════════

def _render_equation(script: str) -> str:
    """Convert Hancom equation script to display-mode LaTeX."""
    latex = hancom_to_latex(script)
    return f"\\[ {latex} \\]"


def _render_inline_equation(script: str) -> str:
    """Convert Hancom equation script to inline-mode LaTeX."""
    latex = hancom_to_latex(script)
    return f"${latex}$"


def _render_choice_text(choice: str) -> str:
    """Render a choice, converting $...$ Hancom equations to LaTeX."""
    return convert_choice(choice)


def _tex_escape(text: str) -> str:
    """Escape special LaTeX characters in plain text."""
    # Only escape characters that would break LaTeX
    replacements = [
        ("\\", r"\textbackslash{}"),
        ("{", r"\{"),
        ("}", r"\}"),
        ("%", r"\%"),
        ("&", r"\&"),
        ("#", r"\#"),
        ("_", r"\_"),
        ("~", r"\textasciitilde{}"),
        ("^", r"\textasciicircum{}"),
    ]
    for old, new in replacements:
        text = text.replace(old, new)
    return text


# ═══════════════════════════════════════════════════════════════════════
#  Exam format generator
# ═══════════════════════════════════════════════════════════════════════

def generate_exam_latex(data: dict, image_paths: dict[int, Path] | None = None) -> str:
    """Generate LaTeX for standardized exam format (학력평가/수능).

    Args:
        data: Problem data dict with exam_type, year, month, etc.
        image_paths: Mapping of problem number → image file path
    """
    if image_paths is None:
        image_paths = {}

    korean_font = _detect_korean_font()
    lines: list[str] = []

    # Preamble
    lines.append(_make_preamble(korean_font))
    lines.append(r"\begin{document}")
    lines.append("")

    # ── Header (full width, before multicols) ──
    year = data.get("year", "")
    month = data.get("month", "")
    grade = data.get("grade", "")
    session = data.get("session", 2)
    subject_area = data.get("subject_area", "수학")

    title = data.get("title", "")
    if not title and year:
        title = f"{year}학년도 {month}월 {grade} 전국연합학력평가 문제지"

    if title:
        lines.append(r"\begin{center}")
        lines.append(rf"\textbf{{{title}}}")
        lines.append(r"\end{center}")
        lines.append("")

    lines.append(r"\begin{center}")
    lines.append(rf"제 {session} 교시 \quad \textbf{{\Large {subject_area} 영역}}")
    lines.append(r"\end{center}")
    lines.append(r"\examrule")
    lines.append(r"\vspace{2mm}")

    # ── Problems in 2 columns ──
    lines.append(r"\begin{multicols}{2}")
    lines.append(r"\raggedcolumns")
    lines.append("")

    problems = data.get("problems", [])
    for i, prob in enumerate(problems, 1):
        _generate_exam_problem(lines, i, prob, image_paths)

    lines.append(r"\end{multicols}")
    lines.append(r"\end{document}")

    return "\n".join(lines)


def _generate_exam_problem(
    lines: list[str],
    num: int,
    prob: dict,
    image_paths: dict[int, Path],
) -> None:
    """Append LaTeX lines for a single exam problem."""
    # Section label (e.g., 주관식)
    section_label = prob.get("section_label", "")
    if section_label:
        lines.append(rf"\sectionbox{{{section_label}}}")
        lines.append("")

    # Problem number + text + points
    text = _tex_escape(prob.get("text", ""))
    points = prob.get("points", "")
    equation = prob.get("equation", "")

    # Build the problem line
    prob_line = rf"\noindent\textbf{{\textit{{{num}.}}}}"
    if text:
        prob_line += f" {text}"
    if points:
        prob_line += rf" \points{{{points}}}"
    lines.append(prob_line)
    lines.append("")

    # Main equation (display mode)
    if equation:
        lines.append(_render_equation(equation))
        lines.append("")

    # Sub-problems
    sub_problems = prob.get("sub_problems", [])
    for j, sub in enumerate(sub_problems):
        sub_text = _tex_escape(sub.get("text", ""))
        sub_eq = sub.get("equation", "")
        label = f"({j + 1})"

        if sub_text and sub_eq:
            lines.append(rf"\noindent {label} {sub_text} {_render_inline_equation(sub_eq)}")
        elif sub_eq:
            lines.append(rf"\noindent {label} {_render_inline_equation(sub_eq)}")
        elif sub_text:
            lines.append(rf"\noindent {label} {sub_text}")
        lines.append("")

    # Graph image
    if num in image_paths:
        img_path = image_paths[num]
        lines.append(r"\begin{center}")
        lines.append(rf"\includegraphics[width=0.6\linewidth]{{{img_path}}}")
        lines.append(r"\end{center}")
        lines.append("")

    # Choices (5-choice horizontal layout)
    choices = prob.get("choices", [])
    if choices:
        _generate_horizontal_choices(lines, choices)

    lines.append(r"\vspace{3mm}")
    lines.append("")


def _generate_horizontal_choices(lines: list[str], choices: list[str]) -> None:
    """Render 5 choices in a horizontal layout using makebox."""
    parts: list[str] = []
    for k, choice in enumerate(choices):
        label = CHOICE_LABELS[k] if k < len(CHOICE_LABELS) else f"({k+1})"
        rendered = _render_choice_text(choice)
        parts.append(f"{label} {rendered}")

    # Use a tabularx for even spacing across the line
    ncols = len(parts)
    col_spec = " ".join(["X"] * ncols)
    lines.append(rf"\noindent\begin{{tabularx}}{{\linewidth}}{{{col_spec}}}")
    lines.append(" & ".join(parts) + r" \\")
    lines.append(r"\end{tabularx}")
    lines.append("")


# ═══════════════════════════════════════════════════════════════════════
#  Worksheet format generator
# ═══════════════════════════════════════════════════════════════════════

def generate_worksheet_latex(data: dict, image_paths: dict[int, Path] | None = None) -> str:
    """Generate LaTeX for simple worksheet format.

    Args:
        data: Problem data dict with title, subtitle, problems
        image_paths: Mapping of problem number → image file path
    """
    if image_paths is None:
        image_paths = {}

    korean_font = _detect_korean_font()
    lines: list[str] = []

    # Preamble
    lines.append(_make_preamble(korean_font))
    lines.append(r"\begin{document}")
    lines.append("")

    # ── Header ──
    title = data.get("title", "")
    subtitle = data.get("subtitle", "")

    if title:
        lines.append(r"\begin{center}")
        lines.append(rf"\textbf{{\Large {title}}}")
        if subtitle:
            lines.append(r"\\[2mm]")
            lines.append(rf"\textbf{{{subtitle}}}")
        lines.append(r"\end{center}")
        lines.append("")

    # Info line
    info = data.get("info", "")
    if info:
        lines.append(rf"\noindent {info}")
    else:
        lines.append(r"\noindent 이름:\underline{\hspace{3cm}} \hfill 날짜:\underline{\hspace{2cm}} \hfill 점수:\underline{\hspace{1.5cm}}")
    lines.append(r"\vspace{3mm}")
    lines.append(r"\examrule")
    lines.append(r"\vspace{3mm}")

    # ── Problems in 2 columns ──
    lines.append(r"\begin{multicols}{2}")
    lines.append(r"\raggedcolumns")
    lines.append("")

    problems = data.get("problems", [])
    for i, prob in enumerate(problems, 1):
        _generate_worksheet_problem(lines, i, prob, image_paths)

    lines.append(r"\end{multicols}")
    lines.append(r"\end{document}")

    return "\n".join(lines)


def _generate_worksheet_problem(
    lines: list[str],
    num: int,
    prob: dict,
    image_paths: dict[int, Path],
) -> None:
    """Append LaTeX lines for a single worksheet problem."""
    text = _tex_escape(prob.get("text", ""))
    equation = prob.get("equation", "")

    # Problem number + text
    prob_line = rf"\noindent\textbf{{{num}.}}"
    if text:
        prob_line += f" {text}"
    lines.append(prob_line)
    lines.append("")

    # Main equation
    if equation:
        lines.append(_render_equation(equation))
        lines.append("")

    # Sub-problems
    sub_problems = prob.get("sub_problems", [])
    for j, sub in enumerate(sub_problems):
        sub_text = _tex_escape(sub.get("text", ""))
        sub_eq = sub.get("equation", "")
        label = f"({j + 1})"

        if sub_text and sub_eq:
            lines.append(rf"\noindent \quad {label} {sub_text} {_render_inline_equation(sub_eq)}")
        elif sub_eq:
            lines.append(rf"\noindent \quad {label} {_render_inline_equation(sub_eq)}")
        elif sub_text:
            lines.append(rf"\noindent \quad {label} {sub_text}")
        lines.append("")

    # Graph image
    if num in image_paths:
        img_path = image_paths[num]
        lines.append(r"\begin{center}")
        lines.append(rf"\includegraphics[width=0.6\linewidth]{{{img_path}}}")
        lines.append(r"\end{center}")
        lines.append("")

    # Choices (vertical for worksheet)
    choices = prob.get("choices", [])
    if choices:
        for k, choice in enumerate(choices):
            label = CHOICE_LABELS[k] if k < len(CHOICE_LABELS) else f"({k+1})"
            rendered = _render_choice_text(choice)
            lines.append(rf"\noindent \quad {label} {rendered}")
        lines.append("")

    lines.append(r"\vspace{4mm}")
    lines.append("")


# ═══════════════════════════════════════════════════════════════════════
#  Router
# ═══════════════════════════════════════════════════════════════════════

def generate_latex(data: dict, image_paths: dict[int, Path] | None = None) -> str:
    """Generate a complete .tex document from problem data.

    Routes to exam or worksheet format based on data["exam_type"].
    Default is exam format (학력평가).

    Args:
        data: Problem data dict
        image_paths: Mapping of problem number (1-based) → image file Path

    Returns:
        Complete LaTeX source string
    """
    exam_type = data.get("exam_type", "학력평가")
    if exam_type == "worksheet":
        return generate_worksheet_latex(data, image_paths)
    return generate_exam_latex(data, image_paths)
