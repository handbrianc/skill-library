---
name: repo-health--phase-8-sbom
description: "INTERNAL SUBSKILL of repo-health. SBOM generation and license compliance audit. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 8 — SBOM and License Audit

## Step 8.1 — Generate SBOM

```bash
./skills/repo-health/scripts/scan-sbom.sh
```

## Step 8.2 — License Compliance Check

```bash
./skills/repo-health/scripts/scan-sbom.sh
```

### License Risk Matrix

| License Family | Risk Level | Notes |
| ------------- | ---------- | -------------------------------------------------- |
| GPL-3.0/AGPL | HIGH | Strong copyleft — commercial use restricted |
| LGPL-3.0 | MEDIUM | Weak copyleft — can link with closed-source |
| MPL-2.0 | MEDIUM | Copyleft with file-level granularity |
| CPOL/CDDL | MEDIUM | Similar to MPL |
| Artistic-2.0 | LOW | Mostly permissive |
| MIT/BSD/ISC | NONE | Permissive |
| Apache-2.0 | NONE | Permissive, includes patent grant |
