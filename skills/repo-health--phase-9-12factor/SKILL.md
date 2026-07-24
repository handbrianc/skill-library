---
name: repo-health--phase-9-12factor
description: "INTERNAL SUBSKILL of repo-health. 12-Factor App methodology compliance check. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 9 — Twelve-Factor App Compliance

**Goal:** Evaluate adherence to the [12-Factor App methodology](https://12factor.net/).

Determine applicability per factor. Document N/A factors with rationale — do NOT count as failures.

## Run

```bash
./skills/repo-health/scripts/scan-12factor.sh
```

## Report Format

```
| Factor | Status | Detail |
| ------ | ------ | ------ |
| I. Codebase | ✅ PASS | git repo with single remote |
| II. Dependencies | ⚠️ WARNING | lockfile missing |
| III. Config | ❌ FAIL | hardcoded config in src/db.js:15 |
| IV. Backing services | ✅ PASS | all services via env var URLs |
| V. Build, release, run | ⚠️ WARNING | no CI/CD found |
| VI. Processes | ✅ PASS | stateless, no sticky sessions |
| VII. Port binding | ✅ PASS | self-contained, port from env |
| VIII. Concurrency | ⚠️ WARNING | no process type definitions |
| IX. Disposability | ❌ FAIL | no SIGTERM handler |
| X. Dev/prod parity | ⚠️ WARNING | sqlite dev vs postgres prod |
| XI. Logs | ✅ PASS | stdout logging, no logfile mgmt |
| XII. Admin processes | ✅ PASS | migrate commands available |
```

## Severity Mapping

- **FAIL** → MEDIUM (architectural concern)
- **FAIL** on Factor III (Config) or Factor VI (Processes) → HIGH (common production incidents)
- **FAIL** on Factor XI (Logs) if managing logfiles directly → HIGH (operational blind spot)
- **WARNING** → LOW (improvement opportunity)
