# Changelog

All notable changes to this skill-library repository are documented here.

Entries use [Keep a Changelog](https://keepachangelog.com/) conventions: Added, Changed, Deprecated, Removed, Fixed, Security.

## [Unreleased]

### Added

- `install-skills.ps1`: Windows installer — PowerShell port of `install-skills.sh`
  with identical flags (`--symlink/--force/--dry-run/--list/--skip/--no-copilot/--dest`)
  and behavior: same destinations (`~/.config/opencode/skills`, `~/.copilot/skills`),
  same SKILL.md script-reference rewrite, same Copilot wrapper generation and
  legacy prompt cleanup. Windows specifics: junction fallback for symlinks
  (no Developer Mode/elevation needed), link-aware removal (junctions are
  unlinked, never recursed), `Remove-Item`/`Get-ChildItem` hints in place of
  `rm`/`ls`; runs on both Windows PowerShell 5.1+ and PowerShell 7+
- `tests/test-install-scripts.ps1`: mirror of the bash installer integration
  test for `install-skills.ps1`; `tests/run-tests.sh` runs it automatically when
  pwsh is available (skipped otherwise)

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

- `install-skills.sh`: installed skills could not find their supporting scripts in
  VS Code / Copilot (agent CWD is the user's project, so `./skills/<skill>/scripts/…`
  and bare `./install-missing-tools.sh` references failed with "No such file or
  directory"). At install time every script reference in the installed SKILL.md
  files is now rewritten to an absolute path under the install destination and all
  bundled scripts are made executable; generated Copilot wrapper skills get the
  same treatment. Idempotent; symlink (dev) installs keep repo-relative paths.
  New integration test `tests/test-install-scripts.sh` asserts scripts run from a
  foreign working directory
- `skills/repo-health/scripts/install-missing-tools.sh`: the gnu-grep/coreutils/
  gnu-date requests were reported as `Failed: 3` on Linux (and "missing" in
  `--check-only`/`--list`) although `grep -P`, `realpath -m` and GNU `date +%s.%N`
  were all available — the checks demanded the Homebrew-style binary names
  (`ggrep`/`grealpath`/`gdate`). A shared `verify_target` capability check now
  satisfies those targets via the underlying tools on Linux (and detects BSD
  `date` printing a literal `N` for `%N`); the exact Phase 0 command
  `install-missing-tools.sh gnu-grep coreutils gnu-date` reports
  `Skipped: 3, Failed: 0`
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
