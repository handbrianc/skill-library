#!/usr/bin/env bash
# scan-setup.sh — PHASE 1 (Setup & Discovery) and PHASE 5 (OpenSpec Specifications)
#
# Usage:
#   ./scan-setup.sh                  # Run both discovery and specs
#   ./scan-setup.sh --mode=discovery # Tech stack, package manager, entry points, docs
#   ./scan-setup.sh --mode=specs     # Spec discovery, archive scan, alignment stub
#
# Exits 0 always.

set -euo pipefail

MODE="${1:-}"
DISCOVERY=false
SPECS=false

case "$MODE" in
  --mode=discovery) DISCOVERY=true ;;
  --mode=specs)     SPECS=true     ;;
  "")               DISCOVERY=true; SPECS=true ;;
  *)
    echo "Unknown mode: $MODE"
    echo "Usage: $0 [--mode=discovery|--mode=specs]"
    exit 0
    ;;
esac

# ────────────────────────────────────────────────────────────
# PHASE 1 — Setup & Discovery
# ────────────────────────────────────────────────────────────
if "$DISCOVERY"; then
  echo "=== PHASE 1: SETUP & DISCOVERY ==="

  # -- Tech stack identification
  echo ""
  echo "--- Tech Stack ---"
  jq '{name, version, private, engines, scripts}' package.json 2>/dev/null || echo "{}"
  ls *.json tsconfig.* pyproject.toml Cargo.toml go.mod Makefile pom.xml build.gradle 2>/dev/null | head -20
  git log --oneline -5

  # -- Package manager artifacts
  echo ""
  echo "--- Package Manager Artifacts ---"
  npm ls --depth=0 2>/dev/null | head -40
  pnpm list --depth=0 2>/dev/null | head -40
  yarn list --depth=0 2>/dev/null | head -40
  pip list 2>/dev/null | head -30

  # -- Entry points
  echo ""
  echo "--- Entry Points ---"
  ls src/ lib/ app/ cmd/ main.* */main.* 2>/dev/null | head -20
  find . -name "__main__.py" -o -name "main.go" 2>/dev/null | head -20

  # -- Documentation locations
  echo ""
  echo "--- Documentation Locations ---"
  ls *.md *.rst *.txt LICENSE* CONTRIBUTING* docs/ wiki/ .github/ 2>/dev/null | head -30

  # -- Specification locations
  echo ""
  echo "--- Specification Locations ---"
  ls specs/ SPEC.md OPENSPEC* .spec/ spec/ arch/ 2>/dev/null | head -30

  echo ""
fi

# ────────────────────────────────────────────────────────────
# PHASE 5 — OpenSpec Specifications
# ────────────────────────────────────────────────────────────
if "$SPECS"; then
  echo "=== PHASE 5: OPENSPEC SPECIFICATIONS ==="

  # -- Step 5.1: Locate specs
  echo ""
  echo "--- Step 5.1: Locate Specs ---"
  ls -la specs/ OPENSPEC* .spec/ arch/ spec/ 2>/dev/null
  find . -maxdepth 4 \( -name "*spec*" -o -name "*SPEC*" -o -name "*requirement*" \) \
    ! -path "./node_modules/*" ! -path "./.git/*" -type f 2>/dev/null | head -40

  # -- Step 5.2: Archive scan
  echo ""
  echo "--- Step 5.2: Archive Scan ---"
  ls -lt specs/archive/ specs/v0.*/ specs/old/ 2>/dev/null

  # -- Step 5.3: Alignment stub
  echo ""
  echo "--- Step 5.3: Alignment Check (STUB) ---"
  echo "Spec alignment not yet automated."
  echo "Manual steps:"
  echo "  1. Read each spec's requirements (Given/When/Then or plain requirements)"
  echo "  2. Cross-reference with code — does implementation exist?"
  echo "  3. Flag: spec requires X but code has no evidence of X implementation"

  echo ""
fi

exit 0
