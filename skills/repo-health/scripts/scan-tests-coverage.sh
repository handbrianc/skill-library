#!/usr/bin/env bash
# scan-tests-coverage.sh — Test Suite Coverage Runner
# Extracted from scan-tests.sh --run-coverage
#
# Usage:
#   ./scan-tests-coverage.sh
#
# Exit 0 always — test failures are data, not script failures.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TEST_OUTPUT="${TEST_OUTPUT:-/tmp/test-output.txt}"

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

  elif command -v pytest &>/dev/null && (for f in "$REPO_ROOT"/pytest.ini "$REPO_ROOT"/pyproject.toml "$REPO_ROOT"/setup.cfg; do [ -f "$f" ] && { found=true; break; }; done; [ "${found:-false}" = true ] || for d in "$REPO_ROOT"/test*/ "$REPO_ROOT"/tests/; do [ -d "$d" ] && { found=true; break; }; done; [ "${found:-false}" = true ]); then
    echo "DETECTED_RUNNER: pytest"
    if python3 -c "import pytest_cov" 2>/dev/null; then
      pytest --cov="$REPO_ROOT" --cov-report=term-missing -v 2>&1 | tee "$TEST_OUTPUT"
    else
      pytest -v 2>&1 | tee "$TEST_OUTPUT"
    fi
    local ec="${PIPESTATUS[0]}"
    echo "TEST_EXIT_CODE: $ec" | tee -a "$TEST_OUTPUT"

  elif command -v go &>/dev/null && (for f in "$REPO_ROOT"/*_test.go; do [ -f "$f" ] && { found=true; break; }; done; [ "${found:-false}" = true ]); then
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_coverage
  exit 0
fi
