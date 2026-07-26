#!/usr/bin/env bash
# ============================================================================
# run-tests.sh — Test runner for skill-library
# ============================================================================
#
# Runs all test suites:
#   1. bats tests for bash scripts (skills/repo-health/scripts/)
#   2. Python validation script tests (scripts/ traversing all skills)
#
# Usage:
#   ./tests/run-tests.sh              # Run all tests
#   ./tests/run-tests.sh --verbose    # Verbose output
#   ./tests/run-tests.sh --ci         # CI mode (fail on first error)
#
# Prerequisites:
#   - bats (npm install -g bats)
#   - python3 with pyyaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERBOSE=false
CI_MODE=false
FAILURES=0

for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=true ;;
    --ci) CI_MODE=true ;;
  esac
done

BATS_FLAGS=""
$VERBOSE && BATS_FLAGS="--tap"
$CI_MODE && BATS_FLAGS="$BATS_FLAGS --timing"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Skill Library — Test Runner"
echo "  Date: $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. bats Tests ────────────────────────────────────────────────────────────

echo "─── Step 1: bats bash script tests ───"
echo ""

if command -v bats &>/dev/null; then
  BATS_TESTS=(
    "$SCRIPT_DIR/bats/test-fix-common.bats"
    "$SCRIPT_DIR/bats/test-fix-rollback.bats"
    "$SCRIPT_DIR/bats/test-scan-tests.bats"
  )

  for test_file in "${BATS_TESTS[@]}"; do
    if [[ -f "$test_file" ]]; then
      echo "  Running: $(basename "$test_file")"
      if $VERBOSE; then
        bats "$test_file" $BATS_FLAGS || ((FAILURES++))
      else
        bats "$test_file" $BATS_FLAGS 2>&1 | tail -1 || ((FAILURES++))
      fi
      echo ""
    fi
  done
else
  echo "  ⚠ bats not installed. Skipping bash tests."
  echo "  Install: npm install -g bats"
fi

# ── 2. Python Validation Tests ───────────────────────────────────────────────

echo "─── Step 2: Python validation script tests ───"
echo ""

VALIDATION_TESTS=(
  "scripts/validate-frontmatter.py"
  "scripts/detect-placeholders.py"
  "scripts/detect-trigger-conflicts.py"
)

for script in "${VALIDATION_TESTS[@]}"; do
  script_path="$REPO_ROOT/$script"
  if [[ -f "$script_path" ]]; then
    echo "  Running: $script"
    python3 "$script_path" --ci 2>&1 && echo "  ✓ Passed" || { echo "  ✖ Failed"; ((FAILURES++)); }
    echo ""
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAILURES" -eq 0 ]; then
  echo "  ✅ All tests passed"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
else
  echo "  ❌ $FAILURES test suite(s) had failures"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi
