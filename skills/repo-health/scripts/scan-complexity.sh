#!/usr/bin/env bash
#
# scan-complexity.sh
# Cyclomatic complexity and code duplication analysis.
# Covers PHASE 2 steps 2.3 and 2.5 of the repo-health audit.
#
# Usage: ./scan-complexity.sh [target-dir]
#   target-dir: source directory or project root (default: src/)
#
# Sources, in priority order:
#   - Python: ruff (C901, PLR0911/0912/0913/0915) from the project's .venv
#     or PATH — the primary complexity source for Python projects.
#   - JS/TS: eslint complexity rule (only if eslint is installed locally —
#     never a network npx install).
#   - Duplication: jscpd (if installed) scoped to src/ + tests/; fallback to
#     find-duplicates.sh otherwise.
# Vendor directories (.venv, venv, node_modules, __pycache__, site-packages,
# *.dist-info, .git) are never scanned. Missing tools degrade to N/A, not
# failure. Every slow subcommand is bounded with `timeout`.
#

set -euo pipefail

TARGET_DIR="${1:-src}"

trap 'exit 0' EXIT
trap '' PIPE

echo "=== CYCLOMATIC COMPLEXITY & DUPLICATION ==="
echo "Target: $TARGET_DIR"
echo ""

if [[ ! -e "$TARGET_DIR" ]]; then
  echo "COMPLEXITY: N/A — target directory not found: $TARGET_DIR"
  echo "COMPLEXITY_SCAN_COMPLETE"
  exit 0
fi

VENDOR_GLOBS=".git,.venv,venv,node_modules,__pycache__,site-packages,*.dist-info,*.egg-info,.tox,.mypy_cache,.pytest_cache,.ruff_cache,.hypothesis,dist,build"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; exit 0' EXIT

# ---- Scan scopes -----------------------------------------------------------
# Python/complexity scope: <target>/src when present, else the target itself.
SRC_SCOPE="$TARGET_DIR"
if [[ -d "$TARGET_DIR/src" ]]; then
  SRC_SCOPE="$TARGET_DIR/src"
fi

# Duplication scope: src/ + tests/ only (never the whole tree / vendor dirs).
DUP_SCOPES=()
if [[ -d "$TARGET_DIR/src" ]]; then
  DUP_SCOPES+=("$TARGET_DIR/src")
fi
if [[ -d "$TARGET_DIR/tests" ]]; then
  DUP_SCOPES+=("$TARGET_DIR/tests")
fi
if [[ ${#DUP_SCOPES[@]} -eq 0 ]]; then
  DUP_SCOPES+=("$TARGET_DIR")
fi

# ---- 1. JS/TS complexity via eslint ----------------------------------------
echo "=== CYCLOMATIC COMPLEXITY — JS/TS (eslint) ==="
JS_TS_PRESENT=false
# Scope detection writes find's output to a temp file instead of piping into
# `grep -q`: under pipefail + `trap '' PIPE`, grep -q exits after the first
# match, find's next write fails with EPIPE, find exits non-zero, and the
# pipeline's non-zero status makes the condition false even when sources exist
# (a walk-duration race — small trees win, large ones silently lose).
find "$SRC_SCOPE" \( -type d \( -name node_modules -o -name .git -o -name .venv -o -name dist -o -name build \) -prune \) \
     -o \( -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) -print \) \
     2>/dev/null > "$TMPDIR/js_scope.txt" || true
if [[ -s "$TMPDIR/js_scope.txt" ]]; then
  JS_TS_PRESENT=true
fi

if [[ "$JS_TS_PRESENT" == "true" && ( -f "package.json" || -f "$TARGET_DIR/package.json" ) ]]; then
  if command -v npx >/dev/null 2>&1 && npx --no-install eslint --version &>/dev/null; then
    rc=0
    timeout 120 npx --no-install eslint "$SRC_SCOPE" \
      --rule 'complexity: ["error", 15]' \
      --format json \
      --no-error-on-unmatched-pattern \
      2>/dev/null > "$TMPDIR/eslint.json" || rc=$?
    if [[ "$rc" -eq 124 ]]; then
      echo "COMPLEXITY: eslint timed out after 120s — N/A"
    elif command -v jq >/dev/null 2>&1; then
      jq -r '.[] | .filePath as $f | .messages[] | select(.ruleId == "complexity") | "\($f):\(.line): \(.message)"' \
        "$TMPDIR/eslint.json" 2>/dev/null | head -30 || true
      echo "COMPLEXITY: eslint scan complete (violations listed above, if any)"
    else
      echo "COMPLEXITY: eslint ran but jq not available to parse its JSON output — N/A"
    fi
  else
    echo "COMPLEXITY: eslint not installed locally (npx --no-install) — JS/TS complexity N/A"
  fi
else
  echo "COMPLEXITY: no JS/TS sources in scope (or no package.json) — eslint complexity N/A"
fi

# ---- 2. Python complexity via ruff ------------------------------------------
echo ""
echo "=== CYCLOMATIC COMPLEXITY — PYTHON (ruff) ==="
PY_PRESENT=false
# Same temp-file scope detection as the JS/TS check above (pipefail race).
find "$SRC_SCOPE" \( -type d \( -name .venv -o -name venv -o -name node_modules -o -name __pycache__ -o -name '*.dist-info' -o -name .git \) -prune \) \
     -o \( -type f -name '*.py' -print \) \
     2>/dev/null > "$TMPDIR/py_scope.txt" || true
if [[ -s "$TMPDIR/py_scope.txt" ]]; then
  PY_PRESENT=true
fi

RUFF_BIN=""
if [[ -x "$TARGET_DIR/.venv/bin/ruff" ]]; then
  RUFF_BIN="$TARGET_DIR/.venv/bin/ruff"
elif [[ -x "$TARGET_DIR/venv/bin/ruff" ]]; then
  RUFF_BIN="$TARGET_DIR/venv/bin/ruff"
elif command -v ruff >/dev/null 2>&1; then
  RUFF_BIN="$(command -v ruff)"
fi

if [[ "$PY_PRESENT" == "true" ]]; then
  if [[ -n "$RUFF_BIN" ]]; then
    echo "Using ruff: $RUFF_BIN"
    rc=0
    timeout 180 "$RUFF_BIN" check --no-cache --isolated --exit-zero \
      --select C901,PLR0911,PLR0912,PLR0913,PLR0915 \
      --exclude "$VENDOR_GLOBS" \
      --output-format concise \
      "$SRC_SCOPE" > "$TMPDIR/ruff_cx.txt" 2>/dev/null || rc=$?
    if [[ "$rc" -eq 124 ]]; then
      echo "COMPLEXITY: ruff timed out after 180s — N/A"
    else
      total=$(awk 'END{print NR+0}' "$TMPDIR/ruff_cx.txt")
      echo "Ruff complexity findings (C901/PLR0911/0912/0913/0915): $total"
      if [[ "$total" -gt 0 ]]; then
        echo "Per-rule counts:"
        grep -oE ' (C901|PLR0911|PLR0912|PLR0913|PLR0915) ' "$TMPDIR/ruff_cx.txt" \
          | sort | uniq -c | sort -rn | sed 's/^/  /' || true
        echo "Top offenders (path:line:col — review thresholds: >15 MEDIUM, >25 HIGH, >40 CRITICAL):"
        head -25 "$TMPDIR/ruff_cx.txt" | sed 's/^/  /'
      fi
      echo "COMPLEXITY: ruff scan complete"
    fi
  else
    echo "COMPLEXITY: N/A — ruff not found (checked $TARGET_DIR/.venv/bin/ruff and PATH); install ruff for Python complexity"
  fi
else
  echo "COMPLEXITY: no Python sources in scope — ruff complexity N/A"
fi

# ---- 3. Duplication ----------------------------------------------------------
echo ""
echo "=== CODE DUPLICATION ==="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

JSCPD_PATH=""
JSCPD_NPX=false
if command -v jscpd >/dev/null 2>&1; then
  JSCPD_PATH="$(command -v jscpd)"
elif command -v npx >/dev/null 2>&1 && npx --no-install jscpd --version &>/dev/null 2>&1; then
  JSCPD_NPX=true
fi

if [[ -n "$JSCPD_PATH" || "$JSCPD_NPX" == "true" ]]; then
  for scope in "${DUP_SCOPES[@]}"; do
    echo "--- jscpd: $scope (min 50 tokens, threshold 3%) ---"
    rc=0
    if [[ -n "$JSCPD_PATH" ]]; then
      timeout 120 "$JSCPD_PATH" --min-tokens 50 --threshold 3 --reporters console "$scope" 2>&1 | head -60 || rc=$?
    else
      timeout 120 npx --no-install jscpd --min-tokens 50 --threshold 3 --reporters console "$scope" 2>&1 | head -60 || rc=$?
    fi
    if [[ "$rc" -eq 124 ]]; then
      echo "DUPLICATION: jscpd timed out after 120s on $scope — N/A for this scope"
    fi
  done
  echo "DUPLICATION: jscpd scan complete"
elif [[ -f "$SCRIPT_DIR/find-duplicates.sh" ]]; then
  echo "jscpd not available — falling back to find-duplicates.sh (exact-match heuristic, slower)"
  for scope in "${DUP_SCOPES[@]}"; do
    timeout 240 "$SCRIPT_DIR/find-duplicates.sh" "$scope" || {
      rc=$?
      if [[ "$rc" -eq 124 ]]; then
        echo "DUPLICATION: find-duplicates timed out after 240s on $scope — N/A for this scope"
      else
        echo "DUPLICATION: find-duplicates exited non-zero on $scope — N/A for this scope"
      fi
    }
  done
else
  echo "DUPLICATION: N/A — neither jscpd nor find-duplicates.sh available"
fi

echo ""
echo "COMPLEXITY_SCAN_COMPLETE"
exit 0
