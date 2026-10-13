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
#   Vendor directories (.venv, venv, node_modules, __pycache__, site-packages,
#   *.dist-info, .git) are always excluded from every file count.
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

# Trap to ensure exit 0 always
trap 'exit 0' EXIT
trap '' PIPE

# ---- Helpers ---------------------------------------------------------------

# awk-based arithmetic — bc is not always installed
calc() { awk "BEGIN{printf \"%.2f\", ($1)}" 2>/dev/null || echo 0; }

# find_source DIR EXTENSIONS... — pruned find printing matching files (newline list)
find_source() {
  local dir="$1"
  shift
  local exts=()
  local ext
  for ext in "$@"; do
    [[ ${#exts[@]} -gt 0 ]] && exts+=(-o)
    exts+=(-name "$ext")
  done
  find "$dir" \
    \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
         -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
         -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
         -o -name dist -o -name build \) -prune \) \
    -o \( -type f \( "${exts[@]}" \) -print \) 2>/dev/null
}

# Count per-file grep matches — always a single integer
file_grep_count() {
  local file="$1" pat="$2"
  { grep -cE -- "$pat" "$file" 2>/dev/null || true; } | awk '{s+=$1} END{print s+0}'
}

# ===========================================================================
# STEP 3.4 — Test Debt Analysis
# ===========================================================================

section "STEP 3.4 — Test Debt Analysis"

sub "Test-to-Production File Ratio"
prod_files=0
test_files=0
if [[ -d "$SRC_DIR" ]]; then
  prod_files=$(find_source "$SRC_DIR" '*.ts' '*.tsx' '*.js' '*.py' '*.go' | awk 'END{print NR+0}')
else
  warn "Source directory not found: $SRC_DIR — production file count N/A"
fi
test_files=$(find_source . '*.test.*' '*.spec.*' '*_test.go' 'test_*.py' '*_test.py' | awk 'END{print NR+0}')

if [[ "$prod_files" -gt 0 ]]; then
  ratio=$(calc "$test_files / $prod_files")
  kv "Test:Production ratio" "$ratio ($test_files test files : $prod_files production files)"
  if [[ "$test_files" -eq 0 ]]; then
    warn "No test files detected anywhere in the tree"
  fi
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
  sleeps=$(file_grep_count "$f" 'sleep|setTimeout|wait.*[0-9]')
  if [[ "$sleeps" -gt 0 ]]; then
    echo "  TEST_SMELL_SLEEP: $f ($sleeps sleep calls)"
    smell_count=$((smell_count + 1))
  fi
  mocks=$(file_grep_count "$f" 'mock|stub|fake|spy')
  if [[ "$mocks" -gt 20 ]]; then
    echo "  TEST_SMELL_OVERMOCKED: $f ($mocks mock/stub/spy references)"
    smell_count=$((smell_count + 1))
  fi
done < <(find . \
  \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
       -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
       -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
       -o -name dist -o -name build \) -prune \) \
  -o \( -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name 'test_*.py' -o -name '*_test.py' \) -print0 \) 2>/dev/null)
kv "Test smells detected" "$smell_count"
