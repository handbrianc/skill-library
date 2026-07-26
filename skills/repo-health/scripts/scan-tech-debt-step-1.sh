#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-tech-debt-step-1.sh — Step 3.1: TODO/FIXME/HACK marker inventory
#
# Counts debt marker keywords with aging (git blame) and density.
# Part of the repo-health technical debt scan suite.
#
# Usage:
#   ./skills/repo-health/scripts/scan-tech-debt-step-1.sh [src-dir]
#
#   src-dir defaults to "src/" if not provided.
#
# Exits 0 always — findings are data, not failures.
# ---------------------------------------------------------------------------

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---- Config ---------------------------------------------------------------
SRC_DIR="${1:-src}"

# Trap to ensure exit 0 always
trap 'exit 0' EXIT
trap '' PIPE

# ===========================================================================
# STEP 3.1 — TODO/FIXME/HACK/XXX Inventory with Aging
# ===========================================================================

section "STEP 3.1 — Technical Debt Marker Inventory"

echo "  Marker Counts:"
total_markers=0
for marker in TODO FIXME HACK XXX WORKAROUND TEMPORARY KLUDGE; do
  cnt=$(count_markers "$marker")
  printf "  %-16s %s\n" "$marker:" "$cnt"
  total_markers=$((total_markers + cnt))
done
kv "Total markers" "$total_markers"

echo ""
sub "Oldest Debt Markers (git blame)"
for marker in TODO FIXME HACK; do
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    git blame "$SRC_DIR" -en -f -w -C 2>/dev/null \
      | grep -i "$marker" | head -10 2>/dev/null || true
  else
    warn "Not a git repository — skipping git blame"
    break
  fi
done

echo ""
sub "Marker Density"
total_lines=$(find "$SRC_DIR" \
  \( -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.jsx' \
     -o -name '*.py' -o -name '*.go' \) \
  -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')

if [[ -n "$total_lines" && "$total_lines" -gt 0 ]]; then
  density=$(calc "scale=2; $total_markers * 1000 / $total_lines")
  kv "Marker density" "$density per 1000 LOC ($total_markers markers in $total_lines lines)"
else
  warn "No source files found for density calculation"
fi
