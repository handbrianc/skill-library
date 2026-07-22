---
name: repo-health--phase-3-tech-debt
description: "INTERNAL SUBSKILL of repo-health. Technical debt profile — markers, architecture, technology currency, test debt, API surface, error handling. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 3 — Technical Debt Review

**Goal:** Assess architectural and systemic technical debt that standard code-quality metrics miss. Requires PHASE 2 (code quality) and PHASE 6 (test suite) results.

## Run

```bash
./skills/repo-health/scripts/scan-tech-debt.sh
```

## Produce

### Marker Debt
```
| Category | Count | Severity |
|----------|-------|----------|
| TODO     | 23    | —        |
| FIXME    | 5     | —        |
| HACK     | 8     | MEDIUM   |
| XXX      | 2     | —        |
| WORKAROUND | 3   | LOW      |
| **Total**  | **41** | **MEDIUM** |
| Marker density | 2.3/1000 LOC | LOW |
```

### Architecture Debt
| Finding | Severity |
|---------|----------|
| Circular dependencies: N | HIGH |
| Layer violations: N | MEDIUM |
| God modules: N | MEDIUM |
| Barrel files: N | LOW |

### Technology Debt
| Finding | Severity |
|---------|----------|
| Node X.x (current LTS: Y.y) | MEDIUM |
| TypeScript X.x (current: Y.y) | MEDIUM |

### Test Debt
| Finding | Severity |
|---------|----------|
| Test:Production ratio X | MEDIUM |
| Sleep-based tests: N | MEDIUM |
| Over-mocked tests: N | LOW |
| Avg test time: Nms | LOW |

### API Surface Debt
| Finding | Severity |
|---------|----------|
| Unused exports: N | MEDIUM |
| Hotspot files (>20 changes/6mo): N | LOW |

### Error Handling Debt
| Finding | Severity |
|---------|----------|
| Empty catch blocks: N | HIGH |
| X% ad-hoc console.log vs structured logging | MEDIUM |
| No error boundaries | MEDIUM |

### Overall Rating
- **LOW**: Minor, schedule when convenient
- **MEDIUM**: Plan within next quarter
- **HIGH**: Actively causing friction — prioritize
- **CRITICAL**: Blocking velocity or creating production risk

**Scoring:** Each distinct finding type = 1 finding. HIGH = -10, MEDIUM = -3, LOW = -1.
