#!/usr/bin/env bash
# scan-tests-report.sh — Coverage Report Extractor
# Extracted from scan-tests.sh --coverage-report
#
# Usage:
#   ./scan-tests-report.sh
#
# Exit 0 always — test failures are data, not script failures.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TEST_OUTPUT="${TEST_OUTPUT:-/tmp/test-output.txt}"

coverage_report() {
  echo "=== COVERAGE REPORT ==="
  if [[ ! -f "$TEST_OUTPUT" ]]; then
    echo "ERROR: No test output found at $TEST_OUTPUT — run --run-coverage first"
    echo "COVERAGE_REPORT_DONE"
    return
  fi

  # Extract coverage percentages from various formats
  local cov_found=false

  # vitest / jest coverage summary: "Lines:       85.43%"
  for metric in Lines Branches Functions Statements; do
    local val
    val=$(grep -E "^\s*${metric}\s*:" "$TEST_OUTPUT" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+%' | head -1 || true)
    if [[ -n "$val" ]]; then
      cov_found=true
      echo "  $metric: $val"
    fi
  done

  # "All files" line (jest/ts-jest)
  local all_files
  all_files=$(grep -E "All files" "$TEST_OUTPUT" 2>/dev/null | head -1 || true)
  if [[ -n "$all_files" ]]; then
    cov_found=true
    echo "  $all_files"
  fi

  # Go test coverage: "coverage: 42.3% of statements"
  local go_cov
  go_cov=$(grep -oE 'coverage: [0-9]+\.[0-9]+% of statements' "$TEST_OUTPUT" 2>/dev/null | head -1 || true)
  if [[ -n "$go_cov" ]]; then
    cov_found=true
    echo "  $go_cov"
  fi

  # pytest-cov: "TOTAL   1234   567   890   54%"
  local pytest_total
  pytest_total=$(grep -E '^TOTAL' "$TEST_OUTPUT" 2>/dev/null | head -1 || true)
  if [[ -n "$pytest_total" ]]; then
    cov_found=true
    echo "  TOTAL: $(echo "$pytest_total" | awk '{print $NF}')"
    echo "  $pytest_total"
  fi

  # "Coverage:" summary line
  local cov_summary
  cov_summary=$(grep -iE "(Coverage|Total)" "$TEST_OUTPUT" 2>/dev/null | tail -5 || true)
  if [[ -n "$cov_summary" ]] && ! $cov_found; then
    cov_found=true
    echo "  $cov_summary"
  fi

  if ! $cov_found; then
    echo "  (no coverage data found in test output)"
  fi

  echo ""
  echo "COVERAGE_REPORT_DONE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  coverage_report
  exit 0
fi
