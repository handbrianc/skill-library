#!/usr/bin/env bash
#
# parse-test-results.sh
# Parses test suite output (Vitest, Jest, Mocha, Pytest, Go test, etc.)
# for pass/fail/error/skip/retry counts and slowest tests.
#
# Usage: ./parse-test-results.sh <test_output_file>
# Output: Structured sections: SUMMARY | SLOWEST | FAILED | ERRORS | SKIPPED
#
set -euo pipefail

INPUT="${1:-/tmp/test-output.txt}"

echo "=== TEST RESULT PARSER ===" >&2
echo "Parsing: $INPUT" >&2

if [ ! -f "$INPUT" ]; then
  echo "File not found: $INPUT — cannot parse" >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# -------- Detect test framework --------
if grep -q "vitest" "$INPUT" 2>/dev/null; then
  FRAMEWORK="vitest"
elif grep -q "jest" "$INPUT" 2>/dev/null; then
  FRAMEWORK="jest"
elif grep -q "pytest" "$INPUT" 2>/dev/null; then
  FRAMEWORK="pytest"
elif grep -q "go test" "$INPUT" 2>/dev/null; then
  FRAMEWORK="gotest"
elif grep -q "mocha" "$INPUT" 2>/dev/null; then
  FRAMEWORK="mocha"
else
  FRAMEWORK="unknown"
fi

echo "Detected framework: $FRAMEWORK" >&2
echo "" >&2

# ============================================================
# JEST/VITEST FORMAT
# ============================================================
if [ "$FRAMEWORK" == "jest" ] || [ "$FRAMEWORK" == "vitest" ]; then
  # Summary line: "Tests: X passed, Y failed, Z total, W skipped"
  echo "--- SUMMARY ---" >&2
  grep -E "Tests?:|" "$INPUT" | grep -v "^$" | tail -10 >&2
  
  PASSED=$(grep -oP "Tests?: \K\d+(?= passed)" "$INPUT" | tail -1 || echo "0")
  FAILED=$(grep -oP "Tests?:.*?, (\d+) failed" "$INPUT" | grep -oP '\d+(?= failed)' | tail -1 || echo "0")
  SKIPPED=$(grep -oP "Tests?:.*?, (\d+) skipped" "$INPUT" | grep -oP '\d+(?= skipped)' | tail -1 || echo "0")
  ERROR_COUNT=$(grep -oP "Tests?:.*?, (\d+) errors" "$INPUT" | grep -oP '\d+(?= errors)' | tail -1 || echo "0")
  TOTAL=$(grep -oP "Tests?: (\d+) " "$INPUT" | grep -oP '\d+' | tail -1 || echo "0")
  RETRIED=$(grep -c "Retry(" "$INPUT" 2>/dev/null || grep -c "retry" "$INPUT" 2>/dev/null || echo "0")
  
  echo "" >&2
  echo "--- SLOWEST TESTS ---" >&2
  # Vitest: "✓ my-test [123ms]"
  # Jest verbose: " PASS  src/foo.test.ts (5 s)"
  grep -E "^  (✓|✗|○|●|[√×✕]) " "$INPUT" \
    | grep -oE '\[[0-9]+(\.[0-9]+)?(ms|s|m)\]' \
    | sort -t'[' -k2 -rn | head -20 | while read -r timing; do
    TIMING_MS=$(echo "$timing" | grep -oP '\d+' | head -1)
    UNIT=$(echo "$timing" | grep -oP '[a-z]+$' )
    echo "  SLOW: ${TIMING_MS}${UNIT}" >&2
  done
  
  echo "" >&2
  echo "--- FAILED TESTS ---" >&2
  grep -A 5 "^  ✗\|^  ×\|^  FAIL\|^\s*\d+\)\) " "$INPUT" 2>/dev/null | head -60 >&2
  
  echo "" >&2
  echo "--- ERRORS ---" >&2
  grep -B2 -A 5 "ERR_TIMEOUT\|Uncaught \|SyntaxError\|ReferenceError\|TypeError.*at " "$INPUT" 2>/dev/null | head -40 >&2
  
  echo "" >&2
  echo "--- SKIPPED ---" >&2
  grep -E "^  ○ |skip|SKIP|todo|TODO" "$INPUT" 2>/dev/null | head -20 >&2

# ============================================================
# PYTEST FORMAT
# ============================================================
elif [ "$FRAMEWORK" == "pytest" ]; then
  echo "--- SUMMARY ---" >&2
  grep -E "passed|failed|error|skipped|rerun" "$INPUT" | tail -10 >&2
  
  FAILED=$(grep -oP "(\d+) failed" "$INPUT" | grep -oP '\d+' | tail -1 || echo "0")
  PASSED=$(grep -oP "(\d+) passed" "$INPUT" | grep -oP '\d+' | tail -1 || echo "0")
  SKIPPED=$(grep -oP "(\d+) skipped" "$INPUT" | grep -oP '\d+' | tail -1 || echo "0")
  ERROR_COUNT=$(grep -oP "(\d+) error" "$INPUT" | grep -oP '\d+' | tail -1 || echo "0")
  
  echo "" >&2
  echo "--- SLOWEST ---" >&2
  # pytest -v shows durations: "test_foo.py::bar [123ms]"
  grep -oE '\[[0-9]+\.?[0-9]*ms\]' "$INPUT" | \
    sort -t'm' -k1 -rn | head -20 || \
    grep -oE '[0-9]+\.?[0-9]*ms' "$INPUT" | sort -rn | head -20
  
  echo "" >&2
  echo "--- FAILED ---" >&2
  grep -B3 -A 5 "FAILED\|ERROR" "$INPUT" | head -60 >&2

# ============================================================
# GO TEST FORMAT
# ============================================================
elif [ "$FRAMEWORK" == "gotest" ]; then
  echo "--- SUMMARY ---" >&2
  grep -E "^ok|^FAIL|^---" "$INPUT" | tail -20 >&2
  
  echo "" >&2
  echo "--- SLOWEST ---" >&2
  grep -oE '[0-9]+\.?[0-9]*s' "$INPUT" | \
    sort -t's' -k1 -rn | head -20
  
  echo "" >&2
  echo "--- FAILED ---" >&2
  grep -B2 -A 5 "--- FAIL:" "$INPUT" | head -40 >&2

# ============================================================
# GENERIC FALLBACK
# ============================================================
else
  echo "Unknown test framework — using generic parsing" >&2
  echo "" >&2
  grep -E "^(PASS|FAIL|OK|ERROR|Tests?)" "$INPUT" | tail -20 >&2
  grep -E "(passed|failed|skipped|error)s?:?" "$INPUT" | tail -10 >&2
fi

echo "" >&2
echo "=== PARSING COMPLETE ===" >&2
echo "Machine-readable counts:" >&2
echo "PASSED=$PASSED" >&2
echo "FAILED=${FAILED:-0}" >&2
echo "SKIPPED=${SKIPPED:-0}" >&2
echo "ERRORS=${ERROR_COUNT:-0}" >&2
echo "RETRIED=${RETRIED:-0}" >&2

exit 0