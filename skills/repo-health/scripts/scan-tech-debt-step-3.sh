#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-tech-debt-step-3.sh — Step 3.3: Technology currency check
#
# Checks framework/language runtime versions and major dependency freshness.
# Part of the repo-health technical debt scan suite.
#
# Usage:
#   ./skills/repo-health/scripts/scan-tech-debt-step-3.sh [src-dir]
#
#   src-dir defaults to "src/" if not provided.
#
# Exits 0 always — findings are data, not failures.
# ---------------------------------------------------------------------------

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---- Config ---------------------------------------------------------------
SRC_DIR="${1:-src}"

# Colours for headings (disabled if not a terminal)
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' CYAN='' NC=''
fi

section()   { echo -e "\n${BOLD}${CYAN}====${NC} ${BOLD}$*${NC}${BOLD}${CYAN} ====${NC}"; }
sub()       { echo -e "  ${GREEN}$*${NC}"; }
warn()      { echo -e "  ${YELLOW}$*${NC}"; }
err()       { echo -e "  ${RED}$*${NC}" >&2; }
kv()        { echo "  $1: $2"; }

# Trap to ensure exit 0 always
trap 'exit 0' EXIT
trap '' PIPE

# ===========================================================================
# STEP 3.3 — Framework and Language Runtime Currency
# ===========================================================================

section "STEP 3.3 — Technology Currency Check"

sub "Node.js"
if [[ -f "package.json" ]]; then
  node_required=$(jq -r '.engines.node // "not specified"' package.json)
  kv "Node required" "$node_required"
  kv "Node current" "$(node --version 2>/dev/null || echo 'N/A')"
  if has_cmd npx; then
    kv "Node LTS" "$(npx semver --lts 2>/dev/null || echo 'check https://nodejs.org')"
  fi
fi

sub "TypeScript"
if [[ -f "tsconfig.json" ]]; then
  kv "TypeScript version" "$(npx tsc --version 2>/dev/null || echo 'N/A')"
  echo "  tsconfig files: $(ls tsconfig*.json 2>/dev/null | tr '\n' ' ')"
fi

sub "Python"
if [[ -f "pyproject.toml" || -f "requirements.txt" ]]; then
  kv "Python required" "$(grep -E 'python_requires' pyproject.toml 2>/dev/null || echo 'not specified')"
  kv "Python current" "$(python3 --version 2>/dev/null || echo 'N/A')"
fi

sub "Go"
if [[ -f "go.mod" ]]; then
  kv "Go version" "$(head -1 go.mod 2>/dev/null)"
  kv "Go current" "$(go version 2>/dev/null || echo 'N/A')"
fi

sub "Rust"
if [[ -f "Cargo.toml" ]]; then
  if grep -qE 'edition\s*=' Cargo.toml 2>/dev/null; then
    kv "Rust edition" "$(grep -E 'edition\s*=' Cargo.toml 2>/dev/null)"
  else
    warn "Rust edition not set (defaults to 2015)"
  fi
fi

echo ""
sub "Major Dependency Versions"
if [[ -f "package.json" ]]; then
  jq -r '.dependencies // {} | to_entries[] | select(.value | test("^\\^0\\.|^\\^1\\.[0-9]|^\\^2\\.[0-9]")) | "- \(.key): \(.value)"' package.json 2>/dev/null | head -20 || true
  echo ""
  if command -v npm &>/dev/null; then
    npm outdated --long 2>/dev/null | head -30 || warn "npm outdated failed (run npm install first?)"
  fi
fi
