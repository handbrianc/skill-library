#!/usr/bin/env bash
#
# scan-docs.sh
# Documentation audit — inventory docs and check accuracy.
# Covers PHASE 4 of the repo-health audit.
#
# Usage: ./scan-docs.sh [--check-links]
#

set -euo pipefail

echo "=== DOCUMENTATION INVENTORY ==="

# Step 4.1 — Inventory all docs
find . -maxdepth 3 \( -name "*.md" -o -name "*.rst" -o -name "*.txt" \) \
  ! -path "./node_modules/*" ! -path "./.git/*" \
  -exec wc -l {} \; | sort -rn | head -30

echo ""
ls -lh README* INSTALL* CONTRIBUTING* CHANGELOG* AUTHORS* SECURITY* LICENSE* 2>/dev/null || echo "No standard doc files found"
ls -lh docs/ README.md API.md ARCHITECTURE* DESIGN* GUIDE* 2>/dev/null || echo "No docs/ directory or expected doc files found"

# Step 4.3 — Accuracy check (link rot)
if [[ "${1:-}" == "--check-links" ]]; then
  echo ""
  echo "=== LINK ROT CHECK ==="
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$SCRIPT_DIR/check-doc-links.sh" ]]; then
    "$SCRIPT_DIR/check-doc-links.sh" docs/
  else
    echo "check-doc-links.sh: not available"
  fi
fi

echo ""
echo "DOC_SCAN_COMPLETE"
exit 0
