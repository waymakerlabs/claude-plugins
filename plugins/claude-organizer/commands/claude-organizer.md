---
name: claude-organizer
description: |
  Organize CLAUDE.md into a skill-based project structure.
  Analyzes project codebase, extracts domains (UI, API, Pipeline, Database, etc.),
  creates modular skills in .claude/skills/, and keeps CLAUDE.md minimal.
  Use when: "organize claude", "setup skills", "refactor claude.md",
  "modularize project", "create skills from claude.md"
  Can be run repeatedly - will update existing skills and re-organize new content.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - TodoWrite
---

# Claude Organizer

Transform your CLAUDE.md into a modular, skill-based project structure.

## Overview

This skill converts a monolithic CLAUDE.md into organized, domain-specific skills that follow the Progressive Disclosure pattern - loading only relevant context when needed.

## Execution Steps

### Step 1: Project Analysis

Analyze the current project to understand its structure:

1. **Read CLAUDE.md** - Extract all documented information
2. **Scan codebase structure** - Identify folders, file patterns, tech stack
3. **Check existing skills** - Look for `.claude/skills/` directory
4. **Analyze config files** - package.json, pyproject.toml, pubspec.yaml, etc.

```bash
# Files to check
ls -la
cat CLAUDE.md 2>/dev/null || echo "No CLAUDE.md found"
ls -la .claude/skills/ 2>/dev/null || echo "No existing skills"
```

### Step 2: Domain Detection

Based on project analysis, identify relevant domains:

| Detection Pattern | Domain | Skill Name |
|-------------------|--------|------------|
| `src/components/`, `*.tsx`, `*.vue`, `pages/` | Frontend UI | `ui-*` or `frontend` |
| `src/api/`, `routes/`, `handlers/`, `controllers/` | Backend API | `api-*` or `backend` |
| `pipeline/`, `scripts/`, `etl/`, data processing | Data Pipeline | `pipeline-*` |
| `prisma/`, `migrations/`, `models/`, `schema/` | Database | `database` |
| `flutter/`, `lib/`, `ios/`, `android/` | Mobile App | `mobile` or `flutter-app` |
| `deploy/`, `k8s/`, `docker/`, `Dockerfile` | Deployment | `deployment` |
| `tests/`, `__tests__/`, `spec/`, `*_test.*` | Testing | `testing` |
| Payment keywords, PG integration | Payment | `payment` |
| Auth, login, session, JWT | Authentication | `auth` |

### Step 3: User Confirmation

Present discovered domains to user for confirmation:

```
I've analyzed your project and found the following domains:

☑ pipeline-vocabulary (Data processing pipeline)
☑ flutter-app (Mobile application)
☑ deployment (Release and deploy process)
☐ testing (Add testing skill?)

Should I proceed with creating/updating these skills?
```

Use AskUserQuestion to:
- Confirm detected domains
- Ask about additional domains to add
- Clarify any ambiguous areas

### Step 4: Create/Update Skills

For each confirmed domain, create skill structure:

```
.claude/skills/{domain-name}/
├── SKILL.md              # Main skill file (< 100 lines)
└── references/           # Detailed documentation
    └── {TOPIC}.md        # Split by topic if needed
```

#### SKILL.md Template

```markdown
---
name: {domain-name}
description: |
  {Domain description in English}
  Use when: "{trigger keywords}"
---

# {Domain Title}

## Quick Start

\`\`\`bash
{most common command}
\`\`\`

## Key Files

| File | Path | Description |
|------|------|-------------|
| ... | ... | ... |

## Checklist

- [ ] Item 1
- [ ] Item 2

## Detailed Guides

- [GUIDE.md](references/GUIDE.md)
```

### Step 5: Reorganize CLAUDE.md

Transform CLAUDE.md to minimal entry point:

```markdown
# CLAUDE.md

## Project Overview
[1-2 sentences only]

## Quick Commands
\`\`\`bash
# Most essential commands only
\`\`\`

## Skills

This project uses skill-based organization.
For detailed guides, invoke the relevant skill.

| Skill | Purpose | Invoke |
|-------|---------|--------|
| {name} | {brief description} | `/{name}` |

## Essential Rules
[Only critical rules that must always be followed]
```

### Step 6: Git Configuration

Update .gitignore to include skills in version control:

```gitignore
# Claude Code
.claude/*
!.claude/skills/
```

### Step 7: Summary Report

After completion, provide summary:

```
✅ Claude Organizer Complete

Created/Updated Skills:
- pipeline-vocabulary (new)
- flutter-app (new)
- deployment (updated)

CLAUDE.md: 450 lines → 45 lines (90% reduction)

Skills are now in .claude/skills/ and tracked by Git.
Run /claude-organizer again anytime CLAUDE.md grows.
```

## Re-run Behavior

When run on a project that already has skills:

1. **Detect changes** - Compare CLAUDE.md with existing skills
2. **Identify new content** - Find sections not yet in skills
3. **Propose updates** - Show what will be added/modified
4. **Merge intelligently** - Update skills without losing existing content

## Best Practices

1. **Keep SKILL.md under 100 lines** - Move details to references/
2. **Use English for description** - For consistent skill matching
3. **Include trigger keywords** - Help Claude auto-load the right skill
4. **Progressive Disclosure** - Core info in SKILL.md, details in references/

## Related Skills

After organizing, consider creating:
- `project-health` - Master skill that checks all domains
- Domain-specific management skills (e.g., `ui-management`)
