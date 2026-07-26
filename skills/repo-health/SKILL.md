---
name: repo-health
description: "Fully automatic repository health audit with mandatory silent remediation loop. Runs the full audit pipeline (Phases 0-10), where Phase 10 synthesizes findings, classifies them, runs fix scripts, re-audits, and loops until only NITPICKs remain — no user prompts, no confirmation gates, no mercy. Use when user says 'review this repo', 'audit this project', 'health check', 'quality gate', 'fix findings', 'remediate issues', or requests a full codebase analysis. NOT for PR-scoped or incremental reviews."
---

# Repository Health Audit — Mandatory Remediation Loop

A rigorous, deterministic repository audit covering nine dimensions with **mandatory** auto-remediation. The audit detects issues, classifies them, fixes them, re-audits, and loops until only trivial nitpicks remain.

> **Prerequisite:** Run `npx gitnexus analyze --force` on the target repo before starting. Do NOT skip this — the remediation loop depends on a fresh index.

---

## MANDATORY WORKFLOW — DO NOT DEVIATE

This skill is **not an advisory report** — it is an **automated remediation system**. The remediation loop is NOT optional. Do NOT ask the user for permission. Do NOT present findings and stop. Phase 10 is a single unified pipeline that synthesizes, classifies, fixes, and loops — it does NOT produce an advisory plan.

```
AUDIT (Phases 0-10) ──► 10.1 SYNTHESIZE ──► 10.2 CLASSIFY ──► 10.3 FIX ──► 10.4 RE-AUDIT ──► LOOP UNTIL NITPICK ──► 10.5 REPORT
```

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
|---|-----------|----------|
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
|--------|---------|---------------|
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

### Step A2 — Phase 0 (Blocking Gate)
```bash
./skills/repo-health/scripts/scan-environment.sh --check-tools
```
If any required tool is MISSING/BROKEN → **ABORT. Do not proceed.**

### Step A3 — Wave 1: Single Synchronous Composite Audit Subagent

**Do NOT fire 8 separate background tasks. That creates a continuation gap — the orchestrator must end its response to wait for them, and the system does not auto-trigger the next turn. The user gets stuck manually typing "continue."**

Instead, launch a **single synchronous composite subagent** that runs ALL audit phases (1-9) internally. It handles the Phase 2+6→Phase 3 dependency within its own session — no orchestrator-level continuation needed.

```typescript
const auditResults = await task(
  category="deep",
  load_skills=[
    "repo-health--helpers",
    "repo-health--phase-1-discovery",
    "repo-health--phase-2-code-quality",
    "repo-health--phase-3-tech-debt",
    "repo-health--phase-4-docs",
    "repo-health--phase-5-specs",
    "repo-health--phase-6-tests",
    "repo-health--phase-7-security",
    "repo-health--phase-8-sbom",
    "repo-health--phase-9-12factor"
  ],
  run_in_background=false,   // SYNCHRONOUS — orchestrator waits for complete result
  prompt=`
TASK: Run ALL audit phases 1-9 sequentially using DIRECT BASH CALLS ONLY. Return a synthesized JSON findings list with all findings plus aggregate metrics.

WORKING DIRECTORY: [WORKING_DIR]

CRITICAL CONSTRAINT: You MUST run every phase by calling scanner scripts via the \`bash\` tool. Do NOT use \`task()\` or any other subagent mechanism — that will create a continuation gap and the user has to manually continue. All phases run sequentially in this single session using \`bash\` tool calls.

EXPECTED OUTCOME: A JSON object with fields:
  { "findings": [{ "phase": number, "severity": "CRITICAL|HIGH|MEDIUM|LOW", "description": "...", "evidence": "...", "fixScript": "..." }], "metrics": { "FAILED_TESTS": number, "LINT_ERRORS": number, "LSP_ERRORS": number } }

PHASE SEQUENCE (run in this exact order, sequentially, via bash tool calls):

1. Phase 1 — Discovery: \`bash ./skills/repo-health/scripts/scan-setup.sh\` + interpret output
2. Phase 2 — Code Quality: run scan-dead-code, scan-complexity, scan-cognitive-complexity, scan-linters, audit-dependency-usage
3. Phase 4 — Docs: \`bash ./skills/repo-health/scripts/scan-docs.sh\`
4. Phase 5 — Specs: \`bash ./skills/repo-health/scripts/scan-setup.sh --mode=specs\`
5. Phase 6 — Tests: \`bash ./skills/repo-health/scripts/scan-tests.sh\`
6. Phase 7 — Security: \`bash ./skills/repo-health/scripts/scan-security.sh\`
7. Phase 8 — SBOM: \`bash ./skills/repo-health/scripts/scan-sbom.sh\`
8. Phase 9 — 12-Factor: \`bash ./skills/repo-health/scripts/scan-12factor.sh\`
9. Phase 3 — Tech Debt: \`bash ./skills/repo-health/scripts/scan-tech-debt.sh\` (depends on Phase 2 + Phase 6 context — pass their results when interpreting)
10. Synthesize all findings into structured JSON

TIP: For each phase, first load its subskill via \`skill(name="repo-health--phase-{N}-{name}")\` to get the full scanner instructions, then run the bash commands it specifies.

MUST DO:
- Load each phase subskill via \`skill(...)\` before running its bash commands
- Load helpers subskill via \`skill(name="repo-health--helpers")\`
- Run \`bash\` commands ONLY — each tool call runs synchronously and returns the output
- Collect scanner output, interpret it against the subskill's rubric, produce findings
- Track aggregate metrics from test output, lint output, and LSP diagnostics
- Return ONLY the JSON object — no prose, no markdown formatting around it

MUST NOT DO:
- Do NOT call \`task()\` with any \`run_in_background\` value — that creates a continuation gap
- Do NOT present findings in a report or narrative format — return raw JSON only
- Do NOT ask the user for anything
- Do NOT edit any files during this phase (Phase 10 handles remediation)
- Do NOT end your response early — run ALL 9 phases in sequence before returning
`
)
```

The orchestrator waits synchronously. When \`auditResults\` comes back, it contains all findings including Phase 3. Zero continuation gaps because the composite subagent uses \`bash\` tool calls only — no \`task()\`, no background work at any level.

### Step A4 — Synthesize Composite Results
Extract the findings list and metrics from the returned \`auditResults\`. If any phase didn't produce findings, document as N/A. Do NOT present to the user. Proceed immediately to Step A5.

### Step A5 — Phase 10: Delegate Remediation Loop to Subagent (MANDATORY — do NOT run inline)

**DO NOT run Phase 10 inline.** You will stop at an advisory plan. You will fail. Phase 10 MUST be delegated to a separate subagent.

The subagent receives the synthesized findings and its ONLY job is: fix → re-audit → loop until exit condition.

**IMPORTANT: The composite subagent in Step A3 already returned synthesized findings. Do NOT re-collect phases. Do NOT present findings to the user. Do NOT stop. Do NOT ask for confirmation. The remediation loop is mandatory and non-optional.**

#### Step A5.1 — Validate Synthesized Findings

The composite subagent returned findings as structured JSON. Verify the list is complete (all phases 1-9 represented). Every finding MUST include:
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Description**: One-line summary
- **Evidence**: file:line or scanner output reference
- **Fix Script**: Which fix script to run (or "Manual")

**You MUST construct the findings list now and pass it to the remediation subagent in the next step.**

#### Step A5.2 — Delegate to Remediation Subagent (SYNCHRONOUS — NOT background)

**Use `run_in_background=false` (synchronous).** The orchestrator MUST wait for the remediation subagent to complete before proceeding. Do NOT use background execution — the exit condition must be met before moving on.

Construct a `task()` call with findings embedded in the prompt. Replace `FINDINGS_JSON` with the actual synthesized findings JSON. Replace `WORKING_DIR` with the actual working directory path.

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
- Run fix scripts, verify LSP is clean, verify lint on source AND test code, verify tests pass, regression guard, re-audit, loop
- If iteration >= 5, stop and flag INCOMPLETE

MUST NOT DO:
- DO NOT produce an advisory/recommendation document
- DO NOT ask for permission to fix things
- DO NOT stop before exit condition is met
- DO NOT commit changes
- DO NOT use as any, @ts-ignore, @ts-expect-error

CONTEXT: Working directory is [WORKING_DIR]. All scripts are under skills/repo-health/scripts/. Run tests with the project's test command. Lint both src/ and test/ directories.
`
)
```

#### Step A5.3 — Collect Result

The subagent will return a "Remediation Complete" report or "INCOMPLETE" with findings.

**If the subagent returned an advisory plan instead of executing fixes** → the delegation failed. Re-launch with stricter prompt: "You MUST execute fix scripts. An advisory plan is not acceptable output."

**Phase 10 is NOT complete until exit condition is met:** `CRITICAL=0 AND HIGH=0 AND MEDIUM=0 AND FAILED_TESTS=0 AND LINT_ERRORS=0 AND LSP_ERRORS=0 AND ACTIONABLE(LOW)=0`

#### Step A5.4 — Fallback: If Phase 10 Delegation Fails

If the `task()` call times out or the subagent returns an advisory plan:
1. **Run Phase 10 inline yourself** — load the remediate subskill and follow its pipeline directly
2. Do NOT stop. Do NOT ask the user. The remediation must complete either way.



## Helper Scripts

Scripts referenced by subskills live in `skills/repo-health/scripts/`. See the `repo-health--helpers` subskill for the full script listing, grading rubric, and finding classification logic.
