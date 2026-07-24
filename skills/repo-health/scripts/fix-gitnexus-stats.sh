#!/usr/bin/env bash
#
# fix-gitnexus-stats.sh
# Sync GitNexus statistics across AGENTS.md, CLAUDE.md, and ARCHITECTURE.md.
# Reads live stats from .gitnexus/meta.json and updates all <!-- gitnexus:start --> blocks.
#
# Usage: ./fix-gitnexus-stats.sh [--dry-run]
#
# Exit codes: 0 = all blocks synced, 1 = some blocks could not be updated

set -euo pipefail

FIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX_REPO_ROOT="$(cd "$FIX_DIR/../../.." && pwd)"
source "$FIX_DIR/lib/fix-common.sh"
SCRIPT_DIR="$FIX_DIR"
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

fix_section "FIX: GitNexus Stats Synchronisation"

# ── Ensure GitNexus index is fresh ──────────────────────────────────────────
META_JSON="$FIX_REPO_ROOT/.gitnexus/meta.json"
if [[ ! -f "$META_JSON" ]]; then
  fix_err "no .gitnexus/meta.json — run 'npx gitnexus analyze --force' first"
  exit 1
fi

NODES=$(jq -r '.stats.nodes // "?"' "$META_JSON")
EDGES=$(jq -r '.stats.edges // "?"' "$META_JSON")
COMMUNITIES=$(jq -r '.stats.communities // "0"' "$META_JSON")
PROCESSES=$(jq -r '.stats.processes // "0"' "$META_JSON")

if [[ "$NODES" == "?" || "$EDGES" == "?" ]]; then
  fix_err "meta.json missing stats fields"
  exit 1
fi

fix_sub "Live stats: $NODES symbols, $EDGES relationships, $COMMUNITIES clusters, $PROCESSES flows"

# ── Build the new stats line ────────────────────────────────────────────────
# Format used in AGENTS.md / CLAUDE.md:
#   **skill-library** (310 symbols, 304 relationships, 0 execution flows)
NEW_STATS_LINE="**skill-library** ($NODES symbols, $EDGES relationships, $PROCESSES execution flows)"

# ── Files to update ─────────────────────────────────────────────────────────
FILES=(
  "$FIX_REPO_ROOT/AGENTS.md"
  "$FIX_REPO_ROOT/CLAUDE.md"
)

UPDATED=0
FAILED=0
SKIPPED=0

for file in "${FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    fix_skip "$(basename "$file") — not found"
    ((SKIPPED++)) || true
    continue
  fi

  fix_sub "Checking $(basename "$file")..."

  # Check if file has a gitnexus block
  if ! grep -q '<!-- gitnexus:start -->' "$file"; then
    fix_skip "$(basename "$file") — no gitnexus block"
    ((SKIPPED++)) || true
    continue
  fi

  # Extract current stats line
  CURRENT_STATS=$(grep -oP '\*\*skill-library\*\* \(.*?\)' "$file" 2>/dev/null || echo "")

  if [[ -z "$CURRENT_STATS" ]]; then
    fix_warn "$(basename "$file") — no stats line found in gitnexus block"
    ((SKIPPED++)) || true
    continue
  fi

  if [[ "$CURRENT_STATS" == "$NEW_STATS_LINE" ]]; then
    fix_ok "$(basename "$file") — already up to date"
    continue
  fi

  fix_info "  was: $CURRENT_STATS"
  fix_info "  now: $NEW_STATS_LINE"

  if $DRY_RUN; then
    fix_info "  [dry-run] would update $(basename "$file")"
    ((UPDATED++)) || true
    continue
  fi

  # Update the stats line in-place
  fix_snapshot "$file"
  # Escape forward slashes for sed
  OLD_ESC=$(printf '%s\n' "$CURRENT_STATS" | sed 's/[\/&]/\\&/g')
  NEW_ESC=$(printf '%s\n' "$NEW_STATS_LINE" | sed 's/[\/&]/\\&/g')
  if sed -i.bak "s/$OLD_ESC/$NEW_ESC/" "$file"; then
    rm -f "${file}.bak" 2>/dev/null || true
    fix_ok "$(basename "$file") — updated"
  else
    fix_err "$(basename "$file") — update failed"
    fix_rollback "$file"
    ((FAILED++)) || true
  fi
done

# ── Also update ARCHITECTURE.md if it has stale stats ───────────────────────
ARCH_FILE="$FIX_REPO_ROOT/ARCHITECTURE.md"
if [[ -f "$ARCH_FILE" ]]; then
  ARCH_CURRENT=$(grep -oP '\*\*skill-library\*\* \(.*?\)' "$ARCH_FILE" 2>/dev/null || echo "")
  if [[ -n "$ARCH_CURRENT" && "$ARCH_CURRENT" != "$NEW_STATS_LINE" ]]; then
    fix_sub "ARCHITECTURE.md has stale stats"
    fix_info "  was: $ARCH_CURRENT"
    if ! $DRY_RUN; then
      fix_snapshot "$ARCH_FILE"
      OLD_ESC=$(printf '%s\n' "$ARCH_CURRENT" | sed 's/[\/&]/\\&/g')
      NEW_ESC=$(printf '%s\n' "$NEW_STATS_LINE" | sed 's/[\/&]/\\&/g')
      if sed -i "s/$OLD_ESC/$NEW_ESC/" "$ARCH_FILE"; then
        fix_ok "ARCHITECTURE.md — updated"
        ((UPDATED++)) || true
      else
        fix_err "ARCHITECTURE.md — update failed"
        fix_rollback "$ARCH_FILE"
        ((FAILED++)) || true
      fi
    else
      fix_info "  [dry-run] would update ARCHITECTURE.md"
      ((UPDATED++)) || true
    fi
  fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
fix_section "GitNexus Stats Fix — Summary"
fix_info "  Updated: $UPDATED  Skipped: $SKIPPED  Failed: $FAILED"
echo ""

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi

# Verify
if ! $DRY_RUN && [[ "$UPDATED" -gt 0 ]]; then
  fix_sub "Verification — checking all gitnexus blocks match meta.json"
  for file in "${FILES[@]}" "$ARCH_FILE"; do
    if [[ -f "$file" ]]; then
      FILE_STATS=$(grep -oP '\*\*skill-library\*\* \(.*?\)' "$file" 2>/dev/null || echo "")
      if [[ -n "$FILE_STATS" && "$FILE_STATS" != "$NEW_STATS_LINE" ]]; then
        fix_err "$(basename "$file") stats mismatch after update: $FILE_STATS"
      fi
    fi
  done
fi

fix_ok "GitNexus stats fix complete"
exit 0
