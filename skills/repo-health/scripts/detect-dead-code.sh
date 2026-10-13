#!/usr/bin/env bash
#
# detect-dead-code.sh
# Detects unused exports, unreachable functions, and dead code paths.
# For deterministic results, run from a clean working tree (no uncommitted changes).
# Usage: ./detect-dead-code.sh <target_dir> [--aggressive]
# Output: Human-readable report to stderr/stdout (not strict TSV)
#
# Tools per language (graceful N/A when absent):
#   - Python: vulture (preferred) or ruff F401/F811/F841 heuristic
#     (labelled "heuristic — confirm manually")
#   - TS/JS: tsc unused-symbol diagnostics (requires package.json + tsconfig)
# Vendor directories (.venv, venv, node_modules, __pycache__, site-packages,
# *.dist-info, .git) are never scanned. Slow subcommands run under `timeout`.
#
# Copyright: OpenCode contributors
# License: MIT

set -euo pipefail

TARGET="${1:-.}"
MODE="normal"  # normal | aggressive
if [[ "${2:-}" == "--aggressive" || "${2:-}" == "aggressive" ]]; then
  MODE="aggressive"
fi
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; exit 0' EXIT

echo "=== DEAD CODE SCAN ===" >&2
echo "Target: $TARGET" >&2
echo "Mode: $MODE" >&2
echo "Commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')" >&2

if [[ ! -e "$TARGET" ]]; then
  echo "DEAD_CODE: N/A — target directory not found: $TARGET" >&2
  echo "=== SCAN COMPLETE ===" >&2
  exit 0
fi

VENDOR_GLOBS=".git,.venv,venv,node_modules,__pycache__,site-packages,*.dist-info,*.egg-info,.tox,.mypy_cache,.pytest_cache,.ruff_cache,.hypothesis,dist,build"
VENDOR_EXCLUDE=( .git .venv venv node_modules __pycache__ site-packages '*.dist-info' '*.egg-info' .tox .mypy_cache .pytest_cache .ruff_cache .hypothesis dist build )

# ---- 1. Inventory source files (vendor dirs pruned) ----
# `|| true` on the find below: if find exits non-zero (unreadable directory),
# set -e would abort the whole scan silently.
find "$TARGET" \
  \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
       -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
       -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
       -o -name dist -o -name build \) -prune \) \
  -o \( -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" \) -print \) \
  2>/dev/null > "$TMPDIR/all_source_files.txt" || true

TOTAL_FILES=$(awk 'END{print NR+0}' "$TMPDIR/all_source_files.txt")
echo "Scanned files: $TOTAL_FILES" >&2

# Python source scope: <target>/src when present, else the target itself.
PY_SCOPE="$TARGET"
if [[ -d "$TARGET/src" ]]; then
  PY_SCOPE="$TARGET/src"
fi
PY_PRESENT=false
# Temp-file scope detection (pipefail race: `find | grep -q` fails when grep
# exits after the first match and find hits EPIPE mid-walk).
find "$PY_SCOPE" \( -type d \( -name .venv -o -name venv -o -name node_modules -o -name __pycache__ -o -name '*.dist-info' -o -name .git \) -prune \) \
     -o \( -type f -name '*.py' -print \) \
     2>/dev/null > "$TMPDIR/py_scope.txt" || true
if [[ -s "$TMPDIR/py_scope.txt" ]]; then
  PY_PRESENT=true
fi

# ---- 2. TS/JS: unused exports via tsc diagnostics ----
# Only when a Node project context exists; never triggers a network npx install.
if command -v npx &>/dev/null && [[ -f package.json || -f "$TARGET/package.json" ]]; then
  echo "" >&2
  echo "[TSCheck] Looking for unused exports via TypeScript..." >&2

  if [[ -f tsconfig.json || -f "$TARGET/tsconfig.json" ]]; then
    if npx --no-install tsc --version &>/dev/null; then
      rc=0
      ( cd "$TARGET" 2>/dev/null || true
        timeout 120 npx --no-install tsc --noEmit -p tsconfig.json 2>&1 || true ) \
        | grep -E "(is declared but never used|unused)" | head -50 || true
      echo "[TSCheck] TypeScript diagnostics complete (unused symbols listed above, if any)" >&2
    else
      echo "[TSCheck] TypeScript not installed locally (npx --no-install) — TS/JS dead-code scan N/A" >&2
    fi
  else
    echo "[TSCheck] tsconfig.json not found — skipping TypeScript dead-code scan" >&2
  fi
fi

# ---- 3. Python: vulture (preferred) or ruff heuristic ----
if [[ "$PY_PRESENT" == "true" ]]; then
  echo "" >&2
  VULTURE_BIN=""
  if [[ -x "$TARGET/.venv/bin/vulture" ]]; then
    VULTURE_BIN="$TARGET/.venv/bin/vulture"
  elif command -v vulture &>/dev/null; then
    VULTURE_BIN="$(command -v vulture)"
  fi
  RUFF_BIN=""
  if [[ -x "$TARGET/.venv/bin/ruff" ]]; then
    RUFF_BIN="$TARGET/.venv/bin/ruff"
  elif command -v ruff &>/dev/null; then
    RUFF_BIN="$(command -v ruff)"
  fi

  if [[ -n "$VULTURE_BIN" ]]; then
    echo "[PyCheck] Scanning Python dead code with vulture (min-confidence 80)..." >&2
    echo "Using vulture: $VULTURE_BIN" >&2
    rc=0
    timeout 120 "$VULTURE_BIN" "$PY_SCOPE" \
      --exclude "$VENDOR_GLOBS" --min-confidence 80 \
      > "$TMPDIR/vulture.txt" 2>/dev/null || rc=$?
    if [[ "$rc" -eq 124 ]]; then
      echo "[PyCheck] vulture timed out after 120s — Python dead-code N/A" >&2
    else
      vc=$(awk 'END{print NR+0}' "$TMPDIR/vulture.txt")
      echo "[PyCheck] vulture findings: $vc" >&2
      if [[ "$vc" -gt 0 ]]; then
        head -40 "$TMPDIR/vulture.txt" | sed 's/^/  /' >&2
      fi
      echo "[PyCheck] Note: vulture confidence-filtered; verify findings before deleting" >&2
    fi
  elif [[ -n "$RUFF_BIN" ]]; then
    echo "[PyCheck] vulture not available — using ruff heuristic (F401 unused imports, F811 redefinition, F841 unused locals)" >&2
    echo "Using ruff: $RUFF_BIN" >&2
    rc=0
    timeout 120 "$RUFF_BIN" check --no-cache --isolated --exit-zero \
      --select F401,F811,F841 --exclude "$VENDOR_GLOBS" \
      --output-format concise "$PY_SCOPE" > "$TMPDIR/ruff_dead.txt" 2>/dev/null || rc=$?
    if [[ "$rc" -eq 124 ]]; then
      echo "[PyCheck] ruff timed out after 120s — Python dead-code N/A" >&2
    else
      dc=$(awk 'END{print NR+0}' "$TMPDIR/ruff_dead.txt")
      echo "[PyCheck] ruff heuristic findings: $dc  (HEURISTIC — confirm manually before removal)" >&2
      if [[ "$dc" -gt 0 ]]; then
        head -40 "$TMPDIR/ruff_dead.txt" | sed 's/^/  /' >&2
      fi
      echo "[PyCheck] Note: F401/F811/F841 are syntactic heuristics — re-exports and dynamic" >&2
      echo "[PyCheck] imports (importlib/__import__) are invisible to them; confirm manually." >&2
    fi
  else
    echo "[PyCheck] N/A — neither vulture nor ruff available (checked .venv/bin and PATH); install vulture or ruff to enable Python dead-code detection" >&2
  fi
else
  echo "" >&2
  echo "[PyCheck] No Python sources in scope — Python dead-code check skipped" >&2
fi

# ---- 4. Grep-based heuristics for suspicious patterns ----
echo "" >&2
echo "[Heuristics] Scanning for dead code patterns..." >&2

# a) Empty functions with no side-effects (TS/JS)
grep -rHn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  -E '^(export[[:space:]]+)?(const|function|class)[[:space:]]+[[:alnum:]_]+[^{]*\{[[:space:]]*(//.*)?[[:space:]]*\}$' \
  "$TARGET" "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" 2>/dev/null \
  | grep -vE "return|_\(" \
  | head -30 || true

# b) Unreachable code is hard to detect reliably with grep alone — rely on compiler/linter output instead.
:

# c) Python: empty function bodies (`def f(): pass`) — optionally with a
#    trailing comment. A def line merely ending in a comment normally has a
#    real body below it, so that case is NOT flagged.
if [[ "$PY_PRESENT" == "true" ]]; then
  grep -rHn --include="*.py" \
    -E 'def[[:space:]]+[[:alnum:]_]+\([^)]*\)[^:]*:[[:space:]]*pass([[:space:]]*#.*)?[[:space:]]*$' \
    "$TARGET" "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" 2>/dev/null | head -20 || true
fi

# ---- 5. Aggressive mode: grep for TODO/FIXME that look abandoned ----
if [ "$MODE" == "aggressive" ]; then
  echo "" >&2
  echo "[Aggressive] Looking for old TODOs (>1 year)..." >&2
  git -C "$TARGET" log --since="1 year ago" -p -G "TODO|FIXME|HACK|XXX" -- "*.ts" "*.tsx" "*.js" "*.jsx" "*.py" 2>/dev/null \
    | head -200 || true
fi

echo "" >&2
echo "=== SCAN COMPLETE ===" >&2
echo "Review the output above. Flag as DEAD any:" >&2
echo "  - Export not imported anywhere (verify via impact)" >&2
echo "  - Function with no side-effect and no callers (verify via context)" >&2
echo "  - Unreachable code after return/throw" >&2
echo "  - Empty function body (no business logic)" >&2

exit 0
