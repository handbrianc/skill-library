# Skill Library

An OpenCode skill distribution template. Packages reusable skill files for agents — nothing to build or run.

> **CI/CD:** PRs are validated via GitHub Actions — frontmatter schema compliance,
> shellcheck on all bash scripts, placeholder detection, and trigger phrase conflict
> checks. See [.github/workflows/validate.yml](.github/workflows/validate.yml).

## What's Inside

| Path | Purpose |
| ------ | --------- |
| `skills/note-taker/` | Conference note-taking and synthesis skill for transforming transcripts into structured summaries |
| `skills/sarcastic/` | A tone/sarcasm skill for agent use |
| `skills/repo-health/` | Repo health audit orchestrator + 10 phase subskills + scripts for secrets, licenses, complexity, coverage, and more. Two modes: `report` (default, findings only) and `fix` (opt-in remediation loop) |
| `skills/spec-compliance/` | Specification compliance verification skill |
| User-installed skills | Located at `~/.config/opencode/skills/` — these take priority over project-local copies |

## Features

### `sarcastic`

Provides a sharp-tongued commentary mode for agents. Activates when users say things
like *"you're so slow"*, *"are you serious"*, or any phrase warranting merciless
sarcasm. Keeps responses punchy, emoji-free, and confrontationally indifferent.

### `repo-health` (skill + 10 subskills + 3 automation scripts)

An **orchestrator skill** (`skill(name="repo-health")`) that delegates to 10 phase
subskills (`repo-health--phase-{N}-{name}`) + one helpers subskill. Subskills are only
callable by the orchestrator. Phases:

| # | Phase | Subskill |
| --- | ------- | ---------- |
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
| 10 | Remediation Loop (mode=fix only) | `repo-health--phase-10-remediate` |

#### Modes: report (default) vs fix

`repo-health` takes one parameter, `mode`, resolved from your request — no CLI flags or
config needed. The skill states the resolved mode at the start of each run.

| mode | Behavior | How to trigger |
| ------ | ----------- | ---------------- |
| `report` **(default)** | Full audit + graded findings report. Read-only: no files modified. | "review this repo", "audit this project", "health check", "quality gate" |
| `fix` | Everything above, plus the Phase 10 remediation loop: fixes findings, re-audits, iterates until only NITPICKs remain. No confirmation gates; changes left uncommitted for review. | "fix findings", "remediate issues", "auto-fix everything", or an explicit `mode=fix` |

```text
# Report mode (default) — findings only, nothing modified
"Run a health check on this project."

# Fix mode — audit + silent remediation loop
"Audit this repo and fix everything you find."
"Run repo-health with mode=fix."

# Two-step: report first, then opt into fixes
"Health check this repo."       # → graded findings report
"Now fix the findings."         # → resumes from the synthesized report, no re-audit
```

Ambiguous requests default to `report` — remediation never runs unless you asked for it.

**Other agents (GitHub Copilot, Claude Code, …):** the OpenCode entry points
(`@repo-health`, `skill(...)`, `/commands`) don't exist there. These agents read the
repo's `AGENTS.md`, which points them at `skills/repo-health/SKILL.md` as the workflow;
mode still resolves from your words (e.g. "run the repo-health audit in fix mode").

**VS Code (GitHub Copilot Chat):** slash commands now come from skills, so they work in
every VS Code harness, the Copilot CLI and the Copilot app. `/repo-health` is served by
the audit skill itself (auto- or manually invoked; append "fix" to remediate), while
`/repo-health-fix` is a manual-only wrapper (`disable-model-invocation: true`) that
`install-skills.sh` generates under `~/.copilot/skills/` from
`.github/prompts/repo-health-fix.prompt.md`. The in-repo `.github/prompts/*.prompt.md`
files still register both commands for this workspace's Chat view (Local) — skip VS
Code's prompt→skills migration button, since its `repo-health` conversion conflicts
with the installed skill.

Also ships Bash helper scripts under `scripts/` (detector, scanner, auditor,
classifier, and synthesizer variants) used by the subskills, plus:

- **`compute-grade.sh`** — Automated grade computation with NITPICK awareness
  (excludes NITPICK findings from deductions). Authoritative replacement for manual
  subagent grading.
- **`classify-finding.sh`** — Applies the NITPICK rubric + non-negotiable CRITICAL
  rules deterministically via jq.
- **`synthesize-findings.sh`** — Deduplicates, resolves conflicts, classifies, and
  grades findings in one pipeline (Step A4.5 in the orchestrator workflow).

A `repo-health--helpers` subskill contains the grading rubric + script reference.

#### Cross-Platform Support

The GNU toolchain auto-installer (`install-missing-tools.sh`) now handles macOS
Homebrew-prefixed tools (`ggrep`, `grealpath`, `gdate`) with PATH hints. On Linux,
uses `pcregrep` as a fallback for PCRE matching. See
`repo-health--phase-0-environment` for details.

## Skill Installation Paths

OpenCode loads skills from two places (this repo vendors skill folders under `./skills/`
for you to copy/symlink into one of these):

1. **User-installed** (`~/.config/opencode/skills/`) — shared across all projects
2. **Project-local source** (`skills/`) — this repository’s local skill folders

User-installed skills override project-local ones of the same name.

**Windows:** use `install-skills.ps1` — the PowerShell port of `install-skills.sh`
with the same flags (`--symlink`, `--force`, `--dry-run`, `--list`, `--skip`,
`--no-copilot`, `--dest <path>`) and behavior. Run it with
`powershell -ExecutionPolicy Bypass -File .\install-skills.ps1`. `--symlink`
needs Developer Mode or elevation; the installer falls back to a directory
junction automatically. Same destinations, same wrapper generation, same
self-contained script-path rewrite (test: `pwsh -NoProfile -File
tests/test-install-scripts.ps1`).

### Scripts work from any working directory

SKILL.md files reference their supporting scripts with repo-relative paths
(`./skills/repo-health/scripts/scan-environment.sh`) so project-local skills
resolve from the repo root. That breaks in other projects, where agents (VS Code
Copilot, Copilot CLI/app, …) run with your project as the working directory.
`install-skills.sh` closes this at install time, for every copy-installed
destination (`~/.config/opencode/skills/`, `~/.copilot/skills/`, or a custom
`--dest`):

- every script reference in the installed SKILL.md files (full-path and bare
  `./install-missing-tools.sh`-style entries alike) is rewritten to an absolute
  path under the install destination — Copilot wrapper skills generated from
  `.github/prompts/*.prompt.md` get the same treatment, and
- every bundled script is made executable, so the whole support suite runs from
  any directory: `~/.copilot/skills/repo-health/scripts/scan-environment.sh
  --check-tools` works in any project, not just this repo.

The rewrite is idempotent (re-runs change nothing) and symlink installs are
left untouched — dev mode keeps repo-relative paths. `tests/test-install-scripts.sh`
asserts all of the above, mirrored for the Windows installer by
`tests/test-install-scripts.ps1`. On Windows the executable-bit step is not
applicable — the `.sh` scripts are run by bash (Git Bash/WSL), which needs no
file attributes.

## Validation & Testing

```bash
# Run the full validation suite (requires python3 + bats)
bash tests/run-tests.sh

# Or run individual checks:
python3 scripts/validate-frontmatter.py --ci      # SKILL.md schema validation
python3 scripts/detect-placeholders.py --ci         # No TODO/FIXME in skills
python3 scripts/detect-trigger-conflicts.py --ci    # No conflicting triggers
bats tests/bats/test-fix-rollback.bats              # Rollback mechanism tests
bats tests/bats/test-scan-tests.bats                # Test scanner tests
bats tests/bats/test-fix-common.bats                # Fix library tests

# ShellCheck all bash scripts
find skills -name '*.sh' -type f -exec shellcheck --severity=warning {} +
```

## Quick Start

```bash
# Symlink a single skill for local testing
ln -sf "$(pwd)/skills/<name>" ~/.config/opencode/skills/<name>

# After modifying, run validation
bash tests/run-tests.sh
```

## License

Licensed under the [MIT License](LICENSE).
