#!/usr/bin/env bash
# scan-12factor-report.sh — Factor 13: Compliance report (Step 9.13)
#
# Collects output from all 12 factor scripts and generates a summary table.
# Called as a subprocess by the orchestrator scan-12factor.sh.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

factor_13_report() {
  echo ""
  echo "=== 12-FACTOR COMPLIANCE SUMMARY ==="
  echo ""
  echo "| Factor | Status | Detail |"
  echo "| ------ | ------ | ------ |"

  # Collect output from all 12 factor scripts
  local results=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^FACTOR_[0-9]+: ]]; then
      results+=("$line")
    fi
  done < <(
    "$SCRIPT_DIR/scan-12factor-factor-1.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-2.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-3.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-4.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-5.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-6.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-7.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-8.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-9.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-10.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-11.sh" 2>&1
    "$SCRIPT_DIR/scan-12factor-factor-12.sh" 2>&1
  )

  local fail_count=0
  local warn_count=0

  for r in "${results[@]}"; do
    # Extract factor number and status
    local factor_num
    factor_num=$(echo "$r" | sed 's/^FACTOR_\([0-9]*\):.*/\1/')
    local factor_status
    factor_status=$(echo "$r" | sed 's/^FACTOR_[0-9]*: \([A-Z]*\) -.*/\1/')
    local factor_detail
    factor_detail=$(echo "$r" | sed 's/^FACTOR_[0-9]*: [A-Z]* - //')

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
    esac

    echo "| ${factor_name} | ${icon} ${factor_status} | ${factor_detail} |"
  done

  echo ""
  echo "SUMMARY: ${fail_count} FAIL, ${warn_count} WARNING across 12 factors"
  echo "FACTOR_13: PASS - Compliance report generated"
}

factor_13_report
exit 0
