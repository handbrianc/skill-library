#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-tech-debt-step-6.sh — Step 3.6: Error handling / resilience debt
#
# Analyses empty catch blocks, global error handlers, error boundaries,
# and logging consistency.
# Part of the repo-health technical debt scan suite.
#
# Usage:
#   ./skills/repo-health/scripts/scan-tech-debt-step-6.sh [src-dir]
#
#   src-dir defaults to "src/" if not provided.
#
# Exits 0 always — findings are data, not failures.
# ---------------------------------------------------------------------------

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---- Config ---------------------------------------------------------------
SRC_DIR="${1:-src}"

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
# STEP 3.6 — Error Handling and Resilience Debt
# ===========================================================================

section "STEP 3.6 — Error Handling Debt"

sub "Empty Catch Blocks"
empty_catches=$(grep -rn 'catch\s*(\s*\w*\s*)\s*{\s*}' "$SRC_DIR" \
  --include='*.js' --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
kv "Empty catch blocks" "$empty_catches"

sub "Bare Catch Blocks (silent ignores)"
bare_catches=$(grep -rnE 'catch\s*\(.*\)\s*\{\s*//\s*(TODO|FIXME|ignore|silent)' \
  "$SRC_DIR" --include='*.js' --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
kv "Bare catch blocks" "$bare_catches"

echo ""
sub "Global Error Handlers"
if grep -rn 'process\.on.*uncaught\|process\.on.*unhandled\|@ExceptionHandler' \
  "$SRC_DIR" --include='*.js' --include='*.ts' 2>/dev/null | head -10; then
  :
else
  echo "  No global error handlers found"
fi

echo ""
sub "Error Boundaries (component apps)"
if [[ -d "$SRC_DIR/components" ]]; then
  error_boundaries=$(grep -rn 'componentDidCatch\|ErrorBoundary\|getDerivedStateFromError' \
    "$SRC_DIR/components/" --include='*.tsx' --include='*.jsx' 2>/dev/null | wc -l)
  kv "Error boundaries" "$error_boundaries"
  component_count=$(find "$SRC_DIR/components/" -name '*.tsx' -o -name '*.jsx' 2>/dev/null | wc -l)
  if [[ "$component_count" -gt 0 ]]; then
    boundary_coverage=$(calc "scale=2; $error_boundaries * 100 / $component_count")
    kv "Error boundary coverage" "${boundary_coverage}% of components"
  fi
else
  echo "  No components directory found — skipping error boundary check"
fi

echo ""
sub "Logging Consistency"
console_count=$(grep -rn 'console\.log\|console\.error\|console\.warn' "$SRC_DIR" \
  --include='*.js' --include='*.ts' 2>/dev/null | wc -l)
structured_count=$(grep -rn 'logger\.\|log\.\|logging\.' "$SRC_DIR" \
  --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | wc -l)
kv "Ad-hoc log statements (console.*)" "$console_count"
kv "Structured log statements" "$structured_count"
if [[ "$structured_count" -gt 0 ]]; then
  total_logs=$((console_count + structured_count))
  if [[ "$total_logs" -gt 0 ]]; then
    console_ratio=$(calc "scale=2; $console_count / $total_logs")
    kv "Ad-hoc log ratio" "$console_ratio (% of all log statements that are ad-hoc)"
  fi
fi
