#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-environment-tools.sh — PHASE 0 Environment Readiness (tool detection)
#
# Standalone script. Run directly or source from scan-environment.sh.
# Output conventions:
#   TOOL_OK:      tool is present and working (with version/details)
#   TOOL_MISSING: tool is absent or broken (with reason)
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

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  check_tools_phase
  echo ""
  echo "=== scan-environment-tools.sh complete (exit 0) ==="
fi
