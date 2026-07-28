---
name: repo-health--helpers
description: "INTERNAL SUBSKILL of repo-health. Grading rubric and script reference for the repo-health audit. Not for direct invocation."
subskill-of: repo-health
---

# repo-health Helpers

Internal reference data for the repo-health audit orchestrator. This subskill is callable only by the orchestrator.

## Scripts Directory

```text
skills/repo-health/scripts/
├── audit-dependency-usage.sh     # Import-graph dependency audit
├── check-doc-links.sh            # Link-rot checker for markdown docs
├── compare-specs.sh              # Archived vs current spec comparator
├── detect-dead-code.sh           # Static dead-code detector
├── find-duplicates.sh            # Text-similarity duplicate finder
├── find-uncovered.sh             # Uncovered line finder
├── fix-doc-links.sh              # (FIX) Check + report broken doc links
├── fix-env-example.sh            # (FIX) Generate/update .env.example
├── fix-gitnexus-stats.sh         # (FIX) Sync GitNexus stats across docs
├── fix-lint.sh                   # (FIX) Auto-fix lint violations
├── fix-rollback.sh               # (FIX) Snapshot rollback + regression detection
├── install-missing-tools.sh      # (INSTALL) OS-agnostic tool installer
├── parse-test-results.sh         # Test output parser
├── run-scan-suite.sh             # Master script — runs all deterministically
├── scan-12factor.sh              # Twelve-Factor App compliance checks
├── scan-cognitive-complexity.sh  # Cyclomatic+cognitive metric scanner
├── scan-complexity.sh            # Cyclomatic complexity + duplication analysis
├── scan-docs.sh                  # Documentation inventory and accuracy
├── scan-environment.sh           # Tool detection + transient file inventory
├── scan-licenses.sh              # SPDX license risk assessor
├── scan-linters.sh               # Multi-language linter detection and run
├── scan-sbom.sh                  # SBOM generation and license compliance
├── scan-security.sh              # Vulnerability scan, SAST, secrets, credentials
├── scan-secrets.sh               # Secret/credential scanner
├── scan-setup.sh                 # Project discovery and spec inventory
├── scan-tech-debt.sh             # Technical debt profile analysis
└── scan-tests.sh                 # Test suite health checks

lib/
├── common.sh                     # Shared library (sourced by all scan scripts)
└── fix-common.sh                 # Shared library (sourced by all fix scripts)
```text

Scan scripts accept `$1` as target directory. Exceptions: `scan-licenses.sh` (SBOM file path), `parse-test-results.sh` (test output file), `find-uncovered.sh` (coverage report path).

Fix scripts accept `--dry-run` for safe preview. `fix-rollback.sh` accepts `--list`, `--restore`, `--check`, `--clean` subcommands.

## Determinism Guarantee

1. Always operate on committed HEAD
2. Pin all tool versions in `package.json`'s `engines` or `.nvmrc`/`.python-version`
3. Capture environment with version commands
4. Log scanner stderr separately
5. Reproducibility: running twice against same commit → identical findings

If a finding cannot be deterministically reproduced, mark it `[NON-DETERMINISTIC — CONFIRM MANUALLY]`.

## Grading Rubric

### ⚠️ NITPICK-Aware Scoring (MANDATORY)

The grade is computed against **ACTIONABLE findings only**. NITPICK-classified findings MUST
be excluded from deductions. This prevents the grade from being misleading — a project
with only cosmetic NITPICK findings scores 100/100 (A), not 89/100 (B) or worse.

### Scoring Deductions (ACTIONABLE findings only)

| Finding Type | Points Deducted |
| --- | --- |
| CRITICAL (ACTIONABLE) | -25 |
| HIGH (ACTIONABLE) | -10 |
| MEDIUM (ACTIONABLE) | -3 |
| LOW (ACTIONABLE) | -1 |

**NITPICK findings (regardless of original severity) are NOT deducted.** See the
NITPICK test below for classification rules.

### Bonuses

| Condition | Points Added |
| --- | --- |
| Clean test run (0 failed/errors) | +5 |
| Line coverage >= 80% | +3 |
| Line coverage >= 90% | +3 (additional, stacks with >=80%) |
| Zero CRITICAL findings (ACTIONABLE only) | +2 |
| Zero HIGH findings (ACTIONABLE only) | +2 |
| Linter configured and clean (0 violations on source AND test code) | +2 |
| Type checker (tsc/mypy) configured and passing | +1 |
| Zero 12-Factor FAIL findings (actionable) | +2 |
| All 12-Factor factors PASS or N/A with rationale | +3 |

### Grade Computation

```text
1. COUNT actionable findings by severity:
     C = count of CRITICAL findings classified ACTIONABLE
     H = count of HIGH findings classified ACTIONABLE
     M = count of MEDIUM findings classified ACTIONABLE
     L = count of LOW findings classified ACTIONABLE

2. COMPUTE deductions:
     POINTS = 100
     POINTS -= (C × 25) + (H × 10) + (M × 3) + (L × 1)

3. ADD bonuses (each applies at most once):
     POINTS += BONUSES as applicable

4. CLAMP to valid range:
     POINTS = max(POINTS, 0)
     POINTS = min(POINTS, 100)

5. MAP to letter grade:
     GRADE = POINTS >= 90 ? "A"
           : POINTS >= 70 ? "B"
           : POINTS >= 50 ? "C"
           : POINTS >= 25 ? "D"
           : "F"

6. OUTPUT:
     **Overall Grade:** {GRADE} ({POINTS}/100)
     **Actionable:** C CRITICAL, H HIGH, M MEDIUM, L LOW
     **NITPICK:** N findings excluded from grade
```

### Automated Script

A deterministic compute script is available:

```bash
./skills/repo-health/scripts/compute-grade.sh --findings findings.json
```

This is the **authoritative** grade computation. Subagents MUST NOT compute grades
manually — always use the script.

## Finding Classification Rubric

Used by the Remediation Loop (Phase 10) to decide which findings must be auto-fixed vs skipped.

### Severity → Classification Mapping

| Severity | Default Classification | Reasoning |
|----------|----------------------|-----------|
| CRITICAL | **ACTIONABLE** | Security or release-blocking — must never skip |
| HIGH | **ACTIONABLE** | Significant impact — must fix |
| MEDIUM | **ACTIONABLE** | Moderate impact — should fix |
| LOW | **Conditional** | Apply the NITPICK test below |

### NITPICK Test (applied to LOW severity findings only)

A LOW finding is a **NITPICK** if ANY of these conditions are true:

| Condition | Question | Indicates |
|-----------|----------|-----------|
| **Cosmetic** | Is the finding purely cosmetic (formatting, minor doc wording, optional enhancement, naming preference)? | Nitpick |
| **Negligible** | Does it have negligible impact on correctness, security, or maintainability? | Nitpick |
| **Quick-manual** | Would fixing it require manual judgment (non-automatable) rather than a scripted change? | Nitpick |

If ALL three are false → classify as **ACTIONABLE** (even though LOW severity).

### Remediation Priority Matrix

| Classification | Priority | Action | Scope |
|---------------|----------|--------|-------|
| ACTIONABLE (CRITICAL) | P0 | Auto-fix silently (no user prompt) | Single file, targeted |
| ACTIONABLE (HIGH) | P1 | Auto-fix silently (no user prompt) | 1-3 files |
| ACTIONABLE (MEDIUM) | P2 | Auto-fix silently (no user prompt) | 1-5 files |
| ACTIONABLE (LOW) | P3 | Auto-fix silently (no user prompt) | Single file |
| NITPICK | P4 | Report only — do not modify code | None |

### Exit Condition

The iterative loop exits when ALL findings in the action plan are classified as **NITPICK**:

```text
CRITICAL=0 AND HIGH=0 AND MEDIUM=0 AND FAILED_TESTS=0 AND LINT_ERRORS=0 AND LSP_ERRORS=0 AND ACTIONABLE(LOW)=0
```

|Metric|Requirement|Source|
|------|-----------|------|
|CRITICAL|= 0|All phases|
|HIGH|= 0|All phases|
|MEDIUM|= 0|All phases|
|FAILED_TESTS|= 0|Test suite run (FAILED + ERRORS)|
|LINT_ERRORS|= 0|Linters on src/ + test/ dirs|
|LSP_ERRORS|= 0|`lsp_diagnostics` on changed files|
|ACTIONABLE(LOW)|= 0|NITPICK-classified LOW findings remain OK|
