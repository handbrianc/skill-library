---
name: repo-health--phase-6-tests
description: "INTERNAL SUBSKILL of repo-health. Test suite health — presence, pass/fail, coverage, slow tests. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 6 — Test Suite Health

## Step 6.1 — Presence Check

```bash
./skills/repo-health/scripts/scan-tests.sh --check-presence
```

If no test files or no test scripts: **CRITICAL**.

## Step 6.2 — Test Run with Coverage

```bash
./skills/repo-health/scripts/scan-tests.sh --run-coverage
```

Produces:
```
PASSED: NNN
FAILED: NN   ← list each failure
ERRORS: NN   ← list each error
SKIPPED: NN  ← list each skip with reason
RETRIED: NN  ← flaky test indicators
TIMED_OUT: NN
```

**Clean run:** EXIT_CODE=0, FAILED=0, ERRORS=0, RETRIED=0. Skips OK if documented.

## Step 6.3 — Parse Results

```bash
./skills/repo-health/scripts/scan-tests.sh --parse-results
```

## Step 6.4 — Slow Tests

```bash
./skills/repo-health/scripts/scan-tests.sh --slow-tests
```

## Step 6.5 — Coverage Analysis

```bash
./skills/repo-health/scripts/scan-tests.sh --coverage-report
```

### Coverage Thresholds

| Coverage | Action Required |
| --------- | --------------------------------------------------------- |
| < 50% | Add tests covering core functionality — prioritize modules |
| 50-80% | Bring coverage above 80%; identify untested hot paths |
| >= 80% | Acceptable; investigate uncovered branches specifically |

### Gap Analysis

```bash
./skills/repo-health/scripts/find-uncovered.sh /tmp/coverage/
```
