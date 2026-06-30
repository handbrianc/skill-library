---
name: repo-health
description: "Comprehensive repository health audit — code quality, docs, specs, tests, security, and SBOM. Use when user says 'review this repo', 'audit this project', 'health check', 'quality gate', or requests a full codebase analysis. NOT for PR-scoped or incremental reviews. Examples: 'Conduct a full repository audit', 'Comprehensive code quality review of this project', 'Health check on the codebase'"
---

# Repository Health Audit

A rigorous, deterministic repository audit covering six dimensions. Produces a prioritized, actionable plan when complete.

> **Prerequisite:** Run `node .gitnexus/run.cjs analyze --force` on the target repo before starting (fallback: `npx gitnexus analyze --force` if the local runner doesn't exist). This ensures the knowledge graph reflects current state.

## Scope & Preconditions

**In scope:**
1. Application code quality (smells, architecture, complexity, duplications, dead code)
2. Documentation completeness and accuracy
3. OpenSpec specification alignment (specs, archived specs)
4. Test suite health (coverage, pass/fail, flakiness, performance)
5. Security posture (CVEs, vulnerable code patterns, secrets exposure)
6. Supply-chain health (SBOM, licenses, outdated dependencies)

**Out of scope:** Infrastructure-as-code, CI/CD pipelines themselves, external services.

**Required environment:**
- Node.js >= 18 (for `npx`)
- Git installed and accessible
- For security scan: `npm audit`, `Grype` or `Syft` (container/jar projects)
- For coverage: project's test runner with coverage reporter (vitest, jest, etc.)
- For complexity metrics: `eslint --quiet` with `complexity` rule, or `tsq` for TS

## Phases

---

### PHASE 1 — Setup & Discovery

**Goal:** Understand project structure, tech stack, package manager, and which audit dimensions actually apply.

Run these discovery commands in parallel:

```bash
# Tech stack identification
cat package.json | jq '{name, version, private, engines, scripts}' 2>/dev/null || echo "{}"
ls *.json tsconfig.* pyproject.toml Cargo.toml go.mod Makefile pom.xml build.gradle 2>/dev/null | head -20
git log --oneline -5

# Package manager artifacts
npm ls --depth=0 2>/dev/null | head -40
pnpm list --depth=0 2>/dev/null | head -40
yarn list --depth=0 2>/dev/null | head -40
pip list 2>/dev/null | head -30

# Entry points
ls src/ lib/ app/ cmd/ main.* */main.* 2>/dev/null | head -20
find . -name "__main__.py" -o -name "main.go" 2>/dev/null | head -20

# Documentation locations
ls *.md *.rst *.txt LICENSE* CONTRIBUTING* docs/ wiki/ .github/ 2>/dev/null | head -30

# Specification locations
ls specs/ SPEC.md OPENSPEC* .spec/ spec/ arch/ 2>/dev/null | head -30
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
| Coverage Tool     | @vitest/coverage-v8 |             |
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
# ESLint complexity rule (JS/TS)
npx eslint src/ \
  --rule 'complexity: ["error", 15]' \
  --format json \
  --max-warnings 0 \
  2>/dev/null | jq '.[] | .filePath as $f | .messages[] | select(.ruleId == "complexity") | {file: $f, line: .line, message: .message}'

# For Python:
# radon cc -a -b src/ --max-complexity 10
```

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
# JavaScript/TypeScript:
npx jscpd --threshold 3 --failOn true src/ 2>/dev/null || true

# Python:
# duplicates.py or coverage/runDuplicate.py

# Generic (works on any text):
# Find files with >80% similarity using line-hash
./skills/repo-health/scripts/find-duplicates.sh src/
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

### PHASE 3 — Documentation Audit

**Step 3.1 — Inventory all docs**

```bash
find . -maxdepth 3 \( -name "*.md" -o -name "*.rst" -o -name "*.txt" \) \
  ! -path "./node_modules/*" ! -path "./.git/*" \
  -exec wc -l {} \; | sort -rn | head -30

ls -lh README* INSTALL* CONTRIBUTING* CHANGELOG* AUTHORS* SECURITY* LICENSE*
ls -lh docs/ README.md API.md ARCHITECTURE* DESIGN* GUIDE* 2>/dev/null
```

**Step 3.2 — Completeness check**

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

**Step 3.3 — Accuracy check**

```bash
# Test that quick-start commands actually work
# Install/deploy commands match current versions
# API docs match actual exported signatures

# Check for link rot:
# Scripts/check-doc-links.sh docs/
```

---

### PHASE 4 — OpenSpec Specifications

**Step 4.1 — Locate specs**

```bash
ls -la specs/ OPENSPEC* .spec/ arch/ spec/ 2>/dev/null
find . -maxdepth 4 \( -name "*spec*" -o -name "*SPEC*" -o -name "*requirement*" \) \
  ! -path "./node_modules/*" ! -path "./.git/*" -type f 2>/dev/null | head -40
```

**Step 4.2 — Archive scan**

Specs older than 6 months should be checked separately:

```bash
# List archived specs:
ls -lt specs/archive/ specs/v0.*/ specs/old/ 2>/dev/null

# Check for inconsistencies between archived and current:
# Scripts/compare-specs.sh specs/current specs/archive/
```

**Step 4.3 — Alignment check**

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

### PHASE 5 — Test Suite Health

**Step 5.1 — Test presence check**

```bash
ls tests/ __tests__/ test/ spec/ *.test.* *.spec.* *-test.* *_test.* 2>/dev/null | head -20
cat package.json | jq '.scripts | to_entries[] | select(.key | test("test|spec|cover"))'
```

If no test files or no test scripts: **CRITICAL** — tests missing entirely.

**Step 5.2 — Test run with coverage**

```bash
# Run the full test suite — NO timeout abort
# Allow sufficient time for full run (up to 10 minutes)
vitest run --coverage --reporter=verbose 2>&1 | tee /tmp/test-output.txt
# OR
jest --coverage --coverageReporters=text-summary 2>&1 | tee /tmp/test-output.txt
# OR
pytest --cov=. --cov-report=term-missing -v 2>&1 | tee /tmp/test-output.txt
# OR
go test -coverprofile=/tmp/cover.out -v ./... 2>&1 | tee /tmp/test-output.txt

EXIT_CODE=$?
echo "TEST_EXIT_CODE: $EXIT_CODE"
```

**Rule: Use a generous timeout (e.g., 10+ minutes) and treat timeouts as failures requiring investigation.**

**Step 5.3 — Parse test results**

```bash
# Script: parse-test-results.sh /tmp/test-output.txt
./skills/repo-health/scripts/parse-test-results.sh /tmp/test-output.txt
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

**Step 5.4 — Slowest tests**

```bash
# From test output, extract timing:
grep -E "^  (✓|✗|○|●|[A-Z]) .+ \[.*\]$" /tmp/test-output.txt \
  | grep -oE '\[[0-9]+\.?[0-9]*s\]' | sort -t'[' -k2 -rn | head -20

# Or for Jest verbose:
grep -E "(slow|ms|SLOW)" /tmp/test-output.txt | sort -rn | head -20
```

Root-cause categories:
- **Network I/O in test** — mock it
- **Database query in test** — seed fixture or mock
- **Large fixture loading** — use smaller fixture or factory
- **Sleep/wait in test** — replace with event-based wait
- **Complex computation** — precompute fixture

**Step 5.5 — Coverage analysis**

From coverage report:

```bash
# Extract line/branch coverage %:
grep -E "(Coverage|Total|All files)" /tmp/test-output.txt | tail -20
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

### PHASE 6 — Security Review

**Step 6.1 — Third-party vulnerability scan**

```bash
# npm audit
npm audit --production --audit-level=moderate 2>&1 | tee /tmp/npm-audit.txt

# For Python:
# pip-audit -r requirements.txt

# For container/containerized projects:
syft . -o cyclonedx-json > /tmp/sbom.json
grype sbom:/tmp/sbom.json --scope=deps 2>&1 | tee /tmp/grype.txt
```

Aggregate all CVE findings with: **Severity, Package, Current Version, Fixed Version, CWE**.

**Step 6.2 — Static code security scan**

```bash
# Semgrep SAST scan:
semgrep --config=auto --json src/ 2>/dev/null | jq '[.results[] | {rule: .check_id, file: .path, line: .start.line, severity: .extra.severity}]'

# ESLint security plugin:
npx eslint src/ --plugin=security --format json 2>/dev/null | jq '.'

# Secrets scanning:
# Scripts/scan-secrets.sh src/
./skills/repo-health/scripts/scan-secrets.sh src/
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

**Step 6.3 — Credential exposure**

```bash
git log --all --full-history -p \
  -- .env* *.env* secrets.* credentials.* 2>/dev/null | grep -iE "password|secret|apikey|token" \
  | grep -v "^[-+]#\|^#\|Binary" | head -50
```

Any committed secret = **CRITICAL** — escalate to immediate remediation.

---

### PHASE 7 — SBOM and License Audit

**Step 7.1 — Generate SBOM**

```bash
# Syft (preferred for speed and accuracy):
syft . -o spdx-json > /tmp/sbom.spdx.json
syft . -o table > /tmp/sbom.txt

# OR npm for JS-only:
npm ls --all --omit=dev > /tmp/npm-tree.txt

# OR spdx-builder for multi-lang:
```

**Step 7.2 — License compliance check**

```bash
# Scan for copyleft / restrictively licensed deps:
# Scripts/scan-licenses.sh /tmp/sbom.spdx.json
./skills/repo-health/scripts/scan-licenses.sh /tmp/sbom.spdx.json

# Common flags:
# GPL-3.0, LGPL-3.0, MPL-2.0, CC-SA-*, EUPL-1.2 → RESTRICTIVE
# Apache-2.0, MIT, BSD-2-Clause, BSD-3-Clause, ISC, Unlicense → PERMISSIVE
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

### PHASE 8 — Consolidated Action Plan

Synthesize all findings into a **prioritized, executable plan**.

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
| Documentation       | 🔴 POOR      | 6             | MEDIUM   |
| Spec Alignment      | 🟢 GOOD      | 0             | —        |
| Test Suite          | 🔴 POOR      | 4             | HIGH     |
| Security            | 🔴 ISSUES    | 7             | CRITICAL |
| Supply Chain        | 🟡 WARNINGS  | 3             | MEDIUM   |

**Overall Grade:** D / 100

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
├── detect-dead-code.sh      # Static dead-code detector
├── find-duplicates.sh       # Text-similarity duplicate finder
├── scan-cognitive-complexity.sh  # Cyclomatic+cognitive metric scanner
├── audit-dependency-usage.sh     # Import-graph dependency audit
├── check-doc-links.sh       # Link-rot checker for markdown docs
├── compare-specs.sh         # Archived vs current spec comparator
├── parse-test-results.sh    # Test output parser
├── find-uncovered.sh        # Uncovered line finder
├── scan-secrets.sh          # Secret/credential scanner
├── scan-licenses.sh         # SPDX license risk assessor
└── run-scan-suite.sh        # Master script — runs all deterministically
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

Apply this overall grade after compiling all findings:

| Grade | Criteria                                                    |
| ----- | ----------------------------------------------------------- |
| **A** | Zero CRITICALs, <=3 HIGHs, coverage >=90%, clean test run   |
| **B** | Zero CRITICALs, <=5 HIGHs, coverage >=80%, clean test run   |
| **C** | <=2 CRITICALs, <=10 HIGHs, coverage >=70%                   |
| **D** | Up to 5 CRITICALs, any coverage, test suite mostly passing   |
| **F** | More than 5 CRITICALs, or test suite not passing, or SECRETS COMMITTED |