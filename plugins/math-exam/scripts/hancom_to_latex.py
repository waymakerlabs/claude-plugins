#!/usr/bin/env python3
"""Convert Hancom equation script to LaTeX.

Hancom equation script is a proprietary math typesetting language used by
한컴오피스 (Hangul/HWP/HWPX). This module parses it and produces equivalent
LaTeX strings.

Architecture:
    1. Tokenizer  – splits raw script into tokens (keywords, braces, operators)
    2. Parser     – recursive-descent, consumes tokens and emits LaTeX directly
    3. Mappings   – lookup tables for Greek letters, operators, accents, etc.

Key design decision: 'over' (fraction) binds to adjacent atoms only, not the
entire preceding expression.  So  x = {a} over {b}  →  x = \\frac{a}{b}.

Usage:
    from hancom_to_latex import hancom_to_latex
    latex = hancom_to_latex("{x+1} over {x-1}")
    # => "\\frac{x+1}{x-1}"
"""

from __future__ import annotations

import re


# ═══════════════════════════════════════════════════════════════════════
#  Mapping tables
# ═══════════════════════════════════════════════════════════════════════

# Greek letters (lowercase)
GREEK_LOWER = {
    "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta",
    "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi",
    "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega",
    "vartheta", "varphi", "varepsilon", "varrho", "varsigma",
}

# Greek letters (uppercase) — Hancom uses e.g. ALPHA, GAMMA, DELTA
GREEK_UPPER = {
    "ALPHA", "BETA", "GAMMA", "DELTA", "EPSILON", "ZETA", "ETA",
    "THETA", "IOTA", "KAPPA", "LAMBDA", "MU", "NU", "XI", "PI",
    "RHO", "SIGMA", "TAU", "UPSILON", "PHI", "CHI", "PSI", "OMEGA",
}

# Simple keyword → LaTeX command mapping
KEYWORD_MAP: dict[str, str] = {
    # Greek lower
    **{g: f"\\{g}" for g in GREEK_LOWER},
    # Greek upper
    **{g: f"\\{g[0] + g[1:].lower()}" for g in GREEK_UPPER},
    # Operators & relations
    "times": r"\times",
    "div": r"\div",
    "cdot": r"\cdot",
    "pm": r"\pm",
    "+-": r"\pm",
    "mp": r"\mp",
    "-+": r"\mp",
    "ne": r"\neq",
    "neq": r"\neq",
    "le": r"\leq",
    "leq": r"\leq",
    "ge": r"\geq",
    "geq": r"\geq",
    "approx": r"\approx",
    "equiv": r"\equiv",
    "sim": r"\sim",
    "propto": r"\propto",
    "ll": r"\ll",
    "gg": r"\gg",
    # Set theory
    "in": r"\in",
    "notin": r"\notin",
    "subset": r"\subset",
    "supset": r"\supset",
    "subseteq": r"\subseteq",
    "supseteq": r"\supseteq",
    "cup": r"\cup",
    "cap": r"\cap",
    "setminus": r"\setminus",
    "emptyset": r"\emptyset",
    # Logic
    "forall": r"\forall",
    "exist": r"\exists",
    "exists": r"\exists",
    "therefore": r"\therefore",
    "because": r"\because",
    "neg": r"\neg",
    "land": r"\land",
    "lor": r"\lor",
    # Arrows
    "->": r"\to",
    "rarrow": r"\rightarrow",
    "larrow": r"\leftarrow",
    "<->": r"\leftrightarrow",
    "lrarrow": r"\leftrightarrow",
    "Rarrow": r"\Rightarrow",
    "Larrow": r"\Leftarrow",
    "uarrow": r"\uparrow",
    "darrow": r"\downarrow",
    # Misc symbols
    "inf": r"\infty",
    "partial": r"\partial",
    "nabla": r"\nabla",
    "deg": r"^{\circ}",
    "cdots": r"\cdots",
    "ldots": r"\ldots",
    "vdots": r"\vdots",
    "ddots": r"\ddots",
    "prime": r"\prime",
    "circ": r"\circ",
    "bullet": r"\bullet",
    "star": r"\star",
    "angle": r"\angle",
    "perp": r"\perp",
    "parallel": r"\parallel",
    "triangle": r"\triangle",
    "square": r"\square",
    "diamond": r"\diamond",
    "ell": r"\ell",
    "hbar": r"\hbar",
    "Re": r"\Re",
    "Im": r"\Im",
    "aleph": r"\aleph",
    "wp": r"\wp",
}

# Built-in function names (rendered in roman/upright)
BUILTIN_FUNCTIONS = {
    "sin", "cos", "tan", "cot", "sec", "csc",
    "arcsin", "arccos", "arctan",
    "sinh", "cosh", "tanh", "coth",
    "log", "ln", "lg", "exp",
    "det", "mod", "gcd",
    "max", "min",
    "dim", "ker", "hom", "arg",
    "lim", "Lim",
    "limsup", "liminf",
}

# Accent / decoration commands  (hancom → LaTeX)
ACCENTS = {
    "hat": r"\hat",
    "tilde": r"\tilde",
    "bar": r"\bar",
    "vec": r"\vec",
    "dot": r"\dot",
    "ddot": r"\ddot",
    "under": r"\underline",
    "overline": r"\overline",
    "overbrace": r"\overbrace",
    "underbrace": r"\underbrace",
    "widetilde": r"\widetilde",
    "widehat": r"\widehat",
    "check": r"\check",
    "breve": r"\breve",
    "acute": r"\acute",
    "grave": r"\grave",
}

# Environment keywords (hancom → LaTeX environment)
MATRIX_ENVS = {
    "matrix": "matrix",
    "pmatrix": "pmatrix",
    "bmatrix": "bmatrix",
    "dmatrix": "vmatrix",   # dmatrix = determinant = | |
    "Bmatrix": "Bmatrix",
    "vmatrix": "vmatrix",
    "Vmatrix": "Vmatrix",
}

# Large operators
LARGE_OPS = {
    "int": r"\int",
    "dint": r"\iint",
    "tint": r"\iiint",
    "oint": r"\oint",
    "sum": r"\sum",
    "prod": r"\prod",
    "coprod": r"\coprod",
    "bigcup": r"\bigcup",
    "bigcap": r"\bigcap",
}

# Bracket pairs for left/right
BRACKET_MAP = {
    "(": "(",
    ")": ")",
    "[": "[",
    "]": "]",
    "|": "|",
    "||": r"\|",
    "lbrace": r"\{",
    "rbrace": r"\}",
    "{": r"\{",
    "}": r"\}",
    "langle": r"\langle",
    "rangle": r"\rangle",
    "lceil": r"\lceil",
    "rceil": r"\rceil",
    "lfloor": r"\lfloor",
    "rfloor": r"\rfloor",
    ".": ".",
}

# Font style commands that take an argument
FONT_STYLES = {
    "rm": r"\mathrm",
    "it": r"\mathit",
    "bold": r"\mathbf",
    "rmbold": r"\mathbf",
    "bb": r"\mathbb",
    "cal": r"\mathcal",
    "frak": r"\mathfrak",
}


# ═══════════════════════════════════════════════════════════════════════
#  Tokenizer
# ═══════════════════════════════════════════════════════════════════════

_TOKEN_RE = re.compile(
    r'"[^"]*"'            # quoted text
    r"|<->"               # bidirectional arrow
    r"|->"                # right arrow
    r"|\+-"               # plus-minus
    r"|-\+"               # minus-plus
    r"|\|\|"              # double vertical bar
    r"|[{}()^_#&~`|=<>+\-*/!,;:\[\]\\]"   # single special chars
    r"|[A-Za-z]+"         # keyword / identifier
    r"|\d+(?:\.\d+)?"    # number
    r"|[^\s]"             # any other non-whitespace
)


def _tokenize(script: str) -> list[str]:
    """Split Hancom equation script into tokens."""
    return _TOKEN_RE.findall(script)


# ═══════════════════════════════════════════════════════════════════════
#  Parser (recursive descent)
# ═══════════════════════════════════════════════════════════════════════

# Boundary tokens — these cause parse_expression to stop
_BOUNDARIES = frozenset(("}", ")", "]", "right"))


class _Parser:
    """Recursive-descent parser: consumes tokens, emits LaTeX.

    Grammar (simplified):
        expression = atom { atom }
        atom       = primary [ 'over' primary ] { ('_'|'^') primary }
        primary    = group | '(' expression ')' | keyword_construct | token
        group      = '{' expression '}'
    """

    def __init__(self, tokens: list[str]):
        self.tokens = tokens
        self.pos = 0

    def peek(self) -> str | None:
        if self.pos < len(self.tokens):
            return self.tokens[self.pos]
        return None

    def advance(self) -> str:
        tok = self.tokens[self.pos]
        self.pos += 1
        return tok

    def expect(self, val: str) -> str:
        tok = self.advance()
        if tok != val:
            raise ValueError(f"Expected '{val}', got '{tok}'")
        return tok

    def at_end(self) -> bool:
        return self.pos >= len(self.tokens)

    # ─── Entry point ──────────────────────────────────────────────

    def parse(self) -> str:
        """Parse the full token stream."""
        return self.parse_expression()

    # ─── Expression (sequence of atoms) ───────────────────────────

    def parse_expression(self) -> str:
        """Parse a sequence of atoms until a boundary or end."""
        parts: list[str] = []
        while not self.at_end():
            tok = self.peek()
            if tok in _BOUNDARIES or tok == "#" or tok == "&":
                break
            old_pos = self.pos
            atom = self.parse_atom()
            # Safety: if no progress was made, consume one token to prevent
            # infinite loops on unexpected input
            if self.pos == old_pos:
                parts.append(self.advance())
                continue
            if atom:
                parts.append(atom)
        return " ".join(parts)

    # ─── Atom (element + optional over + sub/superscript) ─────────

    def parse_atom(self) -> str:
        """Parse one atom: primary + sub/sup, optionally followed by 'over'."""
        base = self.parse_primary()
        # Consume sub/superscripts on the base first
        result = self._consume_scripts(base)

        # Handle 'over' AFTER scripts — so 4^{x-1} over 8^x works correctly
        if self.peek() == "over":
            self.advance()
            denom = self.parse_primary()
            denom = self._consume_scripts(denom)
            return f"\\frac{{{result}}}{{{denom}}}"

        return result

    def _consume_scripts(self, base: str) -> str:
        """Consume optional _/^ subscripts/superscripts after a base."""
        result = base
        while self.peek() in ("_", "^", "SUB", "SUP"):
            tok = self.advance()
            if tok in ("_", "SUB"):
                sub = self.parse_primary()
                result += f"_{{{sub}}}"
            elif tok in ("^", "SUP"):
                sup = self.parse_primary()
                result += f"^{{{sup}}}"
        return result

    # ─── Primary (core element) ───────────────────────────────────

    def parse_primary(self) -> str:
        """Parse a primary element: group, keyword, number, etc."""
        tok = self.peek()
        if tok is None:
            return ""

        # ── Braced group ──
        if tok == "{":
            return self.parse_group()

        # ── Quoted text → \text{...} ──
        if tok.startswith('"') and tok.endswith('"'):
            self.advance()
            inner = tok[1:-1]
            return f"\\text{{{inner}}}"

        # ── Parenthesized group (not left/right) ──
        if tok == "(":
            self.advance()
            inner = self._parse_until(")")
            if self.peek() == ")":
                self.advance()
            return f"({inner})"

        # ── Square brackets ──
        if tok == "[":
            self.advance()
            inner = self._parse_until("]")
            if self.peek() == "]":
                self.advance()
            return f"[{inner}]"

        # ── Special spacing ──
        if tok == "~":
            self.advance()
            return r"\;"

        if tok == "`":
            self.advance()
            return r"\,"

        # ── Line break / column (should be consumed by environments) ──
        if tok == "#":
            self.advance()
            return r"\\"

        if tok == "&":
            self.advance()
            return "&"

        # ── Advance past the token for keyword processing ──
        self.advance()

        # ── sqrt ──
        if tok == "sqrt":
            arg = self.parse_primary()
            return f"\\sqrt{{{arg}}}"

        # ── root n of {x} → \sqrt[n]{x} ──
        if tok == "root":
            n = self.parse_primary()
            if self.peek() == "of":
                self.advance()
            arg = self.parse_primary()
            return f"\\sqrt[{n}]{{{arg}}}"

        # ── left ... right (auto-sizing brackets) ──
        if tok == "left":
            lbracket = self._consume_bracket()
            inner = self._parse_left_right_body()
            if self.peek() == "right":
                self.advance()
                rbracket = self._consume_bracket()
            else:
                rbracket = "."
            return f"\\left{lbracket} {inner} \\right{rbracket}"

        # ── cases / eqalign / pile ──
        if tok == "cases":
            body = self._parse_env_body()
            return f"\\begin{{cases}} {body} \\end{{cases}}"

        if tok == "eqalign":
            body = self._parse_env_body()
            return f"\\begin{{aligned}} {body} \\end{{aligned}}"

        if tok == "pile":
            body = self._parse_env_body()
            return f"\\begin{{gathered}} {body} \\end{{gathered}}"

        # ── Matrix environments ──
        if tok in MATRIX_ENVS:
            env = MATRIX_ENVS[tok]
            body = self._parse_env_body()
            return f"\\begin{{{env}}} {body} \\end{{{env}}}"

        # ── Large operators (int, sum, prod, etc.) ──
        if tok in LARGE_OPS:
            return LARGE_OPS[tok]

        # ── Built-in functions ──
        if tok in BUILTIN_FUNCTIONS:
            if tok == "Lim":
                return r"\lim"
            return f"\\{tok}"

        # ── Accents / decorations ──
        if tok in ACCENTS:
            arg = self.parse_primary()
            return f"{ACCENTS[tok]}{{{arg}}}"

        # ── Font styles (take argument) ──
        if tok in FONT_STYLES:
            arg = self.parse_primary()
            return f"{FONT_STYLES[tok]}{{{arg}}}"

        # ── Simple keyword mapping (Greek, operators, symbols) ──
        if tok in KEYWORD_MAP:
            return KEYWORD_MAP[tok]

        # ── Fallthrough: letters, numbers, operators — pass through ──
        return tok

    # ─── Helpers ──────────────────────────────────────────────────

    def parse_group(self) -> str:
        """Parse { ... } and return inner LaTeX."""
        self.expect("{")
        inner = self._parse_until("}")
        if self.peek() == "}":
            self.advance()
        return inner

    def _parse_until(self, closing: str) -> str:
        """Parse tokens until we see 'closing', handling # and & inside."""
        parts: list[str] = []
        while not self.at_end() and self.peek() != closing:
            tok = self.peek()
            if tok == "#":
                self.advance()
                parts.append(r"\\")
            elif tok == "&":
                self.advance()
                parts.append("&")
            else:
                old_pos = self.pos
                part = self.parse_expression()
                if self.pos == old_pos:
                    # No progress — consume token to prevent infinite loop
                    parts.append(self.advance())
                    continue
                if part:
                    parts.append(part)
        return " ".join(parts)

    def _parse_left_right_body(self) -> str:
        """Parse content between \\left and \\right delimiters."""
        parts: list[str] = []
        while not self.at_end() and self.peek() != "right":
            tok = self.peek()
            if tok == "#":
                self.advance()
                parts.append(r"\\")
            elif tok == "&":
                self.advance()
                parts.append("&")
            else:
                old_pos = self.pos
                part = self.parse_expression()
                if self.pos == old_pos:
                    parts.append(self.advance())
                    continue
                if part:
                    parts.append(part)
        return " ".join(parts)

    def _consume_bracket(self) -> str:
        """Consume the next token and map it to a LaTeX bracket."""
        tok = self.peek()
        if tok is None:
            return "."
        self.advance()
        return BRACKET_MAP.get(tok, tok)

    def _parse_env_body(self) -> str:
        """Parse body of an environment (expects { ... } with # and &)."""
        if self.peek() == "{":
            return self.parse_group()
        return self.parse_primary()


# ═══════════════════════════════════════════════════════════════════════
#  Public API
# ═══════════════════════════════════════════════════════════════════════

def hancom_to_latex(script: str) -> str:
    """Convert a Hancom equation script string to LaTeX.

    Args:
        script: Hancom equation script (e.g. "{x+1} over {x-1}")

    Returns:
        LaTeX string (e.g. "\\frac{x+1}{x-1}")
    """
    if not script or not script.strip():
        return ""
    tokens = _tokenize(script.strip())
    parser = _Parser(tokens)
    result = parser.parse()
    # Clean up extra spaces
    result = re.sub(r"\s+", " ", result).strip()
    return result


def convert_choice(choice: str) -> str:
    """Convert a choice string, handling $...$ wrapping.

    If the choice is wrapped in $...$, the inner content is converted
    from Hancom script to LaTeX and re-wrapped.
    Plain text choices are returned as-is.
    """
    if choice.startswith("$") and choice.endswith("$") and len(choice) > 1:
        inner = choice[1:-1]
        return f"${hancom_to_latex(inner)}$"
    return choice


# ═══════════════════════════════════════════════════════════════════════
#  Self-test
# ═══════════════════════════════════════════════════════════════════════

def _self_test():
    """Run built-in test cases."""
    tests: list[tuple[str, str]] = [
        # --- Basic arithmetic ---
        ("2x + 3 = 7", "2 x + 3 = 7"),

        # --- Fractions ---
        ("a over b", r"\frac{a}{b}"),
        ("{x+1} over {x-1}", r"\frac{x + 1}{x - 1}"),
        ("-{7} over {2} times (-3)", r"- \frac{7}{2} \times (- 3)"),
        # Nested fraction
        ("{a over b} over c", r"\frac{\frac{a}{b}}{c}"),
        # Fraction should not grab preceding unrelated atoms
        ("x = {a} over {b}", r"x = \frac{a}{b}"),

        # --- Square root ---
        ("sqrt {x}", r"\sqrt{x}"),
        ("sqrt {b^2 - 4ac}", r"\sqrt{b^{2} - 4 ac}"),

        # --- nth root ---
        ("root 3 of {27}", r"\sqrt[3]{27}"),

        # --- Subscript / superscript ---
        ("x^2", r"x^{2}"),
        ("x_i", r"x_{i}"),
        ("x_i ^2", r"x_{i}^{2}"),
        ("a_n", r"a_{n}"),

        # --- Large operators ---
        ("int _{a} ^{b} f(x) dx", r"\int_{a}^{b} f (x) dx"),
        ("sum _{k=1} ^{n} a_k", r"\sum_{k = 1}^{n} a_{k}"),
        ("prod _{i=1} ^{n} x_i", r"\prod_{i = 1}^{n} x_{i}"),

        # --- Limits ---
        ("lim _{x -> 0} f(x)", r"\lim_{x \to 0} f (x)"),

        # --- Auto-sizing brackets ---
        ("left ( {a over b} right )", r"\left( \frac{a}{b} \right)"),
        ("left | -{5} over {2} right |", r"\left| - \frac{5}{2} \right|"),
        ("left [ x right ]", r"\left[ x \right]"),
        ("left lbrace x right rbrace", r"\left\{ x \right\}"),

        # --- Cases (systems of equations) ---
        ("cases {2x+y=5 # 3x-2y=4}",
         r"\begin{cases} 2 x + y = 5 \\ 3 x - 2 y = 4 \end{cases}"),

        # --- Matrices ---
        ("pmatrix {a & b # c & d}",
         r"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"),
        ("bmatrix {1 & 0 # 0 & 1}",
         r"\begin{bmatrix} 1 & 0 \\ 0 & 1 \end{bmatrix}"),

        # --- Greek letters ---
        ("alpha", r"\alpha"),
        ("beta", r"\beta"),
        ("theta", r"\theta"),
        ("omega", r"\omega"),
        ("GAMMA", r"\Gamma"),
        ("DELTA", r"\Delta"),

        # --- Special symbols ---
        ("inf", r"\infty"),
        ("partial", r"\partial"),
        ("therefore", r"\therefore"),
        ("pm", r"\pm"),
        ("+-", r"\pm"),
        ("ne", r"\neq"),
        ("le", r"\leq"),
        ("ge", r"\geq"),
        ("approx", r"\approx"),
        ("equiv", r"\equiv"),

        # --- Spacing ---
        ("~", r"\;"),
        ("`", r"\,"),

        # --- Built-in functions ---
        ("sin x", r"\sin x"),
        ("cos ^2 theta", r"\cos^{2} \theta"),
        ("log _2 8", r"\log_{2} 8"),
        ("ln x", r"\ln x"),

        # --- Accents ---
        ("hat a", r"\hat{a}"),
        ("vec v", r"\vec{v}"),
        ("bar x", r"\bar{x}"),
        ("tilde a", r"\tilde{a}"),
        ("dot a", r"\dot{a}"),

        # --- Quoted text ---
        ('"text"', r"\text{text}"),

        # --- Arrows ---
        ("->", r"\to"),
        ("<->", r"\leftrightarrow"),

        # --- Degree ---
        ("60 deg", r"60 ^{\circ}"),

        # --- Complex expressions from sample JSONs ---

        # Quadratic formula
        ("x = {-b +- sqrt {b^2 - 4ac}} over {2a}",
         r"x = \frac{- b \pm \sqrt{b^{2} - 4 ac}}{2 a}"),

        # Fraction equation
        ("{2x+1} over 3 = {x-2} over 5",
         r"\frac{2 x + 1}{3} = \frac{x - 2}{5}"),

        # Powers
        ("(2^4)^3 div 2^{10}",
         r"(2^{4})^{3} \div 2^{10}"),

        # Double integral
        ("dint f(x,y) dxdy", r"\iint f (x , y) dxdy"),

        # From sample_exam: mixed expression
        ("-{7} over {2} times (-3) + 4 times left | -{5} over {2} right |",
         r"- \frac{7}{2} \times (- 3) + 4 \times \left| - \frac{5}{2} \right|"),

        # Limit with fraction
        ("lim _{x -> 0} {sin x} over x",
         r"\lim_{x \to 0} \frac{\sin x}{x}"),

        # Series
        ("sum _{k=1} ^{n} k = {n(n+1)} over 2",
         r"\sum_{k = 1}^{n} k = \frac{n (n + 1)}{2}"),

        # Trig identities
        ("sin ^2 theta + cos ^2 theta = 1",
         r"\sin^{2} \theta + \cos^{2} \theta = 1"),

        # Matrix equation
        ("pmatrix {1 & 2 # 3 & 4} pmatrix {x # y} = pmatrix {5 # 11}",
         r"\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix} \begin{pmatrix} x \\ y \end{pmatrix} = \begin{pmatrix} 5 \\ 11 \end{pmatrix}"),

        # Log with subscript
        ("log _a xy = log _a x + log _a y",
         r"\log_{a} xy = \log_{a} x + \log_{a} y"),

        # Definite integral
        ("int _{0} ^{2} (3x^2 + 2x) dx",
         r"\int_{0}^{2} (3 x^{2} + 2 x) dx"),

        # over after superscript (regression: 4^{x-1} over 8^x)
        ("2^{x+1} times 4^{x-1} over 8^x",
         r"2^{x + 1} \times \frac{4^{x - 1}}{8^{x}}"),

        # General term of sequence
        ("a_n = a_1 + (n-1)d",
         r"a_{n} = a_{1} + (n - 1) d"),

        # Derivative definition
        ("f'(x) = lim _{h -> 0} {f(x+h) - f(x)} over h",
         r"f ' (x) = \lim_{h \to 0} \frac{f (x + h) - f (x)}{h}"),
    ]

    passed = 0
    failed = 0
    for i, (inp, expected) in enumerate(tests, 1):
        result = hancom_to_latex(inp)
        norm_result = re.sub(r"\s+", " ", result).strip()
        norm_expected = re.sub(r"\s+", " ", expected).strip()
        if norm_result == norm_expected:
            passed += 1
        else:
            failed += 1
            print(f"  FAIL #{i}: {inp!r}")
            print(f"    expected: {norm_expected!r}")
            print(f"    got:      {norm_result!r}")

    # Test convert_choice
    choice_tests = [
        ("$3 sqrt 2$", r"$3 \sqrt{2}$"),
        ("$-{1} over {2}$", r"$- \frac{1}{2}$"),
        ("16", "16"),
        ("$sqrt 4 = 2$", r"$\sqrt{4} = 2$"),
        ("$6a^2 + 6a + 1$", r"$6 a^{2} + 6 a + 1$"),
    ]
    for inp, expected in choice_tests:
        result = convert_choice(inp)
        norm_result = re.sub(r"\s+", " ", result).strip()
        norm_expected = re.sub(r"\s+", " ", expected).strip()
        if norm_result == norm_expected:
            passed += 1
        else:
            failed += 1
            print(f"  FAIL choice: {inp!r}")
            print(f"    expected: {norm_expected!r}")
            print(f"    got:      {norm_result!r}")

    total = passed + failed
    print(f"\nSelf-test: {passed}/{total} passed", end="")
    if failed:
        print(f" ({failed} FAILED)")
    else:
        print(" — all OK!")
    return failed == 0


if __name__ == "__main__":
    _self_test()
