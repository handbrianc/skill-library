#!/usr/bin/env bash
# scan-tests.sh — Test Suite Health Scanner (dispatcher)
#
# Usage:
#   ./scan-tests.sh                    # Run all steps
#   ./scan-tests.sh --check-presence   # List test dirs/files/scripts
#   ./scan-tests.sh --run-coverage     # Auto-detect & run test suite with coverage
#   ./scan-tests.sh --parse-results    # Parse test output via parse-test-results.sh
#   ./scan-tests.sh --slow-tests       # Extract timing, find 20 slowest tests
#   ./scan-tests.sh --coverage-report  # Extract coverage % from output
#
# Exit 0 always — test failures are data, not script failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source sub-scripts (each also sources lib/common.sh which overwrites SCRIPT_DIR)
source "$SCRIPT_DIR/scan-tests-presence.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scan-tests-coverage.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scan-tests-parse.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scan-tests-slow.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scan-tests-report.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEST_OUTPUT="/tmp/test-output.txt"

# --- Main ---

RUN_ALL=true
RUN_CHECK=false
RUN_COV=false
RUN_PARSE=false
RUN_SLOW=false
RUN_REPORT=false

if [[ $# -gt 0 ]]; then
  RUN_ALL=false
  for arg in "$@"; do
    case "$arg" in
      --check-presence)  RUN_CHECK=true ;;
      --run-coverage)    RUN_COV=true ;;
      --parse-results)   RUN_PARSE=true ;;
      --slow-tests)      RUN_SLOW=true ;;
      --coverage-report) RUN_REPORT=true ;;
      *)
        echo "Unknown option: $arg"
        echo "Usage: $0 [--check-presence] [--run-coverage] [--parse-results] [--slow-tests] [--coverage-report]"
        exit 0
        ;;
    esac
  done
fi

# Support the scripts dir being accessed via symlink or direct path
if [[ ! -d "$SCRIPT_DIR" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

if $RUN_ALL || $RUN_CHECK; then
  check_presence
fi

if $RUN_ALL || $RUN_COV; then
  run_coverage
fi

if $RUN_ALL || $RUN_PARSE; then
  parse_results
fi

if $RUN_ALL || $RUN_SLOW; then
  slow_tests
fi

if $RUN_ALL || $RUN_REPORT; then
  coverage_report
fi

exit 0
