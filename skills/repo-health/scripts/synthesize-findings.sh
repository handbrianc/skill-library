#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# synthesize-findings.sh — Deduplicate, resolve conflicts, and merge findings
#
# Takes findings from multiple phases (or a single list) and produces a
# deduplicated, conflict-resolved output suitable for Phase 10 remediation.
#
# Usage:
#   ./synthesize-findings.sh --input findings1.json [--input findings2.json ...]
#   cat findings.json | ./synthesize-findings.sh
#
# Deduplication rules:
#   - Findings with the same "description" (case-insensitive fuzzy) are merged
#   - The HIGHEST severity across duplicates is kept
#   - Evidence text is concatenated
#   - The FIRST phase reference is kept, others appended as cross-refs
#
# Conflict resolution:
#   - If Phase 2 scores SC2286 as MEDIUM and Phase 3 scores it as HIGH: use HIGH
#   - If a finding appears in both security and lint phases: highest severity wins
#
# Output: JSON with:
#   { "findings": [deduplicated list],
#     "metrics": { aggregated metrics },
#     "grade": { computed grade },
#     "synthesis": { "duplicates_removed": N, "phases_represented": [...] } }
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Save SCRIPT_DIR before common.sh overwrites it (common.sh sets it to lib/)
SYNTH_SCRIPT_DIR="$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/common.sh"
SCRIPT_DIR="$SYNTH_SCRIPT_DIR"

# ==== Parse args ====
INPUT_FILES=()
OUTPUT_FILE=""
CLASSIFY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) INPUT_FILES+=("$2"); shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --classify) CLASSIFY=true; shift ;;
    --help|-h) echo "Usage: $0 --input f1.json [--input f2.json ...] [--classify]"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Read input
if [[ ${#INPUT_FILES[@]} -gt 0 ]]; then
  COMBINED="[]"
  for f in "${INPUT_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
      err "File not found: $f"
      exit 1
    fi
    PHASE_JSON=$(cat "$f")
    PHASE_FINDINGS=$(echo "$PHASE_JSON" | jq '.findings // []')
    COMBINED=$(echo "$COMBINED" | jq --argjson pf "$PHASE_FINDINGS" '. + $pf')
  done
elif [[ ! -t 0 ]]; then
  RAW=$(cat)
  COMBINED=$(echo "$RAW" | jq '[.findings[]] // [.]')
else
  err "Usage: $0 --input f1.json [--input f2.json ...] or pipe JSON to stdin"
  exit 1
fi

# ==== Normalize findings ====
# Ensure each finding has a normalized description for dedup matching
NORMALIZED=$(echo "$COMBINED" | jq '
  map(
    .normalized = (.description | ascii_downcase | gsub("[^a-z0-9]"; ""))
  )
')

# ==== Deduplicate ====
# Group by normalized description, keep highest severity, merge evidence
DEDUPED=$(echo "$NORMALIZED" | jq '
  group_by(.normalized) | map(
    {
      phase: (.[0].phase // 0),
      severity: ([.[].severity] | unique | sort |
        if contains(["CRITICAL"]) then "CRITICAL"
        elif contains(["HIGH"]) then "HIGH"
        elif contains(["MEDIUM"]) then "MEDIUM"
        else "LOW" end
      ),
      description: .[0].description,
      evidence: ([.[].evidence // ""] | unique | join("; ")),
      fixScript: (.[0].fixScript // ""),
      crossPhases: ([.[].phase // 0] | unique | sort),
      classification: (.[0].classification // null)
    }
  )
')

# Sort by severity (CRITICAL first), then phase
FINAL=$(echo "$DEDUPED" | jq '
  sort_by(
    if .severity == "CRITICAL" then 0
    elif .severity == "HIGH" then 1
    elif .severity == "MEDIUM" then 2
    else 3 end,
    .phase
  )
')

# ==== Aggregate metrics ====
# If input has metrics, merge them (worst-case across all inputs)
TOTAL_FAILED=0
TOTAL_LINT=0
TOTAL_LSP=0
TOTAL_COVERAGE=0
COVERAGE_COUNT=0

for f in "${INPUT_FILES[@]}"; do
  PHASE_JSON=$(cat "$f")
  FT=$(echo "$PHASE_JSON" | jq '.metrics.FAILED_TESTS // 0')
  LI=$(echo "$PHASE_JSON" | jq '.metrics.LINT_ERRORS // 0')
  LS=$(echo "$PHASE_JSON" | jq '.metrics.LSP_ERRORS // 0')
  CV=$(echo "$PHASE_JSON" | jq '.metrics.COVERAGE // 0')
  
  if [[ "$FT" -gt "$TOTAL_FAILED" ]]; then TOTAL_FAILED=$FT; fi
  if [[ "$LI" -gt "$TOTAL_LINT" ]]; then TOTAL_LINT=$LI; fi
  if [[ "$LS" -gt "$TOTAL_LSP" ]]; then TOTAL_LSP=$LS; fi
  if echo "$CV > 0" | bc 2>/dev/null | grep -q 1; then
    TOTAL_COVERAGE=$(echo "$TOTAL_COVERAGE + $CV" | bc 2>/dev/null || echo 0)
    COVERAGE_COUNT=$((COVERAGE_COUNT + 1))
  fi
done

AVG_COVERAGE=0
if [[ "$COVERAGE_COUNT" -gt 0 ]]; then
  AVG_COVERAGE=$(echo "$TOTAL_COVERAGE / $COVERAGE_COUNT" | bc 2>/dev/null || echo 0)
fi

COMB_LEN=$(echo "$COMBINED" | jq 'length')
DEDUP_LEN=$(echo "$FINAL" | jq 'length')
DUPLICATES_REMOVED=$(( COMB_LEN - DEDUP_LEN ))

# ==== Output ====
RESULT=$(jq -n \
  --argjson findings "$FINAL" \
  --argjson failed "$TOTAL_FAILED" \
  --argjson lint "$TOTAL_LINT" \
  --argjson lsp "$TOTAL_LSP" \
  --argjson coverage "$AVG_COVERAGE" \
  --argjson removed "$DUPLICATES_REMOVED" \
  '{
    findings: $findings,
    metrics: {
      FAILED_TESTS: $failed,
      LINT_ERRORS: $lint,
      LSP_ERRORS: $lsp,
      COVERAGE: $coverage
    },
    synthesis: {
      duplicates_removed: $removed,
      phases_represented: ([$findings[].phase] | unique | sort)
    }
  }')

# ==== Optional classification pass ====
if $CLASSIFY; then
  section "Running classification pass..." >&2
  CLASSIFIED=$(echo "$RESULT" | "$SCRIPT_DIR/classify-finding.sh" 2>/dev/null)
  RESULT="$CLASSIFIED"
fi

# ==== Compute grade ====
section "Computing grade..." >&2
GRADE=$(echo "$RESULT" | "$SCRIPT_DIR/compute-grade.sh")
RESULT=$(echo "$RESULT" | jq --argjson grade "$(echo "$GRADE" | jq '.grade')" '. + {grade: $grade}')

# Output summary to stderr only
section "Synthesis Results" >&2
sub "Input files: ${#INPUT_FILES[@]}" >&2
sub "Total raw findings: $(echo "$COMBINED" | jq 'length')" >&2
sub "After dedup: $(echo "$FINAL" | jq 'length')" >&2
sub "Duplicates removed: $DUPLICATES_REMOVED" >&2

# JSON output to stdout only
echo "$RESULT" | jq '.'

# Write to file if requested
if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$RESULT" > "$OUTPUT_FILE"
  sub "Written to: $OUTPUT_FILE" >&2
fi
