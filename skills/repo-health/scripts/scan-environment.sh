#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-environment.sh — repo-health environment readiness & transient file scan
#
# Combines PHASE 0 (Environment Readiness gate) and PHASE 0.5 (Transient File
# Cleanup pre-audit) from the repo-health SKILL.md into a single script.
#
# This is now a thin dispatcher that delegates to:
#   scan-environment-tools.sh      — PHASE 0 tool detection
#   scan-environment-transient.sh  — PHASE 0.5 transient file inventory
#
# Modes (mutually exclusive; no args = both):
#   --check-tools     Run PHASE 0 tool detection only
#   --scan-transient  Run PHASE 0.5 transient file inventory only
#
# Output conventions:
#   TOOL_OK:      tool is present and working (with version/details)
#   TOOL_MISSING: tool is absent or broken (with reason)
# ---------------------------------------------------------------------------
set -euo pipefail

# Always exit 0 — we report findings as data, never as a non-zero exit.
trap 'exit 0' EXIT
trap 'exit 0' INT TERM

# Source shared library
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

RUN_ALL=true
RUN_TOOLS=false
RUN_TRANSIENT=false

# ── arg parsing ────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --check-tools)  RUN_ALL=false; RUN_TOOLS=true    ;;
    --scan-transient) RUN_ALL=false; RUN_TRANSIENT=true ;;
    *) echo "Usage: $0 [--check-tools] [--scan-transient]" >&2; exit 0 ;;
  esac
done

if $RUN_ALL; then
  RUN_TOOLS=true
  RUN_TRANSIENT=true
fi

# Source sub-scripts to make their phase functions available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scan-environment-tools.sh"
source "$SCRIPT_DIR/scan-environment-transient.sh"

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

if $RUN_TOOLS; then
  check_tools_phase
  echo ""
fi

if $RUN_TRANSIENT; then
  scan_transient_phase
  echo ""
fi

echo "=== scan-environment.sh complete (exit 0) ==="
