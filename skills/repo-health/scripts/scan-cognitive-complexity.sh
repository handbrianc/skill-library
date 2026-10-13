#!/usr/bin/env bash
#
# scan-cognitive-complexity.sh
# Measures both cyclomatic and cognitive complexity.
# Relies on ESLint complexity rule for TS/JS (only when installed locally),
# and on ruff (C901/PLR091x) for Python. Grep heuristics flag cognitive
# complexity red flags for TS/JS.
#
# Usage: ./scan-cognitive-complexity.sh <target_dir>
# Output: Text report to stderr summarizing:
#   - ESLint complexity-rule violations (cyclomatic complexity, TS/JS)
#   - ruff complexity-rule violations (cyclomatic complexity, Python)
#   - Heuristic cognitive-complexity red flags (CSV: file,line,pattern,score)
# Vendor directories (.venv, venv, node_modules, __pycache__, site-packages,
# *.dist-info, .git) are never scanned. Missing tools degrade to N/A.
set -euo pipefail

TARGET="${1:-.}"

trap 'exit 0' EXIT
trap '' PIPE

if [[ ! -d "$TARGET" ]]; then
  echo "Target directory not found: $TARGET — complexity scan N/A" >&2
  exit 0
fi

echo "=== COGNITIVE/CYCLOMATIC COMPLEXITY SCAN ===" >&2
echo "Target: $TARGET" >&2
echo "" >&2

TMPDIR=$(mktemp -d)
OUT="$TMPDIR/complexity_out.csv"
COGNITIVE_FLAGS="$TMPDIR/cognitive_flags.csv"

trap 'rm -rf "$TMPDIR"; exit 0' EXIT

VENDOR_GLOBS=".git,.venv,venv,node_modules,__pycache__,site-packages,*.dist-info,*.egg-info,.tox,.mypy_cache,.pytest_cache,.ruff_cache,.hypothesis,dist,build"
VENDOR_EXCLUDE=( .git .venv venv node_modules __pycache__ site-packages '*.dist-info' '*.egg-info' .tox .mypy_cache .pytest_cache .ruff_cache .hypothesis dist build )

# ---- ESLint-based cyclomatic complexity for TS/JS ----------
# Only attempt when a Node project context exists AND eslint is installed
# locally — `npx eslint` without a local install triggers a network download
# that can hang the scan for minutes.
# Scope detection writes find's output to a temp file instead of piping into
# `grep -q`: under pipefail + `trap '' PIPE`, grep -q exits after the first
# match, find's next write fails with EPIPE, find exits non-zero, and the
# pipeline's non-zero status makes the condition false even when sources exist
# (a walk-duration race — small trees win, large ones silently lose).
find "$TARGET" \( -type d \( -name node_modules -o -name .git -o -name .venv -o -name venv -o -name dist -o -name build \) -prune \) \
     -o \( -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) -print \) \
     2>/dev/null > "$TMPDIR/js_scope.txt" || true
if [[ -s "$TMPDIR/js_scope.txt" ]]; then

  echo "JS/TS sources detected — checking for a local eslint..." >&2

  if ! command -v npx &>/dev/null; then
    echo "npx not available — skipping ESLint complexity analysis." >&2
  elif ! command -v jq &>/dev/null; then
    echo "jq not available — skipping ESLint complexity JSON parsing." >&2
  elif [[ ! -f "package.json" && ! -f "$TARGET/package.json" ]]; then
    echo "No package.json (target or CWD) — skipping ESLint complexity analysis (Node project context required)." >&2
  elif ! npx --no-install eslint --version &>/dev/null; then
    echo "eslint not installed locally (npx --no-install) — ESLint complexity analysis N/A." >&2
  else
    echo "Running ESLint complexity analysis..." >&2
    rc=0
    timeout 120 npx --no-install eslint "$TARGET" \
      --parser @typescript-eslint/parser \
      --plugin @typescript-eslint \
      --rule 'complexity: ["warn", 15]' \
      --format json 2>/dev/null > "$TMPDIR/eslint.json" || rc=$?
    if [[ "$rc" -eq 124 ]]; then
      echo "ESLint timed out after 120s — N/A" >&2
    else
      jq -r '.[]
        | select(.messages != null)
        | .filePath as $fp
        | .messages[]
        | select(.ruleId and (.ruleId | contains("complexity")))
        | [$fp, (.line|tostring), (.column|tostring), (.message|gsub("[\t\r\n]+";" ")), .ruleId]
        | @tsv' "$TMPDIR/eslint.json" 2>/dev/null | \
      while IFS=$'\t' read -r filepath line _col msg _rule; do
        printf '%s,%s,"%s"\n' "$filepath" "$line" "${msg//\"/\"\"}" >> "$OUT"
      done || true
    fi
  fi
  if [ -s "$OUT" ]; then
    echo "Cyclomatic Complexity Violations (ESLint):" >&2
    sort -t, -k1,1 -k2,2n "$OUT" | uniq >&2
    echo "" >&2
  fi
else
  echo "No JS/TS sources in scope — ESLint complexity analysis skipped." >&2
fi

# ---- Cyclomatic complexity for Python via ruff ------------------------------
# Same temp-file scope detection as the JS/TS check above (pipefail race).
find "$TARGET" \( -type d \( -name .venv -o -name venv -o -name node_modules -o -name __pycache__ -o -name '*.dist-info' -o -name .git \) -prune \) \
     -o \( -type f -name '*.py' -print \) \
     2>/dev/null > "$TMPDIR/py_scope.txt" || true
if [[ -s "$TMPDIR/py_scope.txt" ]]; then

  RUFF_BIN=""
  if [[ -x "$TARGET/.venv/bin/ruff" ]]; then
    RUFF_BIN="$TARGET/.venv/bin/ruff"
  elif [[ -x "$TARGET/venv/bin/ruff" ]]; then
    RUFF_BIN="$TARGET/venv/bin/ruff"
  elif command -v ruff &>/dev/null; then
    RUFF_BIN="$(command -v ruff)"
  fi

  if [[ -n "$RUFF_BIN" ]]; then
    echo "Running ruff complexity analysis (C901/PLR0911/0912/0913/0915)..." >&2
    echo "Using ruff: $RUFF_BIN" >&2
    rc=0
    timeout 180 "$RUFF_BIN" check --no-cache --isolated --exit-zero \
      --select C901,PLR0911,PLR0912,PLR0913,PLR0915 \
      --exclude "$VENDOR_GLOBS" \
      --output-format concise \
      "$TARGET" > "$TMPDIR/ruff_cx.txt" 2>/dev/null || rc=$?
    if [[ "$rc" -eq 124 ]]; then
      echo "ruff timed out after 180s — Python complexity N/A" >&2
    else
      total=$(awk 'END{print NR+0}' "$TMPDIR/ruff_cx.txt")
      echo "Ruff complexity findings: $total" >&2
      if [[ "$total" -gt 0 ]]; then
        { grep -oE ' (C901|PLR0911|PLR0912|PLR0913|PLR0915) ' "$TMPDIR/ruff_cx.txt" || true; } \
          | sort | uniq -c | sort -rn | sed 's/^/  /' >&2
        echo "Top offenders (thresholds: >15 MEDIUM, >25 HIGH, >40 CRITICAL):" >&2
        head -25 "$TMPDIR/ruff_cx.txt" | sed 's/^/  /' >&2
      fi
    fi
  else
    echo "ruff not found (checked .venv/bin/ruff and PATH) — Python complexity analysis N/A; install ruff to enable." >&2
  fi
else
  echo "No Python sources in scope — ruff complexity analysis skipped." >&2
fi

# ------- Cognitive complexity — manual heuristics --------------
# Since there's no standard free cognitive complexity tool,
# we use regex-based grep heuristics to find red-flag patterns:
echo '"file","line","pattern","score"' > "$COGNITIVE_FLAGS"  # CSV header

find "$TARGET" \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
     -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
     -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
     -o -name dist -o -name build \) -prune \) \
  -o \( -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" \) -print \) \
  2>/dev/null > "$TMPDIR/src_files.txt" || true

# Red-flag patterns and their cognitive complexity increments:
# Recursion: +3
if grep -P '' <<< '' >/dev/null 2>&1; then
  { grep -rnP --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
    '\\bfunction\\s+(\\w+)\\([^)]*\\)\\s*\\{[^}]*\\b\\1\\s*\\(' \
    "$TARGET" "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" 2>/dev/null || true; } | head -20 | while IFS=: read -r f l _; do
    echo "\"$f\",\"$l\",\"RECURSIVE_CALL\",3" >> "$COGNITIVE_FLAGS"
  done || true
else
  echo "Skipping recursion heuristic (grep -P not available)." >&2
fi

# Ternary nesting (chained ternaries): +2
grep -rn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  -E "\?[[:space:]]*[[:alnum:]_].*\?[[:space:]]*[[:alnum:]_].*\?[[:space:]]*[[:alnum:]_]" \
  "$TARGET" "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" 2>/dev/null | head -20 | while IFS=: read -r f l _; do
  echo "\"$f\",\"$l\",\"CHAINED_TERNARY\",2" >> "$COGNITIVE_FLAGS"
done || true

# Arrow function returning arrow function: +2
grep -rn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  -E "=>[[:space:]]*\(.*\)[[:space:]]*=>[[:space:]]*\(|=>[[:space:]]*\([^)]*\)[[:space:]]*=>[[:space:]]*\{[^}]*=>" \
  "$TARGET" "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" 2>/dev/null | head -20 | while IFS=: read -r f l _; do
  echo "\"$f\",\"$l\",\"NESTED_ARROW\",2" >> "$COGNITIVE_FLAGS"
done || true

# Early returns in loops (confusing flow): +1
grep -rn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  -E "for[[:space:]]*\([^)]+\)[^;]*\{[^}]*return[^}]*\}[^}]*\}[[:space:]]*;" \
  "$TARGET" "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" 2>/dev/null | head -20 | while IFS=: read -r f l _; do
  echo "\"$f\",\"$l\",\"EARLY_RETURN_LOOP\",1" >> "$COGNITIVE_FLAGS"
done || true

if [ -s "$COGNITIVE_FLAGS" ] && [ "$(wc -l < "$COGNITIVE_FLAGS")" -gt 1 ]; then
  echo "Cognitive Complexity Red Flags (score contribution):" >&2
  tail -n +2 "$COGNITIVE_FLAGS" | sort -t, -k4 -rn | uniq >&2
  echo "" >&2
fi

# ------- Aggregated Summary -------
echo "=== COMPLEXITY SUMMARY ===" >&2
HIGH_COMPLEXITY=$(perl -ne 'if (/complexity of (\d+)/i) { $c++ if $1 > 15 } END { print $c // 0 }' "$OUT" 2>/dev/null || echo "0")
echo "Functions exceeding cyclomatic complexity threshold (15, ESLint TS/JS only): $HIGH_COMPLEXITY" >&2

if [[ -s "$TMPDIR/ruff_cx.txt" ]]; then
  RUFF_TOTAL=$(awk 'END{print NR+0}' "$TMPDIR/ruff_cx.txt")
  echo "Functions flagged by ruff complexity rules (Python): $RUFF_TOTAL" >&2
fi

TOTAL_COGNITIVE=$( awk -F',' 'NR>1 {sum+=$4} END {print sum+0}' "$COGNITIVE_FLAGS" 2>/dev/null || echo "0")
echo "Total cognitive complexity penalty points found: $TOTAL_COGNITIVE" >&2

echo "" >&2
echo "Flag thresholds:" >&2
echo "  Cyclomatic > 15: MEDIUM risk" >&2
echo "  Cyclomatic > 25: HIGH risk" >&2
echo "  Cyclomatic > 40: CRITICAL" >&2
echo "  Cognitive flags accumulated: review for refactor" >&2

exit 0
