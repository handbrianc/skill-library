#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-tech-debt.sh — Top-Down Technical Debt Review (PHASE 3)
#
# Thin dispatcher that runs all 7 step scripts in order.
#
# Implements Steps 3.1 through 3.7 from the repo-health SKILL.md:
#   3.1  TODO/FIXME/HACK/XXX inventory with aging and density
#   3.2  Module coupling, circular deps, layer violations, god modules
#   3.3  Framework/language runtime currency
#   3.4  Test debt (ratio, slow tests, test smells)
#   3.5  API surface / export debt (unused exports, barrel files, hotspots)
#   3.6  Error handling / resilience debt
#   3.7  Structured report synthesis
#
# Usage:
#   ./skills/repo-health/scripts/scan-tech-debt.sh [src-dir] [test-output-file]
#
#   src-dir defaults to "src/" if not provided (pass "." to scan the whole
#   tree — vendor directories such as .venv/node_modules are always excluded).
#   test-output-file defaults to /tmp/test-output.txt if not provided.
#
# Exits 0 always — findings are data, not failures.
# Requires: bash >= 4.0, git; jq/npx optional (missing tools degrade to N/A).
# ---------------------------------------------------------------------------

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---- Config ---------------------------------------------------------------
SRC_DIR="${1:-src}"
TEST_OUTPUT="${2:-/tmp/test-output.txt}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Trap to ensure exit 0 always
trap 'exit 0' EXIT
trap '' PIPE

# ---- Run all 7 steps in order ---------------------------------------------

echo "=== TECHNICAL DEBT SCAN ==="
echo "Target: $SRC_DIR"
echo "Test output: $TEST_OUTPUT"

step() {
  local script="$1"
  local label="$2"
  shift 2
  if [[ ! -f "$script" ]]; then
    err "MISSING: $script — skipping $label"
    return 0
  fi
  echo "" >&2
  if ! "$script" "$@"; then
    err "$label exited non-zero (continuing with remaining steps)"
  fi
}

step "$SCRIPT_DIR/scan-tech-debt-step-1.sh" "Step 3.1" "$SRC_DIR"
step "$SCRIPT_DIR/scan-tech-debt-step-2.sh" "Step 3.2" "$SRC_DIR"
step "$SCRIPT_DIR/scan-tech-debt-step-3.sh" "Step 3.3" "$SRC_DIR"
step "$SCRIPT_DIR/scan-tech-debt-step-4.sh" "Step 3.4" "$SRC_DIR" "$TEST_OUTPUT"
step "$SCRIPT_DIR/scan-tech-debt-step-5.sh" "Step 3.5" "$SRC_DIR"
step "$SCRIPT_DIR/scan-tech-debt-step-6.sh" "Step 3.6" "$SRC_DIR"
step "$SCRIPT_DIR/scan-tech-debt-step-7.sh" "Step 3.7" "$SRC_DIR" "$TEST_OUTPUT"

echo ""
echo "TECH_DEBT_SCAN_COMPLETE"
