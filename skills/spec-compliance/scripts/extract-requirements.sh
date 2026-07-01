#!/usr/bin/env bash
#
# extract-requirements.sh — Parse a spec file and extract all requirements
#
# Extracts requirements from markdown, text, or spec-format files using
# pattern matching: Gherkin, checkboxes, requirement markers, prose, numbered.
#
# Usage:
#   ./extract-requirements.sh <spec_file> [spec_file...]
#   ./extract-requirements.sh openspec/auth.spec
#   find specs/ -name "*.md" | xargs ./extract-requirements.sh
#
# Output format:
#   LINE_NUM|PATTERN_TYPE|EXTRACTED_TEXT
#
# Pattern types:
#   MARKER     — Contains explicit REQUIREMENT:, RFP-, SRS-, USER STORY:, TICKET:
#   GHERKIN    — Given/When/Then/And scenario steps
#   CHECKBOX_X — Checkbox marked [x] (checked/done)
#   CHECKBOX_SPACE — Checkbox marked [ ] (unchecked/pending)
#   PROSE      — Capitalized prose sentence (min 20 chars, ends . or :)
#   NUMBERED   — Numbered item: 1. or (a) style
#

set -euo pipefail

# Color coding
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

requires_bash_4() {
    if (( BASH_VERSINFO[0] < 4 )); then
        echo -e "${RED}ERROR: $0 requires Bash 4+ (associative arrays are used).${RESET}" >&2
        exit 1
    fi
}

# ── Usage ───────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <spec_file> [spec_file...]"
    echo "       find specs/ -name '*.md' | xargs $0"
    exit 1
}

[[ $# -eq 0 ]] && usage
requires_bash_4

# ── Per-file extraction ─────────────────────────────────────────────────────
extract_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    if [[ ! -f "$filepath" ]]; then
        echo -e "${RED}ERROR: File not found: $filepath${RESET}" >&2
        return 1
    fi

    echo ""
    echo -e "${BOLD}${CYAN}━━━ $filename ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${DIM}Full path: $filepath${RESET}"
    echo ""

    local line_num=0
    local req_count=0

    # Track unique pattern types found
    declare -A pattern_counts=(
        [MARKER]=0
        [GHERKIN_GIVEN]=0
        [GHERKIN_WHEN]=0
        [GHERKIN_THEN]=0
        [GHERKIN_AND]=0
        [GHERKIN_OTHER]=0
        [CHECKBOX_X]=0
        [CHECKBOX_SPACE]=0
        [PROSE]=0
        [NUMBERED]=0
    )

    # Temporary file to accumulate results
    local tmp_file
    tmp_file=$(mktemp)

    # ── Pattern 1: Explicit requirement markers ───────────────────────────
    # Matches: REQUIREMENT:, RFP-, SRS-, USER STORY:, TICKET:
    while IFS=: read -r ln text; do
        # Strip leading whitespace and requirement keyword
        cleaned=$(echo "$text" | sed -E 's/^(REQUIREMENT|RFP-|SRS-|USER STORY|TICKET):[[:space:]]+//')
        echo "$ln|MARKER|$cleaned" >> "$tmp_file"
        pattern_counts[MARKER]=$((pattern_counts[MARKER] + 1))
    done < <(grep -n -E '(REQUIREMENT|RFP-|SRS-|USER STORY|TICKET):[[:space:]]+' "$filepath" 2>/dev/null || true)

    # ── Pattern 2: Gherkin BDD language ─────────────────────────────────
    # Matches: GIVEN, WHEN, THEN, AND at line start (with optional indentation)
    while IFS=: read -r ln text; do
        echo "$ln|GHERKIN_GIVEN|${text#"${text%%[![:space:]]*}"}" >> "$tmp_file"
        pattern_counts[GHERKIN_GIVEN]=$((pattern_counts[GHERKIN_GIVEN] + 1))
    done < <(grep -n -E '^[[:space:]]*(GIVEN)[[:space:]]+' "$filepath" 2>/dev/null || true)

    while IFS=: read -r ln text; do
        echo "$ln|GHERKIN_WHEN|${text#"${text%%[![:space:]]*}"}" >> "$tmp_file"
        pattern_counts[GHERKIN_WHEN]=$((pattern_counts[GHERKIN_WHEN] + 1))
    done < <(grep -n -E '^[[:space:]]*(WHEN)[[:space:]]+' "$filepath" 2>/dev/null || true)

    while IFS=: read -r ln text; do
        echo "$ln|GHERKIN_THEN|${text#"${text%%[![:space:]]*}"}" >> "$tmp_file"
        pattern_counts[GHERKIN_THEN]=$((pattern_counts[GHERKIN_THEN] + 1))
    done < <(grep -n -E '^[[:space:]]*(THEN)[[:space:]]+' "$filepath" 2>/dev/null || true)

    while IFS=: read -r ln text; do
        echo "$ln|GHERKIN_AND|${text#"${text%%[![:space:]]*}"}" >> "$tmp_file"
        pattern_counts[GHERKIN_AND]=$((pattern_counts[GHERKIN_AND] + 1))
    done < <(grep -n -E '^[[:space:]]*(AND)[[:space:]]+' "$filepath" 2>/dev/null || true)

    while IFS=: read -r ln text; do
        echo "$ln|GHERKIN_BLOCK|${text#"${text%%[![:space:]]*}"}" >> "$tmp_file"
        pattern_counts[GHERKIN_OTHER]=$((pattern_counts[GHERKIN_OTHER] + 1))
    done < <(grep -n -E '^[[:space:]]*(BACKGROUND|SCENARIO|EXAMPLE|FEATURE)\>' "$filepath" 2>/dev/null || true)

    # ── Pattern 3: Checkbox items ─────────────────────────────────────────
    # Matches: - [x] (checked) and - [ ] (unchecked)
    while IFS=: read -r ln text; do
        # Remove the '- [x]' prefix
        cleaned=$(echo "$text" | sed -E 's/^[[:space:]]*-[[:space:]]+\[[xX]\][[:space:]]+//')
        echo "$ln|CHECKBOX_X|$cleaned" >> "$tmp_file"
        pattern_counts[CHECKBOX_X]=$((pattern_counts[CHECKBOX_X] + 1))
    done < <(grep -n -E '^[[:space:]]*-[[:space:]]+\[[xX]\]' "$filepath" 2>/dev/null || true)

    while IFS=: read -r ln text; do
        cleaned=$(echo "$text" | sed -E 's/^[[:space:]]*-[[:space:]]+\[ \][[:space:]]+//')
        echo "$ln|CHECKBOX_SPACE|${cleaned}" >> "$tmp_file"
        pattern_counts[CHECKBOX_SPACE]=$((pattern_counts[CHECKBOX_SPACE] + 1))
    done < <(grep -n -E '^[[:space:]]*-[[:space:]]+\[ \]' "$filepath" 2>/dev/null || true)

    # ── Pattern 4: Prose requirements ─────────────────────────────────────
    # Matches: Lines beginning with capital letter, ≥20 chars, ending in . or :
    # Excludes code blocks, headings (#), and short lines
    while IFS=: read -r ln text; do
        # Skip if it looks like a heading or table row
        if echo "$text" | grep -qE '^#{1,6}\s'; then
            continue
        fi
        echo "$ln|PROSE|$text" >> "$tmp_file"
        pattern_counts[PROSE]=$((pattern_counts[PROSE] + 1))
    done < <(grep -n -E '^[^#].*[[:upper:]][[:space:]].[[:space:][:alnum:]]{15,}[.:]$' "$filepath" 2>/dev/null \
        | grep -vE '(^#|```|<http|>|\*\*|^\s*-|\|)' || true)

    # ── Pattern 5: Numbered items ─────────────────────────────────────────
    # Matches: 1. or (a) or 1) style
    while IFS=: read -r ln text; do
        echo "$ln|NUMBERED|$text" >> "$tmp_file"
        pattern_counts[NUMBERED]=$((pattern_counts[NUMBERED] + 1))
    done < <(grep -n -E '^[[:space:]]*([[:digit:]]+[.)]|\([[:lower:]]+\))[[:space:]]' "$filepath" 2>/dev/null || true)

    # Sort by line number and display
    if [[ -s "$tmp_file" ]]; then
        while IFS='|' read -r ln ptype content; do
            req_count=$((req_count + 1))
            # Pretty-print with color
            case "$ptype" in
                MARKER)
                    echo -e "  ${GREEN}✓${RESET} [$ln] ${GREEN}${ptype}${RESET}: $content"
                    ;;
                GHERKIN_GIVEN)
                    echo -e "  ${CYAN}➤${RESET} [$ln] ${CYAN}GIVEN${RESET}: $content"
                    ;;
                GHERKIN_WHEN)
                    echo -e "  ${CYAN}➤${RESET} [$ln] ${CYAN}WHEN${RESET}: $content"
                    ;;
                GHERKIN_THEN)
                    echo -e "  ${CYAN}➤${RESET} [$ln] ${CYAN}THEN${RESET}: $content"
                    ;;
                GHERKIN_AND)
                    echo -e "  ${CYAN}➤${RESET} [$ln] ${CYAN}AND${RESET}: $content"
                    ;;
                GHERKIN_BLOCK)
                    echo -e "  ${CYAN}▸${RESET} [$ln] ${CYAN}${ptype}${RESET}: $content"
                    ;;
                CHECKBOX_X)
                    echo -e "  ${GREEN}☑${RESET} [$ln] ${GREEN}CHECKED${RESET}: $content"
                    ;;
                CHECKBOX_SPACE)
                    echo -e "  ${DIM}☐${RESET} [$ln] ${DIM}PENDING${RESET}: $content"
                    ;;
                PROSE)
                    echo -e "  ${YELLOW}›${RESET} [$ln] ${YELLOW}PROSE${RESET}: $content"
                    ;;
                NUMBERED)
                    echo -e "  ${YELLOW}·${RESET} [$ln] ${YELLOW}NUMBERED${RESET}: $content"
                    ;;
                *)
                    echo "  • [$ln] $ptype: $content"
                    ;;
            esac
        done < <(sort -t'|' -k1 -n "$tmp_file")
    else
        echo -e "  ${DIM}(no requirements detected)${RESET}"
    fi

    # Summary
    echo ""
    echo -e "${DIM}  ├─ Total: $req_count requirements${RESET}"
    [[ ${pattern_counts[MARKER]} -gt 0 ]] && echo -e "${DIM}  ├─ MARKER:    ${pattern_counts[MARKER]}${RESET}"
    [[ ${pattern_counts[GHERKIN_GIVEN]} -gt 0 ]] && echo -e "${DIM}  ├─ GIVEN:     ${pattern_counts[GHERKIN_GIVEN]}${RESET}"
    [[ ${pattern_counts[GHERKIN_WHEN]} -gt 0 ]] && echo -e "${DIM}  ├─ WHEN:      ${pattern_counts[GHERKIN_WHEN]}${RESET}"
    [[ ${pattern_counts[GHERKIN_THEN]} -gt 0 ]] && echo -e "${DIM}  ├─ THEN:      ${pattern_counts[GHERKIN_THEN]}${RESET}"
    [[ ${pattern_counts[GHERKIN_AND]} -gt 0 ]] && echo -e "${DIM}  ├─ AND:       ${pattern_counts[GHERKIN_AND]}${RESET}"
    [[ ${pattern_counts[GHERKIN_OTHER]} -gt 0 ]] && echo -e "${DIM}  ├─ GHERKIN BL:${pattern_counts[GHERKIN_OTHER]}${RESET}"
    [[ ${pattern_counts[CHECKBOX_X]} -gt 0 ]] && echo -e "${DIM}  ├─ CHECKED:   ${pattern_counts[CHECKBOX_X]}${RESET}"
    [[ ${pattern_counts[CHECKBOX_SPACE]} -gt 0 ]] && echo -e "${DIM}  ├─ PENDING:   ${pattern_counts[CHECKBOX_SPACE]}${RESET}"
    [[ ${pattern_counts[PROSE]} -gt 0 ]] && echo -e "${DIM}  ├─ PROSE:     ${pattern_counts[PROSE]}${RESET}"
    [[ ${pattern_counts[NUMBERED]} -gt 0 ]] && echo -e "${DIM}  └─ NUMBERED:  ${pattern_counts[NUMBERED]}${RESET}"

    rm -f "$tmp_file"
}

# ── Process all input files ─────────────────────────────────────────────────
for file in "$@"; do
    extract_file "$file"
done