#!/usr/bin/env bash
#
# compare-specs.sh
# Compares current vs archived OpenSpec specifications to ensure
# application code hasn't diverged from historical requirements.
#
# Usage: ./compare-specs.sh [current_spec_dir] [archive_spec_dir]
#
# Layout detection (in order):
#   1. Explicit args: $1=current spec dir, $2=archive dir (legacy specs/ layout).
#   2. specs/ + specs/archive/         — plain specs layout.
#   3. openspec/ + openspec/changes/archive/ — OpenSpec layout (current
#      capability specs in openspec/specs/<capability>/spec.md, archived
#      change deltas in openspec/changes/archive/<change>/specs/...).
# Exits 0 always; emits "N/A" with rationale when no layout is present.
#
# Output: TABLE: spec_file | archived_req_count | impl_evidence_found | divergence_flag
#
set -euo pipefail

CURRENT="${1:-}"
ARCHIVE="${2:-}"

trap 'exit 0' EXIT

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

parse_requirements() {
  local SPEC_FILE="$1"
  # Extract requirement-like lines; awk guarantees a single integer and
  # swallows grep's exit-1-when-no-match under pipefail.
  { grep -E "^[A-Z].*[.:]|^[[:space:]]*- \[.\]|^[[:space:]]*GIVEN|^[[:space:]]*WHEN|^[[:space:]]*THEN|^[[:space:]]*AND|^[[:space:]]*REQUIREMENT:|^[[:space:]]*RFP-|^[[:space:]]*SRS-" \
      "$SPEC_FILE" 2>/dev/null || true; } | awk 'END{print NR+0}'
}

# ---- Layout detection -------------------------------------------------------
LAYOUT=""

if [[ -n "$CURRENT" && -d "$CURRENT" ]]; then
  # Explicit-arg mode (legacy specs/ layout as used by run-scan-suite.sh)
  LAYOUT="specs"
  if [[ -z "$ARCHIVE" || ! -d "$ARCHIVE" ]]; then
    if [[ -d "$CURRENT/archive" ]]; then
      ARCHIVE="$CURRENT/archive"
    else
      ARCHIVE=""
    fi
  fi
elif [[ -n "$CURRENT" && ! -d "$CURRENT" && -d "openspec" ]]; then
  # Caller passed a specs-style path that doesn't exist, but this is an
  # OpenSpec-layout repo (e.g. compare-specs.sh specs/ against openspec/)
  CURRENT="openspec/specs"
  ARCHIVE="openspec/changes/archive"
  LAYOUT="openspec"
elif [[ -d "specs" ]]; then
  CURRENT="specs"
  ARCHIVE="${ARCHIVE:-specs/archive}"
  LAYOUT="specs"
elif [[ -d "openspec" ]]; then
  CURRENT="openspec/specs"
  ARCHIVE="openspec/changes/archive"
  LAYOUT="openspec"
fi

echo "=== SPEC ALIGNMENT CHECK ===" >&2

if [[ -z "$LAYOUT" ]]; then
  echo "N/A: no specification layout found." >&2
  echo "Expected one of:" >&2
  echo "  - specs/ + specs/archive/                (plain specs layout)" >&2
  echo "  - openspec/ + openspec/changes/archive/  (OpenSpec layout)" >&2
  echo "Nothing to compare — skipping spec alignment (not a failure)." >&2
  exit 0
fi

echo "Layout: $LAYOUT" >&2
echo "Current: $CURRENT" >&2
echo "Archive: ${ARCHIVE:-<none found>}" >&2
echo "" >&2

# ============================================================================
# specs/ layout — flat spec files, archived siblings compared by filename
# ============================================================================
if [[ "$LAYOUT" == "specs" ]]; then
  echo "Checking current specs..." >&2
  echo "" >&2
  echo -e "SPEC_FILE\tREQ_COUNT\tCHECK_STATUS" >&2

  shopt -s nullglob
  for SPEC in "$CURRENT"/*.md "$CURRENT"/*.txt "$CURRENT"/*.spec; do
    [ -e "$SPEC" ] || continue
    NAME=$(basename "$SPEC")
    REQ_COUNT=$(parse_requirements "$SPEC")

    # Basic sanity: does the spec look like a real spec?
    if [ "$REQ_COUNT" -eq 0 ]; then
      echo -e "$NAME\t$REQ_COUNT\tWARN_EMPTY_SPEC" >&2
    else
      echo -e "$NAME\t$REQ_COUNT\tOK" >&2
    fi

    # Store for later
    echo "$NAME:$REQ_COUNT" >> "$TMPDIR/current_specs.txt"
  done
  shopt -u nullglob

  echo "" >&2
  echo "Checking archived specs..." >&2
  echo "" >&2
  echo -e "ARCHIVED_SPEC\tREQ_COUNT\tDIFF_FROM_CURRENT" >&2

  if [[ -n "$ARCHIVE" && -d "$ARCHIVE" ]]; then
    shopt -s nullglob
    for SPEC in "$ARCHIVE"/*.md "$ARCHIVE"/*.txt "$ARCHIVE"/*.spec; do
      [ -e "$SPEC" ] || continue
      NAME=$(basename "$SPEC")
      REQ_COUNT=$(parse_requirements "$SPEC")
      echo "$NAME:$REQ_COUNT" >> "$TMPDIR/archived_specs.txt"

      # Compare with current version if it exists
      CURRENT_COUNT=$(awk -F: -v name="$NAME" '$1 == name {print $2; exit}' "$TMPDIR/current_specs.txt" 2>/dev/null)
      if [[ -n "${CURRENT_COUNT:-}" ]]; then
        DIFF=$((REQ_COUNT - CURRENT_COUNT))
        if [ "$DIFF" -ne 0 ]; then
          echo -e "$NAME\t$REQ_COUNT\tCHANGE: $DIFF reqs (was $CURRENT_COUNT in current)" >&2
        else
          echo -e "$NAME\t$REQ_COUNT\tSAME_AS_CURRENT" >&2
        fi
      else
        echo -e "$NAME\t$REQ_COUNT\tREMOVED_OR_ARCHIVED" >&2
      fi
    done
    shopt -u nullglob

    # Check for deprecated/removed specs
    echo "" >&2
    echo "=== POSSIBLE STALE REQS (in archive but not in current) ===" >&2
    comm -23 <(cut -d: -f1 "$TMPDIR/archived_specs.txt" | sort) \
             <(cut -d: -f1 "$TMPDIR/current_specs.txt" | sort) \
      2>/dev/null | while read -r OLD_SPEC; do
        echo "ARCHIVED_ONLY: $OLD_SPEC — verify implementation no longer needed this" >&2
      done
  else
    echo "Archive dir not found ($ARCHIVE) — skipping archived comparison" >&2
  fi
fi

# ============================================================================
# OpenSpec layout — capability specs + archived change deltas
# ============================================================================
if [[ "$LAYOUT" == "openspec" ]]; then
  echo "Checking current capability specs (openspec/specs/<capability>/spec.md)..." >&2
  echo "" >&2
  echo -e "CAPABILITY\tREQ_COUNT\tCHECK_STATUS" >&2

  shopt -s nullglob
  for SPEC in "$CURRENT"/*/spec.md; do
    [ -e "$SPEC" ] || continue
    NAME=$(basename "$(dirname "$SPEC")")
    REQ_COUNT=$(parse_requirements "$SPEC")
    if [ "$REQ_COUNT" -eq 0 ]; then
      echo -e "$NAME\t$REQ_COUNT\tWARN_EMPTY_SPEC" >&2
    else
      echo -e "$NAME\t$REQ_COUNT\tOK" >&2
    fi
    echo "$NAME:$REQ_COUNT" >> "$TMPDIR/current_specs.txt"
  done
  shopt -u nullglob

  echo "" >&2
  echo "Checking archived change deltas (openspec/changes/archive/<change>/specs/...)..." >&2
  echo "" >&2
  echo -e "ARCHIVED_CHANGE\tCAPABILITY\tADDED\tMODIFIED\tREMOVED" >&2

  shopt -s nullglob
  for CHANGE in "$ARCHIVE"/*/; do
    [ -d "$CHANGE" ] || continue
    CHANGE_NAME=$(basename "$CHANGE")
    # Delta spec files may live at specs/<capability>/spec.md or spec deltas/*.md
    for DELTA in "$CHANGE"/specs/*/spec.md "$CHANGE"/specs/*.md; do
      [ -e "$DELTA" ] || continue
      CAP_NAME=$(basename "$(dirname "$DELTA")")
      [[ "$CAP_NAME" == "specs" ]] && CAP_NAME=$(basename "$DELTA" .md)
      COUNTS=$(awk '
        /^## ADDED Requirements/   { section="added" }
        /^## MODIFIED Requirements/ { section="modified" }
        /^## REMOVED Requirements/ { section="removed" }
        /^## / && !/^## (ADDED|MODIFIED|REMOVED)/ { section="" }
        /^### Requirement:/ {
          if (section == "added") a++
          else if (section == "modified") m++
          else if (section == "removed") r++
          else u++
        }
        END { printf "%d %d %d %d", a+0, m+0, r+0, u+0 }
      ' "$DELTA" 2>/dev/null)
      read -r ADDED MODIFIED REMOVED UNSECTIONED <<< "$COUNTS"
      ADDED="${ADDED:-0}" MODIFIED="${MODIFIED:-0}" REMOVED="${REMOVED:-0}" UNSECTIONED="${UNSECTIONED:-0}"
      echo -e "$CHANGE_NAME\t$CAP_NAME\t+$ADDED\t~$MODIFIED\t-$REMOVED${UNSECTIONED:+ (unsectioned:$UNSECTIONED)}" >&2
      echo "$CAP_NAME" >> "$TMPDIR/archived_capabilities.txt"
    done
  done
  shopt -u nullglob

  # Stale / history cross-checks
  echo "" >&2
  echo "=== POSSIBLE STALE CAPABILITIES (in archived deltas but no current spec) ===" >&2
  if [[ -f "$TMPDIR/archived_capabilities.txt" ]]; then
    comm -23 <(sort -u "$TMPDIR/archived_capabilities.txt") \
             <(cut -d: -f1 "$TMPDIR/current_specs.txt" 2>/dev/null | sort) \
      | while read -r OLD_CAP; do
          echo "ARCHIVED_ONLY: $OLD_CAP — verify this capability was intentionally removed or never promoted" >&2
        done
  fi
  echo "" >&2
  echo "=== CURRENT SPECS WITH NO ARCHIVED CHANGE HISTORY ===" >&2
  if [[ -f "$TMPDIR/archived_capabilities.txt" ]]; then
    comm -23 <(cut -d: -f1 "$TMPDIR/current_specs.txt" | sort) \
             <(sort -u "$TMPDIR/archived_capabilities.txt") \
      | while read -r CAP; do
          echo "NO_HISTORY: $CAP — current spec with no archived change (pre-dates archive policy?) — N/A, informational" >&2
        done
  fi
fi

echo "" >&2
echo "=== ALIGNMENT NOTES ===" >&2
echo "For each spec above, cross-reference with:" >&2
echo "  1. query({search_query: 'spec keyword'}) to find relevant code" >&2
echo "  2. context({name: 'key_symbol'}) to verify symbols are called" >&2
echo "  3. Confirm feature flag or config enables the spec-covered behavior" >&2
echo "" >&2
echo "Divergence = code implemented without matching spec, OR spec not implemented." >&2

exit 0
