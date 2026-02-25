#!/usr/bin/env python3
"""Build a math exam/worksheet PDF from problem JSON data.

This is the PDF-pipeline counterpart of build_math_hwpx.py.
It uses the same JSON format and graph_generator.py, but outputs
PDF via LaTeX (xelatex) instead of HWPX.

Usage:
    # Exam format (default)
    python build_math_pdf.py -p problems.json -o exam.pdf

    # Worksheet format
    python build_math_pdf.py -p problems.json --exam-type worksheet -o ws.pdf

    # Keep intermediate .tex file
    python build_math_pdf.py -p problems.json --keep-tex -o exam.pdf

    # Compile an existing .tex file directly
    python build_math_pdf.py --tex custom.tex -o exam.pdf
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional, Dict

from latex_generator import generate_latex

# Resolve paths relative to this script
SCRIPT_DIR = Path(__file__).resolve().parent


# ═══════════════════════════════════════════════════════════════════════
#  xelatex helpers
# ═══════════════════════════════════════════════════════════════════════

def _find_xelatex() -> Path | None:
    """Find xelatex binary on the system."""
    # Check PATH first
    xelatex = shutil.which("xelatex")
    if xelatex:
        return Path(xelatex)

    # Common TeX Live locations
    candidates = [
        Path("/Library/TeX/texbin/xelatex"),          # macOS (MacTeX)
        Path("/usr/local/texlive/2025/bin/x86_64-linux/xelatex"),
        Path("/usr/local/texlive/2024/bin/x86_64-linux/xelatex"),
        Path("/usr/bin/xelatex"),                       # Linux package
    ]
    for p in candidates:
        if p.is_file():
            return p
    return None


def _run_xelatex(tex_path: Path, work_dir: Path) -> Path:
    """Run xelatex on a .tex file (2-pass for cross-references).

    Args:
        tex_path: Path to the .tex file
        work_dir: Working directory for xelatex output

    Returns:
        Path to the generated .pdf file

    Raises:
        SystemExit: If xelatex fails
    """
    xelatex = _find_xelatex()
    if xelatex is None:
        print("ERROR: xelatex not found!", file=sys.stderr)
        print("", file=sys.stderr)
        print("Install TeX Live:", file=sys.stderr)
        print("  macOS:  brew install --cask basictex", file=sys.stderr)
        print("          (then: sudo tlmgr install collection-langkorean kotex-utf)",
              file=sys.stderr)
        print("  Linux:  sudo apt install texlive-xetex texlive-lang-korean",
              file=sys.stderr)
        print("", file=sys.stderr)
        print("After installing, restart your terminal or run:", file=sys.stderr)
        print('  eval "$(/usr/libexec/path_helper)"', file=sys.stderr)
        raise SystemExit(1)

    cmd = [
        str(xelatex),
        "-interaction=nonstopmode",
        "-output-directory", str(work_dir),
        str(tex_path),
    ]

    # Pass 1
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(work_dir))
    if result.returncode != 0:
        _report_xelatex_error(result, tex_path, work_dir)
        raise SystemExit(1)

    # Pass 2 (resolve cross-references like page numbers)
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(work_dir))
    if result.returncode != 0:
        _report_xelatex_error(result, tex_path, work_dir)
        raise SystemExit(1)

    pdf_name = tex_path.stem + ".pdf"
    pdf_path = work_dir / pdf_name
    if not pdf_path.is_file():
        print(f"ERROR: PDF not generated at {pdf_path}", file=sys.stderr)
        raise SystemExit(1)

    return pdf_path


def _report_xelatex_error(result: subprocess.CompletedProcess, tex_path: Path, work_dir: Path) -> None:
    """Print xelatex error details."""
    print("ERROR: xelatex compilation failed!", file=sys.stderr)
    print(f"  Source: {tex_path}", file=sys.stderr)

    # Try to show the .log file (most useful for debugging)
    log_path = work_dir / (tex_path.stem + ".log")
    if log_path.is_file():
        log_text = log_path.read_text(errors="replace")
        # Extract error lines
        error_lines = []
        for line in log_text.splitlines():
            if line.startswith("!") or "Error" in line or "error" in line:
                error_lines.append(line)
        if error_lines:
            print("\n  Key errors from .log:", file=sys.stderr)
            for line in error_lines[:20]:  # Limit output
                print(f"    {line}", file=sys.stderr)
        print(f"\n  Full log: {log_path}", file=sys.stderr)
    else:
        # Fallback to stderr output
        if result.stderr:
            print("\n  xelatex stderr:", file=sys.stderr)
            for line in result.stderr.splitlines()[:20]:
                print(f"    {line}", file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════
#  Build orchestration
# ═══════════════════════════════════════════════════════════════════════

def build(
    problems_file: Path | None,
    tex_file: Path | None,
    output: Path,
    exam_type: str | None = None,
    keep_tex: bool = False,
) -> None:
    """Main build logic: JSON → .tex → PDF.

    Args:
        problems_file: Path to problems JSON
        tex_file: Path to existing .tex file (bypasses JSON/generation)
        output: Desired output PDF path
        exam_type: Override exam type (worksheet, 학력평가, etc.)
        keep_tex: If True, copy .tex and images alongside the PDF
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        work = Path(tmpdir)

        if tex_file:
            # Direct .tex compilation
            if not tex_file.is_file():
                raise SystemExit(f"TeX file not found: {tex_file}")
            # Copy .tex to work dir (xelatex needs write access)
            tex_path = work / tex_file.name
            shutil.copy2(tex_file, tex_path)

        elif problems_file:
            # JSON → .tex generation
            if not problems_file.is_file():
                raise SystemExit(f"Problems file not found: {problems_file}")

            with open(problems_file, encoding="utf-8") as f:
                data = json.load(f)

            # CLI --exam-type overrides JSON
            if exam_type:
                data["exam_type"] = exam_type

            # Generate graph images
            image_paths: dict[int, Path] = {}
            problems = data.get("problems", [])
            graph_problems = [
                (i, p) for i, p in enumerate(problems, 1) if "graph" in p
            ]
            if graph_problems:
                from graph_generator import generate_graph

                for prob_num, prob in graph_problems:
                    graph_spec = prob["graph"]
                    img_name = f"graph_{prob_num}.png"
                    img_path = work / img_name
                    generate_graph(graph_spec, img_path)
                    image_paths[prob_num] = img_path
                    print(f"  Graph: problem {prob_num} → {img_name}")

            # Generate .tex
            tex_source = generate_latex(data, image_paths)
            tex_path = work / "exam.tex"
            tex_path.write_text(tex_source, encoding="utf-8")
            print(f"  LaTeX: {tex_path}")

        else:
            raise SystemExit("Either --problems or --tex is required")

        # Compile with xelatex
        print("  Compiling with xelatex (2 passes)...")
        pdf_path = _run_xelatex(tex_path, work)
        print(f"  PDF generated: {pdf_path}")

        # Copy PDF to output
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(pdf_path, output)
        print(f"\nOUTPUT: {output}")

        # Optionally keep .tex and images
        if keep_tex:
            tex_out = output.with_suffix(".tex")
            shutil.copy2(tex_path, tex_out)
            print(f"  Kept: {tex_out}")

            # Also copy graph images if generated from JSON
            if problems_file:
                for prob_num, img_path in image_paths.items():
                    img_out = output.parent / img_path.name
                    if img_path.is_file():
                        shutil.copy2(img_path, img_out)
                        print(f"  Kept: {img_out}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build math exam/worksheet PDF from problem data"
    )
    parser.add_argument(
        "--problems", "-p",
        type=Path,
        help="JSON file containing problem data",
    )
    parser.add_argument(
        "--tex",
        type=Path,
        help="Existing .tex file to compile directly (bypasses JSON generation)",
    )
    parser.add_argument(
        "--exam-type",
        choices=["worksheet", "학력평가", "수능", "exam"],
        default=None,
        help="Exam type (default: from JSON or 학력평가)",
    )
    parser.add_argument(
        "--keep-tex",
        action="store_true",
        help="Keep intermediate .tex file alongside the PDF",
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        required=True,
        help="Output .pdf file path",
    )
    args = parser.parse_args()

    if not args.problems and not args.tex:
        parser.error("Either --problems or --tex is required")

    build(
        problems_file=args.problems,
        tex_file=args.tex,
        output=args.output,
        exam_type=args.exam_type,
        keep_tex=args.keep_tex,
    )


if __name__ == "__main__":
    main()
