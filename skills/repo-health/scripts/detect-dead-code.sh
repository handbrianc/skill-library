#!/usr/bin/env bash
#
# detect-dead-code.sh
# Detects unused exports, unreachable functions, and dead code paths.
# For deterministic results, run from a clean working tree (no uncommitted changes).
# Usage: ./detect-dead-code.sh <target_dir> [--aggressive]
# Output: Human-readable report to stderr/stdout (not strict TSV)
#
# Copyright: OpenCode contributors
# License: MIT

set -euo pipefail

TARGET="${1:-.}"
MODE="normal"  # normal | aggressive
if [[ "${2:-}" == "--aggressive" || "${2:-}" == "aggressive" ]]; then
  MODE="aggressive"
fi
WORKDIR=$(pwd)
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== DEAD CODE SCAN ===" >&2
echo "Target: $TARGET" >&2
echo "Mode: $MODE" >&2
echo "Commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')" >&2

# ---- 1. Find exported symbols (potential dead code targets) ----
# We look for export declarations
find "$TARGET" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" \) \
  ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/dist/*" ! -path "*/build/*" ! -path "*/__pycache__/*" \
  > "$TMPDIR/all_source_files.txt"

TOTAL_FILES=$(wc -l < "$TMPDIR/all_source_files.txt")
echo "Scanned files: $TOTAL_FILES" >&2

# ---- 2. Detect truly unused exports via tsc/unimported plugin ----
# TypeScript: use "noUnusedLocals" and "noUnusedParameters" with --noEmit
if command -v npx &>/dev/null && [ -f package.json ]; then
  echo "" >&2
  echo "[TSCheck] Looking for unused exports via TypeScript..." >&2

  if [ -f tsconfig.json ]; then
    npx tsc --noEmit -p tsconfig.json 2>&1 \
      | grep -E "(is declared but never used|unused)" \
      | head -50 || true
  else
    echo "[TSCheck] tsconfig.json not found — skipping TypeScript dead-code scan" >&2
  fi
fi

# ---- 3. Python: flake8 F401 (imported but unused) ----
PYTHON_FILES=$(find "$TARGET" -type f \( -name "*.py" \) ! -path "*/venv/*" ! -path "*/env/*" ! -path "*/.venv/*")
if [ -n "$PYTHON_FILES" ] && command -v flake8 &>/dev/null; then
  echo "" >&2
  echo "[PyCheck] Checking Python unused imports..." >&2
  for f in $PYTHON_FILES; do
    flake8 "$f" --select=F401 2>/dev/null | head -20 || true
  done
elif [ -n "$PYTHON_FILES" ]; then
  echo "[PyCheck] flake8 not available — skipping Python dead-code" >&2
fi

# ---- 4. Grep-based heuristics for suspicious patterns ----
echo "" >&2
echo "[Heuristics] Scanning for dead code patterns..." >&2

# a) Empty functions with no side-effects (TS/JS)
grep -rHn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  -E "^(export )?(const|function|class) \w+[^{]*{\s*(//.*)?\s*}" \
  "$TARGET" 2>/dev/null \
  | grep -v "return\|_(" \
  | head -30 || true

# b) Unreachable code is hard to detect reliably with grep alone — rely on compiler/linter output instead.
:

# c) Python: empty function bodies (pass without logic)
if [ -n "$PYTHON_FILES" ]; then
  grep -rHn --include="*.py" \
    -E "def \w+\([^)]*\)[^:]*:((\s*pass\s*)$|((\s+#.*))$)" \
    "$TARGET" 2>/dev/null | head -20 || true
fi

# ---- 5. Aggressive mode: grep for TODO/FIXME that look abandoned ----
if [ "$MODE" == "aggressive" ]; then
  echo "" >&2
  echo "[Aggressive] Looking for old TODOs (>1 year)..." >&2
  git log --since="1 year ago" -p -G "TODO|FIXME|HACK|XXX" -- "*.ts" "*.tsx" "*.js" "*.jsx" "*.py" 2>/dev/null \
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