# Skill Library — Architecture

This document describes the structural and operational architecture of the
skill-library repository. It is intended for maintainers and contributors who
need to understand the orchestration, delegation, and script dependency
patterns used across the project.

---

## Overview

The skill-library is a **distribution template** for OpenCode skills. It
packages reusable instruction files for AI agent use. The repository contains
no application code, no build system, and no test runner — skills are plain
Markdown files consumed by the OpenCode agent runtime.

```
skills/
├── note-taker/           # Independent skill
├── sarcastic/            # Independent skill
├── spec-compliance/      # Independent skill (scripts/ + SKILL.md)
└── repo-health/          # Orchestrator skill + 10 subskills + 21 scripts
    ├── SKILL.md
    ├── repo-health--helpers/
    ├── repo-health--phase-{0..10}/
    └── scripts/
        ├── lib/
        │   └── common.sh         # Shared library (sourced by all scripts)
        ├── scan-*.sh              # Phase scanners
        ├── detect-*.sh            # Detection helpers
        ├── find-*.sh              # Search helpers
        ├── check-*.sh             # Validation helpers
        ├── audit-*.sh             # Audit helpers
        ├── compare-*.sh           # Comparison helpers
        ├── parse-*.sh             # Parsing helpers
        └── run-scan-suite.sh      # Master runner
```

---

## Orchestrator–Subskill Pattern

The `repo-health` skill is an **orchestrator**: its `SKILL.md` (225 lines)
delegates specific audit phases to subskills rather than containing all
instructions inline.

### Delegation Flow

```
User: "audit this project"
  → OpenCode loads skill(name="repo-health")
    → SKILL.md instructs: run PHASE 0 first (gate)
      → Load phase-0 subskill → execute env checks
      → For each selected phase N:
        → Load repo-health--phase-N-{name} subskill
        → Execute scanner scripts defined in subskill
      → After all phases: load phase-10 → synthesize action plan
```

### Benefits

| Concern | Orchestrator Design |
|---------|---------------------|
| Monolith size | 853 → 64 (orchestrator) + ~720 (subskills) |
| Partial invocation | Each phase loads independently |
| Discoverability | `skill --list` shows 11 subskills |
| Maintainability | Edit one phase without touching others |

---

## Helper Script Architecture

21 Bash helper scripts live under `skills/repo-health/scripts/`. They are
invoked by subskill instructions (via `bash ./scripts/scan-X.sh`) and share a
common library.

### Shared Library: `lib/common.sh`

| Symbol | Purpose |
|--------|---------|
| `SCRIPT_DIR` | Directory of the sourcing script |
| `REPO_ROOT` | Repository root (3 levels up from `lib/`) |
| `TIMEOUT_CMD` | `gtimeout` (macOS) or `timeout` (Linux) |
| `has_cmd()` | Check if a command exists |
| `has_files()` | Check if a glob pattern matches files |

### Script Categories

| Category | Examples | Purpose |
|----------|----------|---------|
| **Environment** | `scan-environment.sh`, `scan-environment-tools.sh`, `scan-environment-transient.sh` | PHASE 0 — tool/transient checks |
| **Discovery** | `scan-setup.sh` | PHASE 1 — project discovery |
| **Code Quality** | `scan-linters.sh`, `scan-complexity.sh`, `scan-cognitive-complexity.sh`, `detect-dead-code.sh`, `find-duplicates.sh`, `audit-dependency-usage.sh` | PHASE 2 — dead code, duplication, complexity |
| **Tech Debt** | `scan-tech-debt.sh`, `scan-tech-debt-step-{1..7}.sh` | PHASE 3 — markers, architecture, currency |
| **Documentation** | `scan-docs.sh`, `check-doc-links.sh` | PHASE 4 — inventory, accuracy |
| **Specs** | `compare-specs.sh` | PHASE 5 — archived vs current |
| **Tests** | `scan-tests.sh`, `scan-tests-{presence,coverage,parse,slow,report}.sh`, `find-uncovered.sh`, `parse-test-results.sh` | PHASE 6 — test health |
| **Security** | `scan-security.sh`, `scan-secrets.sh` | PHASE 7 — vulnerabilities, credentials |
| **SBOM** | `scan-sbom.sh`, `scan-licenses.sh` | PHASE 8 — supply chain |
| **12-Factor** | `scan-12factor.sh`, `scan-12factor-{factor-1..12,report}.sh` | PHASE 9 — 12-factor compliance |
| **Master** | `run-scan-suite.sh` | Runs all deterministically |

### Cross-Script Dependencies

```
scan-tests.sh
  └─ sources: scan-tests-presence.sh
  └─ sources: scan-tests-coverage.sh
  └─ sources: scan-tests-parse.sh
  └─ sources: scan-tests-slow.sh
  └─ sources: scan-tests-report.sh

scan-tech-debt.sh
  └─ sources: scan-tech-debt-step-{1..7}.sh

scan-12factor.sh
  └─ sources: scan-12factor-factor-{1..12}.sh
  └─ sources: scan-12factor-report.sh

scan-environment.sh
  └─ sources: scan-environment-tools.sh
  └─ sources: scan-environment-transient.sh

scan-linters.sh
  └─ sources: scan-linters-detect.sh
  └─ sources: scan-linters-run.sh

All scripts source: lib/common.sh
```

---

## GitNexus Integration

The repository is indexed by GitNexus as `skill-library` (303 symbols, 298
relationships, 0 execution flows). The `AGENTS.md` file documents GitNexus
usage for impact analysis before editing any symbol.

Workflow:
1. `npx gitnexus analyze --force` (refresh index)
2. `npx gitnexus status` (check freshness)
3. `gitnexus_impact({target: "symbolName", direction: "upstream"})` (pre-edit)
4. `gitnexus_detect_changes()` (pre-commit)

---

## Git Workflow

- Main branch: `main`
- Feature branches named `<adjective>-<animal>` (e.g., `calm-beaver`, `groovy-falcon`)
- 226 commits, 9 branches
- Pre-commit hook at `githooks/pre-commit`
- Skill installation script at `install-skills.sh`

---

## Standalone Skills (non-orchestrated)

Three skills do not participate in the orchestrator pattern:

| Skill | Contents | Dependency |
|-------|----------|------------|
| `note-taker` | Single SKILL.md (82 lines) | None |
| `sarcastic` | Single SKILL.md (53 lines) | None |
| `spec-compliance` | SKILL.md (485 lines) + `scripts/` (extract-requirements.sh, compare-specs.sh) | None external |
