#!/usr/bin/env bash
# scan-tests.sh — Test Suite Health Scanner
#
# Usage:
#   ./scan-tests.sh                    # Run all steps
#   ./scan-tests.sh --check-presence   # List test dirs/files/scripts
#   ./scan-tests.sh --run-coverage     # Auto-detect & run test suite with coverage
#   ./scan-tests.sh --parse-results    # Parse test output via parse-test-results.sh
#   ./scan-tests.sh --slow-tests       # Extract timing, find 20 slowest tests
#   ./scan-tests.sh --coverage-report  # Extract coverage % from output
#
# Exit 0 always — test failures are data, not script failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEST_OUTPUT="/tmp/test-output.txt"

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

run_coverage() {
  echo "=== TEST RUN WITH COVERAGE ==="
  cd "$REPO_ROOT"

  # Auto-detect test runner
  if command -v vitest &>/dev/null && [[ -f "vitest.config.ts" || -f "vitest.config.js" || -f "vite.config.ts" ]]; then
    echo "DETECTED_RUNNER: vitest"
    vitest run --coverage --reporter=verbose 2>&1 | tee "$TEST_OUTPUT"
    local ec="${PIPESTATUS[0]}"
    echo "TEST_EXIT_CODE: $ec" | tee -a "$TEST_OUTPUT"

  elif command -v jest &>/dev/null && [[ -f "jest.config.js" || -f "jest.config.ts" || -f "package.json" ]]; then
    echo "DETECTED_RUNNER: jest"
    jest --coverage --coverageReporters=text-summary --coverageReporters=text 2>&1 | tee "$TEST_OUTPUT"
    local ec="${PIPESTATUS[0]}"
    echo "TEST_EXIT_CODE: $ec" | tee -a "$TEST_OUTPUT"

  elif command -v pytest &>/dev/null && (ls "$REPO_ROOT"/pytest.ini "$REPO_ROOT"/pyproject.toml "$REPO_ROOT"/setup.cfg 2>/dev/null | grep -q . || ls "$REPO_ROOT"/test*/ "$REPO_ROOT"/tests/ 2>/dev/null | grep -q .); then
    echo "DETECTED_RUNNER: pytest"
    if python3 -c "import pytest_cov" 2>/dev/null; then
      pytest --cov="$REPO_ROOT" --cov-report=term-missing -v 2>&1 | tee "$TEST_OUTPUT"
    else
      pytest -v 2>&1 | tee "$TEST_OUTPUT"
    fi
    local ec="${PIPESTATUS[0]}"
    echo "TEST_EXIT_CODE: $ec" | tee -a "$TEST_OUTPUT"

  elif command -v go &>/dev/null && ls "$REPO_ROOT"/*_test.go 2>/dev/null | grep -q .; then
    echo "DETECTED_RUNNER: go test"
    go test -coverprofile=/tmp/cover.out -v ./... 2>&1 | tee "$TEST_OUTPUT"
    local ec="${PIPESTATUS[0]}"
    echo "TEST_EXIT_CODE: $ec" | tee -a "$TEST_OUTPUT"

  else
    echo "DETECTED_RUNNER: none — no recognized test runner found"
    echo "TEST_EXIT_CODE: N/A" | tee "$TEST_OUTPUT"
  fi

  echo ""
  echo "TEST_RUN_DONE"
}

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

# --- Main ---

RUN_ALL=true
RUN_CHECK=false
RUN_COV=false
RUN_PARSE=false
RUN_SLOW=false
RUN_REPORT=false

if [[ $# -gt 0 ]]; then
  RUN_ALL=false
  for arg in "$@"; do
    case "$arg" in
      --check-presence)  RUN_CHECK=true ;;
      --run-coverage)    RUN_COV=true ;;
      --parse-results)   RUN_PARSE=true ;;
      --slow-tests)      RUN_SLOW=true ;;
      --coverage-report) RUN_REPORT=true ;;
      *)
        echo "Unknown option: $arg"
        echo "Usage: $0 [--check-presence] [--run-coverage] [--parse-results] [--slow-tests] [--coverage-report]"
        exit 0
        ;;
    esac
  done
fi

# Support the scripts dir being accessed via symlink or direct path
if [[ ! -d "$SCRIPT_DIR" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

if $RUN_ALL || $RUN_CHECK; then
  check_presence
fi

if $RUN_ALL || $RUN_COV; then
  run_coverage
fi

if $RUN_ALL || $RUN_PARSE; then
  parse_results
fi

if $RUN_ALL || $RUN_SLOW; then
  slow_tests
fi

if $RUN_ALL || $RUN_REPORT; then
  coverage_report
fi

exit 0
