#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-tech-debt-step-5.sh — Step 3.5: API surface / export debt
#
# Analyses unused exports, barrel files, and change hotspots.
# Part of the repo-health technical debt scan suite.
#
# Usage:
#   ./skills/repo-health/scripts/scan-tech-debt-step-5.sh [src-dir]
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

# Trap to ensure exit 0 always
trap 'exit 0' EXIT
trap '' PIPE

# ===========================================================================
# STEP 3.5 — API Surface and Export Debt
# ===========================================================================

section "STEP 3.5 — API Surface Analysis"

sub "Unused Exports"
if has_cmd npx && [[ -f "tsconfig.json" ]]; then
  npx ts-prune --project tsconfig.json 2>/dev/null \
    && echo "  TS_PRUNE_CHECK: completed (unused exports listed above)" \
    || warn "TS_PRUNE_CHECK: completed with issues" || true
else
  warn "ts-prune not available or no tsconfig.json"
  # Fallback: count barrel files
fi

echo ""
sub "Barrel Files"
barrel_count=$(find "$SRC_DIR" -name 'index.ts' -o -name 'index.js' 2>/dev/null | wc -l)
kv "Barrel file count" "$barrel_count"

echo ""
sub "Frequently Changed Files (hotspots, last 6 months)"
if git rev-parse --is-inside-work-tree &>/dev/null; then
  git log --oneline --since='6 months ago' --name-only 2>/dev/null \
    | sort | uniq -c | sort -rn | head -20 \
    || echo "  No changes in last 6 months or git history unavailable"
else
  warn "Not a git repository — skipping hotspot analysis"
fi
