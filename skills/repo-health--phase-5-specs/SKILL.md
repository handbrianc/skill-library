---
name: repo-health--phase-5-specs
description: "INTERNAL SUBSKILL of repo-health. OpenSpec specification alignment — active and archived specs. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 5 — OpenSpec Specifications

## Step 5.1 — Locate Specs

```bash
./skills/repo-health/scripts/scan-setup.sh --mode=specs
```

## Step 5.2 — Archive Scan

Check for archived specs under `specs/archive/`, `specs/v0.*/`, or `specs/old/`.

```bash
./skills/repo-health/scripts/scan-setup.sh --mode=specs 2>&1 | grep -E 'archive|v0|old'
```

## Step 5.3 — Alignment Check

For each spec:
1. Read the spec requirements (Given/When/Then or plain requirements)
2. Cross-reference with GitNexus — `query({search_query: "requirement keyword"})`
3. Verify implementation exists

```bash
# Automated alignment:
# ./skills/repo-health/scripts/compare-specs.sh specs/
```

Flag: spec requires X but code has no evidence of X implementation.
