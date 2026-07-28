# Changelog

All notable changes to this skill-library repository are documented here.

Entries use [Keep a Changelog](https://keepachangelog.com/) conventions: Added, Changed, Deprecated, Removed, Fixed, Security.

## [Unreleased]

### Added

- `skills/repo-health/scripts/classify-finding.sh`: Automated NITPICK rubric
  classification — applies severity-based defaults, NITPICK test patterns (cosmetic,
  negligible, quick-manual), and non-negotiable CRITICAL override in a single jq
  invocation
- `skills/repo-health/scripts/compute-grade.sh`: Automated grade computation — counts
  ACTIONABLE-only findings (NITPICK excluded), applies all rubric bonuses including
  type checker (+1), zero 12-Factor FAIL (+2), all 12-Factor pass (+3), coverage,
  zero-critical, zero-high, and clean test run
- `skills/repo-health/scripts/synthesize-findings.sh`: Deduplicates, resolves
  severity conflicts, classifies, and grades findings in one pipeline (Step A4.5)
- `skills/repo-health/scripts/lib/installers.sh`: GNU grep/coreutils/date installer
  functions with Homebrew `ggrep`/`grealpath`/`gdate` detection and Linux `pcregrep`
  fallback

### Changed

- `skills/repo-health--helpers/SKILL.md`: Grading algorithm now excludes NITPICK
  findings from deductions; references `compute-grade.sh` as authoritative
- `skills/repo-health--phase-0-environment/SKILL.md`: GNU toolchain auto-install
  step; `grep -P` / `realpath -m` downgraded from core (blocking) to optional
  (non-blocking) — no more macOS Phase 0 abort
- `skills/repo-health--phase-2-code-quality/SKILL.md`: Added explicit `ruff check`
  and `mypy` scanning for Python projects; shellcheck fallback instructions
- `skills/repo-health/SKILL.md`: Replaced `text` code blocks with `bash` markers;
  added A4.5 automated synthesis pipeline; replaced pseudo-code with proper `task()`
  JSON format; dynamic phase applicability from Phase 1 discovery
- `skills/repo-health/scripts/run-scan-suite.sh`: Portable `date` via
  `python3 -c "import time..."` instead of GNU-only `date +%s.%N`
- `skills/repo-health/scripts/scan-environment-tools.sh`: macOS detection now
  checks for Homebrew-prefixed `ggrep`/`grealpath` with PATH hints
- `skills/repo-health/scripts/install-missing-tools.sh`: Added `gnu-grep`,
  `coreutils`, `gnu-date` to dispatch table and `ALL_TOOLS`; fixed `bin_name`
  resolution for GNU-prefixed binaries
- `AGENTS.md`: Expanded gitnexus block disclaimer to explain downstream risk of staleness
  when manually pasted (pre-existing)
- `CLAUDE.md`: Removed duplicated GitNexus block — instructions reference `AGENTS.md`
  instead (reducing staleness risk) (pre-existing)
- `README.md`: Updated script count from 21 to 24; added documentation for new
  automation scripts and cross-platform support

### Removed

- `skills/repo-health/scripts/classify-finding.sh`: Dead `$NN_FILTER` aggregate
  code that was built but never consumed (replaced by single combined regex pattern)

### Fixed

- Git branch `calm-beaver` now tracks `origin/main` (was previously tracking
  `origin/calm-beaver` which no longer exists on the remote) (pre-existing)
- `skills/repo-health/scripts/lib/installers.sh`: Linux `install_gnu_grep` fallback
  — replaced `apt-get install grep` (ineffective on BusyBox systems) with `pcregrep`
  detection + meaningful warning
- `skills/repo-health/scripts/classify-finding.sh`: Removed `eval(user_input)` from
  non-negotiable keywords (regex special characters crashed `jq test()`)
- `skills/repo-health/scripts/synthesize-findings.sh`: Fixed variable shadowing
  ($LE used for both LINT_ERRORS and LSP_ERRORS); fixed grade object path
  (`$grade.grade` → `$grade`); fixed `DUPLICATES_REMOVED` string vs integer

---

## v2.0.0 — 2024-10-01

### Added (v2)

- `skills/repo-health/` with full 11-script helper suite:
  - `detect-dead-code.sh`, `find-duplicates.sh`, `scan-cognitive-complexity.sh`
  - `audit-dependency-usage.sh`, `check-doc-links.sh`, `compare-specs.sh`
  - `parse-test-results.sh`, `find-uncovered.sh`, `scan-secrets.sh`
  - `scan-licenses.sh`, `run-scan-suite.sh`
- Structured grading rubric (A/B/C/D/F) with weighted scoring

### Changed (v2)

- Migrated `repo-health` skill from `.claude/skills/` to `skills/` top-level directory

---

## v1.0.0 — 2024 initial release

### Added (v1)

- `skills/sarcastic/` — tone/sarcasm skill for agent use
- `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `LICENSE`
- GitNexus code-intelligence integration
- Skill frontmatter schema documentation
- Local testing via symlink installation to `~/.config/opencode/skills/`
