---
name: repo-health--phase-10-remediate
description: "INTERNAL SUBSKILL of repo-health. Self-contained remediation subagent. Receives synthesized findings, runs fix scripts, re-audits, and loops until only NITPICKs remain. Produces a fixed codebase, NOT an advisory plan. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 10 — Remediation Loop Subagent Mission

**You are a remediation subagent.** Your ONLY job: fix the findings, re-audit, and loop
until the exit condition is met. You do NOT produce advisory plans. You do NOT ask for
permission. You do NOT stop early.

```text
RECEIVE FINDINGS ──► 10.2 CLASSIFY ──► 10.3 FIX ──► 10.4 RE-AUDIT ──► LOOP UNTIL NITPICK ──► 10.5 REPORT
```text

---

## ⚠️ ABSOLUTE REQUIREMENTS

### You WILL be terminated if you

- Produce an advisory/recommendation-style document instead of executing fixes
- Stop at any point before the exit condition is met (CRITICAL=0, HIGH=0, MEDIUM=0, FAILED_TESTS=0, LINT_ERRORS=0, LSP_ERRORS=0, ACTIONABLE(LOW)=0)
- Ask the user "should I fix these?" — just fix them
- Present findings in a "here's what I found" format without also fixing them

### You MUST do

- Run fix scripts. Verify they worked. Re-audit. Loop.
- If a fix introduces regressions, use `fix-rollback.sh --restore` and skip it
- Leave all changes uncommitted for user review
- Snapshot files before modifying (`source lib/fix-common.sh; fix_snapshot file...`)
- **Run `git status` before starting AND after completing** — verify no unintended file changes (deleted files, detached HEAD, untracked files appearing unexpectedly)
- **Run `lsp_diagnostics` on every changed file** — fix ALL errors and warnings
- **Run linters on BOTH source and test code** — fix ALL violations
- **Run the test suite after every fix round** — fix ALL failures

---

## 10.1 — Input: Synthesized Findings

You receive findings from the orchestrator as a structured list. Each finding has:

- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Description**: What the finding is
- **Evidence**: file:line or scanner output
- **Fix Script**: Which fix script to run (or "Manual" if human judgment required)

In addition to individual findings, the orchestrator also provides aggregate metrics that MUST be tracked as part of the exit condition:

- `FAILED_TESTS`: count of failing/erroring tests (MUST be 0)
- `LINT_ERRORS`: count of lint violations (errors only) across source AND test code (MUST be 0)
- `LSP_ERRORS`: count of LSP diagnostics (errors + warnings) on changed files (MUST be 0)

---

## 10.2 — Classify Findings

Apply the NITPICK rubric from `repo-health--helpers`:

| Severity | Classification | Action |
| ---------- | --------------- | -------- |
| CRITICAL | **ACTIONABLE** | Fix immediately |
| HIGH | **ACTIONABLE** | Fix immediately |
| MEDIUM | **ACTIONABLE** | Fix immediately |
| LOW | **Conditional** | Apply NITPICK test below |

### ⚠️ Non-Negotiable CRITICAL Findings (MANDATORY)

The following finding types are **ALWAYS CRITICAL and ALWAYS ACTIONABLE**. Do NOT downgrade them. Do NOT skip them. They MUST be addressed:

| Source | Finding Type | Rationale |
| -------- | ------------- | ----------- |
| Phase 7 — Security | Any package with a known CVE | Exploitable attack surface |
| Phase 7 — Security | Insecure code patterns (SQL injection, XSS, command injection, hardcoded secrets, path traversal, XXE, CSRF, JWT none algo, deserialization) | Direct exploitation vector |
| Phase 7 — Security | Committed secrets/credentials | Immediate exposure risk |
| Phase 8 — SBOM | Dependency with known CVE (any severity) | Supply-chain vulnerability |
| Phase 8 — SBOM | Dependency outdated by major version | Accumulated unpatched CVEs |
| Phase 3 — Tech Debt | Runtime/dependency outdated by major version | Missing security patches |

These findings are INELIGIBLE for the NITPICK test. They are always actionable. They MUST flow through the fix loop in 10.3.

### NITPICK Test (LOW findings only)

A LOW finding is **NITPICK** if ANY is true:

- **Cosmetic?** Purely cosmetic (formatting, minor doc wording)
- **Negligible?** Negligible impact on correctness/security/maintainability
- **Quick-manual?** Fixing requires manual judgment, not a scripted change

If ALL three are false → classify as **ACTIONABLE**.

If ALL remaining findings are NITPICK → **exit condition met**. Skip to 10.5.

---

## 10.3 — Apply Fixes (MANDATORY)

For each **ACTIONABLE** finding, in severity order (CRITICAL → HIGH → MEDIUM → ACTIONABLE LOW):

### Finding → Fix Script Mapping

| Finding Pattern | Fix Script | Verification |
| ---------------- | ------------ | ------------- |
| Stale GitNexus stats | `fix-gitnexus-stats.sh` | grep for mismatched stats |
| Broken doc links | `fix-doc-links.sh --external` | check-doc-links exits 0 |
| Missing .env.example | `fix-env-example.sh` | .env.example exists |
| Lint violations — source code | `fix-lint.sh` `src/` | `lsp_diagnostics` 0 errors, scan-linters 0 errors |
| Lint violations — test code | `fix-lint.sh` `test/ tests/ spec/` | `lsp_diagnostics` 0 errors, scan-linters 0 errors on test dirs |
| Shellcheck warnings | `fix-lint.sh` | `shellcheck -f gcc file.sh | grep -c warning` = 0 |
| LSP diagnostics (errors or warnings) | Manual fix (edit source) | `lsp_diagnostics` returns 0 errors AND 0 warnings on changed files |
| Failing tests | Manual fix (edit source/test) | `npm test` / `pytest` exit 0, FAILED=0, ERRORS=0 |
| Any fix needs safety net | `fix-rollback.sh --check` | No new CRITICAL/HIGH findings, no new test failures |

### Fix Procedure — MANDATORY Verification Chain

For EACH fix applied, you MUST run the full verification chain. A fix is NOT complete until all 5 steps pass.

1. **Snapshot**: `source skills/repo-health/scripts/lib/fix-common.sh; fix_snapshot file1 file2...`
2. **Run**: `./skills/repo-health/scripts/fix-{type}.sh`
3. **LSP Verification (MANDATORY)**: Run `lsp_diagnostics` on every changed file.
   - **0 errors AND 0 warnings** required. Any diagnostic = NOT fixed.
   - Fix all LSP callouts until clean. Do not proceed until LSP is clean.
4. **Lint Verification (MANDATORY)**: Run linters on BOTH source and test code.
   - Source: `./skills/repo-health/scripts/scan-linters.sh src/` → 0 errors
   - Tests: `./skills/repo-health/scripts/scan-linters.sh test/ tests/ spec/ __tests__/` → 0 errors
   - Any lint violation = NOT fixed.
5. **Test Suite Verification (MANDATORY)**: Run the project's test command.
   - `npm test` / `pytest` / `go test ./...` / etc. → exit 0, FAILED=0, ERRORS=0
   - Any failure = NOT fixed. Fix tests before proceeding.
6. **Regression guard**: `./skills/repo-health/scripts/fix-rollback.sh --check`
7. **Rollback if regression**: `./skills/repo-health/scripts/fix-rollback.sh --restore file`

If ANY step in the chain fails: fix the issue, then re-run from step 3 (LSP). Do NOT skip steps.

### Parallelization Guidance

When applying multiple fixes, group INDEPENDENT fixes and apply them simultaneously:

| Independent Group | Files | Can Run Together? |
|------------------|-------|-------------------|
| Markdownlint fixes on doc A | `AGENTS.md` | YES — no shared dependencies |
| Shellcheck fixes on script B | `install-missing-tools.sh` | YES — no shared dependencies |
| Temp file fixes on script C | `scan-sbom.sh` | YES — no shared dependencies |

**Independent means:** different files, no shared state, no ordering requirement. Apply
these in a single batch pass rather than one-at-a-time.

**DO NOT parallelize if:** fixes touch the same file, or one fix's output is input to
another (e.g., extracting a shared preamble THEN updating callers).

### Safety Rules

- Never commit anything
- **Never run any git command** (add, rm, mv, reset, checkout, stash, rebase, merge, branch)
- **Never modify .gitignore**
- **If `git status` shows unexpected changes** (deleted files, detached HEAD) — STOP and report immediately
- Never delete failing tests to make verification pass
- Never use `as any`, `@ts-ignore`, `@ts-expect-error`
- Never suppress LSP diagnostics with ignore comments
- Mark regressions as `REGRESSION — SKIPPED` and continue

---

## 10.4 — Re-Audit & Loop (MANDATORY)

After ALL actionable findings in the current round are processed:

1. **Re-index**: `npx gitnexus analyze --force --skip-agents-md`
2. **Run test suite**: Confirm `FAILED=0`, `ERRORS=0`, exit code 0
3. **Run linters on BOTH source and test code**: Confirm `LINT_ERRORS=0`
4. **Run `lsp_diagnostics` on all changed files**: Confirm `LSP_ERRORS=0` (0 errors AND 0 warnings)
5. **Re-run relevant scanners** from phases 1-9
6. **Re-classify**: Run step 10.2 again
7. **Check exit condition**: `CRITICAL=0 AND HIGH=0 AND MEDIUM=0 AND FAILED_TESTS=0 AND LINT_ERRORS=0 AND LSP_ERRORS=0 AND ACTIONABLE(LOW)=0?`
   - YES → proceed to 10.5
   - NO → go to 10.3 for next round
   - Iteration >= 5 → output partial, flag INCOMPLETE, stop

### Exit Condition Detail

| Metric | Requirement | Source |
| -------- | ------------ | -------- |
| CRITICAL | = 0 | All phases |
| HIGH | = 0 | All phases |
| MEDIUM | = 0 | All phases |
| FAILED_TESTS | = 0 | Test suite run (FAILED + ERRORS) |
| LINT_ERRORS | = 0 | Linters on src/ + test/ dirs |
| LSP_ERRORS | = 0 | `lsp_diagnostics` on changed files |
| ACTIONABLE(LOW) | = 0 | NITPICK-classified LOW findings remain OK |

---

## 10.5 — Final Report (only when exit condition met)

```text
## Remediation Complete

**Overall Grade:** A (100/100)
**Rounds:** N
**Items Fixed:** N (X CRITICAL, Y HIGH, Z MEDIUM, W ACTIONABLE LOW)
**Exit Condition Met:**
  - CRITICAL=0 ✅   HIGH=0 ✅   MEDIUM=0 ✅
  - FAILED_TESTS=0 ✅   LINT_ERRORS=0 ✅   LSP_ERRORS=0 ✅
  - ACTIONABLE(LOW)=0 ✅
**Remaining (NITPICK):** N
**Regressions Skipped:** N
**Files Modified:** file1, file2, ...
```text

### Remaining NITPICK Findings

| ID | Description | Rationale |
|----|------------|-----------|
| L1. | ... | cosmetic |

### Regressions Skipped

| ID | Finding | Fix Attempted | Rollback Reason |
|----|---------|--------------|-----------------|

### Modified Files

```text
M file1
M file2
```text
