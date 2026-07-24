#!/usr/bin/env bash
# scan-tests-slow.sh — Slowest Tests Finder
# Extracted from scan-tests.sh --slow-tests
#
# Usage:
#   ./scan-tests-slow.sh
#
# Exit 0 always — test failures are data, not script failures.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TEST_OUTPUT="${TEST_OUTPUT:-/tmp/test-output.txt}"

slow_tests() {
  echo "=== SLOWEST TESTS ==="
  if [[ ! -f "$TEST_OUTPUT" ]]; then
    echo "ERROR: No test output found at $TEST_OUTPUT — run --run-coverage first"
    echo "SLOW_TESTS_DONE"
    return
  fi

  # Try various timing formats
  local timing_found=false

  # Format: [1.23s] or [123ms] (vitest / jest verbose)
  if grep -qE '\[[0-9]+\.?[0-9]*(ms|s)\]' "$TEST_OUTPUT" 2>/dev/null; then
    timing_found=true
    echo "--- Tests sorted by duration (slowest first) ---"
    grep -oE '\[[0-9]+\.?[0-9]*(ms|s)\]' "$TEST_OUTPUT" \
      | sed 's/\[//;s/\]//' \
      | awk '{
          if ($1 ~ /ms$/) { val = substr($1,1,length($1)-2); print val/1000 }
          else if ($1 ~ /s$/) { val = substr($1,1,length($1)-1); print val }
          else print $1
        }' \
      | sort -rn \
      | head -20 \
      | awk '{ printf "  %.3fs\n", $1 }'
  fi

  # Format: "✓ test name (Nms)" (common format)
  if grep -qE '\([0-9]+ms\)' "$TEST_OUTPUT" 2>/dev/null; then
    timing_found=true
    echo ""
    echo "--- Tests with timing (ms) ---"
    grep -oE '\([0-9]+ms\)' "$TEST_OUTPUT" \
      | sed 's/(//;s/)//;s/ms//' \
      | sort -rn \
      | head -20 \
      | awk '{ printf "  %dms\n", $1 }'
  fi

  # Format: "PASS  my/test (5.23s)" / "ok 1 test_name (0.42s)"
  if grep -qE '(PASS|ok)\s.*\([0-9]+\.[0-9]+s\)' "$TEST_OUTPUT" 2>/dev/null; then
    timing_found=true
    echo ""
    echo "--- Test/suite timing from PASS/ok lines ---"
    grep -oE '\([0-9]+\.[0-9]+s\)' "$TEST_OUTPUT" \
      | sed 's/(//;s/)//;s/s//' \
      | sort -rn \
      | head -20 \
      | awk '{ printf "  %.2fs\n", $1 }'
  fi

  # Also try extracting full lines with timing for more context
  if grep -qE '(slow|SLOW|TIME|duration)' "$TEST_OUTPUT" 2>/dev/null; then
    timing_found=true
    echo ""
    echo "--- Lines mentioning timing (slow/timing/duration) ---"
    grep -iE '(slow|SLOW|TIME|duration)' "$TEST_OUTPUT" 2>/dev/null | head -20 | sed 's/^/  /'
  fi

  if ! $timing_found; then
    echo "  (no timing data found in test output)"
  fi

  echo ""
  echo "SLOW_TESTS_DONE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  slow_tests
  exit 0
fi
