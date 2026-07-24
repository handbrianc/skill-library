#!/usr/bin/env bash
#
# scan-linters.sh
# Detect available linters for the project's language(s), run them,
# and output violation counts for use by the repo-health audit.
#
# Usage: ./scan-linters.sh [target-dir]
#   target-dir: source directory to scan (default: auto-detect src/ lib/ app/ or .)
#
# Outputs violation files to /tmp/ for each detected linter:
#   /tmp/eslint-violations.txt, /tmp/ruff-violations.txt, etc.
#
# Returns: 0 always (non-zero exits from linters are captured as violations, not failures)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Source directory detection ----
TARGET_DIR="${1:-}"
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="."
  for d in src lib app; do
    if [[ -d "$d" ]]; then TARGET_DIR="$d"; break; fi
  done
fi

echo "SCAN_LINTERS_TARGET: $TARGET_DIR"

echo ""
echo "=== LINTER DETECTION ==="
bash "$SCRIPT_DIR/scan-linters-detect.sh" "$TARGET_DIR"

echo ""
echo "=== LINTER RUN ==="
bash "$SCRIPT_DIR/scan-linters-run.sh" "$TARGET_DIR" || true

echo ""
echo "=== LINTER SCAN COMPLETE ==="
exit 0
