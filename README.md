# Skill Library

An OpenCode skill distribution template. Packages reusable skill files for agents — nothing to build, run, or test.

## What's Inside

| Path | Purpose |
|------|---------|
| `skills/sarcastic/` | A tone/sarcasm skill for agent use |
| `skills/repo-health/` | Repo health auditing skill with scripts for secrets, licenses, complexity, coverage, and more |
| User-installed skills | Located at `~/.config/opencode/skills/` — these take priority over project-local copies |

## Features

### `sarcastic`
Provides a sharp-tongued commentary mode for agents. Activates when users say things like *"you're so slow"*, *"are you serious"*, or any phrase warranting merciless sarcasm. Keeps responses punchy, emoji-free, and confrontationally indifferent.

### `repo-health`
Conducts deterministic, six-phase repository audits:
- **Phase 1**: Tech-stack discovery (Node/Python/Go/etc.), package manager, entry-points inventory
- **Phase 2**: Code quality — dead-code detection, cyclomatic/cognitive complexity, duplication scans, dependency-utilization analysis
- **Phase 3**: Documentation audit — completeness, accuracy, and link-rot checks
- **Phase 4**: OpenSpec specification alignment verification
- **Phase 5**: Test suite health — presence, coverage, pass/fail parsing, slowest-test profiling
- **Phase 6**: Security review — npm/dependency CVE scan, SAST secrets scanning, credential-exposure audit
- **Phase 7**: SBOM and license compliance (GPL copyleft flags, permissiveness scoring)
- **Phase 8**: Consolidated actionable plan with per-finding prioritization and verification steps

Also ships 11 Bash helper scripts under `scripts/` (detector, scanner, auditor variants) used by the skill phases.

## Skill Installation Paths

OpenCode loads skills from two places (this repo vendors skill folders under `./skills/` for you to copy/symlink into one of these):

1. **User-installed** (`~/.config/opencode/skills/`) — shared across all projects
2. **Project-local source** (`skills/`) — this repository’s local skill folders

User-installed skills override project-local ones of the same name.

## Repos Using This

- `@gitnexus` group uses this as a package source for distributed skill files

## Quick Ref

```bash
# No build, no test suite — skills are markdown files
# To install: copy or symlink skill folders to ~/.config/opencode/skills/
```
