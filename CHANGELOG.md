# Changelog

All notable changes to this skill-library repository are documented here.

Entries use [Keep a Changelog](https://keepachangelog.com/) conventions: Added, Changed, Deprecated, Removed, Fixed, Security.

## [Unreleased]

### Changed
- `AGENTS.md`: Expanded gitnexus block disclaimer to explain downstream risk of staleness when manually pasted
- `README.md`: Added **Features** section documenting each skill's capabilities and the repo-health phase breakdown
- `CLAUDE.md`: Removed duplicated GitNexus block — instructions reference `AGENTS.md` instead (reducing staleness risk)
- `CHANGELOG.md`: Cleaned up superseded `[2.0.0]` entry — version never finalized; content preserved with corrected header
- `AGENTS.md`: Synced GitNexus index stats (195→190 symbols, 190→185 relationships)

### Fixed
- Git branch `calm-beaver` now tracks `origin/main` (was previously tracking `origin/calm-beaver` which no longer exists on the remote)

---

## [2.0.0] — 2024-10-01 (unreleased — version superseded; content documents historical changes)

### Added
- `skills/repo-health/` with full 11-script helper suite:
  - `detect-dead-code.sh`, `find-duplicates.sh`, `scan-cognitive-complexity.sh`
  - `audit-dependency-usage.sh`, `check-doc-links.sh`, `compare-specs.sh`
  - `parse-test-results.sh`, `find-uncovered.sh`, `scan-secrets.sh`
  - `scan-licenses.sh`, `run-scan-suite.sh`
- Structured grading rubric (A/B/C/D/F) with weighted scoring

### Changed
- Migrated `repo-health` skill from `.claude/skills/` to `skills/` top-level directory

---

## [1.0.0] — 2024 initial release

### Added
- `skills/sarcastic/` — tone/sarcasm skill for agent use
- `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `LICENSE`
- GitNexus code-intelligence integration
- Skill frontmatter schema documentation
- Local testing via symlink installation to `~/.config/opencode/skills/`