#!/usr/bin/env bats
# ============================================================================
# bats tests for scan-tests.sh
# ============================================================================

setup() {
  export TEST_PROJECT="${BATS_TEST_DIRNAME}/../fixtures/sample-project"
  export SCAN_TESTS="${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/scan-tests.sh"
}

@test "scan-tests --check-presence detects test files" {
  run bash "$SCAN_TESTS" --check-presence "$TEST_PROJECT"
  [ "$status" -eq 0 ]
}

@test "scan-tests --check-presence handles dirs without tests" {
  run bash "$SCAN_TESTS" --check-presence "$BATS_TEST_DIRNAME"
  [ "$status" -eq 0 ]
}

@test "scan-tests --parse-results handles empty output file" {
  TMPFILE=$(mktemp)
  run bash "$SCAN_TESTS" --parse-results "$TMPFILE"
  [ "$status" -eq 0 ]
  rm -f "$TMPFILE"
}

@test "scan-tests --parse-results handles TAP output" {
  TMPFILE=$(mktemp)
  cat > "$TMPFILE" << 'EOF'
TAP version 14
1..3
ok 1 - greet returns greeting
not ok 2 - add returns sum
ok 3 - handles negative # SKIP known issue
EOF
  run bash "$SCAN_TESTS" --parse-results "$TMPFILE"
  [ "$status" -eq 0 ]
  rm -f "$TMPFILE"
}

@test "scan-tests.sh script exists" {
  [ -f "$SCAN_TESTS" ]
}

@test "scan-tests sub-scripts exist" {
  SCRIPT_DIR="$(dirname "$SCAN_TESTS")"
  [ -f "$SCRIPT_DIR/scan-tests-presence.sh" ]
  [ -f "$SCRIPT_DIR/scan-tests-coverage.sh" ]
  [ -f "$SCRIPT_DIR/scan-tests-parse.sh" ]
  [ -f "$SCRIPT_DIR/scan-tests-slow.sh" ]
  [ -f "$SCRIPT_DIR/scan-tests-report.sh" ]
}

@test "run-scan-suite.sh exists" {
  SCRIPT_DIR="$(dirname "$SCAN_TESTS")"
  [ -f "$SCRIPT_DIR/run-scan-suite.sh" ]
}
