#!/usr/bin/env bash
#
# compare-specs.sh
# Compares current vs archived OpenSpec specifications to ensure
# application code hasn't diverged from historical requirements.
#
# Usage: ./compare-specs.sh <current_spec_dir> <archive_spec_dir>
# Output: TABLE: spec_file | archived_req_count | impl_evidence_found | divergence_flag
#
set -euo pipefail

CURRENT="${1:-specs}"
ARCHIVE="${2:-specs/archive}"

echo "=== SPEC ALIGNMENT CHECK ===" >&2
echo "Current: $CURRENT" >&2
echo "Archive: $ARCHIVE" >&2
echo "" >&2

if [ ! -d "$CURRENT" ]; then
  echo "Current spec dir not found: $CURRENT" >&2
  exit 1
fi

if [ ! -d "$ARCHIVE" ]; then
  echo "Archive dir not found: $ARCHIVE — skipping archived check" >&2
  echo "" >&2
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# -------- Parse requirements from spec files --------
# OpenSpec typically uses Given/When/Then or bullet requirements

parse_requirements() {
  local SPEC_FILE="$1"
  # Extract requirement-like lines
  grep -E "^[A-Z].*[.:]|^\s*- \[.\]|^\s*GIVEN|^\s*WHEN|^\s*THEN|^\s*AND|^\s*REQUIREMENT:|^\s*RFP-|^\s*SRS-" \
    "$SPEC_FILE" 2>/dev/null | wc -l
}

echo "Checking current specs..." >&2
echo "" >&2
echo -e "SPEC_FILE\tREQ_COUNT\tCHECK_STATUS" >&2

shopt -s nullglob
for SPEC in "$CURRENT"/*.md "$CURRENT"/*.txt "$CURRENT"/*.spec; do
  [ -e "$SPEC" ] || continue
  NAME=$(basename "$SPEC")
  REQ_COUNT=$(parse_requirements "$SPEC" 2>/dev/null)
  
  # Basic sanity: does the spec look like a real spec?
  if [ "$REQ_COUNT" -eq 0 ]; then
    echo -e "$NAME\t$REQ_COUNT\tWARN_EMPTY_SPEC" >&2
  else
    echo -e "$NAME\t$REQ_COUNT\tOK" >&2
  fi
  
  # Store for later
  echo "$NAME:$REQ_COUNT" >> "$TMPDIR/current_specs.txt"
done

echo "" >&2
echo "Checking archived specs..." >&2
echo "" >&2
echo -e "ARCHIVED_SPEC\tREQ_COUNT\tDIFF_FROM_CURRENT" >&2

if [ -d "$ARCHIVE" ]; then
  for SPEC in "$ARCHIVE"/*.md "$ARCHIVE"/*.txt "$ARCHIVE"/*.spec; do
    [ -e "$SPEC" ] || continue
    NAME=$(basename "$SPEC")
    REQ_COUNT=$(parse_requirements "$SPEC")
    echo "$NAME:$REQ_COUNT" >> "$TMPDIR/archived_specs.txt"
    
    # Compare with current version if it exists
    CURRENT_COUNT=$(grep "^${NAME}:" "$TMPDIR/current_specs.txt" 2>/dev/null | cut -d: -f2 || echo "?")
    if [ "$CURRENT_COUNT" != "?" ]; then
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
  
  # Check for deprecated/removed specs
  echo "" >&2
  echo "=== POSSIBLE STALE REQS (in archive but not in current) ===" >&2
  comm -23 <(cut -d: -f1 "$TMPDIR/archived_specs.txt" | sort) \
           <(cut -d: -f1 "$TMPDIR/current_specs.txt" | sort) \
    2>/dev/null | while read -r OLD_SPEC; do
      echo "ARCHIVED_ONLY: $OLD_SPEC — verify implementation no longer needed this" >&2
    done
fi

echo "" >&2
echo "=== ALIGNMENT NOTES ===" >&2
echo "For each spec above, cross-reference with:" >&2
echo "  1. gitnexus_query({query: 'spec keyword'}) to find relevant code" >&2
echo "  2. gitnexus_context() on key symbols to verify they're called" >&2
echo "  3. Confirm feature flag or config enables the spec-covered behavior" >&2
echo "" >&2
echo "Divergence = code implemented without matching spec, OR spec not implemented." >&2

exit 0