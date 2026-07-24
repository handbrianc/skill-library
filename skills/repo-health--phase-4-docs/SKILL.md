---
name: repo-health--phase-4-docs
description: "INTERNAL SUBSKILL of repo-health. Documentation audit — inventory, completeness, accuracy. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 4 — Documentation Audit

## Step 4.1 — Inventory All Docs

```bash
./skills/repo-health/scripts/scan-docs.sh
```

## Step 4.2 — Completeness Check

| Doc Type | Expected Sections |
| --------- | -------------------------------------------------------- |
| README | Overview, Quick Start, Installation, Features, License |
| CONTRIBUTING | Dev Setup, PR Process, Coding Standards, Testing Guide |
| ARCHITECTURE | System Diagram, Component Map, Data Flow, Decisions |
| API Reference | All endpoints/functions, Params, Returns, Errors, Auth |
| Changelog | Per-release changes with dates and breaking changes |

Flag missing 2+ sections → **INCOMPLETE**.
Flag stale info (broken links, outdated commands) → **INACCURATE**.

## Step 4.3 — Accuracy Check

```bash
./skills/repo-health/scripts/scan-docs.sh --check-links
```
