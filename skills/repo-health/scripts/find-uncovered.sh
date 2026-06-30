#!/usr/bin/env bash
#
# find-uncovered.sh
# Identifies code lines not covered by tests.
# Works with lcov/gcov (C), istanbul/jest-coverage (JS), coverage-py (Python).
#
# Usage: ./find-uncovered.sh <coverage_report_dir_or_file>
# Output: LIST of uncovered files with uncovered line ranges
#
set -euo pipefail

COVER_DATA="${1:-coverage}"

echo "=== UNCOVERED CODE ANALYSIS ===" >&2
echo "Coverage data: $COVER_DATA" >&2
echo "" >&2

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# -------- Istanbul/Jest JSON coverage format --------
# coverage-final.json format: {"/abs/path/file.js": { s: {"1": 0, ...}, ... }, ...}
if [ -f "$COVER_DATA" ] && jq -e 'type=="object" and (to_entries[0].value | has("s"))' "$COVER_DATA" >/dev/null 2>&1; then
  echo "Detected Istanbul/Jest JSON format" >&2

  jq -r '
    to_entries[]
    | .key as $file
    | (.value.s | to_entries) as $stmts
    | ($stmts | length) as $total
    | ($stmts | map(select(.value > 0)) | length) as $covered
    | (if $total == 0 then 100 else (($covered * 100) / $total) end) as $pct
    | select($pct < 50)
    | "LOW_COVERAGE: \($file) (stmt_pct=\($pct)%)"' "$COVER_DATA" 1>&2 2>/dev/null
  jq -r 'to_entries[] | select((.value.s | to_entries | map(.value) | max) == 0) | .key' "$COVER_DATA" 2>/dev/null \
    | while read -r f; do echo "ZERO_COVERAGE: $f" >&2; done
# -------- LCOV format --------
elif [ -d "$COVER_DATA" ] && ls "$COVER_DATA"/*.info "$COVER_DATA"/*.lcov 2>/dev/null | head -1 | grep -q .; then
  echo "Detected LCOV format" >&2
  
  for INFO in "$COVER_DATA"/*.info "$COVER_DATA"/*.lcov; do
    [ -f "$INFO" ] || continue
    UNCOVERED=$(grep -E "^SF:|^DA:" "$INFO" 2>/dev/null | grep -v "DA:.*,[1-9][0-9]*$" | grep "DA:" || true)
    ZERO_HITS=$(grep -E "^DA:[0-9]+,0$" "$INFO" 2>/dev/null | cut -d: -f2 | cut -d, -f1 | sort -n | uniq | head -20)
    if [ -n "$ZERO_HITS" ]; then
      echo "UNCOVERED:${INFO}: ${ZERO_HITS}" >&2
    fi
  done

# -------- Cobertura XML --------
elif ls "$COVER_DATA"/*.xml 2>/dev/null | head -1 | grep -q .; then
  echo "Detected Cobertura XML format" >&2
  for XML in "$COVER_DATA"/*.xml; do
    [ -f "$XML" ] || continue
    xp=$(which xpath || which xmlstarlet 2>/dev/null || echo "")
    if [ -n "$xp" ]; then
      "$xp" "//class[@line-rate='0']/@filename" "$XML" 2>/dev/null || true
    else
      grep -E 'line-rate="0"' "$XML" -A1 2>/dev/null | grep "filename" || true
    fi
  done

# -------- Python coverage.py --------
elif [ -f "$COVER_DATA" ] && grep -q "missing_lines" "$COVER_DATA" 2>/dev/null; then
  echo "Detected Python coverage.py JSON format" >&2
  jq -r '.[] | select(.missing_lines | length > 0) | .filename, .missing_lines[]' \
    "$COVER_DATA" 2>/dev/null | paste -d: - - | head -30

else
  echo "Unsupported coverage format or no coverage data found at: $COVER_DATA" >&2
  echo "Supported: Istanbul JSON, LCOV, Cobertura XML, Python coverage JSON" >&2
fi

echo "" >&2
echo "=== GAPS FOUND ===" >&2
echo "The above files/lines have either 0% or below-threshold coverage." >&2
echo "Prioritize adding tests for:" >&2
echo "  1. Files with ZERO coverage — greenfield tests needed" >&2
echo "  2. Files with <50% coverage — substantial test additions needed" >&2
echo "  3. Hot-path code (high cyclomatic complexity) with low coverage" >&2
echo "Use context() on high-complexity functions with no coverage" >&2

exit 0