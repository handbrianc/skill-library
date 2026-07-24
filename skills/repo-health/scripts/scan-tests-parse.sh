#!/usr/bin/env bash
# scan-tests-parse.sh — Test Results Parser
# Extracted from scan-tests.sh --parse-results
#
# Usage:
#   ./scan-tests-parse.sh
#
# Exit 0 always — test failures are data, not script failures.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_OUTPUT="${TEST_OUTPUT:-/tmp/test-output.txt}"

parse_results() {
  echo "=== PARSE TEST RESULTS ==="
  if [[ ! -f "$TEST_OUTPUT" ]]; then
    echo "ERROR: No test output found at $TEST_OUTPUT — run --run-coverage first"
    echo "PARSE_RESULTS_DONE"
    return
  fi

  if [[ -f "$SCRIPT_DIR/parse-test-results.sh" ]]; then
    bash "$SCRIPT_DIR/parse-test-results.sh" "$TEST_OUTPUT"
  else
    echo "WARNING: parse-test-results.sh not found at $SCRIPT_DIR/parse-test-results.sh"
    echo "Performing basic inline parse instead:"

    local passed failed errors skipped
    passed=$(grep -cE '^\s*(✓|PASS|\.\.\. ok)' "$TEST_OUTPUT" 2>/dev/null || echo "0")
    failed=$(grep -cE '^\s*(✗|FAIL)' "$TEST_OUTPUT" 2>/dev/null || echo "0")
    errors=$(grep -cE '^\s*(×|ERROR)' "$TEST_OUTPUT" 2>/dev/null || echo "0")
    skipped=$(grep -cE '^\s*(○|SKIP|skipped)' "$TEST_OUTPUT" 2>/dev/null || echo "0")

    echo "PASSED: $passed"
    echo "FAILED: $failed"
    echo "ERRORS: $errors"
    echo "SKIPPED: $skipped"
  fi

  echo ""
  echo "PARSE_RESULTS_DONE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  parse_results
  exit 0
fi
