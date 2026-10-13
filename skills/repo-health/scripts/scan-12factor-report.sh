#!/usr/bin/env bash
# scan-12factor-report.sh — Factor 13: Compliance report (Step 9.13)
#
# Collects output from all 12 factor scripts and generates a summary table.
# Called as a subprocess by the orchestrator scan-12factor.sh.
#
# Usage: ./scan-12factor-report.sh [target-dir] [factors-output-file]
#   target-dir: project directory to audit (default: current directory);
#               forwarded to the factor scripts when re-running them.
#   factors-output-file: if given and readable, FACTOR_* lines are parsed from
#               this file instead of re-running the factor scripts.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="${1:-$PWD}"
if [[ ! -d "$TARGET" ]]; then
  echo "FACTOR_13: WARNING - target directory not found: ${1:-<none>}"
  exit 0
fi
TARGET="$(cd "$TARGET" && pwd)"
FACTOR_OUTPUT_FILE="${2:-}"

trap 'exit 0' EXIT

factor_13_report() {
  echo ""
  echo "=== 12-FACTOR COMPLIANCE SUMMARY ==="
  echo ""
  echo "| Factor | Status | Detail |"
  echo "| ------ | ------ | ------ |"

  # Collect FACTOR_* lines either from the provided file or by re-running factors
  local results=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^FACTOR_[0-9]+: ]]; then
      results+=("$line")
    fi
  done < <(
    if [[ -n "$FACTOR_OUTPUT_FILE" && -f "$FACTOR_OUTPUT_FILE" ]]; then
      cat "$FACTOR_OUTPUT_FILE"
    else
      for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        "$SCRIPT_DIR/scan-12factor-factor-$i.sh" "$TARGET" 2>&1 || true
      done
    fi
  )

  if [[ ${#results[@]} -eq 0 ]]; then
    echo "| (none) | ❓ NO_DATA | no FACTOR_* results were collected — see factor script output above |"
    echo ""
    echo "SUMMARY: no factor results collected across 12 factors"
    echo "FACTOR_13: WARNING - Compliance report generated with no factor data"
    exit 0
  fi

  local fail_count=0
  local warn_count=0

  for r in "${results[@]}"; do
    # Extract factor number and status
    local factor_num="${r#FACTOR_}"
    factor_num="${factor_num%%:*}"
    local rest="${r#*: }"
    local factor_status="${rest%% -*}"
    local factor_detail="${rest#* - }"

    local icon
    case "$factor_status" in
      PASS)    icon="✅" ;;
      FAIL)    icon="❌"; fail_count=$((fail_count + 1)) ;;
      WARNING) icon="⚠️"; warn_count=$((warn_count + 1)) ;;
      *)       icon="❓" ;;
    esac

    # Map factor number to name
    local factor_name=""
    case "$factor_num" in
      1)  factor_name="I. Codebase" ;;
      2)  factor_name="II. Dependencies" ;;
      3)  factor_name="III. Config" ;;
      4)  factor_name="IV. Backing services" ;;
      5)  factor_name="V. Build, release, run" ;;
      6)  factor_name="VI. Processes" ;;
      7)  factor_name="VII. Port binding" ;;
      8)  factor_name="VIII. Concurrency" ;;
      9)  factor_name="IX. Disposability" ;;
      10) factor_name="X. Dev/prod parity" ;;
      11) factor_name="XI. Logs" ;;
      12) factor_name="XII. Admin processes" ;;
      13) factor_name="XIII. Report" ;;
    esac

    echo "| ${factor_name} | ${icon} ${factor_status} | ${factor_detail} |"
  done

  echo ""
  echo "SUMMARY: ${fail_count} FAIL, ${warn_count} WARNING across 12 factors"
  echo "FACTOR_13: PASS - Compliance report generated"
}

factor_13_report
exit 0
