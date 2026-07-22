---
name: repo-health
description: "Comprehensive repository health audit — code quality, linting, docs, specs, tests, security, SBOM, 12-Factor App compliance, and technical debt review. Use when user says 'review this repo', 'audit this project', 'health check', 'quality gate', or requests a full codebase analysis. NOT for PR-scoped or incremental reviews. Examples: 'Conduct a full repository audit', 'Comprehensive code quality review of this project', 'Health check on the codebase'"
---

# Repository Health Audit

A rigorous, deterministic repository audit covering nine dimensions. Produces a prioritized, actionable plan when complete.

> **Prerequisite:** Run `node .gitnexus/run.cjs analyze --force` on the target repo before starting (fallback: `npx gitnexus analyze --force` if the local runner doesn't exist). This ensures the knowledge graph reflects current state.

## Critical Constraints

### MUST DO
- Produce a prioritized, actionable plan before considering the audit complete
- Flag as CRITICAL any finding that is security-relevant or blocking release
- Run actual scanners/tool commands — do not speculate about outcomes
- Preserve the original commit (operate on HEAD, never mixed working tree + staging)
- **Run PHASE 0 (Environment Readiness) before all other phases** — stop immediately if any required tool is missing and report the gap

### MUST NOT DO
- Never suppress type errors with `as any`, `@ts-ignore`, or `@ts-expect-error`
- Never delete failing tests to make a build pass — fix the underlying code
- Never commit changes without running `gitnexus_detect_changes()` to verify affected scope
- Never edit any symbol without first running `gitnexus_impact(target, direction: "upstream")`
- Never use find-and-replace for renames — use `gitnexus_rename` which respects the call graph
- Never treat an N/A dimension as a failure — document the rationale (e.g., "no test suite — intentional for this project type")

## Scope & Preconditions

**In scope:**
1. Application code quality (smells, architecture, complexity, duplications, dead code, linting)
2. Documentation completeness and accuracy
3. OpenSpec specification alignment (specs, archived specs)
4. Test suite health (coverage, pass/fail, flakiness, performance)
5. Security posture (CVEs, vulnerable code patterns, secrets exposure)
6. Supply-chain health (SBOM, licenses, outdated dependencies)
7. Twelve-Factor App methodology compliance (SaaS/cloud-native architecture patterns)
8. Linter configuration and violation count (per-language static analysis tools)
9. Technical debt profile (TODO/FIXME inventory, architecture erosion, technology currency, test debt, API surface stability, error handling debt)

**Out of scope:** Infrastructure-as-code, CI/CD pipelines themselves, external services.

**Required environment:**
- Node.js >= 18 (for `npx`)
- Bash >= 4.0 (for associative-array support in `find-duplicates.sh`)
- Git installed and accessible
- `jq` (for JSON parsing in PHASE 1 discovery)
- GNU `find` with `-maxdepth` support (for PHASE 0.5 inventory commands; macOS ships BSD find — install GNU findutils and ensure it is available as `find`)
- GNU `grep` with BRE alternation support (for PHASE 9 12-factor grep commands; macOS ships BSD grep — install GNU grep via `brew install grep`)
- `timeout`/`gtimeout` (for PHASE 9 disposability startup timing; macOS: `brew install coreutils` provides `gtimeout`)
- For security scan: `npm audit`, `Grype` or `Syft` (container/jar projects)
- For coverage: project's test runner with coverage reporter (vitest, jest, etc.)
- For complexity metrics: `eslint --quiet` with `complexity` rule, or `tsq` for TS

## Phases

---

### PHASE 0 — Environment Readiness (Gate)

**Goal:** Validate baseline tools required for all audits (bash, git, node/npm, jq, find) and report language/project-specific tools as informational. If any required baseline tool is missing, **abort immediately** and report the gaps.

```bash
./skills/repo-health/scripts/scan-environment.sh --check-tools
```

**If any core utility prints `MISSING/BROKEN`, or any helper script prints `SKILL_ERR` / `SKILL_MISSING`:**
- Collect all missing/malformed items into a single block
- **ABORT — do not proceed to PHASE 1**

> Optional language/test/security tools may print `MISSING (optional)`; only treat them as blocking if the repo’s stack requires them.
>
> ```markdown
> ## 🚫 ENVIRONMENT GAP — Cannot Proceed
>
> The following tools are missing or broken. Install them before re-running the audit:
>
> | Tool | Status | Install Command |
> | ---- | ------ | --------------- |
> | bash | MISSING | (system package manager) |
> | ./skills/repo-health/scripts/scan-secrets.sh | SYNTAX ERROR (bash -n) | fix script |
> ```
- The user must resolve all gaps before the audit can proceed.

---

### PHASE 0.5 — Transient File Cleanup (Pre-Audit)

**Goal:** Inventory transient/generated/no-value files before auditing so scans operate only on meaningful source material; remove items only after explicit review. Keeps all `openspec/`, `opencode/`, and `.claude/` files intact.

```bash
./skills/repo-health/scripts/scan-environment.sh --scan-transient
```

**Decision rule — ALWAYS KEEP:**
- Anything under `./openspec/` (OpenSpec specifications, if present)
- Anything under `./opencode/` (OpenCode configuration/skills, if present)
- Anything under `./.claude/` (Claude Code configuration and memory)
- Anything under `.git/` (never touch)
- Source files matching common extensions: `.js`, `.ts`, `.jsx`, `.tsx`, `.py`, `.go`, `.rs`, `.java`, `.rb`, `.php`, `.cs`, `.cpp`, `.c`, `.h`, `.hpp`, `.sql`, `.sh`, `.bash`, `.zsh`, `.fish`, `.ps1`, `.yaml`, `.yml`, `.toml`, `.json`, `.xml`, `.html`, `.htm`, `.css`, `.scss`, `.sass`, `.less`, `.svg`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.ico`, `.pdf`, `.md`, `.rst`, `.txt`

**Decision rule — SAFE TO REMOVE:**
- `node_modules/`, `__pycache__/`, `.pytest_cache/`, `.next/`, `dist/`, `build/`, `target/`, `.venv/`, `venv/`
- `vendor/` — REVIEW; keep if tracked or required for builds (e.g., Go `go mod vendor`)
- Lock files (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `poetry.lock`, `Cargo.lock`) — KEEP if tracked; remove only if explicitly untracked and safe for this repo
- `.cache/`, `tmp/`, `temp/` directories
- `*.log` files
- `*.swp`, `*.swo`, `*~`, `.DS_Store` (editor/OS noise)
- Empty directories left after removing above

**Report:**
```
## Transient File Summary

| Category            | Count | Action  |
| -------------------- | ----- | ------- |
| node_modules         | N     | Review  |
| lock files           | N     | Keep    |
| cache dirs           | N     | Remove  |
| editor noise         | N     | Remove  |
| empty dirs           | N     | Remove  |
```
> **Note:** If in doubt about any file, err on the side of keeping it. The audit must never destroy valuable files.

---

### PHASE 1 — Setup & Discovery
**Goal:** Understand project structure, tech stack, package manager, and which audit dimensions actually apply.

Run these discovery commands:

```bash
./skills/repo-health/scripts/scan-setup.sh --mode=discovery
```

**Produce:**
```
| Dimension         | Stack       | Toolchain          |
| ----------------- | ----------- | ------------------ |
| Language          | TypeScript  | node/npm           |
| Framework         | Next.js 14  | eslint, vitest     |
| Package Manager   | npm         | npm ls             |
| Build Target      | SPA + API   | tsc, next build   |
| Has Specs Dir?    | YES         | ./specs/           |
| Has Docs Dir?     | PARTIAL     | ./docs/ partial   |
| Test Runner       | vitest      | vitest run --coverage |
| Coverage Tool     | —                   |             |
```

Mark any dimension as **NOT APPLICABLE** if the project type makes it irrelevant (e.g., no test runner found for a pure-config repo).

---

### PHASE 2 — Code Quality Analysis

Uses GitNexus + static analysis scripts for deterministic results.

**Step 2.1 — Ensure fresh GitNexus index**

```bash
npx gitnexus status
```

If stale: `npx gitnexus analyze --force`

**Step 2.2 — Dead/unused code scan**

```bash
# skills/repo-health/scripts/detect-dead-code.sh  (see helpers below)
./skills/repo-health/scripts/detect-dead-code.sh src/
```

**Step 2.3 — Cyclomatic complexity**

```bash
./skills/repo-health/scripts/scan-complexity.sh
```

For Python: `radon cc -a -b src/ --max-complexity 10`

Flag cyclomatic complexity > 15 as MEDIUM risk, > 25 as HIGH risk, and > 40 as CRITICAL.

**Step 2.4 — Cognitive complexity**

Cognitive complexity is harder to automate. Use:

```bash
# scan-cognitive-complexity.sh (see helpers)
./skills/repo-health/scripts/scan-cognitive-complexity.sh src/

# Manual spot-check via GitNexus:
query({search_query: "deeply nested callback hell", limit: 5})
query({search_query: "monstrous switch statement", limit: 5})
```

**Step 2.5 — Duplicated code**

```bash
./skills/repo-health/scripts/scan-complexity.sh
```

Report duplicates > 50 lines identical.

**Step 2.6 — Architecture weakness review**

Use GitNexus clusters to assess architectural coherence:

```bash
query({search_query: "arch component module service layer"})
READ gitnexus://repo/{name}/clusters
READ gitnexus://repo/{name}/processes
```

Flag clusters with LOW cohesion or no natural grouping.

**Step 2.7 — Dependency utilization review**

```bash
# Script: audit-dependency-usage.sh
./skills/repo-health/scripts/audit-dependency-usage.sh
```

Checks `package.json` dependencies against `node_modules/` and import graphs:
- Are all `dependencies` actually imported anywhere? (dead installs)
- Are `devDependencies` correctly scoped as dev-only?
- Are any `optionalDependencies` that should be `dependencies`?

---

**Step 2.8 — Linting**

**Goal:** Detect available linters for the project's language(s), run them, and report violations as part of code quality.

**Step 2.8a — Detect and run linters**

Detect available linters for the project's language(s) and run them with a single invocation. The script auto-detects the source directory (src/ → lib/ → app/ → .) and covers all major language linters.

```bash
# Run linter detection + scan in one step
./skills/repo-health/scripts/scan-linters.sh
```

If no linter is available for the project's language(s), flag as **MEDIUM** — "Linter available but not configured; consider adding one."

Violation counts are written to `/tmp/<linter>-violations.txt` for each detected linter. The script exits 0 always; linter violations are captured as data, not failures.

**Step 2.8c — Report linting findings**

Compile all linter violations into a structured finding per linter.

**Important note on severity-to-scoring mapping:** The severity assigned to a linting finding (LOW/MEDIUM/HIGH/CRITICAL) represents the finding's **overall code quality impact**, NOT one point per violation. For example, a linting tool with >200 violations produces **1 CRITICAL finding** (-25 points in the grading rubric), not 200 separate CRITICAL findings. Each linter tool generates at most 1 finding in the action plan.

**Example mapping:**
| Linter | Violations | Finding Severity | Rubric Impact |
|--------|-----------|-----------------|---------------|
| eslint | 0 errors, 5 warnings | LOW | -1 point |
| ruff | 3 errors, 20 warnings | MEDIUM | -3 points |
| pylint | 12 errors, 100 warnings | HIGH | -10 points |
| phpcs | 50+ errors | CRITICAL | -25 points |

Compile all linter violations into a structured finding per linter:

```
LINTING FINDING:
  Tool: eslint
  Config: .eslintrc.js (found) / NO CONFIG (missing)
  Violations: N errors, N warnings
  Severity: LOW (<10 violations) / MEDIUM (10-50) / HIGH (50-200) / CRITICAL (>200)
  Blocking: YES if >0 errors / NO if only warnings
```

Flag findings:
- **Linter available but no config** → MEDIUM
- **Linter configured but >0 errors** → HIGH (must fix errors before they cause bugs)
- **Linter configured and >50 total violations** → MEDIUM (code style debt)
- **Linter configured but no lint script in package.json** → LOW (missing CI integration)
- **No linter available for project's primary language** → MEDIUM (no automated code quality enforcement)
- **Type checker (tsc/mypy) available but not configured in CI** → MEDIUM

**Add to Scoring Rubric:**
- Linter configured and clean (0 violations) → +2 bonus to overall grade
- Type checker configured and passing → +1 bonus

---

### PHASE 3 — Top-Down Technical Debt Review

**Goal:** Assess architectural and systemic technical debt that standard code-quality metrics miss. This phase looks at the big picture — module coupling, aging workarounds, technology currency, test debt, and API surface stability — to produce a consolidated debt profile.

**How to use this phase:** Run the automated checks, then synthesize findings into the debt profile table. Flag findings using the severity guide below. This phase depends on PHASE 2 (code quality) and PHASE 6 (test suite) results — run those first.

```bash
./skills/repo-health/scripts/scan-tech-debt.sh
```

Compile findings into a structured debt profile:

```
## TECHNICAL DEBT PROFILE

### Marker Debt
| Category | Count | Severity |
|----------|-------|----------|
| TODO     | 23    | —        |
| FIXME    | 5     | —        |
| HACK     | 8     | MEDIUM   |
| XXX      | 2     | —        |
| WORKAROUND | 3   | LOW      |
| **Total**  | **41** | **MEDIUM** |
| Marker density | 2.3/1000 LOC | LOW |

### Architecture Debt
| Finding | Severity |
|---------|----------|
| Circular dependencies: 2 | HIGH |
| Layer violations: 1 | MEDIUM |
| God modules: 3 | MEDIUM |
| Barrel files: 24 | LOW |

### Technology Debt
| Finding | Severity |
|---------|----------|
| Node 18.x (current LTS: 22.x) | MEDIUM |
| TypeScript 4.9 (current: 5.5) | MEDIUM |
| ESLint < 9 (flat config not supported) | LOW |

### Test Debt
| Finding | Severity |
|---------|----------|
| Test:Production ratio 0.25 | MEDIUM |
| 3 sleep-based tests | MEDIUM |
| 1 over-mocked test (>20 mocks) | LOW |
| Avg test time: 320ms | LOW |

### API Surface Debt
| Finding | Severity |
|---------|----------|
| 14 unused exports | MEDIUM |
| 3 hotspot files (>20 changes/6mo) | LOW |

### Error Handling Debt
| Finding | Severity |
|---------|----------|
| 12 empty catch blocks | HIGH |
| 40% ad-hoc console.log vs structured logging | MEDIUM |
| No error boundaries | MEDIUM |

### OVERALL TECHNICAL DEBT RATING
- **LOW**: Minor, schedule when convenient
- **MEDIUM**: Plan to address within next quarter
- **HIGH**: Actively causing friction or risk — prioritize
- **CRITICAL**: Blocking velocity or creating production risk — address now

**Overall rating: MEDIUM** (based on HIGH findings in error handling + architecture)
```

**Scoring integration:** The HIGH/MEDIUM/LOW findings in this phase map to the grading rubric using the standard weights (HIGH = -10, MEDIUM = -3, LOW = -1). Each distinct finding type (e.g., "circular dependencies") counts as one finding, not per-violation.

---

### PHASE 4 — Documentation Audit

**Step 4.1 — Inventory all docs**

```bash
./skills/repo-health/scripts/scan-docs.sh
```

**Step 4.2 — Completeness check**

Evaluate each doc for:

| Doc Type        | Expected Sections                                        |
| --------------- | -------------------------------------------------------- |
| README          | Overview, Quick Start, Installation, Features, License   |
| CONTRIBUTING    | Dev Setup, PR Process, Coding Standards, Testing Guide   |
| ARCHITECTURE    | System Diagram, Component Map, Data Flow, Decisions      |
| API Reference   | All endpoints/functions, Params, Returns, Errors, Auth   |
| Changelog       | Per-release changes with dates and breaking changes      |

Flag docs missing 2+ expected sections as **INCOMPLETE**.
Flag docs with stale info (links broken, commands that don't match current state) as **INACCURATE**.

**Step 4.3 — Accuracy check**

```bash
./skills/repo-health/scripts/scan-docs.sh --check-links
```

---

### PHASE 5 — OpenSpec Specifications

**Step 5.1 — Locate specs**

```bash
./skills/repo-health/scripts/scan-setup.sh --mode=specs
```

**Step 5.2 — Archive scan**

Specs older than 6 months should be checked separately. Step 5.1 already ran the full spec inventory — review the output above for archived specs under `specs/archive/`, `specs/v0.*/`, or `specs/old/`.

```bash
# Re-run with archive focus if needed:
# ./skills/repo-health/scripts/scan-setup.sh --mode=specs 2>&1 | grep -E 'archive|v0|old'
```

**Step 5.3 — Alignment check**

For each spec:
1. Read the spec requirements (Given/When/Then or plain requirements)
2. Cross-reference with GitNexus — `query({search_query: "requirement keyword"})`
3. Verify implementation exists

```bash
# Automated alignment:
# Scripts/check-spec-alignment.sh specs/
```

Flag: spec requires X but code has no evidence of X implementation.

---

### PHASE 6 — Test Suite Health

**Step 6.1 — Test presence check**

```bash
./skills/repo-health/scripts/scan-tests.sh --check-presence
```

If no test files or no test scripts: **CRITICAL** — tests missing entirely.

**Step 6.2 — Test run with coverage**

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
TIMED_OUT: NN ← if any (should be 0)
```

**Clean run definition:** EXIT_CODE=0, FAILED=0, ERRORS=0, RETRIED=0.
A run with SKIPPED tests is acceptable if skips are documented.

**Step 6.3 — Parse test results**

```bash
./skills/repo-health/scripts/scan-tests.sh --parse-results
```

**Step 6.4 — Slowest tests**

```bash
./skills/repo-health/scripts/scan-tests.sh --slow-tests
```

**Step 6.5 — Coverage analysis**

```bash
./skills/repo-health/scripts/scan-tests.sh --coverage-report
```

Coverage threshold enforcement:
| Coverage   | Action Required                                           |
| ---------- | --------------------------------------------------------- |
| < 50%      | Add tests covering core functionality — prioritize modules |
| 50-80%     | Bring coverage above 80%; identify untested hot paths     |
| >= 80%     | Acceptable; investigate uncovered branches specifically    |

Gap analysis — find untested code:
```bash
# GitNexus for untested symbols:
impact({target: "CriticalModule", direction: "downstream", includeTests: false})

# Or use coverage report:
# Script: find-uncovered.sh /tmp/coverage/
./skills/repo-health/scripts/find-uncovered.sh /tmp/coverage/
```

---

### PHASE 7 — Security Review

**Step 7.1 — Third-party vulnerability scan**

```bash
./skills/repo-health/scripts/scan-security.sh --vuln-scan
```

Aggregate all CVE findings with: **Severity, Package, Current Version, Fixed Version, CWE**.

**Step 7.2 — Static code security scan**

```bash
./skills/repo-health/scripts/scan-security.sh --vuln-scan
```

Common patterns to flag:

| Pattern                         | Severity | Example                          |
| ------------------------------- | -------- | --------------------------------- |
| SQL string concatenation         | CRITICAL | `db.query("SELECT * FROM u WHERE id=" + id)` |
| eval(user_input)                | CRITICAL | `eval(req.body.code)`             |
| innerHTML without sanitize      | HIGH     | `el.innerHTML = userData`         |
| Command injection               | CRITICAL | `exec(userCmd)`                   |
| Hardcoded password/secret       | HIGH     | `password: "hunter2"`             |
| JWT none algorithm              | HIGH     | `{ algorithm: "none" }`           |
| Insecure random                 | MEDIUM   | `Math.random()` for tokens        |
| Path traversal                  | HIGH     | `fs.readFile(userPath)`           |
| XXE                             | HIGH     | XML parsing without safe settings |
| Deserialization of untrusted    | CRITICAL | `pickle.load(userData)`           |
| Missing rate limiting           | MEDIUM   | Auth endpoints without ratelimit  |
| Missing CSRF protection         | HIGH     | Stateful POST without token       |
| Insecure cookie flags           | MEDIUM   | Cookie without httpOnly, secure   |
| Server info disclosure          | LOW      | Banner exposing version in header |

**Step 7.3 — Credential exposure**

```bash
./skills/repo-health/scripts/scan-security.sh --credential-exposure
```

Any committed secret = **CRITICAL** — escalate to immediate remediation.

---

### PHASE 8 — SBOM and License Audit

**Step 8.1 — Generate SBOM**

```bash
./skills/repo-health/scripts/scan-sbom.sh
```

**Step 8.2 — License compliance check**

```bash
./skills/repo-health/scripts/scan-sbom.sh
```

License risk matrix:

| License Family | Risk Level | Notes                                              |
| ------------- | ---------- | -------------------------------------------------- |
| GPL-3.0/AGPL  | HIGH       | Strong copyleft — commercial use restricted        |
| LGPL-3.0      | MEDIUM     | Weak copyleft — can link with closed-source        |
| MPL-2.0       | MEDIUM     | Copyleft with file-level granularity               |
| CPOL/CDDL     | MEDIUM     | Similar to MPL                                     |
| Artistic-2.0  | LOW        | Mostly permissive                                  |
| MIT/BSD/ISC   | NONE       | Permissive                                         |
| Apache-2.0    | NONE       | Permissive, includes patent grant                  |

---

### PHASE 9 — Twelve-Factor App Compliance

**Goal:** Evaluate the project's adherence to the [12-Factor App methodology](https://12factor.net/), a methodology for building SaaS applications that are portable, resilient, and deployable to modern cloud platforms.

**How to use this phase:** For each factor, determine applicability to the project. Some factors may not apply (e.g., a library without backing services, or a CLI tool without a web server). Document N/A factors with a rationale; do NOT count them as failures. Run the checks for applicable factors and report findings.

> **Portability note:** The `grep` commands inside the script use GNU grep BRE alternation (`\|`), which works on Linux natively. On macOS, install GNU grep via `brew install grep` and ensure `ggrep` is available as `grep` in your PATH.

**Step 9.1 — Run all 12-factor checks**

```bash
./skills/repo-health/scripts/scan-12factor.sh
```

Compile the results into a findings table:

```
## 12-FACTOR APP COMPLIANCE

| Factor | Status | Detail |
| ------ | ------ | ------ |
| I. Codebase | ✅ PASS | git repo with single remote |
| II. Dependencies | ⚠️ WARNING | lockfile missing |
| III. Config | ❌ FAIL | hardcoded database config in src/db.js:15 |
| IV. Backing services | ✅ PASS | all services via env var URLs |
| V. Build, release, run | ⚠️ WARNING | no CI/CD found |
| VI. Processes | ✅ PASS | stateless, no sticky sessions |
| VII. Port binding | ✅ PASS | self-contained, port from env |
| VIII. Concurrency | ⚠️ WARNING | no process type definitions |
| IX. Disposability | ❌ FAIL | no SIGTERM handler in main server |
| X. Dev/prod parity | ⚠️ WARNING | sqlite dev vs postgres prod suspected |
| XI. Logs | ✅ PASS | stdout logging, no logfile mgmt |
| XII. Admin processes | ✅ PASS | migrate commands available |
```

**Severity mapping for 12-factor violations:**
- **FAIL**: Flag as MEDIUM (architectural concern, not blocking)
- **FAIL** on Factor III (Config) or Factor VI (Processes): Flag as HIGH (common source of production incidents)
- **FAIL** on Factor XI (Logs) if app manages logfiles directly: Flag as HIGH (operational blind spot)
- **WARNING**: Flag as LOW (document as improvement opportunity)

---

### PHASE 10 — Consolidated Action Plan

Synthesize all findings from PHASEs 1-9 into a **prioritized, actionable plan**.

## Template

```markdown
## Repository Health Audit — Action Plan

**Audited:** `{repo}`
**Date:** `{YYYY-MM-DD}`
**Auditors:** Human (repo-health skill) + automated scanners
---

### SUMMARY

| Dimension           | Status       | Issues Found | Priority |
| ------------------- | ------------ | ------------- | -------- |
| Code Quality        | 🟡 MODERATE  | 12            | HIGH     |
| Linting             | 🟢 CLEAN     | 0             | —        |
| Documentation       | 🔴 POOR      | 6             | MEDIUM   |
| Spec Alignment      | 🟢 GOOD      | 0             | —        |
| Test Suite          | 🔴 POOR      | 4             | HIGH     |
| Security            | 🔴 ISSUES    | 7             | CRITICAL |
| Supply Chain        | 🟡 WARNINGS  | 3             | MEDIUM   |
| 12-Factor App       | 🟡 WARNINGS  | 4             | MEDIUM   |
| Tech Debt           | 🟡 MODERATE  | 8             | MEDIUM   |

### GRADE COMPUTATION

Using the tally counts from the ACTION PLAN, apply the scoring weights from the Grading Rubric section above to arrive at a numeric score, then output:

```
**Overall Grade:** {GRADE} ({POINTS}/100)
```

---

## ACTION PLAN

### 🔴 CRITICAL — Fix Immediately (Blocking Release)

#### C1. [SEVERITY] [One-line description]
- **Evidence:** `file:line` or scanner output
- **Impact:** [Security/testing/business impact]
- **Remediation:** [Concrete fix]
- **Verification:** [Test or command to confirm fixed]

[Repeat for each CRITICAL finding]

---

### 🟠 HIGH — Address Within Sprint

#### H1. ...

[Repeat for each HIGH finding]

---

### 🟡 MEDIUM — Schedule

[Repeat for each MEDIUM finding]

---

### 🟢 LOW — Improve When Possible

[Repeat for each LOW / informational finding]

---

## METRICS SNAPSHOT

### Complexity
- Functions exceeding complexity threshold (15): N
- Highest complexity function: X (complexity=Y)
- Functions exceeding cognitive complexity threshold: N

### Coverage
- Line coverage: XX%
- Branch coverage: XX%
- Files with <50% coverage: N

### Dependencies
- Total packages: NNN
- Outdated by major version: N
- With known vulnerabilities: N
- With restrictive licenses: N

### Documentation
- Missing docs: [list]
- Incomplete docs: [list]
- Stale docs: [list]

---

## APPENDIX: Scanner Outputs

<details>
<summary>Test Suite Output</summary>

```
[paste relevant excerpt]
```

</details>

<details>
<summary>Coverage Report</summary>

```
[table of per-module coverage]
```

</details>

<details>
<summary>Dependency Tree</summary>

```
[paste npm ls or equivalent]
```

</details>

<details>
<summary>Vulnerability Scan</summary>

```
[relevant CVE findings]
```

</details>
```

---

## Helper Scripts Location

Supporting scripts referenced in this skill live at:

```
skills/repo-health/scripts/
├── audit-dependency-usage.sh     # Import-graph dependency audit
├── check-doc-links.sh            # Link-rot checker for markdown docs
├── compare-specs.sh              # Archived vs current spec comparator
├── detect-dead-code.sh           # Static dead-code detector
├── find-duplicates.sh            # Text-similarity duplicate finder
├── find-uncovered.sh             # Uncovered line finder
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
```

Most scripts accept a target directory as `$1`. Exceptions: `scan-licenses.sh` expects an SBOM file path, `parse-test-results.sh` expects a test output file, and `find-uncovered.sh` expects a coverage report path. See each script's usage header for details.

---

## Determinism Guarantee

To ensure consistent, reproducible results across runs:

1. **Always operate on committed HEAD**, never working-tree mixed with staging
2. **Pin all tool versions** in `package.json`'s `engines` or a `.nvmrc`/`.python-version`
3. **Capture environment** with `node --version`, `npm --version`, `python --version`, etc.
4. **Log all scanner stderr** separately — some tools emit important warnings to stderr even on success
5. **Reproducibility check:** Running twice against the same commit should produce identical findings

If a finding cannot be deterministically reproduced, mark it `[NON-DETERMINISTIC — CONFIRM MANUALLY]` and still include in the plan.

---

## Grading Rubric

Convert findings into a numeric score, then map to a letter grade.

### Scoring Weights

| Finding Type | Points Deducted |
|---|---|
| CRITICAL | -25 |
| HIGH | -10 |
| MEDIUM | -3 |
| LOW | -1 |

| Bonuses | Points Added |
|---|---|
| Clean test run (0 failed/errors) | +5 |
| Line coverage >= 80% | +3 |
| Line coverage >= 90% | +3 (additional) |
| Zero CRITICALs | +2 |
| Zero HIGHs | +2 |
| Linter configured and clean (0 violations) | +2 |
| Type checker (tsc/mypy) configured and passing | +1 |
| Zero 12-Factor FAIL findings | +2 |
| All 12-Factor factors PASS or N/A with rationale | +3 |

### Grade Computation Steps

1. **Start at 100 points**
2. **Subtract** point values from all CRITICAL/HIGH/MEDIUM/LOW findings
3. **Add** applicable bonuses
4. **Cap** final score at minimum 0 and maximum 100

### Letter Grade Mapping

| Grade | Numeric Score |
| ----- | ------------- |
| **A** | 90 – 100 |
| **B** | 70 – 89 |
| **C** | 50 – 69 |
| **D** | 25 – 49 |
| **F** | 0 – 24 |

### GRADE COMPUTATION

From tally counts, compute:

```
POINTS = 100
POINTS -= (CRITICAL × 25) + (HIGH × 10) + (MEDIUM × 3) + (LOW × 1)
POINTS += BONUSES as applicable
POINTS = clamp(POINTS, 0, 100)

GRADE =
  POINTS >= 90 ? "A"
  POINTS >= 70 ? "B"
  POINTS >= 50 ? "C"
  POINTS >= 25 ? "D"
  : "F"

Output: **Overall Grade:** {GRADE} ({POINTS}/100)
```