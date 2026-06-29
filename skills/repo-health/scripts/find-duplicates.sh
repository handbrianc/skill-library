#!/usr/bin/env bash
#
# find-duplicates.sh
# Detects duplicated code blocks across the codebase using text similarity.
# Uses a sliding-window line-hash approach for deterministic results.
#
# Usage: ./find-duplicates.sh <target_dir> [min_lines] [threshold]
set -euo pipefail

TARGET="${1:-.}"
MIN_LINES="${2:-50}"
THRESHOLD="${3:-100}"

echo "=== DUPLICATE CODE SCAN ===" >&2
echo "Target: $TARGET" >&2
echo "Min lines: $MIN_LINES, Threshold: $THRESHOLD" >&2
echo "" >&2

TMPDIR=$(mktemp -d)
FILES="$TMPDIR/files.txt"
LINES="$TMPDIR/lines.txt"

trap "rm -rf $TMPDIR" EXIT

# Collect files
find "$TARGET" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.java" \) \
  ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/dist/*" ! -path "*/build/*" ! -path "*/vendor/*" \
  > "$FILES"

FILE_COUNT=$(wc -l < "$FILES")
echo "Files to scan: $FILE_COUNT" >&2

# Strip comments and normalize whitespace before hashing
# This prevents false-negatives from cosmetic differences
normalize() {
  sed 's/#.*//' | sed 's|//.*||' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ +//; s/ +$//' | grep -v '^[[:space:]]*$'
}

# Build hash index of line-windows
if (( ${BASH_VERSINFO[0]:-0} < 4 )); then
  echo "Bash >= 4 is required for associative arrays (declare -A)." >&2
  echo "Run with a newer bash (e.g., brew install bash) and re-run this script." >&2
  exit 1
fi

declare -A HASH_MAP

while IFS= read -r FILE; do
  LINECOUNT=$(wc -l < "$FILE")
  WINDOW_SIZE=$(( MIN_LINES ))
  
  if [ "$LINECOUNT" -lt "$WINDOW_SIZE" ]; then
    continue
  fi
  
  # Sliding window hashes
  for START in $(seq 1 $((LINECOUNT - WINDOW_SIZE + 1))); do
    CONTENT=$(sed -n "${START},$((START + WINDOW_SIZE - 1))p" "$FILE" \
      | normalize)
    
    if [ -z "$CONTENT" ]; then
      continue
    fi
    
    HASH=$(echo "$CONTENT" | sha256sum | cut -d' ' -f1)
    KEY="${HASH}:${WINDOW_SIZE}"
    
    if [ -z "${HASH_MAP[$KEY]+isset}" ]; then
      HASH_MAP[$KEY]="$FILE:$START"
    else
      # Found a duplicate
      ORIG="${HASH_MAP[$KEY]}"
      echo -e "$ORIG\t$FILE:$START\t$WINDOW_SIZE lines\t100% (hash match)"
    fi
  done
  
done < "$FILES"

echo "" >&2
echo "=== DUPLICATES FOUND ===" >&2
echo "Above listings show files sharing $MIN_LINES+ consecutive normalized lines." >&2
echo "Verify duplicates >50 identical lines for manual refactoring." >&2
echo "Note: Normalized content shown (comments/whitespace stripped)." >&2

exit 0