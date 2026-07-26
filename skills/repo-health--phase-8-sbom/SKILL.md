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

## Step 8.3 — CVE & Outdated Dependency Classification

### CRITICAL Severity Rules (MANDATORY)

| Condition | Severity | Rationale |
| ----------- | ---------- | ----------- |
| Any dependency has a known CVE (any severity) | **CRITICAL** | Exploitable attack surface — do NOT downgrade |
| Any dependency outdated by a major version | **CRITICAL** | Missing security patches, known-vulnerable surface |
| GPL-3.0/AGPL licensed dependency | HIGH | Strong copyleft — commercial use restricted (stays HIGH) |
| Dependency outdated by minor version with CVE in changelog | **CRITICAL** | Same class as major-outdated with CVE |

All CRITICAL SBOM/CVE findings MUST flow into the remediation loop (Phase 10). Do NOT classify them as MEDIUM or HIGH.

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

---

## ⚠️ Known Failure Modes

### syft may not be installed

The `scan-sbom.sh` script depends on `syft` for SBOM generation. If `syft` is not
available (Phase 0 check shows `TOOL_MISSING: syft`), the entire scan-sbom.sh run
produces no useful output.

**Fallback — Manual dependency inventory:** When syft is missing, do not run scan-sbom.sh.
Instead, manually inventory dependencies:

```bash
# Find all package manifests
echo "=== MANUAL DEPENDENCY INVENTORY ==="
find . -name 'package.json' -not -path '*/node_modules/*' -maxdepth 3
find . -name 'requirements.txt' -not -path '*/node_modules/*' -maxdepth 3
find . -name 'Cargo.toml' -not -path '*/target/*' -maxdepth 3
find . -name 'go.mod' -not -path '*/vendor/*' -maxdepth 3
find . -name 'Gemfile' -maxdepth 3
find . -name 'Pipfile' -maxdepth 3

# For each found manifest, extract dependency names and versions
# Report: "No package manager at root — SBOM N/A" if none found
```

### scan-licenses.sh also depends on SBOM output

The `scan-licenses.sh` script reads SBOM output to check license compliance. If the SBOM
step was skipped (no syft), license compliance must also be done manually:

```bash
# Manual license check for root project
head -5 LICENSE 2>/dev/null || echo "No LICENSE file found"

# Check for GPL/AGPL in any dependency documentation
grep -rl 'GPL' --include='LICENSE*' --include='LICENCE*' . 2>/dev/null | head -5
```
