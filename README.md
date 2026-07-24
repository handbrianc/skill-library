# Skill Library

An OpenCode skill distribution template. Packages reusable skill files for agents — nothing to build, run, or test.

## What's Inside

| Path | Purpose |
|------|---------|
| `skills/note-taker/` | Conference note-taking and synthesis skill for transforming transcripts into structured summaries |
| `skills/sarcastic/` | A tone/sarcasm skill for agent use |
| `skills/repo-health/` | Repo health audit orchestrator + 10 phase subskills + scripts for secrets, licenses, complexity, coverage, and more |
| `skills/spec-compliance/` | Specification compliance verification skill |
| User-installed skills | Located at `~/.config/opencode/skills/` — these take priority over project-local copies |

## Features

### `sarcastic`
Provides a sharp-tongued commentary mode for agents. Activates when users say things like *"you're so slow"*, *"are you serious"*, or any phrase warranting merciless sarcasm. Keeps responses punchy, emoji-free, and confrontationally indifferent.

### `repo-health` (skill + 10 subskills)

An **orchestrator skill** (`skill(name="repo-health")`) that delegates to 10 phase subskills (`repo-health--phase-{N}-{name}`) + one helpers subskill. Subskills are only callable by the orchestrator. Phases:

| # | Phase | Subskill |
|---|-------|----------|
| 0 | Environment Readiness (Gate) | `repo-health--phase-0-environment` |
| 1 | Project Discovery | `repo-health--phase-1-discovery` |
| 2 | Code Quality | `repo-health--phase-2-code-quality` |
| 3 | Technical Debt | `repo-health--phase-3-tech-debt` |
| 4 | Documentation Audit | `repo-health--phase-4-docs` |
| 5 | OpenSpec Alignment | `repo-health--phase-5-specs` |
| 6 | Test Suite Health | `repo-health--phase-6-tests` |
| 7 | Security Review | `repo-health--phase-7-security` |
| 8 | SBOM & License Audit | `repo-health--phase-8-sbom` |
| 9 | 12-Factor Compliance | `repo-health--phase-9-12factor` |
| 10 | Remediation Loop | `repo-health--phase-10-remediate` |

Also ships 21 Bash helper scripts under `scripts/` (detector, scanner, auditor variants) used by the subskills, and a `repo-health--helpers` subskill containing the grading rubric + script reference.

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

## Quick Start

```bash
# Symlink a single skill for local testing
ln -sf "$(pwd)/skills/<name>" ~/.config/opencode/skills/<name>
```

## License

Licensed under the [MIT License](LICENSE).
