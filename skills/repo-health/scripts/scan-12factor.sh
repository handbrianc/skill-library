#!/usr/bin/env bash
# scan-12factor.sh — Twelve-Factor App Compliance Scanner (Orchestrator)
#
# Runs all 12 factor scans, then generates a summary report.
# Delegates to scan-12factor-factor-[1-12].sh and scan-12factor-report.sh.
#
# Usage: ./scan-12factor.sh
# Exit 0 always — findings are data, not script failures.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  --help|-h)
    echo "Usage: $0"
    echo "Evaluates Twelve-Factor App compliance."
    echo "Outputs FACTOR_[N]: [PASS|FAIL|WARNING] - detail for each factor."
    echo "Exit 0 always."
    exit 0
    ;;
esac

echo "=== 12-FACTOR APP COMPLIANCE SCAN ==="
echo "REPO: $REPO_ROOT"
echo ""

# Run all 12 factor scripts
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

# Generate summary report
"$SCRIPT_DIR/scan-12factor-report.sh" 2>&1

exit 0
