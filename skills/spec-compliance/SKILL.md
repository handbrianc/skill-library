---
name: spec-compliance
description: "Verify that code and tests meet specifications defined in openspec/specs folders. Use when user says 'check spec compliance', 'verify specs are met', 'spec coverage', 'are specs reflected in tests', 'compliance audit', or requests to verify that implementation matches specification. Examples: 'Verify all specs are covered by tests', 'Check which requirements have no code implementation', 'Audit spec compliance across archived and active specs'"
---

# Spec Compliance Verifier

Checks that application code and test suites provably satisfy specifications defined in `openspec/` or `specs/` folders. Operates bidirectionally: (1) specs → code evidence and (2) specs → test evidence.

> **Prerequisite:** Run `npx gitnexus analyze --force` on the target repo before starting to ensure the knowledge graph is fresh.

## Critical Constraints

### MUST DO
- Treat both **active** and **archived** specs with equal rigor — archived specs represent commitments too
- Distinguish three separate compliance states: **implemented** (code exists), **test-proven** (tests assert it), and **fully-compliant** (both)
- Report every requirement with at least one divergence (no code evidence OR no test evidence) as a distinct finding
- Prioritize findings by: CRITICAL (security-relevant requirement unmet) > HIGH > MEDIUM > LOW

### MUST NOT DO
- Never claim a spec is "met" without showing concrete file-level evidence (not just plausible-sounding queries)
- Never ignore archived specs — they may contain requirements still implemented but no longer actively maintained
- Never rely solely on the existence of tests — tests must actually exercise the requirement's intent
- Never conflate "implemented" with "proven by tests" — these are separate compliance axes

---

## Two-Axis Compliance Model

Every requirement has **two independent compliance axes**:

| Axis | Question | Detection Method |
|------|----------|------------------|
| **Code Compliance** | Does production code implement the requirement? | `query(search_query:)` for requirement keywords → `gitnexus_context()` on matched symbols |
| **Test Compliance** | Do tests prove the code satisfies the requirement's intent? | Test file analysis linked to requirement-verifying functions |

**Combined Status:**
- `✅ FULLY COMPLIANT` — code implements AND tests prove it
- `🟡 PARTIAL (code only)` — code exists, no test proof
- `🟡 PARTIAL (test only)` — tests exist, no identifiable code path
- `❌ NON-COMPLIANT` — neither code nor test evidence found

---

## Six Phases

---

### PHASE 1 — Spec Discovery

**Goal:** Locate and enumerate all specification files in the project, classified as active or archived.

```bash
# Primary discovery
ls openspec/ 2>/dev/null
ls specs/ 2>/dev/null
find . -maxdepth 4 \( -name "*.spec" -o -name "*spec*.md" -o -name "SPEC*" -o -name "*requirement*" -o -name "*.frs" \) ! -path "./node_modules/*" ! -path "./.git/*" -type f 2>/dev/null

# Archive discovery (specs older than 6 months or in explicit archive dirs)
ls openspec/archive/ 2>/dev/null
ls specs/archive/ 2>/dev/null
ls specs/v0.*/ 2>/dev/null
ls specs/old/ 2>/dev/null

# Alternative naming conventions
find . -maxdepth 4 -type d \( -name "archive" -o -name "legacy" -o -name "deprecated" \) 2>/dev/null | head -10
```

**Inventory Table:**

```
| Spec File                     | Classification | Age/Location    | Requirement Count |
| ----------------------------- | -------------- | ---------------- | ----------------- |
| openspec/auth.spec            | ACTIVE         | current          | 12                |
| openspec/api-requirements.md  | ACTIVE         | current          | 8                 |
| specs/archive/v0.1-auth.md    | ARCHIVED       | >6 months        | 15                |
| specs/archive/old-api.md      | DEPRECATED     | explicit archive | 6                 |
```

**Classification Rules:**
- Active: in root `specs/` or `openspec/` with no archive marker
- Archived: in `*/archive/*`, `*/v*/*`, `*/old/*`, `*/legacy/*`, or modified >6 months ago
- Deprecated: explicitly named with `deprecated`, `archive`, `old` in path

---

### PHASE 2 — Requirement Extraction

**Goal:** Parse each spec file into individual requirement statements using multiple regex patterns.

**Extraction Patterns (checked in order for each line):**

| Priority | Pattern | Regex | Means |
|----------|---------|-------|-------|
| 1 | Explicit marker | `^(?:.*?)(REQUIREMENT|RFP-|SRS-|USER STORY|TICKET):\s*(.+)$` | Named requirement |
| 2 | Gherkin BDD | `^\s*(GIVEN|WHEN|THEN|AND|BACKGROUND|SCENARIO)\s+(.+)$` | Scenario step |
| 3 | Checkbox item | `^\s*-\s+\[(x| )\]\s*(.+)$` | Checklist item (checked or unchecked) |
| 4 | Capital sentence | `^[A-Z][A-Za-z0-9\s]{20,}[.:]$` | Prose requirement (min 20 chars, ends . or :) |
| 5 | Numbered item | `^(?:\d+[.)]|\([a-z]\))\s*(.+)$` | Numbered sequence item |
| 6 | Quoted directive | `^["'].{15,}["']\s*$` | Longer quoted requirement |

**Extraction Commands:**

```bash
# Per-file extraction with line numbers (preserve for later evidence linking)
# Output format: LINE_NUM|PATTERN_TYPE|EXTRACTED_TEXT

for spec in $(find openspec/ specs/ -type f \( -name "*.md" -o -name "*.txt" -o -name "*.spec" \) 2>/dev/null); do
  echo "=== $spec ==="
  grep -n -E 'REQUIREMENT:|RFP-|SRS-|USER STORY:|GIVEN|WHEN|THEN|AND\b|-\s+\[.\]|^\s*\d+[.)]\s|^\s*\([a-z]\)\s|^["'"'"'][A-Z].{15,}["'"'"']$' "$spec" | head -100
done
```

**Example Extracted Requirements:**

```
42|GHERKIN_THEN|The response shall include a paginated list|
45|CHECKBOX_X|Rate limiting enforces 100 req/min|
67|PROSE|Authentication tokens expire after 24 hours.|
89|MARKER|Data must be encrypted at rest and in transit.|
103|NUMBERED|1. All inputs must be validated before processing.|
```

**Categorization:**
- `GHERKIN_GIVEN` / `GHERKIN_WHEN` / `GHERKIN_THEN` / `GHERKIN_AND` — Individual Gherkin lines extracted separately
- `GHERKIN_BLOCK` — SCENARIO/BACKGROUND/FEATURE block headers
- `CHECKBOX_X` — Checkbox item marked `[x]` (requirement satisfied in spec)
- `CHECKBOX_` — Checkbox item marked `[ ]` (future/dropped requirement)
- `PROSE` — Capital-sentence prose requirements (≥20 chars, ends in `.` or `:`)
- `MARKER` — Explicit REQUIREMENT:/RFP-/SRS- prefixed items (highest confidence)
- `NUMBERED` — Numbered sequence items (`1.` or `(a)` style)

---

### PHASE 3 — Code Compliance Check

**Goal:** For each extracted requirement, determine if production code implements it.

**Workflow:**

```
For each requirement_text:
  1. Strip noise words: "shall", "must", "should", "will", "the", "that"
  2. Build search query from key nouns/verbs
  3. Run query({search_query: cleaned_keywords, goal: "implementation"})
  4. If results found → record file locations, symbol names
  5. If no results → run query with alternate phrasing
  6. If still no results → mark as MISSING_CODE_COMPLIANCE
```

**Detailed Search Strategy:**

```bash
# Phase 3 Step 1: Extract searchable terms from requirement
# Example: "The system shall enforce rate limiting of 100 req/min"
# → KEYWORDS: "rate limiting", "req/min", "throttle", "rate limit enforcement"

# Phase 3 Step 2: Primary GitNexus query
query({
  search_query: "rate limiting throttle enforcement",
  goal: "find code that implements rate limiting/throttling",
  limit: 5
})

# Phase 3 Step 3: Fallback queries with synonyms
query({ search_query: "request throttling", goal: "alternate phrasing" })
query({ search_query: "api limits enforced", goal: "variant wording" })

# Phase 3 Step 4: Symbol drill-down (if query returned results)
gitnexus_context({
  name: "rateLimit",
  include_content: true
})
```

**Compliance Determination:**

```
FULL_CODE_EVIDENCE  — query() call returned ≥1 high-confidence result AND
                       gitnexus_context confirmed production code involvement
PARTIAL_CODE_EVIDENCE — query returned fuzzy match (confidence < 0.7)
                        OR only infrastructure/config files (not core logic)
MISSING_CODE_COMPLIANCE — Zero results across all query variations
```

**Example Tracking Table:**

```
| Req ID | Requirement Text                  | Evidence Found                  | Status              |
| ------- | --------------------------------- | ------------------------------- | ------------------- |
| R-042   | Rate limiting enforces 100 req/min| src/middleware/ratelimit.ts     | FULL_CODE_EVIDENCE  |
| R-043   | Tokens expire after 24 hours      | src/auth/token.ts (partial)     | PARTIAL_CODE_EVIDENCE |
| R-044   | Data encrypted at rest            | NO_RESULTS                      | MISSING_CODE_COMPLIANCE |
```

---

### PHASE 4 — Test Compliance Check

**Goal:** For each extracted requirement, determine if tests prove the implementation meets the intent.

**Critical Distinction:**
> **Phase 3 asks:** "Does code implement the requirement?"
> **Phase 4 asks:** "Do TESTS prove that the implementation satisfies the requirement's intent?"

This is not the same as code coverage. A function covered by tests may still not test the specific requirement.

**Workflow:**

```
For each requirement with FULL_CODE_EVIDENCE or PARTIAL_CODE_EVIDENCE:
  1. Identify the implementation file(s) and symbol(s) from Phase 3
  2. Find test files associated with those symbols
  3. Analyze test assertions to determine if they validate the requirement
  4. Classify as: FULL_TEST_PROOF | PARTIAL_TEST_PROOF | NO_TEST_PROOF
```

**Test Discovery Methods:**

```bash
# Via GitNexus (if indexed):
query({
  search_query: "ratelimit test spec-compliant",
  goal: "find tests that verify rate limiting behavior",
  limit: 5
})

# Via file system patterns:
find . -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.*" -o -name "*-test.*" \) \
  ! -path "./node_modules/*" 2>/dev/null | head -50

# Via test directory scanning:
ls tests/ __tests__/ test/ spec/ 2>/dev/null
```

**Assertion Analysis (manual inference from test files):**

For each test file suspected of covering the requirement:

1. **Read the test file**
2. **Identify the assertion(s)**
3. **Map assertion to requirement intent:**

```
Requirement Intent: "rate limiting enforces 100 req/min"
Validating Assertion: expect(throttledRequests.length).toBeLessThanOrEqual(100)
→ FULL_TEST_PROOF ✓

Requirement Intent: "authentication tokens expire after 24 hours"
Validating Assertion: expect(token.expiresAt).toBeBefore(now + 25hours)
→ FULL_TEST_PROOF ✓

Requirement Intent: "data must be encrypted at rest"
Supporting But Insufficient: Encryption tested for transit but not rest
→ PARTIAL_TEST_PROOF ⚠

Requirement Intent: "API responds within 200ms"
No Timing Assertion Found
→ NO_TEST_PROOF ✗
```

**Test Quality Criteria:**

| Criterion | Meaning |
|-----------|---------|
| Specific assertion exists | Test explicitly asserts the requirement condition |
| Boundary conditions tested | Edges (0, null, max, overflow) are tested |
| Negative cases tested | Invalid inputs are asserted to be rejected |
| Mock boundaries correct | External deps mocked at appropriate abstraction |

**Tracking Table Extension:**

```
| Req ID | Code Status      | Test Evidence                    | Test Quality    | Overall Status |
| ------- | ---------------- | -------------------------------- | ---------------- | -------------- |
| R-042   | FULL_CODE_EVIDENCE | tests/unit/ratelimit.test.ts   | SPECIFIC_ASSERT | ✅ FULL COMPLIANCE |
| R-043   | PARTIAL_CODE_EVIDENCE | tests/auth.token.test.ts (weak)| BOUNDARY_MISSING | 🟡 PARTIAL |
| R-044   | MISSING_CODE_COMPLIANCE | (no code, cannot test)       | N/A              | ❌ NON-COMPLIANT |
```

---

### PHASE 5 — Archival Analysis

**Goal:** Compare archived spec requirements against current state to detect regressions or latent implementations.

**Discovery:**

```bash
# List all archived specs
for dir in openspec/archive specs/archive specs/v0.* specs/old specs/archive/backup; do
  ls -la "$dir" 2>/dev/null
done
```

**Comparison Method:**

For each requirement in an archived spec:

```
1. Extract requirement (same parser as Phase 2)
2. Search current codebase for implementation (Phase 3 method)
3. Search current tests for coverage (Phase 4 method)
4. If FOUND: Check if still satisfies current product needs
   → May be INTENTIONAL OMISSION (deliberately removed feature)
   → May be LATENT FEATURE (still implemented but no longer spec'd)
5. If NOT FOUND: Likely deprecated requirement — flag as STALE_ARCHIVED
```

**Divergence Scenarios:**

| Scenario | Archived Has | Current Has | Implication |
|----------| ------------ | ----------- | ------------|
| Feature Regression | Requirement R existed | No code evidence | Removed functionality, intentional or accidental |
| Spec Drift | No archived requirement | Code implements R | New capability, needs spec update |
| Latent Implementation | Archived R | Code + test evidence | Currently compliant despite archive status |
| Silent Deprecation | Requirement R in archived | Neither code nor test | Fully retired capability |

**Tracking Table:**

```
| Archived Spec         | Requirement        | Current Status       | Classification          |
| --------------------- | ------------------ | -------------------- | ------------------------ |
| v0.1-auth.md R-015    | Session persistence | NO code or test    | STALE_ARCHIVED          |
| v0.1-auth.md R-016    | Remember Me token  | EXISTS (auth/rm.ts) | LATENT_IMPLEMENTATION   |
| old-api.md R-003      | SOAP XML API       | NO code              | INTENTIONAL_REGRESSION  |
```

Flag STALE_ARCHIVED findings at MEDIUM priority (requirements may still have business value).

---

### PHASE 6 — Compliance Reporting

**Goal:** Synthesize all six phases into a prioritized, actionable report.

**Output Format:**

```markdown
## Spec Compliance Report

**Audited:** `{repo}`
**Date:** `{YYYY-MM-DD}`
**Specs Scanned:** N active, M archived
**Total Requirements:** X extracted

---

### COMPLIANCE DASHBOARD

| Spec File           | Total Reqs | Fully Compliant | Partial | Non-Compliant | Compliance % |
| ------------------- | ---------- | --------------- | ------- | ------------- | ------------ |
| openspec/auth.spec  | 12         | 9               | 2       | 1             | 83%          |
| openspec/api-req.md | 8          | 6               | 1       | 1             | 81%          |
| specs/archive/v0.1  | 15         | 4               | 3       | 8             | 27%          |
| **OVERALL**         | **35**     | **19**          | **6**   | **10**        | **54%**      |

---

### TWO-AXIS STATUS MATRIX

| Req ID | Requirement Text                    | Code Status | Test Status | Combined |
| ------- | ----------------------------------- | ----------- | ----------- | -------- |
| R-001   | Rate limiting: 100 req/min          | ✅ Present  | ✅ Proven   | ✅ FULL  |
| R-002   | Token expiry: 24 hours              | ✅ Present  | ⚠️ Weak    | 🟡 PARTIAL |
| R-003   | Data encryption at rest             | ❌ Absent   | N/A         | ❌ FAIL  |
| R-004   | API response time < 200ms           | ✅ Present  | ❌ No timing| 🟡 PARTIAL |
| ...     | ...                                 | ...         | ...         | ...      |

---

### FINDINGS (Prioritized)

#### 🔴 CRITICAL — Security/Compliance Requirements Unmet

**[C1]** REQUIREMENT: "Data must be encrypted at rest"
- **Spec:** openspec/data-security.md:89
- **Code Evidence:** NONE — no disk encryption found in codebase
- **Test Evidence:** N/A
- **Impact:** Regulatory non-compliance (GDPR, SOC2), data breach risk
- **Remediation:** Implement AES-256 encryption at storage layer; add `EncryptedStorage` class

**[C2]** REQUIREMENT: "Authentication required for all API endpoints"
- **Spec:** openspec/auth.spec:R-005
- **Code Evidence:** `src/api/publicRoutes.ts` exposes unauthenticated endpoints
- **Test Evidence:** No auth-check assertions on `GET /api/health`
- **Impact:** Unauthenticated administrative access possible
- **Remediation:** Require auth middleware on `GET /api/health` or document exception

---

#### 🟠 HIGH — Functional Requirements Partially Met

**[H1]** REQUIREMENT: "Tokens expire after 24 hours"
- **Spec:** openspec/auth.spec:R-007
- **Code Evidence:** `src/auth/token.ts` implements 24h expiry (token.ts:42)
- **Test Evidence:** `tests/auth.test.ts` tests only 23h and 25h — never precisely 24h
- **Impact:** Boundary condition at exactly 24h untested — potential off-by-one
- **Remediation:** Add test case for `expiresAt === 24h` (86400000ms)

---

#### 🟡 MEDIUM — Test Coverage Gaps

**[M1]** REQUIREMENT: "API response time < 200ms"
- **Spec:** openspec/perf.md:R-012
- **Code Evidence:** `src/api/handler.ts` — no perf benchmarks found
- **Test Evidence:** No timing assertions in `tests/api.test.ts`
- **Impact:** Performance regression undetected
- **Remediation:** Add `describe('performance')` with `expect(responseTime).toBeLessThan(200)`

---

#### 🟢 LOW — Informational / Archived Spec Findings

**[L1]** STALE: "Remember Me" persistent sessions (archived v0.1 R-016)
- **Spec:** specs/archive/v0.1-auth.md:R-016
- **Code Evidence:** EXISTS in `src/auth/remember.ts` — still implemented!
- **Test Evidence:** Tests exist in `tests/auth-remember.test.ts`
- **Classification:** LATENT_FEATURE — requirement dropped from active spec but still shipped
- **Recommendation:** Decide: re-add to active spec, or remove feature code

---

### ARCHIVED-SPEC REGRESSIONS

| Archived Requirement | Was In | Current Status | Recommendation |
| -------------------- | ------ | -------------- | --------------- |
| Session affinity fallback | v0.1-auth:R-022 | NO code found  | Investigate — may be intentional removal |
| Legacy SOAP interface | old-api:R-003 | NO code found  | Confirm deprecation, clean archived spec |

---

### RECOMMENDED ACTIONS

1. **[IMMEDIATE]** Implement data-at-rest encryption (`C1`)
2. **[THIS SPRINT]** Add 24h boundary test for token expiry (`H1`)
3. **[NEXT SPRINT]** Add API performance timing assertions (`M1`)
4. **[DISCUSSION]** Resolve `Remember Me` feature status — spec drift (`L1`)

---

## Appendix: Extracted Requirements Log

<details>
<summary>All extracted requirements by file</summary>

```
openspec/auth.spec (12 requirements)
  R-001: "Rate limiting: 100 req/min" .............. ✅ FULL
  R-002: "Token expiry: 24 hours" ................. 🟡 PARTIAL
  ...

openspec/api-req.md (8 requirements)
  R-009: "GET /users returns paginated list" ...... ✅ FULL
  ...
```

</details>

---

## Helper Scripts

Supporting scripts live at:

```
skills/spec-compliance/scripts/
├── compare-specs.sh        # Archived vs current spec extractor + delta reporter
└── extract-requirements.sh # Standalone requirement parser with pattern matching
```

### compare-specs.sh Usage

```bash
./skills/spec-compliance/scripts/compare-specs.sh openspec/ specs/archive/
# Output: formatted table of spec_file, archived/current requirement counts, archive presence, and comparison status
```

### extract-requirements.sh Usage

```bash
./skills/spec-compliance/scripts/extract-requirements.sh openspec/auth.spec
# Output: LINE_NUM|PATTERN_TYPE|EXTRACTED_TEXT per requirement
```