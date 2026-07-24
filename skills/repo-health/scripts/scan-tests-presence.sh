#!/usr/bin/env bash
# scan-tests-presence.sh — Test Presence Check
# Extracted from scan-tests.sh --check-presence
#
# Usage:
#   ./scan-tests-presence.sh
#
# Exit 0 always — test failures are data, not script failures.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

check_presence() {
  echo "=== TEST PRESENCE CHECK ==="

  # List test directories
  echo ""
  echo "--- Test Directories ---"
  for dir in tests __tests__ test spec; do
    if [[ -d "$REPO_ROOT/$dir" ]]; then
      echo "  FOUND: $dir/"
    fi
  done

  # List test files
  echo ""
  echo "--- Test Files ---"
  find "$REPO_ROOT" \
    -path "*/node_modules" -prune -o \
    -path "*/.git" -prune -o \
    \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.go" -o -name "test_*.py" \) \
    -print 2>/dev/null | head -20

  # Package.json test scripts
  echo ""
  echo "--- Package.json Test Scripts ---"
  if [[ -f "$REPO_ROOT/package.json" ]]; then
    jq -r '.scripts | to_entries[] | select(.key | test("test|spec|cover")) | "  \(.key): \(.value)"' "$REPO_ROOT/package.json" 2>/dev/null || echo "  (no test scripts found)"
  else
    echo "  (no package.json)"
  fi

  echo ""
  echo "TEST_PRESENCE_DONE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  check_presence
  exit 0
fi
