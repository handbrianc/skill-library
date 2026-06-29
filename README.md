# Skill Library

An OpenCode skill distribution template. Packages reusable skill files for agents — nothing to build, run, or test.

## What's Inside

| Path | Purpose |
|------|---------|
| `.claude/skills/gitnexus/` | Project-local GitNexus skill files (cli, exploring, impact-analysis, debugging, refactoring, guide) |
| `skills/sarcastic/` | A tone/sarcasm skill for agent use |
| User-installed skills | Located at `~/.config/opencode/skills/` — these take priority over project-local copies |

## Skill Installation Paths

OpenCode loads skills from two places:

1. **User-installed** (`~/.config/opencode/skills/`) — shared across all projects
2. **Project-local** (`.claude/skills/`) — scoped to this repo

User-installed skills override project-local ones of the same name.

## Repos Using This

- `@gitnexus` group uses this as a package source for distributed skill files

## Quick Ref

```bash
# No build, no test suite — skills are markdown files
# To install: copy or symlink skill folders to ~/.config/opencode/skills/
```