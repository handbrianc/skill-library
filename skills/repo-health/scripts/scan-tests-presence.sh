#!/usr/bin/env bash
# scan-tests-presence.sh — Test Presence Check
# Extracted from scan-tests.sh --check-presence
#
# Usage:
#   ./scan-tests-presence.sh
#
# Target directory: $REPO_HEALTH_TARGET_DIR env override, else the current
# working directory. (lib/common.sh sets REPO_ROOT to the skill's own parent
# tree, which is wrong when auditing a project repo — overridden below.)
#
# Multi-stack: detects pytest/unittest for Python, *_test.go for Go, *.test.*/
# *.spec.* for Node, and package.json test scripts. Vendor trees (.venv,
# node_modules, site-packages, ...) are never counted as project code.
#
# Exit 0 always — test failures are data, not script failures.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

REPO_ROOT="${REPO_HEALTH_TARGET_DIR:-$PWD}"

# Count test files of a given kind, excluding vendor/dependency trees.
# `|| true` guards the pipeline: grep exits 1 when nothing survives filtering.
py_test_files() {
  find "$REPO_ROOT" -type f \( -name "test_*.py" -o -name "*_test.py" \) -print 2>/dev/null \
    | grep -vE '/(\.venv|venv|node_modules|__pycache__|site-packages|\.tox|\.git|\.mypy_cache|\.ruff_cache)/' \
    | wc -l | tr -d '[:space:]' || true
}
go_test_files() {
  find "$REPO_ROOT" -type f -name "*_test.go" -print 2>/dev/null \
    | grep -vE '/(\.venv|venv|node_modules|\.git)/' \
    | wc -l | tr -d '[:space:]' || true
}
js_test_files() {
  find "$REPO_ROOT" -type f \( -name "*.test.*" -o -name "*.spec.*" \) -print 2>/dev/null \
    | grep -vE '/(\.venv|venv|node_modules|\.git|\.next|dist|build)/' \
    | wc -l | tr -d '[:space:]' || true
}

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

  # Python test framework signals (pytest/unittest)
  echo ""
  echo "--- Python Test Framework ---"
  PY_CONFIG=""
  if [[ -f "$REPO_ROOT/pyproject.toml" ]] && grep -qE '^\[tool\.pytest' "$REPO_ROOT/pyproject.toml" 2>/dev/null; then
    echo "  PYTEST_CONFIG: pyproject.toml [tool.pytest.ini_options]"
    PY_CONFIG="pyproject.toml"
  fi
  for f in pytest.ini tox.ini setup.cfg conftest.py tests/conftest.py test/conftest.py; do
    if [[ -f "$REPO_ROOT/$f" ]]; then
      echo "  FOUND: $f"
      if [[ -z "$PY_CONFIG" ]]; then PY_CONFIG="$f"; fi
    fi
  done

  PYTEST_BIN=""
  for cand in "$REPO_ROOT/.venv/bin/pytest" "$REPO_ROOT/venv/bin/pytest"; do
    if [[ -x "$cand" ]]; then PYTEST_BIN="$cand"; break; fi
  done
  if [[ -z "$PYTEST_BIN" ]]; then
    PYTEST_BIN=$(command -v pytest 2>/dev/null || true)
  fi

  PY_TEST_N=$(py_test_files)
  if [[ -n "$PYTEST_BIN" ]] && [[ -n "$PY_CONFIG" || "$PY_TEST_N" -gt 0 ]]; then
    echo "  TEST_RUNNER: pytest ($("$PYTEST_BIN" --version 2>&1 | head -1))"
    if [[ -n "$PY_CONFIG" ]]; then
      echo "  TEST_FRAMEWORK: pytest (config: $PY_CONFIG)"
    fi
  fi
  if [[ "$PY_TEST_N" -gt 0 ]]; then
    # unittest usage signal (stdlib runner, may coexist with pytest)
    if grep -rlE '^\s*(import unittest|from unittest)' "$REPO_ROOT/tests" "$REPO_ROOT/test" 2>/dev/null | head -1 | grep -q .; then
      echo "  TEST_FRAMEWORK: unittest (also used — stdlib)"
    fi
  fi

  # List test files (sample)
  echo ""
  echo "--- Test Files ---"
  find "$REPO_ROOT" \
    -path "*/node_modules" -prune -o \
    -path "*/.git" -prune -o \
    -path "*/.venv" -prune -o \
    -path "*/venv" -prune -o \
    -path "*/__pycache__" -prune -o \
    -path "*/site-packages" -prune -o \
    \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.go" -o -name "test_*.py" -o -name "*_test.py" \) \
    -print 2>/dev/null | head -20 || true

  # Per-stack test file counts
  GO_TEST_N=$(go_test_files)
  JS_TEST_N=$(js_test_files)
  echo "TEST_FILE_COUNT: python=$PY_TEST_N go=$GO_TEST_N js-ts=$JS_TEST_N (vendor trees excluded)"
  if [[ -d "$REPO_ROOT/tests" ]]; then
    TESTS_DIR_N=$(find "$REPO_ROOT/tests" -type f \( -name "test_*.py" -o -name "*_test.py" \) -print 2>/dev/null | wc -l | tr -d '[:space:]' || true)
    echo "TESTS_DIR_FILE_COUNT: ${TESTS_DIR_N:-0} python test file(s) in tests/"
  fi

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
