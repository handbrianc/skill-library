#!/usr/bin/env bash
#
# scan-complexity.sh
# Cyclomatic complexity and code duplication analysis.
# Covers PHASE 2 steps 2.3 and 2.5 of the repo-health audit.
#
# Usage: ./scan-complexity.sh [target-dir]
#   target-dir: source directory (default: src/)
#

set -euo pipefail

TARGET_DIR="${1:-src}"

echo "=== CYCLOMATIC COMPLEXITY ==="

# Step 2.3 — ESLint complexity rule (JS/TS)
if command -v npx >/dev/null 2>&1 && [[ -f "package.json" ]]; then
  npx eslint "$TARGET_DIR" \
    --rule 'complexity: ["error", 15]' \
    --format json \
    --max-warnings 0 \
    2>/dev/null | jq '.[] | .filePath as $f | .messages[] | select(.ruleId == "complexity") | {file: $f, line: .line, message: .message}' || echo "COMPLEXITY: eslint scan complete (no results or non-JSON output)"
else
  echo "COMPLEXITY: eslint not available"
fi

# Python complexity (commented hint)
# radon cc -a -b "$TARGET_DIR" --max-complexity 10

echo ""
echo "=== CODE DUPLICATION ==="

# Step 2.5 — jscpd for JS/TS
if command -v npx >/dev/null 2>&1 && [[ -f "package.json" ]]; then
  npx jscpd --threshold 3 --failOn true "$TARGET_DIR" 2>/dev/null || true
fi

# Generic duplicate check via find-duplicates.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/find-duplicates.sh" ]]; then
  "$SCRIPT_DIR/find-duplicates.sh" "$TARGET_DIR"
fi

echo ""
echo "COMPLEXITY_SCAN_COMPLETE"
exit 0
