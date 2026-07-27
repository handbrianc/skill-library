#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# compute-grade.sh — Automated grade computation with NITPICK awareness
#
# Reads a JSON findings list from stdin or --findings flag and computes the
# health grade using the repo-health--helpers rubric. NITPICK-classified
# findings are excluded from the deduction pool.
#
# Usage:
#   ./compute-grade.sh --findings findings.json
#   cat findings.json | ./compute-grade.sh
#
# Input JSON format:
#   { "findings": [
#       { "severity": "CRITICAL|HIGH|MEDIUM|LOW",
#         "classification": "ACTIONABLE|NITPICK",
#         "description": "..."
#       }, ...
#     ],
#     "metrics": {
#       "FAILED_TESTS": 0,
#       "LINT_ERRORS": 0,
#       "LSP_ERRORS": 0
#     }
#   }
#
# Output: JSON with grade, score, breakdown, and excluded NITPICK count.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ---- Parse args ----
INPUT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --findings) INPUT_FILE="$2"; shift 2 ;;
    --help|-h) echo "Usage: $0 [--findings file.json]"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

JSON=""
if [[ -n "$INPUT_FILE" ]]; then
  if [[ ! -f "$INPUT_FILE" ]]; then
    err "File not found: $INPUT_FILE"
    exit 1
  fi
  JSON=$(cat "$INPUT_FILE")
elif [[ ! -t 0 ]]; then
  JSON=$(cat)
else
  err "Usage: $0 --findings file.json or pipe JSON to stdin"
  exit 1
fi

# ---- Validate JSON ----
if ! echo "$JSON" | jq empty 2>/dev/null; then
  err "Invalid JSON input"
  exit 1
fi

# ---- Extract counts ----
# Total findings by severity (regardless of classification)
TOTAL_CRITICAL=$(echo "$JSON" | jq '[.findings[] | select(.severity == "CRITICAL")] | length')
TOTAL_HIGH=$(echo "$JSON" | jq '[.findings[] | select(.severity == "HIGH")] | length')
TOTAL_MEDIUM=$(echo "$JSON" | jq '[.findings[] | select(.severity == "MEDIUM")] | length')
TOTAL_LOW=$(echo "$JSON" | jq '[.findings[] | select(.severity == "LOW")] | length')

# Actionable findings by severity
ACT_CRITICAL=$(echo "$JSON" | jq '[.findings[] | select(.severity == "CRITICAL" and .classification == "ACTIONABLE")] | length')
ACT_HIGH=$(echo "$JSON" | jq '[.findings[] | select(.severity == "HIGH" and .classification == "ACTIONABLE")] | length')
ACT_MEDIUM=$(echo "$JSON" | jq '[.findings[] | select(.severity == "MEDIUM" and .classification == "ACTIONABLE")] | length')
ACT_LOW=$(echo "$JSON" | jq '[.findings[] | select(.severity == "LOW" and .classification == "ACTIONABLE")] | length')

# NITPICK count (findings classified as NITPICK, regardless of original severity)
NITPICK_COUNT=$(echo "$JSON" | jq '[.findings[] | select(.classification == "NITPICK")] | length')

# ---- Compute grade ----
POINTS=100
DEDUCTIONS=$(( ACT_CRITICAL * 25 + ACT_HIGH * 10 + ACT_MEDIUM * 3 + ACT_LOW * 1 ))
PRELIM=$(( POINTS - DEDUCTIONS ))

# ---- Bonuses ----
BONUSES=0
BONUS_DETAIL=""

# Clean test run
FAILED_TESTS=$(echo "$JSON" | jq '.metrics.FAILED_TESTS // 0')
LINT_ERRORS=$(echo "$JSON" | jq '.metrics.LINT_ERRORS // 0')

if [[ "$FAILED_TESTS" -eq 0 ]]; then
  BONUSES=$(( BONUSES + 5 ))
  BONUS_DETAIL="${BONUS_DETAIL}cleanTestRun +5, "
fi

# Zero CRITICAL actionable
if [[ "$ACT_CRITICAL" -eq 0 ]]; then
  BONUSES=$(( BONUSES + 2 ))
  BONUS_DETAIL="${BONUS_DETAIL}zeroCriticalActionable +2, "
fi

# Zero HIGH actionable
if [[ "$ACT_HIGH" -eq 0 ]]; then
  BONUSES=$(( BONUSES + 2 ))
  BONUS_DETAIL="${BONUS_DETAIL}zeroHighActionable +2, "
fi

# Linter clean
if [[ "$LINT_ERRORS" -eq 0 ]]; then
  BONUSES=$(( BONUSES + 2 ))
  BONUS_DETAIL="${BONUS_DETAIL}zeroLintViolations +2, "
fi

# Coverage >= 80% (read from metrics if available)
COVERAGE=$(echo "$JSON" | jq '.metrics.COVERAGE // 0')
COVERAGE_OK=$(echo "$COVERAGE >= 80" | bc 2>/dev/null || echo "0")
COVERAGE_GREAT=$(echo "$COVERAGE >= 90" | bc 2>/dev/null || echo "0")
if [[ "$COVERAGE_OK" -eq 1 ]]; then
  BONUSES=$(( BONUSES + 3 ))
  BONUS_DETAIL="${BONUS_DETAIL}coverage80 +3, "
fi
if [[ "$COVERAGE_GREAT" -eq 1 ]]; then
  BONUSES=$(( BONUSES + 3 ))
  BONUS_DETAIL="${BONUS_DETAIL}coverage90 +3, "
fi

# Type checker (tsc/mypy) configured and passing — +1
TYPE_CHECKER=$(echo "$JSON" | jq '.metrics.TYPE_CHECKER_PASSING // false')
if [[ "$TYPE_CHECKER" == "true" ]]; then
  BONUSES=$(( BONUSES + 1 ))
  BONUS_DETAIL="${BONUS_DETAIL}typeCheckerPassing +1, "
fi

# Zero 12-Factor FAIL findings (actionable) — +2
TWELVE_FACTOR_ZERO_FAIL=$(echo "$JSON" | jq '.metrics.TWELVE_FACTOR_ZERO_FAIL // false')
if [[ "$TWELVE_FACTOR_ZERO_FAIL" == "true" ]]; then
  BONUSES=$(( BONUSES + 2 ))
  BONUS_DETAIL="${BONUS_DETAIL}twelveFactorZeroFail +2, "
fi

# All 12-Factor factors PASS or N/A with rationale — +3
TWELVE_FACTOR_ALL_PASS=$(echo "$JSON" | jq '.metrics.TWELVE_FACTOR_ALL_PASS // false')
if [[ "$TWELVE_FACTOR_ALL_PASS" == "true" ]]; then
  BONUSES=$(( BONUSES + 3 ))
  BONUS_DETAIL="${BONUS_DETAIL}twelveFactorAllPass +3, "
fi

# Strip trailing comma
BONUS_DETAIL="${BONUS_DETAIL%, }"

FINAL=$(( PRELIM + BONUSES ))
# Clamp
if [[ "$FINAL" -lt 0 ]]; then FINAL=0; fi
if [[ "$FINAL" -gt 100 ]]; then FINAL=100; fi

# Letter grade
LETTER="F"
if [[ "$FINAL" -ge 90 ]]; then LETTER="A"
elif [[ "$FINAL" -ge 70 ]]; then LETTER="B"
elif [[ "$FINAL" -ge 50 ]]; then LETTER="C"
elif [[ "$FINAL" -ge 25 ]]; then LETTER="D"
fi

# ---- Output ----
jq -n --arg letter "$LETTER" \
      --argjson score "$FINAL" \
      --argjson points "$POINTS" \
      --argjson deductions "$DEDUCTIONS" \
      --argjson bonuses "$BONUSES" \
      --argjson act_critical "$ACT_CRITICAL" \
      --argjson act_high "$ACT_HIGH" \
      --argjson act_medium "$ACT_MEDIUM" \
      --argjson act_low "$ACT_LOW" \
      --argjson total_critical "$TOTAL_CRITICAL" \
      --argjson total_high "$TOTAL_HIGH" \
      --argjson total_medium "$TOTAL_MEDIUM" \
      --argjson total_low "$TOTAL_LOW" \
      --argjson nitpick_count "$NITPICK_COUNT" \
      --arg bonus_detail "$BONUS_DETAIL" \
'{
  grade: {
    letter: $letter,
    score: $score,
    base: $points,
    deductions: $deductions,
    bonuses: $bonuses,
    bonusDetail: $bonus_detail,
    actionable: {
      critical: $act_critical,
      high: $act_high,
      medium: $act_medium,
      low: $act_low
    },
    totalFindings: {
      critical: $total_critical,
      high: $total_high,
      medium: $total_medium,
      low: $total_low
    },
    nitpickExcluded: $nitpick_count
  }
}'
