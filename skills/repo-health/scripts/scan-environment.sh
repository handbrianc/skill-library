#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-environment.sh — repo-health environment readiness & transient file scan
#
# Combines PHASE 0 (Environment Readiness gate) and PHASE 0.5 (Transient File
# Cleanup pre-audit) from the repo-health SKILL.md into a single script.
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

# ── helpers ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 0 — Environment Readiness (Gate)
# ═══════════════════════════════════════════════════════════════════════════

check_tools_phase() {
  echo "=== PHASE 0: ENVIRONMENT READINESS ==="
  echo ""

  # ── Core utilities ──────────────────────────────────────────────────────
  echo "--- Core Utilities ---"

  if command -v bash >/dev/null 2>&1 && bash --version >/dev/null 2>&1; then
    if bash -c 'exit $((BASH_VERSINFO[0] < 4))' >/dev/null 2>&1; then
      echo "TOOL_OK: bash $(bash --version | head -1)"
    else
      echo "TOOL_MISSING: bash version < 4.0 (need bash >= 4.0 for associative arrays)"
    fi
  else
    echo "TOOL_MISSING: bash (not found or broken)"
  fi

  if command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1; then
    echo "TOOL_OK: node $(node --version)"
  else
    echo "TOOL_MISSING: node"
  fi

  if command -v npm >/dev/null 2>&1 && npm --version >/dev/null 2>&1; then
    echo "TOOL_OK: npm $(npm --version)"
  else
    echo "TOOL_MISSING: npm"
  fi

  if command -v npx >/dev/null 2>&1 && npx --version >/dev/null 2>&1; then
    echo "TOOL_OK: npx $(npx --version)"
  else
    echo "TOOL_MISSING: npx"
  fi

  if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
    echo "TOOL_OK: git $(git --version)"
  else
    echo "TOOL_MISSING: git"
  fi

  if command -v jq >/dev/null 2>&1 && jq --version >/dev/null 2>&1; then
    echo "TOOL_OK: jq $(jq --version)"
  else
    echo "TOOL_MISSING: jq"
  fi

  if command -v find >/dev/null 2>&1; then
    if find . -maxdepth 1 -type d >/dev/null 2>&1; then
      echo "TOOL_OK: find (supports -maxdepth)"
    else
      echo "TOOL_MISSING: find does not support -maxdepth (install GNU findutils; on macOS: brew install findutils)"
    fi
  else
    echo "TOOL_MISSING: find (not found)"
  fi

  echo ""

  # ── Language runtimes (informational) ──────────────────────────────────
  echo "--- Language Runtimes (Informational) ---"

  if command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then
    echo "TOOL_OK: python3 $(python3 --version)"
  else
    echo "TOOL_MISSING: python3 (optional)"
  fi

  if command -v pip3 >/dev/null 2>&1 && pip3 --version >/dev/null 2>&1; then
    echo "TOOL_OK: pip3 $(pip3 --version 2>/dev/null | head -1)"
  else
    echo "TOOL_MISSING: pip3 (optional)"
  fi

  if command -v go >/dev/null 2>&1 && go version >/dev/null 2>&1; then
    echo "TOOL_OK: go $(go env GOVERSION 2>/dev/null || go version | awk '{print $3}')"
  else
    echo "TOOL_MISSING: go (optional)"
  fi

  if command -v cargo >/dev/null 2>&1 && cargo --version >/dev/null 2>&1; then
    echo "TOOL_OK: cargo $(cargo --version 2>/dev/null)"
  else
    echo "TOOL_MISSING: cargo (optional)"
  fi

  echo ""

  # ── Repo-health helper scripts ──────────────────────────────────────────
  echo "--- Repo-Health Helper Scripts ---"

  for script in \
    audit-dependency-usage.sh \
    check-doc-links.sh \
    compare-specs.sh \
    detect-dead-code.sh \
    find-duplicates.sh \
    find-uncovered.sh \
    parse-test-results.sh \
    run-scan-suite.sh \
    scan-12factor.sh \
    scan-cognitive-complexity.sh \
    scan-complexity.sh \
    scan-docs.sh \
    scan-environment.sh \
    scan-licenses.sh \
    scan-linters.sh \
    scan-sbom.sh \
    scan-security.sh \
    scan-secrets.sh \
    scan-setup.sh \
    scan-tech-debt.sh \
    scan-tests.sh
  do
    path="$SCRIPT_DIR/$script"
    if [[ -f "$path" ]]; then
      if bash -n "$path" 2>/dev/null; then
        echo "TOOL_OK: $script (valid syntax)"
      else
        echo "TOOL_MISSING: $script (syntax error via bash -n)"
      fi
    else
      echo "TOOL_MISSING: $script (not found at $path)"
    fi
  done

  echo ""

  # ── Project-type specific tools (informational) ─────────────────────────
  echo "--- Project-Type Tools (Informational) ---"

  if command -v vitest >/dev/null 2>&1; then
    echo "TOOL_OK: vitest $(vitest --version 2>/dev/null)"
  else
    echo "TOOL_MISSING: vitest (optional)"
  fi

  if command -v jest >/dev/null 2>&1; then
    echo "TOOL_OK: jest $(jest --version 2>/dev/null)"
  else
    echo "TOOL_MISSING: jest (optional)"
  fi

  if command -v pytest >/dev/null 2>&1; then
    echo "TOOL_OK: pytest $(pytest --version 2>/dev/null | head -1)"
  else
    echo "TOOL_MISSING: pytest (optional)"
  fi

  if command -v eslint >/dev/null 2>&1; then
    echo "TOOL_OK: eslint $(eslint --version 2>/dev/null)"
  else
    echo "TOOL_MISSING: eslint (optional)"
  fi

  if command -v jscpd >/dev/null 2>&1; then
    echo "TOOL_OK: jscpd $(jscpd --version 2>/dev/null)"
  else
    echo "TOOL_MISSING: jscpd (optional)"
  fi

  if command -v semgrep >/dev/null 2>&1; then
    echo "TOOL_OK: semgrep $(semgrep --version 2>/dev/null)"
  else
    echo "TOOL_MISSING: semgrep (optional)"
  fi

  if command -v syft >/dev/null 2>&1; then
    echo "TOOL_OK: syft $(syft version 2>/dev/null | head -1)"
  else
    echo "TOOL_MISSING: syft (optional)"
  fi

  if command -v grype >/dev/null 2>&1; then
    echo "TOOL_OK: grype $(grype version 2>/dev/null | head -1)"
  else
    echo "TOOL_MISSING: grype (optional)"
  fi

  # GitNexus (via PATH)
  if command -v gitnexus >/dev/null 2>&1; then
    echo "TOOL_OK: gitnexus (available via PATH)"
  else
    echo "TOOL_MISSING: gitnexus (PATH)"
  fi

  # GitNexus (via npx local)
  if npx --yes --no-install gitnexus --version >/dev/null 2>&1; then
    echo "TOOL_OK: gitnexus (available via npx local)"
  else
    echo "TOOL_MISSING: gitnexus (npx local)"
  fi

  echo ""
  echo "--- PHASE 0 complete ---"
}

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
