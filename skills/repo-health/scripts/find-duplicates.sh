#!/usr/bin/env bash
#
# find-duplicates.sh
# Detects duplicated code blocks across the codebase using text similarity.
# Uses a sliding-window + N-gram fingerprint approach with configurable threshold.
#
# Usage: ./find-duplicates.sh <target_dir> [min_lines] [threshold]
#   threshold: 0-100, percentage of N-gram fingerprint intersection required.
#              100 = exact match only. Lower values enable fuzzy detection.
set -euo pipefail

TARGET="${1:-.}"
MIN_LINES="${2:-50}"
THRESHOLD="${3:-100}"

if [[ ! "$THRESHOLD" =~ ^[0-9]+$ ]] || [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 100 ]; then
  echo "Error: threshold must be an integer 1-100, got '$THRESHOLD'" >&2
  exit 1
fi

if [[ ! "$MIN_LINES" =~ ^[0-9]+$ ]] || [ "$MIN_LINES" -lt 2 ]; then
  echo "Error: min_lines must be an integer >= 2, got '$MIN_LINES'" >&2
  exit 1
fi

if (( ${BASH_VERSINFO[0]:-0} < 4 )); then
  echo "Error: Bash >= 4 is required (for associative arrays). Current: ${BASH_VERSINFO[0]:-0}" >&2
  exit 1
fi

echo "=== DUPLICATE CODE SCAN ===" >&2
echo "Target: $TARGET" >&2
echo "Min lines: $MIN_LINES, Threshold: $THRESHOLD%" >&2
echo "" >&2

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

FILES="$TMPDIR/files.txt"
find "$TARGET" -type f \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.java" \) \
  -path "*/node_modules" -prune -o -path "*/.git" -prune -o -path "*/dist" -prune -o \
  -path "*/build" -prune -o -path "*/vendor" -prune -o -print \
  > "$FILES"

FILE_COUNT=$(wc -l < "$FILES")
echo "Files to scan: $FILE_COUNT" >&2

# --- Normalize a multiline string: strip comments, collapse whitespace ---
normalize() {
  sed 's/#.*//' 2>/dev/null | sed 's|//.*||' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ +//; s/ +$//' | grep -av '^[[:space:]]*$' 2>/dev/null
}

# --- Hash a normalized window for exact-matching mode (fast path) ---
fast_hash() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

# --- Build N-gram fingerprint set for a normalized window ---
# Returns a space-delimited list of line-prefix hashes representing N-gram components.
fingerprint_ngram() {
  local content="$1"
  local ngrams=""
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Hash each line; the collection represents the window's fingerprint
    local fh
    fh=$(printf '%s' "$line" | sha256sum | awk '{print $1}')
    ngrams="${ngrams}${fh} "
  done <<<"$content"
  echo "${ngrams%. }"
}

# --- Jaccard similarity between two space-delimited fingerprint lists ---
# Returns integer percentage (0-100): share of unique ngrams in common.
jaccard_pct() {
  local a="$1" b="$2"
  local -A seen_a seen_b union_seen intersect_seen
  local item

  for item in $a; do seen_a[$item]=1; done
  for item in $b; do seen_b[$item]=1; done
  for item in "${!seen_a[@]}"; do union_seen[$item]=1; done
  for item in "${!seen_b[@]}"; do union_seen[$item]=1; done
  for item in "${!seen_a[@]}"; do
    [[ "${seen_b[$item]:-}" ]] && intersect_seen[$item]=1
  done

  local union_count=${#union_seen[@]}
  local intersect_count=${#intersect_seen[@]}
  if (( union_count == 0 )); then
    echo 0
    return
  fi
  echo $(( intersect_count * 100 / union_count ))
}

# --- Fast path: exact hash match for a single window ---
# Uses HASH_INDEX_EXACT to detect and report identical normalized windows.
exact_scan() {
  local content="$1" win_key="$2"
  local h
  h=$(fast_hash "$content")
  if [ -n "${HASH_INDEX_EXACT[$h]:-}" ]; then
    local orig="${HASH_INDEX_EXACT[$h]}"
    local pair_key=""
    [[ "$orig" < "$win_key" ]] && pair_key="${orig}:${win_key}" || pair_key="${win_key}:${orig}"
    if [ -z "${REPORTED_PAIRS[$pair_key]:-}" ]; then
      REPORTED_PAIRS[$pair_key]=1
      printf '%s\t%s\t%d lines\t100%% similarity (exact hash match)\n' "$orig" "$win_key" "$MIN_LINES"
    fi
  else
    HASH_INDEX_EXACT[$h]="$win_key"
  fi
}

# --- Fuzzy path: compare a window against all previously seen windows ---
# Builds an N-gram fingerprint and uses Jaccard similarity to find duplicates.
compare_windows() {
  local content="$1" win_key="$2" scanned="$3" start="$4" windows="$5"
  local fp
  fp=$(fingerprint_ngram "$content")
  CANONICAL_FP[$win_key]="$fp"

  local prev_key prev_fp sim pair_sort
  for prev_key in "${!CANONICAL_FP[@]}"; do
    [[ "$prev_key" == "$win_key" ]] && continue
    [[ "$prev_key" < "$win_key" ]] && pair_sort="${prev_key}:${win_key}" || pair_sort="${win_key}:${prev_key}"
    [ -n "${REPORTED_PAIRS[$pair_sort]:-}" ] && continue

    prev_fp="${CANONICAL_FP[$prev_key]}"
    [ -z "$prev_fp" ] && continue

    sim=$(jaccard_pct "$fp" "$prev_fp")

    if (( sim >= THRESHOLD )); then
      REPORTED_PAIRS[$pair_sort]=1
      printf '%s\t%s\t%d lines\t%d%% similarity (N-gram fingerprint)\n' "$prev_key" "$win_key" "$MIN_LINES" "$sim"
    fi
  done

  # Memory guard: flush FP cache periodically to avoid unbounded growth
  if (( scanned % 200 == 0 )) && (( start == windows )); then
    unset CANONICAL_FP
    declare -A CANONICAL_FP
  fi
}

# --- Process a single file: normalize, iterate sliding windows, detect duplicates ---
scan_file() {
  local file="$1"

  [ ! -f "$file" ] && return
  local linecount
  linecount=$(wc -l < "$file")
  [ "$linecount" -lt "$MIN_LINES" ] && return

  local norm_file="$TMPDIR/norm_${SCANNED}.txt"
  normalize < "$file" > "$norm_file"
  local norm_lc
  norm_lc=$(wc -l < "$norm_file")

  local windows=$(( norm_lc - MIN_LINES + 1 ))
  [ "$windows" -lt 1 ] && return

  local start end win_key content
  for (( start=1; start<=windows; start++ )); do
    end=$(( start + MIN_LINES - 1 ))
    win_key="${file}:${start}"

    content=$(sed -n "${start},${end}p" "$norm_file" | tr -d '\0')
    [ -z "$content" ] && continue

    if (( THRESHOLD == 100 )); then
      exact_scan "$content" "$win_key"
    else
      compare_windows "$content" "$win_key" "$SCANNED" "$start" "$windows"
    fi
  done
}

# ============================================================
# MAIN
# ============================================================

declare -A HASH_INDEX_EXACT   # fast_hash -> "file:start" (for threshold=100 only)
declare -A REPORTED_PAIRS     # dedup prevention: "file1:start1:file2:start2" -> 1
declare -A CANONICAL_FP       # window_key -> fingerprint_ngram result (cache)

FILE_LIST=$(cat "$FILES")
_TOTAL_FILES=$(echo "$FILE_LIST" | wc -l)
SCANNED=0

while IFS= read -r FILE; do
  (( SCANNED++ )) || true
  scan_file "$FILE"
done <<<"$FILE_LIST"

echo "" >&2
if (( THRESHOLD == 100 )); then
  echo "=== SCAN COMPLETE ===" >&2
  echo "Reported windows with identical normalized lines (exact hash match)." >&2
else
  echo "=== SCAN COMPLETE ===" >&2
  echo "Reported pairs sharing >= $THRESHOLD% of line N-grams in common." >&2
fi
echo "Threshold $THRESHOLD% — verify results, especially for low thresholds." >&2
exit 0
