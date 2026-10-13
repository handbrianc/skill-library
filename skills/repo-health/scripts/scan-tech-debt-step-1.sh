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
#   src-dir defaults to "src/" if not provided. Vendor directories
#   (.venv, venv, node_modules, __pycache__, site-packages, *.dist-info, .git)
#   are always excluded from counting.
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

# ---- Local helpers ---------------------------------------------------------
# Vendor directories that must never be counted as project code.
VENDOR_EXCLUDE=( .git .venv venv node_modules __pycache__ site-packages '*.dist-info' '*.egg-info' .tox .mypy_cache .pytest_cache .ruff_cache .hypothesis dist build )

# awk-based arithmetic — bc is not always installed.
calc() { awk "BEGIN{printf \"%.2f\", ($1)}" 2>/dev/null || echo 0; }

# count_src_markers MARKER [SRC_DIR] — always prints a single integer.
# (grep -c exits 1 when the count is 0; a trailing awk normalizes both the
#  exit status and any multi-line per-file output.)
count_src_markers() {
  local marker="$1" srcdir="${2:-src}"
  # Every fallible stage is neutralized (|| true) — under pipefail the
  # pipeline status is the rightmost NON-ZERO exit, and grep exits 1/2 on
  # "no matches"/"file errors", which must not abort under set -e.
  { grep -rni "$marker" "$srcdir" \
      --include='*.js' --include='*.ts' --include='*.tsx' --include='*.jsx' \
      --include='*.py' --include='*.go' --include='*.rs' --include='*.java' \
      --include='*.rb' --include='*.php' --include='*.cs' --include='*.kt' \
      --include='*.swift' --include='*.dart' \
      "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" \
      2>/dev/null || true; } \
    | { grep -v 'node_modules\|\.git\|/test/\|/tests/\|/spec/' || true; } \
    | { grep -vic 'nocheck\|eslint-disable\|pragma' || true; } \
    | awk '{s+=$1} END{print s+0}'
}

# count_code_lines DIR — total lines across counted source files (single integer)
count_code_lines() {
  local srcdir="$1"
  { grep -rc '' "$srcdir" \
      --include='*.js' --include='*.ts' --include='*.tsx' --include='*.jsx' \
      --include='*.py' --include='*.go' \
      "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" \
      2>/dev/null || true; } \
    | awk -F: '{s+=$NF} END{print s+0}'
}

# ===========================================================================
# STEP 3.1 — TODO/FIXME/HACK/XXX Inventory with Aging
# ===========================================================================

section "STEP 3.1 — Technical Debt Marker Inventory"

if [[ ! -d "$SRC_DIR" ]]; then
  warn "Source directory not found: $SRC_DIR — marker inventory N/A"
  exit 0
fi
echo "  Target: $SRC_DIR"

echo "  Marker Counts:"
total_markers=0
for marker in TODO FIXME HACK XXX WORKAROUND TEMPORARY KLUDGE; do
  cnt=$(count_src_markers "$marker" "$SRC_DIR")
  printf "  %-16s %s\n" "$marker:" "$cnt"
  total_markers=$((total_markers + cnt))
done
kv "Total markers" "$total_markers"

echo ""
sub "Oldest Debt Markers (git blame)"
if git rev-parse --is-inside-work-tree &>/dev/null; then
  for marker in TODO FIXME HACK; do
    files_blamed=0
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      files_blamed=$((files_blamed + 1))
      [[ "$files_blamed" -le 3 ]] || break
      git blame -w -C -- "$f" 2>/dev/null | grep -i -- "$marker" | head -5 || true
    done < <(grep -rli -- "$marker" "$SRC_DIR" \
      --include='*.js' --include='*.ts' --include='*.tsx' --include='*.jsx' \
      --include='*.py' --include='*.go' \
      "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" 2>/dev/null | head -3)
  done
else
  warn "Not a git repository — skipping git blame"
fi

echo ""
sub "Marker Density"
total_lines=$(count_code_lines "$SRC_DIR")

if [[ "$total_lines" -gt 0 ]]; then
  density=$(calc "$total_markers * 1000 / $total_lines")
  kv "Marker density" "$density per 1000 LOC ($total_markers markers in $total_lines lines)"
else
  warn "No source files found for density calculation"
fi
