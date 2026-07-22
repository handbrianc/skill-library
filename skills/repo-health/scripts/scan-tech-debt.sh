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
#   src-dir defaults to "src/" if not provided.
#   test-output-file defaults to /tmp/test-output.txt if not provided.
#
# Exits 0 always — findings are data, not failures.
# Requires: bash >= 4.0, git, jq, npx (for madge/dpdm/ts-prune)
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

"$SCRIPT_DIR/scan-tech-debt-step-1.sh" "$SRC_DIR"
"$SCRIPT_DIR/scan-tech-debt-step-2.sh" "$SRC_DIR"
"$SCRIPT_DIR/scan-tech-debt-step-3.sh" "$SRC_DIR"
"$SCRIPT_DIR/scan-tech-debt-step-4.sh" "$SRC_DIR" "$TEST_OUTPUT"
"$SCRIPT_DIR/scan-tech-debt-step-5.sh" "$SRC_DIR"
"$SCRIPT_DIR/scan-tech-debt-step-6.sh" "$SRC_DIR"
"$SCRIPT_DIR/scan-tech-debt-step-7.sh" "$SRC_DIR"
