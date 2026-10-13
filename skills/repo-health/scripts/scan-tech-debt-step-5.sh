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
npx_has() {
  has_cmd npx || return 1
  npx --no-install "$1" --version &>/dev/null
}

# ===========================================================================
# STEP 3.5 — API Surface and Export Debt
# ===========================================================================

section "STEP 3.5 — API Surface Analysis"

if [[ ! -d "$SRC_DIR" ]]; then
  warn "Source directory not found: $SRC_DIR — API surface analysis N/A"
  exit 0
fi
echo "  Target: $SRC_DIR"

sub "Unused Exports"
if [[ -f "package.json" && -f "tsconfig.json" ]]; then
  if npx_has ts-prune; then
    rc=0
    timeout 120 npx --no-install ts-prune --project tsconfig.json 2>/dev/null | head -40 || rc=$?
    if [[ "$rc" -eq 124 ]]; then
      warn "TS_PRUNE_CHECK: timed out after 120s — N/A"
    else
      echo "  TS_PRUNE_CHECK: completed (unused exports listed above, if any)"
    fi
  else
    warn "ts-prune not installed — unused export check N/A for TS/JS (npx ts-prune to enable)"
  fi
else
  warn "No package.json/tsconfig.json — TS/JS unused-export check N/A (for Python see detect-dead-code.sh)"
fi

echo ""
sub "Barrel Files"
barrel_count=$(find "$SRC_DIR" \
  \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
       -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
       -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
       -o -name dist -o -name build \) -prune \) \
  -o \( -type f \( -name 'index.ts' -o -name 'index.js' \) -print \) 2>/dev/null | awk 'END{print NR+0}')
kv "Barrel file count (index.ts/js)" "$barrel_count"

py_inits=$(find "$SRC_DIR" \
  \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
       -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
       -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
       -o -name dist -o -name build \) -prune \) \
  -o \( -type f -name '__init__.py' -print \) 2>/dev/null | awk 'END{print NR+0}')
kv "Python package inits (__init__.py, barrel analog)" "$py_inits"

echo ""
sub "Frequently Changed Files (hotspots, last 6 months)"
if git rev-parse --is-inside-work-tree &>/dev/null; then
  git log --oneline --since='6 months ago' --name-only 2>/dev/null \
    | sort | uniq -c | sort -rn | head -20 \
    || echo "  No changes in last 6 months or git history unavailable"
else
  warn "Not a git repository — skipping hotspot analysis"
fi
