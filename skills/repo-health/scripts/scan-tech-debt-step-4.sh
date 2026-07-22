#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-tech-debt-step-4.sh — Step 3.4: Test debt analysis
#
# Analyses test-to-production ratio, slow tests, and test smells.
# Part of the repo-health technical debt scan suite.
#
# Usage:
#   ./skills/repo-health/scripts/scan-tech-debt-step-4.sh [src-dir] [test-output-file]
#
#   src-dir defaults to "src/" if not provided.
#   test-output-file defaults to /tmp/test-output.txt if not provided.
#
# Exits 0 always — findings are data, not failures.
# ---------------------------------------------------------------------------

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---- Config ---------------------------------------------------------------
SRC_DIR="${1:-src}"
TEST_OUTPUT="${2:-/tmp/test-output.txt}"

# Colours for headings (disabled if not a terminal)
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' CYAN='' NC=''
fi

section()   { echo -e "\n${BOLD}${CYAN}====${NC} ${BOLD}$*${NC}${BOLD}${CYAN} ====${NC}"; }
sub()       { echo -e "  ${GREEN}$*${NC}"; }
warn()      { echo -e "  ${YELLOW}$*${NC}"; }
err()       { echo -e "  ${RED}$*${NC}" >&2; }
kv()        { echo "  $1: $2"; }

# ---- Helpers --------------------------------------------------------------

# Safe bc arithmetic (returns 0 or value)
calc() {
  local expr="$1"
  echo "$expr" | bc 2>/dev/null || echo "0"
}

# Trap to ensure exit 0 always
trap 'exit 0' EXIT
trap '' PIPE

# ===========================================================================
# STEP 3.4 — Test Debt Analysis
# ===========================================================================

section "STEP 3.4 — Test Debt Analysis"

sub "Test-to-Production File Ratio"
prod_files=$(find "$SRC_DIR" \
  -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.go' \
  2>/dev/null | wc -l)
test_files=$(find . -path ./node_modules -prune -o \
  \( -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.go' -o -name 'test_*.py' \) \
  -print 2>/dev/null | wc -l)

if [[ "$prod_files" -gt 0 ]]; then
  ratio=$(calc "scale=2; $test_files / $prod_files")
  kv "Test:Production ratio" "$ratio ($test_files test files : $prod_files production files)"
else
  warn "No production source files found"
fi

echo ""
sub "Slowest Tests"
if [[ -f "$TEST_OUTPUT" ]]; then
  grep -E '✓|✗|PASS|FAIL' "$TEST_OUTPUT" 2>/dev/null \
    | grep -oE '[0-9]+ms|[0-9]+\.[0-9]+s' \
    | sort -rn | head -10 \
    || echo "  No timing data available"
else
  warn "Test output not found at $TEST_OUTPUT — skipping slow test analysis"
fi

echo ""
sub "Test Smell Detection"
smell_count=0
while IFS= read -r -d '' f; do
  sleeps=$(grep -cE 'sleep|setTimeout|wait.*[0-9]' "$f" 2>/dev/null || echo "0")
  if [[ "$sleeps" -gt 0 ]]; then
    echo "  TEST_SMELL_SLEEP: $f ($sleeps sleep calls)"
    smell_count=$((smell_count + 1))
  fi
  mocks=$(grep -cE 'mock|stub|fake|spy' "$f" 2>/dev/null || echo "0")
  if [[ "$mocks" -gt 20 ]]; then
    echo "  TEST_SMELL_OVERMOCKED: $f ($mocks mock/stub/spy references)"
    smell_count=$((smell_count + 1))
  fi
done < <(find . -path ./node_modules -prune -o \
  \( -name '*.test.*' -o -name '*.spec.*' \) -print0 2>/dev/null)
kv "Test smells detected" "$smell_count"
