#!/usr/bin/env bash
#
# scan-licenses.sh
# Parses an SPDX-formatted SBOM and flags license compliance risks.
#
# Usage: ./scan-licenses.sh <sbom_spdx_json>
# Output: GROUPED by risk tier: PERMISSIVE | COPYLEFT_WEAK | COPYLEFT_STRONG | UNKNOWN
set -euo pipefail

SBOM="${1:-/tmp/sbom.spdx.json}"

echo "=== LICENSE COMPLIANCE SCAN ===" >&2
echo "SBOM: $SBOM" >&2
echo "" >&2

if [ ! -f "$SBOM" ]; then
  # Try generating via syft if available
  if command -v syft &>/dev/null; then
    echo "SBOM not found — generating with syft..." >&2
    syft . -o spdx-json > /tmp/sbom.spdx.json 2>/dev/null && SBOM="/tmp/sbom.spdx.json" || true
  fi
  
  if [ ! -f "$SBOM" ]; then
    echo "No SBOM available — cannot scan licenses" >&2
    exit 1
  fi
fi

echo "Loaded SBOM: $SBOM ($(wc -l < "$SBOM") lines)" >&2
echo "" >&2

# ---- License categorization ----
# Based on SPDX license list and FOSSology taxonomy

PERMISSIVE=()
COPYLEFT_WEAK=()     # LGPL-2.1, MPL-1.1, CDDL-1.0, EPL-1.0, OSL-3.0
COPYLEFT_STRONG=()   # GPL-3.0, AGPL-3.0, EUPL-1.2
RESTRICTIVE=()       # Commercial, Proprietary, Business Source License (BSL), other non-standard licenses

PERMISSIVE_PATTERNS="Apache-2\.0|MIT|BSD-2-Clause|BSD-3-Clause|ISC|CC0-1\.0|Unlicense|BlueOak-1\.0|WTFpl|PHP-3\.0|PostgreSQL"
WEAK_PATTERNS="LGPL-2\.1|LGPL-3\.0|MPL-1\.1|MPL-2\.0|CDDL-1\.0|EPL-1\.0|EPL-2\.0|OSL-3\.0|AFPL-3\.0|APL-1\.0"
STRONG_PATTERNS="GPL-2\.0|GPL-3\.0|AGPL-3\.0|EUPL-1\.2|NUnit"
UNKNOWN_PATTERNS="NOASSERTION|NONE|Unknown|Custom"

if command -v jq &>/dev/null; then
  # SPDX JSON: packages[*].licenseConcluded or packages[*].licenseInfoFromFiles
  PACKAGES=$(jq -r '.packages[] | select(.licenseConcluded != "NOASSERTION") | {name: .name, license: .licenseConcluded}' "$SBOM" 2>/dev/null || true)
  
  if [ -n "$PACKAGES" ]; then
    while IFS= read -r line; do
      NAME=$(echo "$line" | jq -r '.name' 2>/dev/null || echo "unknown")
      LIC=$(echo "$line" | jq -r '.license' 2>/dev/null || echo "NOASSERTION")
      
      if echo "$LIC" | grep -qE "$PERMISSIVE_PATTERNS"; then
        PERMISSIVE+=("$NAME ($LIC)")
      elif echo "$LIC" | grep -qE "$WEAK_PATTERNS"; then
        COPYLEFT_WEAK+=("$NAME ($LIC)")
      elif echo "$LIC" | grep -qE "$STRONG_PATTERNS"; then
        COPYLEFT_STRONG+=("$NAME ($LIC)")
      elif echo "$LIC" | grep -qE "$UNKNOWN_PATTERNS"; then
        UNKNOWN+=("$NAME ($LIC)")
      else
        # Commercial or unusual licenses
        COPYLEFT_WEAK+=("$NAME ($LIC) [VERIFY]")
      fi
    done <<< "$PACKAGES"
  fi
else
  echo "jq not available — falling back to text parsing" >&2
  grep -oE "\"licenseConcluded\":\s*\"[^\"]+\"" "$SBOM" | \
    sed 's/"licenseConcluded": "//' | tr -d '"' | sort | uniq -c | sort -rn | head -30
fi

# ---- REPORT ----
echo "========== LICENSE GROUPS ==========" >&2

section() {
  local label="$1"
  shift
  local arr=("$@")
  echo "" >&2
  echo "### $label (${#arr[@]} packages)" >&2
  for item in "${arr[@]}"; do
    echo "  $item" >&2
  done
}

section "PERMISSIVE (use freely)" "${PERMISSIVE[@]}"
section "COPYLEFT WEAK (weak copyleft — linking exemption)" "${COPYLEFT_WEAK[@]}"
section "COPYLEFT STRONG (strong copyleft — careful)" "${COPYLEFT_STRONG[@]}"
section "UNKNOWN/CUSTOM (verify before use)" "${UNKNOWN[@]}"

# ---- LICENSE COUNT SUMMARY ----
echo "" >&2
echo "========== SUMMARY ==========" >&2
echo "Permissive licenses: ${#PERMISSIVE[@]}" >&2
echo "Weak copyleft:       ${#COPYLEFT_WEAK[@]}" >&2
echo "Strong copyleft:     ${#COPYLEFT_STRONG[@]}" >&2
echo "Unknown/custom:      ${#UNKNOWN[@]}" >&2
echo "" >&2

# ---- ACTIONABLE FLAGS ----
echo "========== ACTIONS NEEDED ==========" >&2

if [ ${#COPYLEFT_STRONG[@]} -gt 0 ]; then
  echo "HIGH RISK: Strong copyleft licenses detected." >&2
  echo "  These packages may require your entire codebase to be released under GPL-compatible terms." >&2
  echo "  Consult legal counsel before shipping." >&2
fi

if [ ${#COPYLEFT_WEAK[@]} -gt 0 ]; then
  echo "MEDIUM RISK: Weak copyleft packages detected." >&2
  echo "  Linking exemption applies (LGPL with dynamic linking, MPL with file-level)." >&2
  echo "  Verify your linking strategy complies." >&2
fi

if [ ${#UNKNOWN[@]} -gt 0 ]; then
  echo "LOW RISK (verify): Unknown license designations." >&2
  echo "  Contact package maintainers or search SPDX license list." >&2
fi

echo "" >&2
echo "Scan complete. Consult your organization's legal/compliance team for definitive license risk assessment." >&2

exit 0