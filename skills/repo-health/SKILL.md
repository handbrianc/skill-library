---
name: repo-health
description: "Fully automatic repository health audit with mandatory silent remediation loop. Runs the full audit pipeline (Phases 0-10), where Phase 10 synthesizes findings, classifies them, runs fix scripts, re-audits, and loops until only NITPICKs remain — no user prompts, no confirmation gates, no mercy. Use when user says 'review this repo', 'audit this project', 'health check', 'quality gate', 'fix findings', 'remediate issues', or requests a full codebase analysis. NOT for PR-scoped or incremental reviews."
---

# Repository Health Audit — Mandatory Remediation Loop

A rigorous, deterministic repository audit covering nine dimensions with **mandatory**
auto-remediation. The audit detects issues, classifies them, fixes them, re-audits, and
loops until only trivial nitpicks remain.

> **Prerequisite:** Run `npx gitnexus analyze --force` on the target repo before starting.
> Do NOT skip this — the remediation loop depends on a fresh index.

---

## MANDATORY WORKFLOW — DO NOT DEVIATE

This skill is **not an advisory report** — it is an **automated remediation system**.
The remediation loop is NOT optional. Do NOT ask the user for permission. Do NOT present
findings and stop. Phase 10 is a single unified pipeline that synthesizes, classifies,
fixes, and loops — it does NOT produce an advisory plan.

```text
AUDIT (Phases 0-10) ──► 10.1 SYNTHESIZE ──► 10.2 CLASSIFY ──► 10.3 FIX ──► 10.4 RE-AUDIT ──► LOOP UNTIL NITPICK ──► 10.5 REPORT
```text

---

## Critical Constraints

### MUST DO

- **Run PHASE 0 before all other phases** — abort if any required tool is missing
- **Phase 10 is the remediation pipeline (synthesize → classify → fix → loop)** — do NOT stop after synthesis. Classification, fix execution, re-audit, and loop are all mandatory parts of Phase 10.
- **Re-audit after each remediation round** within Phase 10 — loop until exit condition met (CRITICAL=0 AND HIGH=0 AND MEDIUM=0 AND FAILED_TESTS=0 AND LINT_ERRORS=0 AND LSP_ERRORS=0 AND ACTIONABLE(LOW)=0)
- **Outdated libraries, packages with known CVEs, and insecure code patterns are CRITICAL severity** — they MUST BE ADDRESSED in the remediation loop. Do NOT downgrade them. Do NOT classify them as MEDIUM or HIGH.
- Run actual scanners/tool commands — do not speculate about outcomes
- Operate on committed HEAD (preserve original commit, never mixed working tree + staging)
- If a fix introduces a regression (new CRITICAL/HIGH finding), **revert via fix-rollback.sh** and skip that fix

### MUST NOT DO

- Never present an advisory action plan without executing the remediation steps in Phase 10.3-10.4
- Never stop after Phase 10.1 (Synthesize) — that is only the first of five sub-steps
- Never ask "do you want me to fix these?" — fix them. That is the entire point of this skill.
- Never suppress type errors with `as any`, `@ts-ignore`, or `@ts-expect-error`
- Never delete failing tests to make a build pass
- Never commit changes (leave uncommitted for user review)
- Never edit any symbol without first running `gitnexus_impact(target, direction: "upstream")`
- Never treat an N/A dimension as a failure — document rationale

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
| 10 | Remediation Loop (delegated to subagent — fixes, re-audits, loops) | `repo-health--phase-10-remediate` |

---

## Fix Scripts Reference

Six fix scripts live under `skills/repo-health/scripts/`:

| Script | Purpose | Finding Types |
| -------- | --------- | --------------- |
| `fix-gitnexus-stats.sh` | Sync GitNexus stats across AGENTS.md/CLAUDE.md/ARCHITECTURE.md | Stale gitnexus blocks |
| `fix-doc-links.sh` | Check + report broken external/internal links in docs | Broken links |
| `fix-env-example.sh` | Generate/update .env.example from code-scanned env vars | Missing .env.example |
| `fix-lint.sh` | Run linters with --fix (ESLint, Ruff, gofmt, etc.) | Lint violations |
| `fix-rollback.sh` | Snapshot rollback + regression detection | Safety net |
| `lib/fix-common.sh` | Shared library (sourced by all fix scripts) | — |

---

## Phase A — Audit: Phases 0-10

### Step A1 — Prerequisite & Helpers

1. Ensure `npx gitnexus analyze --force` ran on the target repo
2. Load the helpers subskill: `skill(name="repo-health--helpers")`
3. Load ALL phase subskills: `skill(name="repo-health--phase-{N}-{name}")` for N=0..10

### Step A2 — Phase 0 (Gate + Auto-Install)

```bash
# Step 0.1 — Check what's present
./skills/repo-health/scripts/scan-environment.sh --check-tools
```text

**If any core utility is MISSING/BROKEN** (bash, node, npm, npx, git, jq, find, grep,
realpath) → **ABORT. Do not proceed.** The audit cannot run without them.

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
```text

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
```text

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
```text

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

```text
const auditResults = await task(
  category="deep",
  load_skills=[
    "repo-health--helpers",
    // Only include phases that are applicable (Phase 1 already ran separately)
    // Dynamic: add/remove based on discovery output from Step A3
    "repo-health--phase-2-code-quality",     // Include if source code exists
    // "repo-health--phase-3-tech-debt",     // Include only if Phase 2 + Phase 6 ran
    "repo-health--phase-4-docs",             // Include if docs exist
    // "repo-health--phase-5-specs",         // Include only if specs/ dir exists
    "repo-health--phase-6-tests",            // Include if test files exist
    "repo-health--phase-7-security",         // Always include (runs on any code)
    // "repo-health--phase-8-sbom",          // Include only if dependency manifest exists
    // "repo-health--phase-9-12factor"       // Include only if runtime app
  ],
  run_in_background=false,   // SYNCHRONOUS — orchestrator waits for complete result
  prompt=`
TASK: Run applicable audit phases (Phase 1 already completed separately). Execute scanners via the \`bash\` tool (no nested \`task()\` calls). Return a synthesized JSON findings list with all findings plus aggregate metrics.

WORKING DIRECTORY: [WORKING_DIR]

PRE-FLIGHT VALIDATION RESULTS (tool availability):
[INCLUDE OUTPUT FROM STEP A2.5 HERE — e.g., TOOL_OK: shellcheck, TOOL_MISSING: syft]

KNOWN FAILURE MODES — read these BEFORE running each phase:

PHASE 2 (Code Quality):
- \`scan-linters.sh\` may NOT detect shellcheck/markdownlint (it targets ESLint/Ruff etc.)
  Fallback: If scan-linters.sh returns empty, run manually:
  \`shellcheck --severity=warning \$(find . -name '*.sh' -type f)\`
- PHASE 2 LINTING: ALSO run \`markdownlint 'skills/*/SKILL.md' --config .markdownlint.json\`
- Shellcheck config check: Run shellcheck WITH config THEN WITHOUT (\`--norc\`) to detect masked violations

PHASE 6 (Tests):
- \`parse-test-results.sh\` may auto-detect the wrong framework and return "Couldn't auto-detect"
  Fallback: Manually parse test output for PASSED/FAILED/ERRORS counts
- \`scan-tests.sh\` scripts may not exist or return empty for bash-only repos
  Fallback: Run \`bash tests/run-tests.sh\` directly and parse exit code + output

PHASE 7 (Security):
- \`semgrep --config=auto\` may fail to resolve registry rules
  Fallback: Write targeted \`grep -P\` patterns for command injection, hardcoded secrets, eval, unsafe temp files
- \`scan-security.sh --credential-exposure\` uses git history scan — on shallow clones, this returns nothing
  Fallback: Check HEAD for .env files, API keys, and private key patterns via grep

PHASE 8 (SBOM):
- If \`syft\` is not installed (TOOL_MISSING above), skip scan-sbom.sh entirely
  Fallback: Manual dependency inventory via \`find . -name 'package.json' -o -name 'requirements.txt' -o -name 'Cargo.toml'\`
- \`scan-licenses.sh\` also depends on SBOM output — skip both if syft missing

CRITICAL CONSTRAINT: You MAY call \`skill(...)\` to load phase instructions, but you MUST run every phase's scanner scripts via the \`bash\` tool. Do NOT use \`task()\` or any other subagent mechanism — that will create a continuation gap and the user has to manually continue. All phases run sequentially in this single session using \`bash\` tool calls.

EXPECTED OUTCOME: A JSON object with fields:
  { "findings": [{ "phase": number, "severity": "CRITICAL|HIGH|MEDIUM|LOW", "description": "...", "evidence": "...", "fixScript": "..." }], "metrics": { "FAILED_TESTS": number, "LINT_ERRORS": number, "LSP_ERRORS": number } }

PHASE SEQUENCE (run only applicable phases, in this order, sequentially, via bash tool calls):

1. Phase 2 — Code Quality: run scan-dead-code, scan-complexity, scan-cognitive-complexity, scan-linters + shellcheck + markdownlint fallbacks, audit-dependency-usage
2. Phase 4 — Docs: \`bash ./skills/repo-health/scripts/scan-docs.sh\`
3. Phase 5 — Specs (if applicable): \`bash ./skills/repo-health/scripts/scan-setup.sh --mode=specs\`
4. Phase 6 — Tests: \`bash ./skills/repo-health/scripts/scan-tests.sh\` + fallback \`bash tests/run-tests.sh\`
5. Phase 7 — Security: \`bash ./skills/repo-health/scripts/scan-security.sh\` + semgrep/grep fallbacks
6. Phase 8 — SBOM (if applicable): \`bash ./skills/repo-health/scripts/scan-sbom.sh\` or manual dependency inventory
7. Phase 9 — 12-Factor (if applicable): \`bash ./skills/repo-health/scripts/scan-12factor.sh\`
8. Phase 3 — Tech Debt (if applicable): \`bash ./skills/repo-health/scripts/scan-tech-debt.sh\` (depends on Phase 2 + Phase 6 context — pass their results when interpreting)
9. Synthesize all findings into structured JSON

TIP: For each phase, first load its subskill via \`skill(name="repo-health--phase-{N}-{name}")\` to get the full scanner instructions, then run the bash commands it specifies. Check the KNOWN FAILURE MODES above BEFORE running each phase.

MUST DO:
- Load each phase subskill via \`skill(...)\` before running its bash commands
- Load helpers subskill via \`skill(name="repo-health--helpers")\`
- Run \`bash\` commands ONLY — each tool call runs synchronously and returns the output
- Collect scanner output, interpret it against the subskill's rubric, produce findings
- Track aggregate metrics from test output, lint output, and LSP diagnostics
- If a scanner returns empty or errors, use the KNOWN FAILURE MODES fallback above
- Return ONLY the JSON object — no prose, no markdown formatting around it

MUST NOT DO:
- Do NOT call \`task()\` with any \`run_in_background\` value — that creates a continuation gap
- Do NOT present findings in a report or narrative format — return raw JSON only
- Do NOT ask the user for anything
- Do NOT edit any files during this phase (Phase 10 handles remediation)
- Do NOT end your response early — run ALL applicable phases in sequence before returning
`
)
```text

The orchestrator waits synchronously. When \`auditResults\` comes back, it contains all findings including Phase 3. Zero continuation gaps because the composite subagent uses \`bash\` tool calls only — no \`task()\`, no background work at any level.

### Step A4.5 — Findings Synthesis & Deduplication (NEW)

Before passing findings to Phase 10, run a synthesis step to ensure consistency:

```text
1. COLLECT all findings from the composite subagent result
2. DEDUPLICATE: If the same finding appears across multiple phases (e.g., SC2286 flagged by both Phase 2 and Phase 3), keep the HIGHEST severity version
3. RESOLVE CONFLICTS: If Phase 2 scores SC2286 as MEDIUM (-3) and Phase 3 scores it as HIGH (-10), use HIGH
4. MERGE: Combine overlapping findings into a single entry with cross-phase references
5. CLASSIFY: Apply the NITPICK rubric to all LOW findings
6. OUTPUT: Produced deduplicated findings list + aggregate metrics
```text

**Example of deduplication:**

```text
Phase 2: "SC2286 empty string as command in install-missing-tools.sh" → MEDIUM
Phase 3: "SC2286 empty-string-as-command bugs (×2)" → HIGH
Phase 7: "No command injection vectors found" (didn't catch this)

SYNTHESIS: Keep Phase 3's HIGH severity. Merge evidence from Phase 2 (line numbers).
Single entry severity: HIGH.
```text

This prevents Phase 10 from seeing the same finding 3 times with inconsistent
scores. It also prevents Phase 10 from over-counting findings toward the grade.

### Step A6 — Phase 10: Delegate Remediation Loop to Subagent (MANDATORY)

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

Construct a `task()` call with findings embedded in the prompt. Replace
`FINDINGS_JSON` with the actual synthesized findings JSON. Replace `WORKING_DIR`
with the actual working directory path.

```typescript
const result = await task(
  category="deep",
  load_skills=["repo-health--phase-10-remediate"],
  run_in_background=false,   // MUST be synchronous — orchestrator waits for completion
  prompt=`
TASK: Execute the remediation loop for the findings below.

INPUT FINDINGS:
[FINDINGS_JSON]

EXPECTED OUTCOME: All actionable findings fixed, codebase modified, exit condition met (CRITICAL=0, HIGH=0, MEDIUM=0, FAILED_TESTS=0, LINT_ERRORS=0, LSP_ERRORS=0, ACTIONABLE(LOW)=0).

REQUIRED TOOLS: bash, test runner (npm test / pytest / etc.), linter (eslint / ruff / shellcheck), lsp_diagnostics, npx gitnexus (re-index)

MUST DO:
- Load the repo-health--phase-10-remediate subskill: skill(name="repo-health--phase-10-remediate")
- Follow the subskill's 10.2 → 10.3 → 10.4 → 10.5 pipeline exactly
- Snapshot files before modifying (source lib/fix-common.sh; fix_snapshot)
- **Parallelize independent fixes** — e.g., markdownlint fixes on doc A are independent of shellcheck fixes on script B. Apply them simultaneously rather than sequentially.
- Run fix scripts, verify LSP is clean, verify lint on source AND test code, verify tests pass, regression guard, re-audit, loop
- If iteration >= 5, stop and flag INCOMPLETE

MUST NOT DO:
- DO NOT produce an advisory/recommendation document
- DO NOT ask for permission to fix things
- DO NOT stop before exit condition is met
- **DO NOT run any git command** (add, rm, mv, reset, checkout, stash, rebase, merge)
- **DO NOT modify .gitignore**
- **DO run git status BEFORE starting AND AFTER completing** to verify no unintended file changes
- **If git state changes unexpectedly** (files deleted, detached HEAD, untracked files appearing), STOP and report immediately
- DO NOT commit changes
- DO NOT use as any, @ts-ignore, @ts-expect-error

CONTEXT: Working directory is [WORKING_DIR]. All scripts are under skills/repo-health/scripts/. Run tests with the project's test command. Lint both src/ and test/ directories.
`
)
```text

#### Step A6.3 — Collect Result

The subagent will return a "Remediation Complete" report or "INCOMPLETE" with findings.

**If the subagent returned an advisory plan instead of executing fixes** → the delegation failed. Re-launch with stricter prompt: "You MUST execute fix scripts. An advisory plan is not acceptable output."

**Phase 10 is NOT complete until exit condition is met:** `CRITICAL=0 AND HIGH=0 AND MEDIUM=0 AND FAILED_TESTS=0 AND LINT_ERRORS=0 AND LSP_ERRORS=0 AND ACTIONABLE(LOW)=0`

#### Step A6.4 — Fallback: If Phase 10 Delegation Fails

If the `task()` call times out or the subagent returns an advisory plan:

1. **Run Phase 10 inline yourself** — load the remediate subskill and follow its pipeline directly
2. Do NOT stop. Do NOT ask the user. The remediation must complete either way.

## Helper Scripts

Scripts referenced by subskills live in `skills/repo-health/scripts/`. See the `repo-health--helpers` subskill for the full script listing, grading rubric, and finding classification logic.
