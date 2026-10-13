#!/usr/bin/env bash
# scan-12factor.sh — Twelve-Factor App Compliance Scanner (Orchestrator)
#
# Runs all 12 factor scans, then generates a summary report.
# Delegates to scan-12factor-factor-[1-12].sh and scan-12factor-report.sh.
#
# Usage: ./scan-12factor.sh [target-dir]
#   target-dir: the project directory to audit (default: current directory).
#   All factor scripts receive it as $1; relative paths are resolved.
# Exit 0 always — findings are data, not script failures.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  --help|-h)
    echo "Usage: $0 [target-dir]"
    echo "Evaluates Twelve-Factor App compliance for target-dir (default: current directory)."
    echo "Outputs FACTOR_[N]: [PASS|FAIL|WARNING] - detail for each factor."
    echo "Exit 0 always."
    exit 0
    ;;
esac

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "ERROR: target directory not found: ${1:-<none>} — 12-factor scan N/A"
  exit 0
fi

echo "=== 12-FACTOR APP COMPLIANCE SCAN ==="
echo "REPO: $TARGET"
echo ""

# Run all 12 factor scripts once, capturing their FACTOR_* lines for the
# summary report so factors are not executed twice.
FACTOR_OUT="$(mktemp "${TMPDIR:-/tmp}/12factor-factors.XXXXXX")"
trap 'rm -f "$FACTOR_OUT"' EXIT
: > "$FACTOR_OUT"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if ! "$SCRIPT_DIR/scan-12factor-factor-$i.sh" "$TARGET" 2>&1 | tee -a "$FACTOR_OUT"; then
    echo "FACTOR_$i: WARNING - factor script exited non-zero (see above)" | tee -a "$FACTOR_OUT"
  fi
done

# Generate summary report (reads the captured factor output)
"$SCRIPT_DIR/scan-12factor-report.sh" "$TARGET" "$FACTOR_OUT" 2>&1

exit 0
