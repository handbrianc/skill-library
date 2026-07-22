---
name: repo-health--phase-10-action-plan
description: "INTERNAL SUBSKILL of repo-health. Synthesizes all phase findings into prioritized action plan. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 10 — Consolidated Action Plan

Synthesize all findings from PHASEs 1-9 into a prioritized, actionable plan.

Use the grading rubric from the `repo-health--helpers` subskill for scoring.

## Template

```markdown
## Repository Health Audit — Action Plan

**Audited:** `{repo}`
**Date:** `{YYYY-MM-DD}`
---

### SUMMARY

| Dimension | Status | Issues Found | Priority |
| --------- | ------------ | ------------- | -------- |
| Code Quality | 🟡 MODERATE | 12 | HIGH |
| Linting | 🟢 CLEAN | 0 | — |
| Documentation | 🔴 POOR | 6 | MEDIUM |
| Spec Alignment | 🟢 GOOD | 0 | — |
| Test Suite | 🔴 POOR | 4 | HIGH |
| Security | 🔴 ISSUES | 7 | CRITICAL |
| Supply Chain | 🟡 WARNINGS | 3 | MEDIUM |
| 12-Factor App | 🟡 WARNINGS | 4 | MEDIUM |
| Tech Debt | 🟡 MODERATE | 8 | MEDIUM |

### GRADE COMPUTATION

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
- Functions exceeding threshold (15): N
- Highest complexity function: X (complexity=Y)

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
```

Load the helpers subskill for the grading rubric before computing the final grade.
