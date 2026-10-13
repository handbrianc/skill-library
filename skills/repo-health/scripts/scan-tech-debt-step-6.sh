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
#   src-dir defaults to "src/" if not provided. Vendor directories are
#   always excluded.
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

# Trap to ensure exit 0 always
trap 'exit 0' EXIT
trap '' PIPE

# ---- Helpers ---------------------------------------------------------------
VENDOR_EXCLUDE=( .git .venv venv node_modules __pycache__ site-packages '*.dist-info' '*.egg-info' .tox .mypy_cache .pytest_cache .ruff_cache .hypothesis dist build )

# awk-based arithmetic — bc is not always installed
calc() { awk "BEGIN{printf \"%.2f\", ($1)}" 2>/dev/null || echo 0; }

# match_count GREP-ARGS... — number of matched lines, always a single integer
# (a bare `grep ... | wc -l` fails under pipefail when grep matches nothing).
match_count() {
  { grep -rn "$@" 2>/dev/null || true; } | awk 'END{print NR+0}'
}

# ===========================================================================
# STEP 3.6 — Error Handling and Resilience Debt
# ===========================================================================

section "STEP 3.6 — Error Handling Debt"

if [[ ! -d "$SRC_DIR" ]]; then
  warn "Source directory not found: $SRC_DIR — error handling analysis N/A"
  exit 0
fi
echo "  Target: $SRC_DIR"

sub "Empty Catch Blocks (JS/TS)"
empty_catches=$(match_count 'catch\s*(\s*\w*\s*)\s*{\s*}' "$SRC_DIR" \
  --include='*.js' --include='*.ts' --include='*.tsx' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}")
kv "Empty catch blocks" "$empty_catches"

sub "Bare Catch Blocks (silent ignores, JS/TS)"
bare_catches=$(match_count -E 'catch\s*\(.*\)\s*\{\s*//\s*(TODO|FIXME|ignore|silent)' "$SRC_DIR" \
  --include='*.js' --include='*.ts' --include='*.tsx' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}")
kv "Bare catch blocks" "$bare_catches"

echo ""
sub "Empty Except Blocks (Python, heuristic — 2-line 'except: pass' form)"
empty_excepts=$({ grep -rnE -A1 'except[^:]*:' "$SRC_DIR" \
  --include='*.py' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" 2>/dev/null || true; } \
  | { grep -cE -- '-[0-9]+:[[:space:]]*(pass|\.\.\.)[[:space:]]*$' || true; } \
  | awk '{s+=$1} END{print s+0}')
kv "Empty except blocks" "$empty_excepts"

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
  error_boundaries=$(match_count 'componentDidCatch\|ErrorBoundary\|getDerivedStateFromError' "$SRC_DIR/components/" \
    --include='*.tsx' --include='*.jsx' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}")
  kv "Error boundaries" "$error_boundaries"
  component_count=$(find "$SRC_DIR/components/" -name '*.tsx' -o -name '*.jsx' 2>/dev/null | awk 'END{print NR+0}')
  if [[ "$component_count" -gt 0 ]]; then
    boundary_coverage=$(calc "$error_boundaries * 100 / $component_count")
    kv "Error boundary coverage" "${boundary_coverage}% of components"
  fi
else
  echo "  No components directory found — skipping error boundary check"
fi

echo ""
sub "Logging Consistency"
console_count=$(match_count 'console\.log\|console\.error\|console\.warn' "$SRC_DIR" \
  --include='*.js' --include='*.ts' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}")
structured_count=$(match_count 'logger\.\|log\.\|logging\.' "$SRC_DIR" \
  --include='*.js' --include='*.ts' --include='*.py' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}")
print_count=$(match_count -E '(^|[^a-zA-Z_])print\(' "$SRC_DIR" \
  --include='*.py' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}")
kv "Ad-hoc log statements (console.*)" "$console_count"
kv "Structured log statements (logger/log/logging)" "$structured_count"
kv "Bare print() statements (Python, heuristic)" "$print_count"
if [[ "$structured_count" -gt 0 ]]; then
  total_logs=$((console_count + structured_count))
  if [[ "$total_logs" -gt 0 ]]; then
    console_ratio=$(calc "$console_count * 100 / $total_logs")
    kv "Ad-hoc log ratio" "${console_ratio}% of counted log statements are ad-hoc"
  fi
fi
