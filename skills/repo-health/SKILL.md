---
name: repo-health
description: "Repository health audit with two modes. mode=report (DEFAULT): runs the audit pipeline (Phases 0-9), synthesizes, classifies, grades, and presents a findings report — no code changes. mode=fix (opt-in): after the audit, Phase 10 additionally runs a silent remediation loop that fixes findings, re-audits, and iterates until only NITPICKs remain — no user prompts, no confirmation gates. Resolve mode from the user's request: 'review this repo', 'audit this project', 'health check', 'quality gate' → mode=report; 'fix findings', 'remediate issues', 'auto-fix everything', or an explicit mode=fix → mode=fix. NOT for PR-scoped or incremental reviews."
---

# Repository Health Audit

A rigorous, deterministic repository audit covering nine dimensions. The audit detects
issues, classifies them, and computes a grade. Behavior then depends on the **mode**:

- **mode=report (default)** — present the graded findings report and stop. No files are modified.
- **mode=fix (opt-in)** — additionally run the Phase 10 remediation loop: fix, re-audit,
  and iterate until only trivial nitpicks remain.

> **Prerequisite:** None. Phase 0 gates the audit on required tools.

---

## Mode Selection — Resolve BEFORE Phase 10

The skill takes one parameter, `mode`. Resolve it from the user's request before running
the audit, and state the resolved mode in one line at the start of the run.

| mode | Behavior | Triggered when the user says |
| -------- | ----------- | ------------------------------ |
| `report` **(DEFAULT)** | Audit + graded findings report. Stop. No code changes. | "review this repo", "audit this project", "health check", "quality gate", "analyze this codebase", or any audit request without remediation intent |
| `fix` | Audit + report + Phase 10 remediation loop (fix → re-audit → iterate until only NITPICKs remain). No confirmation gates. | "fix findings", "remediate issues", "auto-fix everything", "fix everything you find", or an explicit `mode=fix` |

Rules:

- **Default to `report` when the request is ambiguous.** Never silently escalate to `fix`.
- **Never downgrade to `report` when the user clearly asked for fixes.**
- After a `report`-mode run, the user can trigger remediation in a follow-up ("now fix
  these findings") — reuse the synthesized findings file instead of re-running the audit.

```
AUDIT (Phases 0-9) ──► SYNTHESIZE ──► CLASSIFY ──► GRADE ──► REPORT ──► done (mode=report)
                                                                │
                                                mode=fix only   ▼
                                                10.3 FIX ──► 10.4 RE-AUDIT ──► LOOP UNTIL NITPICK ──► 10.5 REPORT
```

---

## Critical Constraints

### MUST DO (both modes)

- **Run PHASE 0 before all other phases** — abort if any required tool is missing
- **Resolve `mode` before Phase 10** and state it in one line at the start of the run
- Run actual scanners/tool commands — do not speculate about outcomes
- Operate on committed HEAD (preserve original commit, never mixed working tree + staging)
- **Outdated libraries, packages with known CVEs, and insecure code patterns are CRITICAL severity** — never downgrade them to MEDIUM or HIGH; in mode=fix they MUST be addressed in the remediation loop

### MUST DO (mode=fix only)

- **Phase 10 is the remediation pipeline (classify → fix → re-audit → loop)** — do NOT stop after synthesis. Classification, fix execution, re-audit, and loop are all mandatory parts of Phase 10.
- **Re-audit after each remediation round** within Phase 10 — loop until exit condition met (CRITICAL=0 AND HIGH=0 AND MEDIUM=0 AND FAILED_TESTS=0 AND LINT_ERRORS=0 AND LSP_ERRORS=0 AND ACTIONABLE(LOW)=0)
- If a fix introduces a regression (new CRITICAL/HIGH finding), **revert via fix-rollback.sh** and skip that fix

### MUST NOT DO (both modes)

- Never suppress type errors with `as any`, `@ts-ignore`, or `@ts-expect-error`
- Never delete failing tests to make a build pass
- Never treat an N/A dimension as a failure — document rationale

### MUST NOT DO (mode=report)

- Never modify, create, or delete any file — the audit is read-only
- Never run fix scripts with write access (no `fix-*.sh` outside `--dry-run` / `--check`)

### MUST NOT DO (mode=fix)

- Never present an advisory action plan without executing the remediation steps in Phase 10.3-10.4
- Never stop after Phase 10.1 (Synthesize) — that is only the first of five sub-steps
- Never ask "do you want me to fix these?" — the user already opted in via mode=fix
- Never commit changes (leave uncommitted for user review)
- Never edit any symbol without understanding its callers first

---

## Phase Reference

| # | Dimension | Subskill |
| --- | ----------- | ---------- |
| 0 | Environment Readiness (Gate) | `repo-health--phase-0-environment` |
| 1 | Project Discovery | `repo-health--phase-1-discovery` |
| 2 | Code Quality | `repo-health--phase-2-code-quality` |
| 3 | Technical Debt | `repo-health--phase-3-tech-debt` |
| 4 | Documentation | `repo-health--phase-4-docs` |
| 5 | OpenSpec Specifications | `repo-health--phase-5-specs` |
| 6 | Test Suite Health | `repo-health--phase-6-tests` |
| 7 | Security Review | `repo-health--phase-7-security` |
| 8 | SBOM & License Audit | `repo-health--phase-8-sbom` |
| 9 | 12-Factor App Compliance | `repo-health--phase-9-12factor` |
| 10 | Remediation Loop (**mode=fix only** — delegated to subagent; fixes, re-audits, loops) | `repo-health--phase-10-remediate` |

---

## Fix Scripts Reference

Fix scripts run only in mode=fix (or manually by the user after a report-mode run). Six
fix scripts live under `skills/repo-health/scripts/`:

| Script | Purpose | Finding Types |
| -------- | --------- | --------------- |
| `fix-doc-links.sh` | Check + report broken external/internal links in docs | Broken links |
| `fix-env-example.sh` | Generate/update .env.example from code-scanned env vars | Missing .env.example |
| `fix-lint.sh` | Run linters with --fix (ESLint, Ruff, gofmt, etc.) | Lint violations |
| `fix-rollback.sh` | Snapshot rollback + regression detection | Safety net |
| `lib/fix-common.sh` | Shared library (sourced by all fix scripts) | — |

---

## Phase A — Audit: Phases 0-10

### Step A1 — Prerequisite & Helpers

1. Load the helpers subskill: `skill(name="repo-health--helpers")`
3. Load PHASE 1 subskill: `skill(name="repo-health--phase-1-discovery")`
   (Do NOT load all phase subskills — only Phase 1 runs first. The composite
   subagent loads the phase subskills it needs internally.)

### Step A2 — Phase 0 (Gate + Auto-Install)

```bash
# Step 0.0 — Ensure GNU toolchain on macOS (auto-install if needed)
./skills/repo-health/scripts/install-missing-tools.sh gnu-grep coreutils gnu-date 2>&1 | tail -5
```

On macOS, the GNU toolchain (grep -P, realpath -m) is auto-installed via Homebrew when
missing. The installer detects Homebrew-prefixed `ggrep`/`grealpath` and reports the
exact PATH to add. If install fails, proceed anyway — scanners use fallback patterns.

```bash
# Step 0.1 — Check what's present
./skills/repo-health/scripts/scan-environment.sh --check-tools
```

**If any core utility is MISSING/BROKEN** (bash, node, npm, npx, git, jq, find) →
**ABORT. Do not proceed.** The audit cannot run without them.
*(grep -P and realpath -m are NOT core utilities — see note above.)*

**If only optional tools are missing** (test runners, linters, security scanners, etc.):

```bash
# Step 0.2 — Auto-install everything that's missing
./skills/repo-health/scripts/install-missing-tools.sh

# Or install by category matching the project's stack
./skills/repo-health/scripts/install-missing-tools.sh --filter=test
./skills/repo-health/scripts/install-missing-tools.sh --filter=security
./skills/repo-health/scripts/install-missing-tools.sh --filter=linter

# Step 0.3 — Re-verify after install
./skills/repo-health/scripts/scan-environment.sh --check-tools
```

If any optional tool still cannot be installed, proceed to Phase 1 anyway — the
corresponding scanner section will produce reduced output with adjusted findings.

### Step A2.5 — Pre-Flight Tooling Validation (NEW)

Before launching any audit phases, validate that the tools each phase depends on are
actually available. This prevents subagents from failing silently or wasting time
debugging missing tooling.

```bash
# Check all phase-critical tools
echo "=== PRE-FLIGHT TOOL VALIDATION ==="

# Phase 2 (Code Quality) — linters
command -v shellcheck >/dev/null 2>&1 && echo "TOOL_OK: shellcheck" || echo "TOOL_MISSING: shellcheck — Phase 2 linting will be manual"
command -v markdownlint >/dev/null 2>&1 && echo "TOOL_OK: markdownlint" || echo "TOOL_MISSING: markdownlint — Phase 2 MD linting reduced"

# Phase 6 (Tests)
command -v bats >/dev/null 2>&1 && echo "TOOL_OK: bats" || echo "TOOL_MISSING: bats — Phase 6 test running reduced"

# Phase 7 (Security)
command -v semgrep >/dev/null 2>&1 && echo "TOOL_OK: semgrep" || echo "TOOL_MISSING: semgrep — Phase 7 SAST skipped; use grep for pattern scan"
command -v grype >/dev/null 2>&1 && echo "TOOL_OK: grype" || echo "TOOL_MISSING: grype — Phase 7 CVE scan reduced"

# Phase 8 (SBOM)
command -v syft >/dev/null 2>&1 && echo "TOOL_OK: syft" || echo "TOOL_MISSING: syft — Phase 8 SBOM skipped; fall back to manual dependency inventory"

echo "=== PRE-FLIGHT COMPLETE ==="
```

**Known failure modes and fallbacks:**

| Phase | Missing Tool | Fallback |
|-------|-------------|----------|
| Phase 2 | `shellcheck` | Manual grep for shell anti-patterns (eval, unsafe temp files) |
| Phase 2 | `markdownlint` | Manual review of MD013/line-length only |
| Phase 6 | `bats` | Run test scripts directly via `bash tests/run-tests.sh` |
| Phase 7 | `semgrep` | Use `grep -P` for security patterns directly (command injection, hardcoded secrets) |
| Phase 8 | `syft` | Manual dependency inventory via `find + ls` package manifests |

Pass the validation results to the composite subagent so it can skip or adapt phases
that lack tooling.

### Step A3 — Phase 1: Discovery (Serial-First — NEW ORDERING)

**Run Phase 1 FIRST, before the composite audit subagent.** This determines which phases
are applicable, saving ~25 minutes on repos where multiple phases are N/A (e.g.,
skill-library repos where Phases 5, 8, 9 are N/A).

```bash
# Step 3.1 — Run Phase 1 discovery
./skills/repo-health/scripts/scan-setup.sh --mode=discovery
```

**Extract applicable phases from the discovery output:**

| If Project Has | Then Include Phases |
|----------------|-------------------|
| Source code (`.js`, `.ts`, `.py`, `.go`, `.rs`) | 2 (Code Quality), 3 (Tech Debt) |
| Documentation (`docs/`, `README.md`, `*.md`) | 4 (Documentation) |
| A `specs/` or `openspec/` directory | 5 (Specs) |
| Test files (`tests/`, `test/`, `spec/`, `__tests__/`) | 6 (Tests) |
| Any source code (always run) | 7 (Security) |
| A dependency manifest (`package.json`, `requirements.txt`, `go.mod`, `Cargo.toml`) | 8 (SBOM) |
| An application with runtime processes | 9 (12-Factor) |

**Build the applicable phases list** and pass it to the composite subagent. Include
Phase 3 (Tech Debt) only if Phase 2 and Phase 6 both ran, since it depends on their
output.

### Step A4 — Wave 2: Single Synchronous Composite Audit Subagent

**Do NOT fire 8 separate background tasks. That creates a continuation gap — the orchestrator must end its response to wait for them, and the system does not auto-trigger the next turn. The user gets stuck manually typing "continue."**

Instead, launch a **single synchronous composite subagent** that runs ONLY the applicable phases (Phase 1 already ran in Step A3). It handles the Phase 2+6→Phase 3 dependency within its own session — no orchestrator-level continuation needed.

**Include pre-flight validation results and known failure modes in the prompt** so the subagent knows which tools are missing and can use fallbacks.

```json
{
  "category": "deep",
  "load_skills": [
    "repo-health--helpers",
    // Only include phases that are applicable (Phase 1 already ran separately)
    // Dynamic: add/remove based on discovery output from Step A3
    "repo-health--phase-2-code-quality",
    "repo-health--phase-4-docs",
    "repo-health--phase-6-tests",
    "repo-health--phase-7-security"
    // Conditionally add:
    // "repo-health--phase-3-tech-debt"   // only if Phase 2 + Phase 6 ran
    // "repo-health--phase-5-specs"       // only if specs/ dir exists
    // "repo-health--phase-8-sbom"        // only if dependency manifest exists
    // "repo-health--phase-9-12factor"    // only if runtime app
  ],
  "run_in_background": false,
  "prompt": "Run applicable audit phases... (see template below)"
}
```

The orchestrator waits synchronously. When the result comes back, it contains all
findings including Phase 3. Zero continuation gaps because the composite subagent
uses `bash` tool calls only — no `task()`, no background work at any level.

**Composite audit prompt template** (replace placeholders `[WORKING_DIR]`,
`[APPLICABLE_PHASES]`, `[PRE_FLIGHT_RESULTS]`):

```markdown
TASK: Run applicable audit phases (Phase 1 already completed separately).
Execute scanners via the \`bash\` tool (no nested \`task()\` calls).
Return a structured JSON findings list with all findings plus aggregate metrics.

WORKING DIRECTORY: [WORKING_DIR]

APPLICABLE PHASES: [APPLICABLE_PHASES] (e.g., "2,4,6,7,3" — skip all others)

PRE-FLIGHT VALIDATION RESULTS:
[PRE_FLIGHT_RESULTS]

KNOWN FAILURE MODES (read BEFORE running each phase):

NOTE (2026-10-13): The scanner family was fixed for multi-stack (Python/Go/Rust/JVM) repos —
scan-setup.sh, scan-tests*.sh, scan-docs.sh, scan-security.sh, scan-linters*.sh,
parse-test-results.sh, scan-complexity*.sh, scan-tech-debt*.sh, scan-12factor*.sh,
compare-specs.sh, detect-dead-code.sh, audit-dependency-usage.sh, find-duplicates.sh.
Invocation convention: scripts target $PWD (cwd), or set REPO_HEALTH_TARGET_DIR; run them
FROM the audited repo root. scan-setup.sh's $1 is a mode flag, not the target.
Vendor trees (.venv, node_modules, site-packages, __pycache__) are pruned from all scans.

PHASE 2 (Code Quality):
- For Python projects: scan-linters.sh now runs ruff (check + format), mypy, bandit,
  shellcheck, markdownlint — still fine to double-run the critical ones explicitly
- Shellcheck: run WITH config THEN WITHOUT (--norc) to detect masked violations

PHASE 6 (Tests):
- parse-test-results.sh now detects pytest FIRST (parses `N passed/failed`,
  collect-only, `-ra` failure lines). Manual parsing only needed for exotic formats.

PHASE 7 (Security):
- semgrep --config=auto may fail (network/rate limiting)
  → Fallback: grep -P for command injection, hardcoded secrets
- scan-secrets.sh does NOT prune .venv (known limitation) — scan-security.sh works
  around it by targeting src/lib/app; for flat layouts use the staged-copy path

PHASE 8 (SBOM):
- If syft missing, skip SBOM. Fallback: manual find for manifests.
- Even with syft, SPDX output may be all-NOASSERTION — cross-check licenses from
  site-packages .dist-info METADATA License-Expression fields.

PHASE SEQUENCE (run only APPLICABLE phases, sequentially, via bash):

1. Phase 2 — Code Quality
2. Phase 4 — Docs
3. Phase 5 — Specs (if applicable)
4. Phase 6 — Tests
5. Phase 7 — Security
6. Phase 8 — SBOM (if applicable)
7. Phase 9 — 12-Factor (if applicable)
8. Phase 3 — Tech Debt (if applicable — depends on Phase 2 + Phase 6 output)
9. Synthesize all findings into structured JSON

MUST DO:
- Load each phase subskill via skill(...) before running its commands
- Run bash commands ONLY (no task() delegations)
- For Python: explicitly run ruff check src/ AND mypy src/ in Phase 2
- Track metrics: FAILED_TESTS, LINT_ERRORS, LSP_ERRORS
- Return ONLY the JSON object — no prose, no markdown

MUST NOT DO:
- Do NOT call task() with any run_in_background value
- Do NOT present findings in a narrative format
- Do NOT ask for permission
- Do NOT edit any files (Phase 10 remediation happens later, and only when the orchestrator resolved mode=fix)
- Do NOT end early — run all applicable phases before returning
```

### Step A4.5 — Findings Synthesis & Deduplication (AUTOMATED)

Before passing findings to Phase 10, run the automated synthesis pipeline:

```bash
# Step 4.5.1 — Write composite audit output to a temp file
# Replace the heredoc body below with the actual findings JSON collected from all phases
cat > /tmp/repo-health-raw-findings.json << 'TEMPLATE'
{
  "findings": [
    { "phase": 2, "severity": "HIGH", "description": "Example finding", "evidence": "..." }
  ],
  "metrics": {
    "FAILED_TESTS": 0,
    "LINT_ERRORS": 0,
    "LSP_ERRORS": 0,
    "COVERAGE": 0
  }
}
TEMPLATE

# Step 4.5.2 — Run synthesis: dedup, resolve conflicts, classify, compute grade
./skills/repo-health/scripts/synthesize-findings.sh \
  --input /tmp/repo-health-raw-findings.json \
  --classify \
  --output /tmp/repo-health-synthesized.json

# Step 4.5.3 — Read the synthesized result
cat /tmp/repo-health-synthesized.json | jq '.'
```

The `synthesize-findings.sh` script handles:
1. **DEDUPLICATE**: Same description (normalized) across multiple phases → keep highest severity
2. **RESOLVE CONFLICTS**: If Phase 2 scores as MEDIUM and Phase 3 as HIGH → use HIGH
3. **MERGE**: Combine overlapping evidence into a single entry with cross-phase references
4. **CLASSIFY**: `classify-finding.sh` applies the NITPICK rubric to all LOW findings
5. **COMPUTE GRADE**: `compute-grade.sh` computes the grade using ACTIONABLE findings only
6. **OUTPUT**: Deduplicated findings + aggregate metrics + grade

**Example of deduplication:**

```text
Phase 2: "SC2286 empty string as command in install-missing-tools.sh" → MEDIUM
Phase 3: "SC2286 empty-string-as-command bugs (×2)" → HIGH
Phase 7: "No command injection vectors found" (didn't catch this)

SYNTHESIS: Keep Phase 3's HIGH severity. Merge evidence from Phase 2 (line numbers).
Single entry severity: HIGH.
```

This prevents Phase 10 from seeing the same finding 3 times with inconsistent
scores. It also prevents Phase 10 from over-counting findings toward the grade.

### Step A6 — Phase 10: Delegate Remediation Loop to Subagent (mode=fix ONLY)

**Mode gate:** Run this step ONLY if the resolved mode is `fix`. If mode is `report`,
skip this step entirely and go to **"Final Report — mode=report (DEFAULT)"** below.

**DO NOT run Phase 10 inline.** You will stop at an advisory plan. You will fail.
Phase 10 MUST be delegated to a separate subagent.

The subagent receives the synthesized findings and its ONLY job is: fix → re-audit
→ loop until exit condition.

**IMPORTANT: The composite subagent in Step A4 already returned synthesized findings.
Do NOT re-collect phases. Do NOT present findings to the user. Do NOT stop. Do NOT
ask for confirmation. The remediation loop is mandatory and non-optional.**

#### Step A6.1 — Validate Synthesized Findings

The composite subagent returned findings as structured JSON. Verify the list is
complete (all phases 1-9 represented). Every finding MUST include:

- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Description**: One-line summary
- **Evidence**: file:line or scanner output reference
- **Fix Script**: Which fix script to run (or "Manual")

**You MUST construct the findings list now and pass it to the remediation subagent
in the next step.**

#### Step A6.2 — Delegate to Remediation Subagent (SYNCHRONOUS)

**Use `run_in_background=false` (synchronous).** The orchestrator MUST wait for the
remediation subagent to complete before proceeding. Do NOT use background execution
— the exit condition must be met before moving on.

**Before delegating,** the orchestrator MUST have run Step A4.5 to produce a
synthesized, classified, and graded findings file at
`/tmp/repo-health-synthesized.json`. Pass this file's contents as `INPUT_FINDINGS`.

Construct the `task()` call with the synthesized findings embedded in the prompt:

```json
{
  "category": "deep",
  "load_skills": ["repo-health--phase-10-remediate"],
  "run_in_background": false,
  "prompt": "TASK: Execute mandatory remediation loop... (see template below)"
}
```

**Phase 10 delegation prompt template** (replace `[SYNTHESIZED_FINDINGS_JSON]`
and `[WORKING_DIR]` with actual values):

```markdown
TASK: Execute the remediation loop for the findings below.
INPUT FINDINGS:
[SYNTHESIZED_FINDINGS_JSON]

EXPECTED OUTCOME: All actionable findings fixed, codebase modified, exit condition
met (CRITICAL=0, HIGH=0, MEDIUM=0, FAILED_TESTS=0, LINT_ERRORS=0, LSP_ERRORS=0,
ACTIONABLE(LOW)=0).

The INPUT FINDINGS above already have classification and grade computed. Use the
existing classification field to determine what to fix:
- ACTIONABLE = fix immediately
- NITPICK = skip (do not modify code)

REQUIRED TOOLS: bash, test runner (/ pytest / etc.), linter (ruff / shellcheck / etc.),
lsp_diagnostics

MUST DO:
- Load the repo-health--phase-10-remediate subskill via skill(...)
- Follow the subskill's 10.2 → 10.3 → 10.4 → 10.5 pipeline exactly
- Snapshot files before modifying (source lib/fix-common.sh; fix_snapshot)
- Parallelize independent fixes (different files, no shared state)
- Run LSP diagnostics on all changed files — 0 errors AND 0 warnings
- Run linters on BOTH src/ and tests/ — 0 violations
- Run full test suite after every fix round — 0 failures
- If iteration >= 5, stop and flag INCOMPLETE

MUST NOT DO:
- DO NOT produce an advisory/recommendation document
- DO NOT ask for permission to fix things
- DO NOT stop before exit condition is met
- DO NOT run any git command (add, rm, mv, reset, checkout, stash, rebase, merge)
- DO NOT modify .gitignore
- DO run git status BEFORE starting AND AFTER completing
- DO NOT use as any, @ts-ignore, @ts-expect-error
- DO NOT re-classify or re-grade — use the classifications from INPUT FINDINGS

CONTEXT: Working directory is [WORKING_DIR]. Scripts under skills/repo-health/scripts/.
Run tests with the project's test command. Lint both src/ and test/ directories.
```

#### Step A6.3 — Collect Result

The subagent will return a "Remediation Complete" report or "INCOMPLETE" with findings.

**If the subagent returned an advisory plan instead of executing fixes** → the delegation failed. Re-launch with stricter prompt: "You MUST execute fix scripts. An advisory plan is not acceptable output."

**Phase 10 is NOT complete until exit condition is met:** `CRITICAL=0 AND HIGH=0 AND MEDIUM=0 AND FAILED_TESTS=0 AND LINT_ERRORS=0 AND LSP_ERRORS=0 AND ACTIONABLE(LOW)=0`

#### Step A6.4 — Fallback: If Phase 10 Delegation Fails

If the `task()` call times out or the subagent returns an advisory plan:

1. **Run Phase 10 inline yourself** — load the remediate subskill and follow its pipeline directly
2. Do NOT stop. Do NOT ask the user. The remediation must complete either way.

---

## Final Report — mode=report (DEFAULT)

When the resolved mode is `report`, the run ends after Step A4.5 (synthesis +
classification + grade). Do NOT delegate Phase 10, do NOT run any fix script with write
access, and do NOT modify any file. Present the findings report:

```markdown
## Repository Health Report

**Mode:** report (no files were modified)
**Overall Grade:** {GRADE} ({POINTS}/100)        # from compute-grade.sh — authoritative
**Actionable:** C CRITICAL, H HIGH, M MEDIUM, L LOW
**NITPICK (excluded from grade):** N

### Actionable Findings

| # | Severity | Phase | Description | Evidence | Recommended Fix |
|---|----------|-------|-------------|----------|-----------------|
| 1 | CRITICAL | 7 | ... | file:line | fix-lint.sh / Manual |

### NITPICK Findings (not graded)

| # | Description | Rationale |
|---|-------------|-----------|

### Recommended Remediation (not executed)

Ranked fix list ordered CRITICAL → HIGH → MEDIUM → ACTIONABLE LOW, using the Finding →
Fix Script mapping from the phase-10 subskill. State the exit condition that mode=fix
would target: CRITICAL=0 AND HIGH=0 AND MEDIUM=0 AND FAILED_TESTS=0 AND LINT_ERRORS=0
AND LSP_ERRORS=0 AND ACTIONABLE(LOW)=0. To execute it, re-run this skill with mode=fix
(e.g., "now fix these findings").
```

**Resume support:** keep `/tmp/repo-health-synthesized.json` on disk so a follow-up
`mode=fix` request can proceed straight to Step A6 from the existing synthesis without
re-running the audit.

## Helper Scripts

Scripts referenced by subskills live in `skills/repo-health/scripts/`. See the `repo-health--helpers` subskill for the full script listing, grading rubric, and finding classification logic.
