#!/usr/bin/env bash
#
# parse-test-results.sh
# Parses test suite output (pytest, Vitest, Jest, Mocha, Go test, unittest)
# for pass/fail/error/skip/retry counts and slowest tests.
#
# Usage: ./parse-test-results.sh <test_output_file>
# Output: Structured sections: SUMMARY | SLOWEST | FAILED | ERRORS | SKIPPED,
#         then machine-readable COUNT lines on stderr:
#         PASSED= FAILED= SKIPPED= ERRORS= RETRIED= FRAMEWORK= XFAILED= ...
#
# pytest signatures are checked FIRST: they are the most specific (pytest
# summary bars like "=== 5 passed, 1 failed in 2.1s ===" and the
# "test session starts" header never appear in JS-runner output), so raw
# pytest output is parsed as a first-class citizen instead of falling through
# to the generic/unknown branch.
#
set -euo pipefail

INPUT="${1:-/tmp/test-output.txt}"

echo "=== TEST RESULT PARSER ===" >&2
echo "Parsing: $INPUT" >&2

if [ ! -f "$INPUT" ]; then
  echo "File not found: $INPUT — cannot parse" >&2
  exit 1
fi

# -------- Detect test framework --------
FRAMEWORK="unknown"
if grep -qE '(test session starts|short test summary info|no tests ran)' "$INPUT" 2>/dev/null \
   || grep -qE '^[ =]*[0-9]+ (passed|failed|error)' "$INPUT" 2>/dev/null \
   || grep -qE '^[0-9]+(/[0-9]+)? tests? collected' "$INPUT" 2>/dev/null; then
  FRAMEWORK="pytest"
elif grep -q "vitest" "$INPUT" 2>/dev/null; then
  FRAMEWORK="vitest"
elif grep -q "jest" "$INPUT" 2>/dev/null; then
  FRAMEWORK="jest"
elif grep -q "go test" "$INPUT" 2>/dev/null; then
  FRAMEWORK="gotest"
elif grep -q "mocha" "$INPUT" 2>/dev/null; then
  FRAMEWORK="mocha"
elif grep -qE '^Ran [0-9]+ tests? in' "$INPUT" 2>/dev/null; then
  FRAMEWORK="unittest"
fi

echo "Detected framework: $FRAMEWORK" >&2
echo "" >&2

# Initialize counters to defaults before framework-specific parsing (set -u safety)
PASSED=0
FAILED=0
SKIPPED=0
ERROR_COUNT=0
RETRIED=0
XFAILED=0
XPASSED=0
DESELECTED=0
COLLECTED=0
WARNINGS=0

# ============================================================
# PYTEST FORMAT
# ============================================================
if [ "$FRAMEWORK" == "pytest" ]; then
  echo "--- SUMMARY ---" >&2
  grep -E "(passed|failed|error|skipped|xfailed|xpassed|deselected|warnings|no tests ran|collected)" "$INPUT" | tail -10 >&2 || true

  PASSED=$(perl -ne 'if (/(\d+)\s+passed\b/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  FAILED=$(perl -ne 'if (/(\d+)\s+failed\b/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  SKIPPED=$(perl -ne 'if (/(\d+)\s+skipped\b/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  ERROR_COUNT=$(perl -ne 'if (/(\d+)\s+errors?\b/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  XFAILED=$(perl -ne 'if (/(\d+)\s+xfailed\b/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  XPASSED=$(perl -ne 'if (/(\d+)\s+xpassed\b/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  DESELECTED=$(perl -ne 'if (/(\d+)\s+deselected\b/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  WARNINGS=$(perl -ne 'if (/(\d+)\s+warnings?\b/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  COLLECTED=$(perl -ne 'if (/(\d+)\s+tests?\s+collected/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")

  if grep -q "no tests ran" "$INPUT" 2>/dev/null; then
    echo "NOTE: pytest reported 'no tests ran' (empty selection or collection error)" >&2
  fi

  echo "" >&2
  echo "--- SLOWEST ---" >&2
  # pytest --durations table: "3.20s call     tests/test_x.py::test_y"
  grep -E '^[0-9]+(\.[0-9]+)?s\s+(call|setup|teardown)\s' "$INPUT" 2>/dev/null \
    | sort -rn | head -20 | sed 's/^/  SLOW: /' >&2 || true
  # pytest -v node-id timing: "test_foo.py::bar [123ms]" (legacy format)
  grep -oE '\[[0-9]+\.?[0-9]*ms\]' "$INPUT" | \
    sort -t'm' -k1 -rn | head -20 || \
    grep -oE '[0-9]+\.?[0-9]*ms' "$INPUT" | sort -rn | head -20 || true

  echo "" >&2
  echo "--- FAILED ---" >&2
  # -ra short summary lines: "FAILED tests/test_x.py::test_y - AssertionError: ..."
  grep -E '^(FAILED|ERROR) ' "$INPUT" 2>/dev/null | head -40 >&2 || true
  # verbose run failure blocks: "_____ test_name _____"
  grep -B3 -A 5 "FAILED\|ERROR" "$INPUT" | head -60 >&2 || true

# ============================================================
# JEST/VITEST FORMAT
# ============================================================
elif [ "$FRAMEWORK" == "jest" ] || [ "$FRAMEWORK" == "vitest" ]; then
  # Summary line: "Tests: X passed, Y failed, Z total, W skipped"
  echo "--- SUMMARY ---" >&2
  grep -E "Tests?:" "$INPUT" | grep -v "^$" | tail -10 >&2 || true

  PASSED=$(perl -ne 'if (/Tests?:.*?\b(\d+)\s+passed\b/i) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  FAILED=$(perl -ne 'if (/Tests?:.*?\b(\d+)\s+failed\b/i) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  SKIPPED=$(perl -ne 'if (/Tests?:.*?\b(\d+)\s+skipped\b/i) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  ERROR_COUNT=$(perl -ne 'if (/Tests?:.*?\b(\d+)\s+errors?\b/i) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
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
  grep -A 5 -E "^  (✗|×)|^  FAIL|^[[:space:]]*[0-9]+\)" "$INPUT" 2>/dev/null | head -60 >&2 || true

  echo "" >&2
  echo "--- ERRORS ---" >&2
  grep -B2 -A 5 -E "ERR_TIMEOUT|Uncaught|SyntaxError|ReferenceError|TypeError.*at " "$INPUT" 2>/dev/null | head -40 >&2 || true

  echo "" >&2
  echo "--- SKIPPED ---" >&2
  grep -E "^  ○ |skip|SKIP|todo|TODO" "$INPUT" 2>/dev/null | head -20 >&2 || true

# ============================================================
# GO TEST FORMAT
# ============================================================
elif [ "$FRAMEWORK" == "gotest" ]; then
  echo "--- SUMMARY ---" >&2
  grep -E "^ok|^FAIL|^---" "$INPUT" | tail -20 >&2 || true

  echo "" >&2
  echo "--- SLOWEST ---" >&2
  grep -oE '[0-9]+\.?[0-9]*s' "$INPUT" | \
    sort -t's' -k1 -rn | head -20 || true

  echo "" >&2
  echo "--- FAILED ---" >&2
  grep -B2 -A 5 "--- FAIL:" "$INPUT" | head -40 >&2 || true

# ============================================================
# PYTHON UNITTEST FORMAT
# ============================================================
elif [ "$FRAMEWORK" == "unittest" ]; then
  echo "--- SUMMARY ---" >&2
  grep -E "^Ran [0-9]+ tests? in|^OK|^FAILED" "$INPUT" | tail -5 >&2 || true

  RAN=$(perl -ne 'if (/^Ran (\d+) tests?/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  FAILED=$(perl -ne 'if (/FAILED \(failures=(\d+)/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  ERROR_COUNT=$(perl -ne 'if (/errors=(\d+)/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  SKIPPED=$(perl -ne 'if (/skipped=(\d+)/) { $v=$1 } END { print defined($v) ? $v : 0 }' "$INPUT")
  if [ "$RAN" -ge $(( FAILED + ERROR_COUNT + SKIPPED )) ]; then
    PASSED=$(( RAN - FAILED - ERROR_COUNT - SKIPPED ))
  else
    PASSED=$RAN
  fi

  echo "" >&2
  echo "--- FAILED ---" >&2
  grep -B2 -A 5 -E "^(FAIL|ERROR):" "$INPUT" 2>/dev/null | head -40 >&2 || true

# ============================================================
# GENERIC FALLBACK
# ============================================================
else
  echo "Unknown test framework — using generic parsing" >&2
  echo "" >&2
  grep -E "^(PASS|FAIL|OK|ERROR|Tests?)" "$INPUT" | tail -20 >&2 || true
  grep -E "(passed|failed|skipped|error)s?:?" "$INPUT" | tail -10 >&2 || true
  PASSED=$(grep -oE '[0-9]+ passed' "$INPUT" 2>/dev/null | head -1 | grep -oE '^[0-9]+' || echo "0")
  FAILED=$(grep -oE '[0-9]+ failed' "$INPUT" 2>/dev/null | head -1 | grep -oE '^[0-9]+' || echo "0")
fi

echo "" >&2
echo "=== PARSING COMPLETE ===" >&2
echo "Machine-readable counts:" >&2
echo "FRAMEWORK=$FRAMEWORK" >&2
echo "PASSED=${PASSED:-0}" >&2
echo "FAILED=${FAILED:-0}" >&2
echo "SKIPPED=${SKIPPED:-0}" >&2
echo "ERRORS=${ERROR_COUNT:-0}" >&2
echo "RETRIED=${RETRIED:-0}" >&2
echo "XFAILED=${XFAILED:-0}" >&2
echo "XPASSED=${XPASSED:-0}" >&2
echo "DESELECTED=${DESELECTED:-0}" >&2
echo "COLLECTED=${COLLECTED:-0}" >&2
echo "WARNINGS=${WARNINGS:-0}" >&2

exit 0
