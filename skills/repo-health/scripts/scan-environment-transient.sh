#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-environment-transient.sh — PHASE 0.5 Transient File Inventory
#
# Standalone script. Run directly or source from scan-environment.sh.
# ---------------------------------------------------------------------------

# Only apply strict mode and traps when executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  trap 'exit 0' EXIT
  trap 'exit 0' INT TERM
fi

# Source shared library
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# Override SCRIPT_DIR: common.sh points to lib/, we need scripts/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 0.5 — Transient File Cleanup (Pre-Audit)
# ═══════════════════════════════════════════════════════════════════════════

scan_transient_phase() {
  echo "=== PHASE 0.5: TRANSIENT FILE INVENTORY ==="
  echo ""

  # ── Build artifacts ────────────────────────────────────────────────────
  echo "--- Build Artifact Directories ---"
  find . \
    \( -path "./openspec" -o -path "./opencode" -o -path "./.claude" -o -path "./.git" \) -prune -o \
    -type d \( \
      -name "node_modules" -o \
      -name "__pycache__" -o \
      -name ".pytest_cache" -o \
      -name ".next" -o \
      -name "dist" -o \
      -name "build" -o \
      -name "target" -o \
      -name "vendor" -o \
      -name ".venv" -o \
      -name "venv" \
    \) -prune -print \
    2>/dev/null | head -50

  echo ""

  # ── Lock files ──────────────────────────────────────────────────────────
  echo "--- Lock Files (Inventory Only — Usually Keep) ---"
  find . -maxdepth 3 \( \
    -name "package-lock.json" -o \
    -name "pnpm-lock.yaml" -o \
    -name "yarn.lock" -o \
    -name "poetry.lock" -o \
    -name "Cargo.lock" \
  \) ! -path "./node_modules/*" ! -path "./.git/*" 2>/dev/null

  echo ""

  # ── Cache directories ───────────────────────────────────────────────────
  echo "--- Cache Directories ---"
  find . -maxdepth 5 -type d \( \
    -name ".cache" -o \
    -name "tmp" -o \
    -name "temp" -o \
    -name "*.egg-info" -o \
    -name ".tox" \
  \) \
    ! -path "./openspec/*" \
    ! -path "./opencode/*" \
    ! -path "./.claude/*" \
    ! -path "./.git/*" \
    2>/dev/null | head -50

  echo ""

  # ── Editor/IDE noise ────────────────────────────────────────────────────
  echo "--- Editor / IDE Noise ---"
  find . -maxdepth 3 \( \
    -name "*.swp" -o \
    -name "*.swo" -o \
    -name ".DS_Store" -o \
    -name "Thumbs.db" -o \
    -name ".idea" -o \
    -name ".vscode/settings.json" -o \
    -name "*.orig" -o \
    -name "*~" \
  \) \
    ! -path "./openspec/*" \
    ! -path "./opencode/*" \
    ! -path "./.claude/*" \
    ! -path "./.git/*" \
    2>/dev/null

  echo ""

  # ── Log files ───────────────────────────────────────────────────────────
  echo "--- Log Files ---"
  find . -maxdepth 4 -name "*.log" \
    ! -path "./openspec/*" \
    ! -path "./opencode/*" \
    ! -path "./.claude/*" \
    ! -path "./.git/*" \
    2>/dev/null | head -20

  echo ""

  # ── OS artifacts ────────────────────────────────────────────────────────
  echo "--- OS Artifacts ---"
  find . -maxdepth 3 \( \
    -name ".Spotlight-V100" -o \
    -name ".Trashes" -o \
    -name ".fseventsd" \
  \) \
    ! -path "./openspec/*" \
    ! -path "./opencode/*" \
    ! -path "./.claude/*" \
    ! -path "./.git/*" \
    2>/dev/null

  echo ""
  echo "=== TRANSIENT FILE INVENTORY (REVIEW ONLY) ==="
  echo "Review the lists above; do NOT remove anything automatically."
  echo ""
  echo "--- PHASE 0.5 complete ---"
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  scan_transient_phase
  echo ""
  echo "=== scan-environment-transient.sh complete (exit 0) ==="
fi
