# WaymakerLabs Claude Plugins

[한국어](README.ko.md) | **English**

A collection of useful Claude Code plugins by WaymakerLabs.

> `tools/` holds shared tools that live outside the plugins (e.g. `tools/agent-orchestrator/`). They are not registered in the marketplace.

## Add Marketplace

First, add the WaymakerLabs marketplace to Claude Code:

```bash
/plugin marketplace add waymakerlabs/claude-plugins
```

---

## Available Plugins

---

## ▶ minimal-statusline

> Minimal single-line statusline with Nord Aurora theme.

**Preview:**

![Minimal Statusline Preview](plugins/minimal-statusline/assets/preview.svg)

**Layout:**

| Position | Element | Description |
|----------|---------|-------------|
| 1 | Model | Current Claude model (e.g., `Opus 4.5`) |
| 2 | Directory | Working directory path (e.g., `~/Dev`) |
| 3 | Git | Branch name + status (e.g., `(main)✓`) |
| 4 | Context | Remaining context until auto-compact |
| 5 | 5H | 5-hour API usage % + reset time (e.g., `8% (2h58m)`) |
| 6 | 7D | 7-day API usage % + reset day (e.g., `15% (Fri)`) |

**Git Status Symbols:**

| Symbol | Meaning |
|--------|---------|
| ✓ | Clean (no changes) |
| + | Staged changes |
| ! | Unstaged changes |
| ? | Untracked files |

**Context Status:**

| Label | Remaining | Action |
|-------|-----------|--------|
| `Full` | > 50% | Plenty of context |
| `Half` | 30-50% | Midway point |
| `Low` | 15-30% | Consider wrapping up |
| `Compact` | 5-15% | Run `/compact` soon |
| `Compact!` | < 5% | Run `/compact` now |

#### Install

```bash
/plugin install minimal-statusline@waymakerlabs-claude-plugins
```

#### Setup

```bash
/minimal-statusline-start
```

Then restart Claude Code.

#### Update

Updates are applied automatically when plugin version changes:

1. Update the plugin:
```bash
/plugin marketplace update waymakerlabs-claude-plugins
/plugin update minimal-statusline@waymakerlabs-claude-plugins
```

2. Restart Claude Code - the new version is automatically applied via SessionStart hook.

#### Manual Installation

If you prefer not to use the plugin system:

**1. Download script**
```bash
curl -o ~/.claude/minimal-statusline.sh \
  https://raw.githubusercontent.com/waymakerlabs/claude-plugins/main/plugins/minimal-statusline/scripts/minimal-statusline.sh
```

**2. Make executable**
```bash
chmod +x ~/.claude/minimal-statusline.sh
```

**3. Add to settings.json**

Add to `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/minimal-statusline.sh"
  }
}
```

#### Credits

Based on [Awesome Statusline](https://github.com/awesomejun/awesome-claude-plugins) by awesomejun

---

## ▶ wrap-up

> Session wrap-up skill - Obsidian documentation + Git commit in one go, with a pre-commit verification gate.

**Features:**

| Feature | Description |
|---------|-------------|
| Daily Log | Record today's work in daily log |
| Handoff | Generate handoff document (single file, overwrites previous) |
| Verification Gate | Auto-detect and run the repo's own typecheck/lint/test/build before committing; runs the code-review gate with the project/global cross-check setup (e.g. direct codex CLI run) when configured |
| Doc Update | Auto-update related docs (project overview, etc.) |
| Git Commit/Push | Commit and push code changes |

> **Note**: Handoff maintains only one file. Previous handoff is deleted and a new timestamped file is created, so you can see when the last session ended. The "Next steps" section is written with each item's file scope and independence/dependency marked explicitly, so a successor session (or a parallel agent) can tell which items are safe to dispatch in parallel.

**Execution Flow (Sequential, 10 steps):**

```
/wrap-up
    │
    1. Check config (ask for Obsidian vault path if not set)
    2. Confirm work type & find project folder
    3. Analyze this session's work (collect changed/read files, decisions, dead ends)
    4. Write/update daily log
    5. Write handoff doc (next steps marked independent vs. dependent)
    6. Verification gate — deterministic checks, then code review
       (project/global cross-check setup, e.g. codex CLI, when configured)
    7. Bump project version
    8. Update related docs
    9. Git commit & push
    10. Print next-session start prompt
```

#### Install

```bash
/plugin install wrap-up@waymakerlabs-claude-plugins
```

#### Usage

```bash
/wrap-up              # Normal execution
/wrap-up --reconfigure  # Reconfigure Obsidian vault path
```

#### Output Example

```
✅ Wrap-up complete!

📝 Daily log: Logos App/daily-logs/2026-01-21.md
📋 Handoff: Logos App/handoffs/HANDOFF-2026-01-21-1730.md
📦 Commit: abc1234 - feat: add vocabulary validation

---
🚀 Next session prompt:

.../Logos App/handoffs/HANDOFF-2026-01-21-1730.md - read and continue working.
```

---

## ▶ obsidian-documents

> Obsidian documentation - Say "옵시디언에 저장해줘" and it saves to Obsidian as markdown.

**Features:**

| Feature | Description |
|---------|-------------|
| Natural Language | Triggers on "옵시디언에 저장해줘", "옵시디안에 정리해줘", "obsidian에 넣어줘", etc. |
| Slash Command | Also available as `/obsidian-documents` |
| Smart Location | Saves to project `documents/` folder or vault root |
| Shared Config | Uses same config as wrap-up |

**Save Location:**

| Context | Save Location |
|---------|---------------|
| Inside Git project | `{project}/documents/{filename}.md` |
| Outside project | Obsidian vault root |

#### Install

```bash
/plugin install obsidian-documents@waymakerlabs-claude-plugins
```

#### Usage

Natural language:
```
이 내용 옵시디언에 저장해줘
방금 논의한 API 설계 정리해서 옵시디언에 넣어줘
```

Slash command:
```bash
/obsidian-documents [content or topic]
```

#### Config

Uses `~/.claude/wrap-up-config.json` (shared with wrap-up):

```json
{
  "obsidianVault": "/path/to/obsidian/vault",
  "projectsPath": "001. 프로젝트/진행중"
}
```

---

## ▶ verify-skills

> Self-maintaining code verification framework - auto-generate and run project-specific verify skills.

Based on [codefactory-co/kimoring-ai-skills](https://github.com/codefactory-co/kimoring-ai-skills).

**Skills:**

| Skill | Description |
|-------|-------------|
| `/manage-skills` | Analyze session changes and auto-create/update verify skills |
| `/verify-implementation` | Run all registered verify skills and generate unified report |

**How It Works:**

```
1. Write code
2. /manage-skills
   → Analyze git diff → Suggest verify skill creation
   → Creates .claude/skills/verify-*/SKILL.md on approval
3. /verify-implementation
   → Run all verify skills → Unified report → Auto-fix suggestions
4. Create PR
```

#### Install

```bash
/plugin install verify-skills@waymakerlabs-claude-plugins
```

#### Usage

```bash
/manage-skills                    # Analyze changes, create/update verify skills
/verify-implementation            # Run all verify skills
/verify-implementation api        # Run specific verify skill only
```

---

## ▶ plan-and-build

> Structured development workflow: Research → Plan → Annotation Cycle → Implementation.

Inspired by Boris Tane's "How I Use Claude Code" blog post. Instead of asking AI to code right away, this skill separates **research, planning, and implementation** — humans make decisions, AI executes.

**Workflow:**

```
/plan-and-build {task description}
    │
    ├─ Research: Deep codebase analysis → research.md
    ├─ Plan: Implementation plan with code snippets → plan.md
    ├─ Annotation Cycle: You add inline comments → AI updates plan
    │   └─ Repeat until satisfied
    ├─ Todo: Checklist added to plan.md
    ├─ Implementation: Execute plan mechanically
    └─ Done: Summary report
```

**Key Principle:** No code changes until you say "구현 시작" (start implementation). All documents are preserved in `docs/plan-and-build/` for future reference.

#### Install

```bash
/plugin install plan-and-build@waymakerlabs-claude-plugins
```

#### Usage

```bash
/plan-and-build Add user authentication system
/plan-and-build Refactor monolithic UserService into domain services
```

---

## ▶ linear

> Linear issue management, dev cycle automation, and planning workflows.

**Skills:**

| Skill | Description |
|-------|-------------|
| `/linear` | General Linear management - issue CRUD, bug triage, team workload analysis, labeling, sprint retrospectives |
| `/linear-dev` | Dev cycle automation - start issues (branch creation), create PRs, merge & cleanup, next task suggestions |
| `/linear-plan` | Planning & structuring - Epic decomposition, sprint planning, release planning with milestones |

**Dev Cycle Flow:**

```
/linear-dev start LOG-101  →  Code  →  /linear-dev pr  →  Review  →  /linear-dev finish
                                                                            │
                                                                            ▼
                                                                /linear-dev start LOG-102
```

**Core Principles:**
- 1 Issue = 1 Branch = 1 PR
- PR-reviewable size (200-400 lines)
- Auto state transitions via GitHub-Linear integration

#### Install

```bash
/plugin install linear@waymakerlabs-claude-plugins
```

#### Usage

```bash
/linear 내 이슈 보여줘              # List my issues
/linear-dev start LOG-101          # Start working on an issue
/linear-dev pr                     # Create PR from current branch
/linear-dev finish                 # Merge PR + cleanup
/linear-dev next                   # Show next tasks by priority
/linear-plan 기능 분해              # Decompose feature into sub-tasks
/linear-plan 스프린트 계획           # Sprint planning
/linear-plan 릴리즈 계획            # Release planning with milestones
```

---

## ▶ llm-wiki

> LLM Wiki intake + recall + classify integrated helper for Karpathy's 4-layer LLM Wiki structure (Topics / Entities / Syntheses / Sources). Capture external URLs/memos into `00. Inbox` with security redaction, retrieve by keyword (read-only), and auto-classify on schedule.

**Sub-commands:**

| Command | Description | Version |
|---|---|---|
| `/llm-wiki:capture <URL\|text>` | External URL/memo/bundle → `00. Inbox` intake. URL token redaction + SSRF block + 4-stage dedupe + fetch fallback (login-required pages kept with user note). **No auto bundling** (`same_candidate` labels only). Callable from Telegram(openclaw) adapter. | v1.2.0 |
| `/llm-wiki:search <keyword>` | 4-layer recall search + quality self-check report (strictly read-only) | v1.0.1 |
| `/llm-wiki:classify [--mode dry-run\|live]` | Auto-classify `00. Inbox` per migration plan §8 + classification rules v1.1 + classification prompt v1.1. Suitable for unattended `home-macmini` schedule. | v1.1.0 |

**LLM Wiki data flow:**

```
[external sources]
   ↓ /llm-wiki:capture  (intake — security redact, normalize, dedupe)
[00. Inbox]
   ↓ /llm-wiki:classify  (classification — daily KST 01:00)
[60. Topics / 70. Entities / 80. Syntheses / 20. Raw Sources/derived]
   ↑ /llm-wiki:search    (recall — read-only)
[user query]
```

(Future sub-commands: `configure`, `audit`, `promote`)

**Output Format:**

1. Match count summary
2. Grouped tables by layer (Synthesis → Topic → Entity → derived/Archive)
3. Recommended reading order (3-5 steps)
4. ★ Recall quality self-check (missing / noise / latent candidates / tag boost suggestions)

**Natural Language Triggers:**

```
"vault에서 하네스 도구 관련 자료 보여줘"
"Codex와 Claude Code 협업 자료 비교해줘"
"AI Browser Agent 관련 스크랩 인벤토리"
```

**Search Scope:**

```
{vault}/{llmWikiWorkspace}/
├── 60. Topics/                ← Operational perspective
├── 70. Entities/              ← Sub-grouped by kind
│   └── tools, plugins, skills, repos, sites, tips
├── 80. Syntheses/             ← Comparison · judgment
├── 20. Raw Sources/derived/   ← Distilled notes
├── 30. Briefs/                ← Legacy (only if matched)
├── 40. Research/              ← Legacy (only if matched)
└── 90. Archive/               ← Original sources
```

#### Install

```bash
/plugin install llm-wiki@waymakerlabs-claude-plugins
```

#### Usage

```bash
# Capture (intake — URL → 00. Inbox)
/llm-wiki:capture https://example.com/article            # Single URL
/llm-wiki:capture <pasted text with URLs and notes>      # Bundle / notes mixed
claude --print "/llm-wiki:capture {message body}"        # From openclaw / channel adapter

# Recall (read-only)
/llm-wiki:search 하네스                  # Korean keyword
/llm-wiki:search Codex review loop       # English keyword
/llm-wiki:search Antigravity             # Multi-layer matches

# Inbox auto-classify
/llm-wiki:classify                       # Default: --mode dry-run (safe, no vault changes)
/llm-wiki:classify --mode live           # Actual classification + archive

# Unattended (home-macmini schedule)
claude --print "/llm-wiki:classify --mode dry-run"   # daily KST 01:00
```

#### Config

Uses `~/.claude/wrap-up-config.json` (shared with wrap-up / obsidian-documents):

```json
{
  "obsidianVault": "/path/to/obsidian/vault",
  "llmWikiWorkspace": "006. 레제 작업장"
}
```

If `llmWikiWorkspace` is missing, the plugin auto-detects by searching for a folder containing all three: `60. Topics/`, `70. Entities/`, `80. Syntheses/`.

#### Design Principle

- **Recall essence = Karpathy's 4-layer ordering** (Sources → Topics → Entities → Syntheses)
- **Noise visibility**: Surface false-positive matches so users can see them immediately
- **Latent candidate hint**: Suggest entities that don't match the keyword but belong structurally to the same domain — useful for tag-augmentation decisions

---

## ▶ auto-chain

> Milestone → wave → task autonomous execution for large multi-session work. Opus plans, GPT-6.1 Sol (OpenCode `review-sol`) reviews, parallel Claude workers implement, and one lean coordinator session per milestone integrates, verifies and hands off to the next milestone. The execution backend is auto-selected (2.0.0): inside [herdr](https://herdr.dev), workers run as Claude sessions in side panes (coordinator stays large on the left, model picked per pane, two-way messaging during work); inside Orca, the 1.7.1 Orca-tab flow (tag `auto-chain-v1.7.1-orca`).

**Covers:**

- **Four agents with fixed model/effort** — `chain-planner` (Opus high), `chain-planner-deep` (Opus xhigh), `chain-worker` (Sonnet high), `chain-worker-deep` (Opus high).
- **Lean coordinator** — never reads worker code or reruns worker tests; workers never stage/commit, the coordinator commits each task's reported paths one at a time (avoids `index.lock` races).
- **Verification budget** — full verification once per wave integration and once at milestone close.
- **Sol gates** — plan review, wave high-risk review (light, 1 round), milestone final review (heavy, max 3 rounds); verdict taken from the last `# 판정:` block with a matching snapshot.
- **Authority ceiling** — skill defaults and review SHIP never create push/external-write approval.
- **Project profile** — `.claude/autonomous-chain.md` sets verify commands, parallelism, commit/push policy and per-stage hooks.

#### Install

```bash
/plugin install auto-chain@waymakerlabs-claude-plugins
```

#### Usage

Ask for an autonomous chain on a large task ("자율체인으로 진행해"), or invoke it directly:

```bash
Skill(auto-chain:autonomous-chain)
```

---

## ▶ helpai

> Project helper skill set under the `helpai` namespace. The first skill, `project-setup`, bootstraps the current folder with a private GitHub repo, a fixed `docs/` layout, a milestone ledger and project rules. More project-helper skills will be added to this namespace over time.

**Covers (`project-setup`):**

- **Fixed `docs/` layout** — creates `product`, `architecture`, `design`, `plans`, `milestones`, `operations` and `archive`, plus `docs/index.md` that indexes every document under `docs/`. If `docs/` already exists, it back-fills the index and never moves existing files.
- **Milestone ledger** — creates `docs/milestones/README.md` using milestone IDs `M{plan}-{nn}` (e.g. `M1-01`, `M1-02`). The plan number increments each time a new milestone plan is made.
- **Project rules** — adds a marker-delimited docs/milestone rules section to the project `CLAUDE.md` (and `AGENTS.md` if present). Safe to re-run: the section is updated in place, never duplicated.
- **Private GitHub repo (last)** — local files are prepared first; then, if the folder is not a git repo (or has no remote), it asks once (owner + commit file list) and creates a private repo named after the folder with the active `gh` account, adds a `.gitignore`, and pushes everything as a single initial commit, excluding secret-looking files.

#### Install

```bash
/plugin install helpai@waymakerlabs-claude-plugins
```

#### Usage

Run it from the project folder you want to set up:

```bash
/helpai:project-setup
```

---

## Troubleshooting

### Usage shows N/A

API usage requires Claude Pro/Max subscription with OAuth authentication.

### Colors look wrong

Your terminal must support True Color (24-bit). We recommend modern terminals like iTerm2, Warp, or Alacritty.

## License

MIT
