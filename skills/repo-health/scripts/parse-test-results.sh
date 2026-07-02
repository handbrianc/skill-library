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
trap 'rm -rf "$TMPDIR"' EXIT
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

# Initialize counters to defaults before framework-specific parsing (set -u safety)
PASSED=0
FAILED=0
SKIPPED=0
ERROR_COUNT=0
RETRIED=0

# ============================================================
# JEST/VITEST FORMAT
# ============================================================
if [ "$FRAMEWORK" == "jest" ] || [ "$FRAMEWORK" == "vitest" ]; then
  # Summary line: "Tests: X passed, Y failed, Z total, W skipped"
  echo "--- SUMMARY ---" >&2
  grep -E "Tests?:" "$INPUT" | grep -v "^$" | tail -10 >&2
  
  PASSED=$(perl -ne 'if (/Tests?:.*?\b(\d+)\s+passed\b/i) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  FAILED=$(perl -ne 'if (/Tests?:.*?\b(\d+)\s+failed\b/i) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  SKIPPED=$(perl -ne 'if (/Tests?:.*?\b(\d+)\s+skipped\b/i) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  ERROR_COUNT=$(perl -ne 'if (/Tests?:.*?\b(\d+)\s+errors?\b/i) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  _TOTAL=$(perl -ne 'if (/Tests?:.*?\b(\d+)\s+total\b/i) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  RETRIED=$(grep -ciE 'Retry\(|retry' "$INPUT" 2>/dev/null || true)
  
  echo "" >&2
  echo "--- SLOWEST TESTS ---" >&2
  # Vitest: "✓ my-test [123ms]"
  # Jest verbose: " PASS  src/foo.test.ts (5 s)"
  grep -E "^  (✓|✗|○|●|[√×✕]) " "$INPUT" \
    | grep -E '\[[0-9]+(\.[0-9]+)?(ms|s|m)\]' \
    | awk 'match($0, /\[([0-9.]+)(ms|s|m)\]/, a) { num=a[1]; unit=a[2]; ms=(unit=="ms")?num:(unit=="s")?num*1000:num*60000; printf "%.0f\t%s\n", ms, $0 }' \
    | sort -nr | head -20 | cut -f2- \
    | while IFS= read -r line; do
        echo "  SLOW: ${line}" >&2
      done
  
  echo "" >&2
  echo "--- FAILED TESTS ---" >&2
  grep -A 5 -E "^  (✗|×)|^  FAIL|^[[:space:]]*[0-9]+\)" "$INPUT" 2>/dev/null | head -60 >&2
  
  echo "" >&2
  echo "--- ERRORS ---" >&2
  grep -B2 -A 5 -E "ERR_TIMEOUT|Uncaught|SyntaxError|ReferenceError|TypeError.*at " "$INPUT" 2>/dev/null | head -40 >&2
  
  echo "" >&2
  echo "--- SKIPPED ---" >&2
  grep -E "^  ○ |skip|SKIP|todo|TODO" "$INPUT" 2>/dev/null | head -20 >&2

# ============================================================
# PYTEST FORMAT
# ============================================================
elif [ "$FRAMEWORK" == "pytest" ]; then
  echo "--- SUMMARY ---" >&2
  grep -E "passed|failed|error|skipped|rerun" "$INPUT" | tail -10 >&2
  
  FAILED=$(perl -ne 'if (/(\d+) failed/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  PASSED=$(perl -ne 'if (/(\d+) passed/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  SKIPPED=$(perl -ne 'if (/(\d+) skipped/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  ERROR_COUNT=$(perl -ne 'if (/(\d+) error/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  
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
echo "PASSED=${PASSED:-0}" >&2
echo "FAILED=${FAILED:-0}" >&2
echo "SKIPPED=${SKIPPED:-0}" >&2
echo "ERRORS=${ERROR_COUNT:-0}" >&2
echo "RETRIED=${RETRIED:-0}" >&2

exit 0