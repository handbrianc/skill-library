#!/usr/bin/env bash
# scan-tests-coverage.sh — Test Suite Coverage Runner
# Extracted from scan-tests.sh --run-coverage
#
# Usage:
#   ./scan-tests-coverage.sh
#
# Target directory: $REPO_HEALTH_TARGET_DIR env override, else the current
# working directory.
#
# Exit 0 always — test failures are data, not script failures.
# Runner pipelines are wrapped in set +e / set -e so a failing test run is
# captured as data (TEST_EXIT_CODE) instead of aborting under set -e.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

REPO_ROOT="${REPO_HEALTH_TARGET_DIR:-$PWD}"
TEST_OUTPUT="${TEST_OUTPUT:-/tmp/test-output.txt}"

run_coverage() {
  echo "=== TEST RUN WITH COVERAGE ==="
  if [[ ! -d "$REPO_ROOT" ]]; then
    echo "ERROR: target directory not found: $REPO_ROOT"
    echo "TEST_RUN_DONE"
    return
  fi
  cd "$REPO_ROOT"

  # ---- Auto-detect test runner ----
  if command -v vitest &>/dev/null && [[ -f "vitest.config.ts" || -f "vitest.config.js" || -f "vite.config.ts" ]]; then
    echo "DETECTED_RUNNER: vitest"
    set +e
    vitest run --coverage --reporter=verbose 2>&1 | tee "$TEST_OUTPUT"
    local ec="${PIPESTATUS[0]}"
    set -e
    echo "TEST_EXIT_CODE: $ec" | tee -a "$TEST_OUTPUT"

  elif command -v jest &>/dev/null && [[ -f "jest.config.js" || -f "jest.config.ts" || -f "package.json" ]]; then
    echo "DETECTED_RUNNER: jest"
    set +e
    jest --coverage --coverageReporters=text-summary --coverageReporters=text 2>&1 | tee "$TEST_OUTPUT"
    local ec="${PIPESTATUS[0]}"
    set -e
    echo "TEST_EXIT_CODE: $ec" | tee -a "$TEST_OUTPUT"

  elif pytest_available; then
    local PYTEST_BIN
    PYTEST_BIN=$(resolve_pytest)
    local PY_PY
    PY_PY=$(pytest_python)
    echo "DETECTED_RUNNER: pytest ($("$PYTEST_BIN" --version 2>&1 | head -1))"
    # pytest-cov availability is checked against the SAME interpreter that
    # runs pytest (a global python may lack the project's plugins).
    local PYTEST_ARGS=(-v --durations=20 -p no:cacheprovider)
    if "$PY_PY" -c "import pytest_cov" >/dev/null 2>&1; then
      local COV_TARGET="."
      if [[ -d src ]]; then COV_TARGET="src"; fi
      echo "COVERAGE: enabled (pytest-cov available; --cov=$COV_TARGET)"
      set +e
      "$PYTEST_BIN" --cov="$COV_TARGET" --cov-report=term-missing "${PYTEST_ARGS[@]}" 2>&1 | tee "$TEST_OUTPUT"
      local ec="${PIPESTATUS[0]}"
      set -e
    else
      echo "COVERAGE: skipped (pytest-cov not importable in $PY_PY)"
      set +e
      "$PYTEST_BIN" "${PYTEST_ARGS[@]}" 2>&1 | tee "$TEST_OUTPUT"
      local ec="${PIPESTATUS[0]}"
      set -e
    fi
    echo "TEST_EXIT_CODE: $ec" | tee -a "$TEST_OUTPUT"

  elif command -v go &>/dev/null && compgen -G '*_test.go' >/dev/null 2>&1; then
    echo "DETECTED_RUNNER: go test"
    set +e
    go test -coverprofile=/tmp/cover.out -v ./... 2>&1 | tee "$TEST_OUTPUT"
    local ec="${PIPESTATUS[0]}"
    set -e
    echo "TEST_EXIT_CODE: $ec" | tee -a "$TEST_OUTPUT"

  else
    echo "DETECTED_RUNNER: none — no recognized test runner found"
    echo "TEST_EXIT_CODE: N/A" | tee "$TEST_OUTPUT"
  fi

  echo ""
  echo "TEST_RUN_DONE"
}

# ---- helpers (shared shape with scan-linters scripts) ----

# True when a pytest binary exists AND the project looks like a pytest project.
pytest_available() {
  local bin
  bin=$(resolve_pytest) || return 1
  if [[ -f pytest.ini || -f tox.ini || -f setup.cfg || -f conftest.py \
        || -f tests/conftest.py || -f test/conftest.py ]] \
     || grep -qE '^\[tool\.pytest' pyproject.toml 2>/dev/null \
     || [[ -n "$(find tests test -maxdepth 2 -name 'test_*.py' -print -quit 2>/dev/null)" ]] \
     || [[ -n "$(find src -maxdepth 4 -name 'test_*.py' -print -quit 2>/dev/null)" ]]; then
    return 0
  fi
  return 1
}

# Prefer the project's own virtualenv pytest over PATH shims.
resolve_pytest() {
  local cand
  for cand in .venv/bin/pytest venv/bin/pytest; do
    if [[ -x "$cand" ]]; then echo "$cand"; return 0; fi
  done
  command -v pytest 2>/dev/null || return 1
}

# The python interpreter matching the selected pytest binary.
pytest_python() {
  local bin
  bin=$(resolve_pytest) || { echo "python3"; return 0; }
  if [[ "$bin" == *"/.venv/bin/pytest" || "$bin" == *"/venv/bin/pytest" ]]; then
    echo "${bin%/pytest}python"
  else
    echo "python3"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_coverage
  exit 0
fi
