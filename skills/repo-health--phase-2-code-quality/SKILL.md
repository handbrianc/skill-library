---
name: repo-health--phase-2-code-quality
description: "INTERNAL SUBSKILL of repo-health. Code quality analysis — dead code, complexity, duplication, architecture, dependency utilization, linting. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 2 — Code Quality Analysis

Uses GitNexus + static analysis scripts for deterministic results.

## Step 2.1 — Ensure Fresh GitNexus Index

```bash
npx gitnexus status
```

If stale: `npx gitnexus analyze --force`

## Step 2.2 — Dead/Unused Code

```bash
./skills/repo-health/scripts/detect-dead-code.sh src/
```

## Step 2.3 — Cyclomatic Complexity

```bash
./skills/repo-health/scripts/scan-complexity.sh
```

Flag: >15 MEDIUM, >25 HIGH, >40 CRITICAL.

## Step 2.4 — Cognitive Complexity

```bash
./skills/repo-health/scripts/scan-cognitive-complexity.sh src/
```

Manual spot-check via GitNexus:
```
query({search_query: "deeply nested callback hell", limit: 5})
query({search_query: "monstrous switch statement", limit: 5})
```

## Step 2.5 — Duplicated Code

```bash
./skills/repo-health/scripts/scan-complexity.sh
```

Report duplicates > 50 lines identical.

## Step 2.6 — Architecture Weakness

Use GitNexus clusters:

```bash
query({search_query: "arch component module service layer"})
READ gitnexus://repo/{name}/clusters
READ gitnexus://repo/{name}/processes
```

Flag clusters with LOW cohesion or no natural grouping.

## Step 2.7 — Dependency Utilization

```bash
./skills/repo-health/scripts/audit-dependency-usage.sh
```

Check: dead installs, mis-scoped devDependencies, optionalDependencies classification.

## Step 2.8 — Linting

### ⚠️ Lint BOTH source code AND test code (MANDATORY)

Linting violations in test files are equally important as violations in source files. The linter scan MUST cover both directories.

```bash
# Lint source code
./skills/repo-health/scripts/scan-linters.sh src/

# Lint test code — MANDATORY separate scan
./skills/repo-health/scripts/scan-linters.sh test/ tests/ spec/ __tests__/
```

If both `src/` and test directories exist, you MUST run both scans. Report findings from BOTH. Any lint violation in either source or test code is reportable.

### Linting Report Format

```
LINTING FINDING (Source):
  Tool: eslint
  Config: .eslintrc.js (found) / NO CONFIG (missing)
  Violations: N errors, N warnings
  Severity: LOW (<10) / MEDIUM (10-50) / HIGH (50-200) / CRITICAL (>200)
  Blocking: YES if >0 errors / NO if only warnings

LINTING FINDING (Tests):
  Tool: eslint
  Violations: N errors, N warnings
  Severity: (same mapping)
  Blocking: YES if >0 errors
```

### Linting Severity Mapping

| Linter | Violations | Finding Severity | Rubric Impact |
|--------|-----------|-----------------|---------------|
| eslint | 0 errors, 5 warnings | LOW | -1 point |
| ruff | 3 errors, 20 warnings | MEDIUM | -3 points |
| pylint | 12 errors, 100 warnings | HIGH | -10 points |
| phpcs | 50+ errors | CRITICAL | -25 points |

**Key rule:** Each linter tool generates at most **1 finding per scan target** (source vs test), not 1 per violation. The severity reflects overall code quality impact. Source and test are separate findings.

### Linter Findings to Flag

- **Linter available but no config** → MEDIUM
- **Linter configured but >0 errors** → HIGH
- **Linter configured and >50 total violations** → MEDIUM
- **Linter configured but no lint script in package.json** → LOW
- **No linter for primary language** → MEDIUM
- **Type checker available but not in CI** → MEDIUM
- **Lint violations in test code that differ from source code** → MEDIUM (inconsistent standards)

### Exit Condition for Linting

A finding is **NOT fixed** until:
- 0 errors in source code lint
- 0 errors in test code lint
- Total warnings < 10 across both (or as configured)

All lint violations (source + test) are tracked under the `LINT_ERRORS` metric in the Phase 10 exit condition.

### Scoring Bonuses

- Linter configured and clean (0 violations on source AND test) → +2 bonus
- Type checker configured and passing → +1 bonus
