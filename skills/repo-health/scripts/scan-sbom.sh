#!/usr/bin/env bash
#
# scan-sbom.sh
# SBOM generation and license compliance check.
# Covers PHASE 8 of the repo-health audit.
#
# Usage: ./scan-sbom.sh
#   No args = runs all checks.
#

set -euo pipefail

echo "=== SBOM GENERATION ==="

# Step 8.1 — Generate SBOM
SBOM_SPDX_FILE=$(mktemp /tmp/sbom-spdx.XXXXXX.json)
SBOM_TABLE_FILE=$(mktemp /tmp/sbom-table.XXXXXX.txt)
NPM_TREE_FILE=$(mktemp /tmp/sbom-npm-tree.XXXXXX.txt)

if command -v syft >/dev/null 2>&1; then
  syft . -o spdx-json > "$SBOM_SPDX_FILE"
  echo "SBOM: generated spdx-json ($(wc -c < "$SBOM_SPDX_FILE") bytes)"
  syft . -o table > "$SBOM_TABLE_FILE"
  echo "SBOM: generated table format"
elif [[ -f "package.json" ]]; then
  npm ls --all --omit=dev > "$NPM_TREE_FILE"
  echo "SBOM: npm tree generated (syft not available)"
else
  echo "SBOM: no package manager detected, skipping"
fi

# Step 8.2 — License compliance check
echo ""
echo "=== LICENSE COMPLIANCE ==="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/scan-licenses.sh" ]]; then
  if [[ -f "$SBOM_SPDX_FILE" ]]; then
    "$SCRIPT_DIR/scan-licenses.sh" "$SBOM_SPDX_FILE"
  else
    echo "scan-licenses.sh requires an SBOM file (run syft first)"
  fi
else
  echo "scan-licenses.sh: not available"
fi

echo ""
echo "SBOM_SCAN_COMPLETE"
exit 0
