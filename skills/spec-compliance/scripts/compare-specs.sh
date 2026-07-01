#!/usr/bin/env bash
#
# compare-specs.sh — Compare specs across archived vs current directories
#
# Compares the requirement counts and detects divergences between archived specs
# and current ones to identify: removed features, latent implementations, and
# spec drift.
#
# Usage:
#   ./compare-specs.sh <current_spec_dir> [archived_spec_dir]
#
# Examples:
#   ./compare-specs.sh openspec/ specs/archive/
#   ./compare-specs.sh specs/ archive/
#
# Output:
#   TABLE: SPEC_FILE | ARCHIVED_REQ_COUNT | CURRENT_REQ_COUNT | FOUND | STATUS
#

set -euo pipefail

CURRENT_DIR="${1:-}"
ARCHIVE_DIR="${2:-}"

# ── Color escape codes ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Header ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║           SPEC COMPARISON REPORT (Archived vs Current)       ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Arg validation ──────────────────────────────────────────────────────────
if [[ -z "$CURRENT_DIR" ]]; then
    echo "ERROR: Usage: $0 <current_spec_dir> [archived_spec_dir]"
    exit 1
fi

if [[ ! -d "$CURRENT_DIR" ]]; then
    echo "ERROR: Current spec directory '$CURRENT_DIR' does not exist"
    exit 1
fi

# Default archive dir to sibling if not provided
if [[ -z "$ARCHIVE_DIR" ]]; then
    ARCHIVE_DIR="$(dirname "$CURRENT_DIR")/archive"
    if [[ ! -d "$ARCHIVE_DIR" ]]; then
        ARCHIVE_DIR=""
    fi
fi

# ── Helpers ────────────────────────────────────────────────────────────────

requires_bash_4() {
    if (( BASH_VERSINFO[0] < 4 )); then
        echo "ERROR: $0 requires Bash 4+ (associative arrays are used)" >&2
        exit 1
    fi
}

requires_bash_4

# Extract requirements from a single spec file
# Returns: line_number|pattern_type|extracted_text
extract_from_file() {
    local file="$1"
    local tmp_file
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/compare-specs.XXXXXX")

    # Gherkin: SCENARIO, GIVEN, WHEN, THEN, AND, BACKGROUND blocks
    grep -n -E '^[[:space:]]*(SCENARIO|GIVEN|WHEN|THEN|AND|BACKGROUND)[[:space:]]+' "$file" 2>/dev/null \
        | awk -F: '{print $1"|GHERKIN|"$2}' >> "$tmp_file" || true

    # Checkbox items: - [x] or - [ ]
    grep -n -E '^[[:space:]]*-[[:space:]]+\[[ xX]\]' "$file" 2>/dev/null \
        | awk -F: '{print $1"|CHECKBOX|"$2}' >> "$tmp_file" || true

    # Explicit requirement markers
    grep -n -E '(REQUIREMENT|RFP-|SRS-|USER STORY|TICKET):[[:space:]]+' "$file" 2>/dev/null \
        | awk -F: '{print $1"|MARKER|"$2}' >> "$tmp_file" || true

    # Capital-prose sentences (min 20 chars, starts capital, ends . or :)
    grep -n -E '^[A-Z][A-Za-z0-9\s]{18,}[.:]$' "$file" 2>/dev/null \
        | awk -F: '{print $1"|PROSE|"$2}' >> "$tmp_file" || true

    # Numbered items: 1. or (a) style
    grep -n -E '^[[:space:]]*([[:digit:]]+[.)]|\([[:lower:]]+\))[[:space:]]' "$file" 2>/dev/null \
        | awk -F: '{print $1"|NUMBERED|"$2}' >> "$tmp_file" || true

    sort -n "$tmp_file" | head -200
    rm -f "$tmp_file"
}

count_requirements() {
    local file="$1"
    extract_from_file "$file" | wc -l
}

comparison_status() {
    local current_count="$1"
    local archived_count="$2"

    if (( archived_count > current_count )); then
        echo "REGRESSION"
    elif (( current_count > archived_count )); then
        echo "GROWTH"
    else
        echo "BALANCED"
    fi
}

list_spec_files() {
    local dir="$1"
    find "$dir" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.spec" -o -name "*.frs" \) 2>/dev/null | sort
}

echo -e "${BOLD}Current:${RESET}  $CURRENT_DIR"
if [[ -n "$ARCHIVE_DIR" ]]; then
    echo -e "${BOLD}Archived:${RESET} $ARCHIVE_DIR"
else
    echo -e "${YELLOW}Archived: none found (using sibling archive/)${RESET}"
fi
echo ""

# ── Main Report Header ──────────────────────────────────────────────────────
echo -e "${BOLD}┌─────────────────────────────────────────────────────────────┐${RESET}"
printf "${BOLD}│ %-35s │ %5s │ %5s │ %6s │ %10s │${RESET}\n" \
    "SPEC FILE" "ARC_R" "CUR_R" "FOUND" "STATUS"
echo -e "${BOLD}├─────────────────────────────────────────────────────────────┤${RESET}"

# Track totals
total_current=0
total_archive=0
total_found=0

# ── Process each current spec ───────────────────────────────────────────────
declare -A archive_counts
declare -A archive_files

# Pre-load archive counts if available
if [[ -n "$ARCHIVE_DIR" && -d "$ARCHIVE_DIR" ]]; then
    while IFS= read -r afile; do
        acount=$(count_requirements "$afile")
        archive_files["$afile"]=1
        # Try to match by basename
        bname=$(basename "$afile")
        archive_counts["$bname"]=$acount
    done < <(list_spec_files "$ARCHIVE_DIR")
fi

# Process current specs
while IFS= read -r cfile; do
    cur_count=$(count_requirements "$cfile")
    total_current=$((total_current + cur_count))

    bname=$(basename "$cfile")

    # Determine if archived version exists
    arc_count=""
    arc_label="—"
    has_archive="—"
    status="NEW"

    if [[ -n "${archive_counts[$bname]+x}" ]]; then
        arc_count="${archive_counts[$bname]}"
        arc_label="$arc_count"
        has_archive="📦"
        total_archive=$((total_archive + arc_count))
        status=$(comparison_status "$cur_count" "$arc_count")
    elif [[ -d "$ARCHIVE_DIR" ]]; then
        # Look for any archived version of this spec by fuzzy matching
        matching_arc=$(find "$ARCHIVE_DIR" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.spec" \) 2>/dev/null \
            | while IFS= read -r af; do
                abname=$(basename "$af")
                # Simple Levenshtein-ish match (basename contains or common prefix)
                if [[ "$abname" == *"${bname%%.*}"* ]] || [[ "${bname%%.*}" == *"$abname"* ]]; then
                    echo "$(basename "$af"):$(count_requirements "$af")"
                    break
                fi
            done | head -1)
        if [[ -n "$matching_arc" ]]; then
            arc_count_real="${matching_arc##*:}"
            arc_label="$arc_count_real"
            has_archive="🔶"
            total_archive=$((total_archive + arc_count_real))
            status=$(comparison_status "$cur_count" "$arc_count_real")
        fi
    fi

    # Emit row
    printf "│ %-35s │ %5s │ %5s │ %6s │ %-10s │${RESET}\n" \
        "${bname:0:35}" "$arc_label" "$cur_count" "$has_archive" "$status"

done < <(list_spec_files "$CURRENT_DIR")

echo -e "${BOLD}└─────────────────────────────────────────────────────────────┘${RESET}"

# ── Totals ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Totals:${RESET}"
echo "  Current requirements: $total_current"
if [[ -d "$ARCHIVE_DIR" ]]; then
    echo "  Archived requirements looked up: $total_archive"
fi
echo ""

# ── Divergence Detection ────────────────────────────────────────────────────
if [[ -d "$ARCHIVE_DIR" ]]; then
    echo -e "${BOLD}${BLUE}━━━ Divergence Analysis ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    while IFS= read -r cfile; do
        bname=$(basename "$cfile")
        cur_reqs=$(extract_from_file "$cfile")

        # Find corresponding archived version
        matching_arc=$(find "$ARCHIVE_DIR" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.spec" \) 2>/dev/null \
            | head -20 \
            | while IFS= read -r af; do
                abname=$(basename "$af")
                if [[ "$abname" == *"${bname%%.*}"* ]] || [[ "${bname%%.*}" == *"$abname"* ]]; then
                    echo "$af"
                    break
                fi
            done)

        if [[ -z "$matching_arc" ]]; then
            # No archived counterpart — could be NEW feature (not a regression)
            echo -e "${GREEN}  ➕ NEW (no archive): ${bname}${RESET}"
            continue
        fi

        arc_reqs=$(extract_from_file "$matching_arc")

        cur_count=$(echo "$cur_reqs" | wc -l)
        arc_count=$(echo "$arc_reqs" | wc -l)

        echo ""
        echo -e "  ${CYAN}$bname${RESET} (current) vs ${CYAN}$(basename "$matching_arc")${RESET} (archived)"
        echo "    Current: $cur_count requirements"
        echo "    Archived: $arc_count requirements"

        if (( arc_count > cur_count )); then
            diff=$((arc_count - cur_count))
            echo -e "    ${RED}  ⚠️  REGRESSION: archived has $diff MORE requirements${RESET}"
        elif (( cur_count > arc_count )); then
            diff=$((cur_count - arc_count))
            echo -e "    ${YELLOW}  📈 GROWTH: current has $diff MORE requirements${RESET}"
        else
            echo -e "    ${GREEN}  ✅ BALANCED: same requirement count${RESET}"
        fi

    done < <(list_spec_files "$CURRENT_DIR")
fi

echo ""
echo "Done."