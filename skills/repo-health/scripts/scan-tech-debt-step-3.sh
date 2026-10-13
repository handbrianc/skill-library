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
# shellcheck disable=SC2034 # kept for interface consistency with other steps
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

# ---- Helpers ---------------------------------------------------------------
# npx tool available offline? (never trigger a network install)
npx_has() {
  has_cmd npx || return 1
  npx --no-install "$1" --version &>/dev/null
}

# ===========================================================================
# STEP 3.3 — Framework and Language Runtime Currency
# ===========================================================================

section "STEP 3.3 — Technology Currency Check"

sub "Node.js"
if [[ -f "package.json" ]]; then
  node_required=$(jq -r '.engines.node // "not specified"' package.json 2>/dev/null || echo "not specified")
  kv "Node required" "$node_required"
  kv "Node current" "$(node --version 2>/dev/null || echo 'N/A')"
else
  warn "No package.json — Node.js currency N/A"
fi

sub "TypeScript"
if [[ -f "tsconfig.json" ]]; then
  if npx_has tsc; then
    kv "TypeScript version" "$(timeout 60 npx --no-install tsc --version 2>/dev/null || echo 'N/A')"
  else
    warn "TypeScript not installed (npx --no-install) — version check N/A"
  fi
  echo "  tsconfig files: $(ls tsconfig*.json 2>/dev/null | tr '\n' ' ')"
else
  warn "No tsconfig.json — TypeScript currency N/A"
fi

sub "Python"
if [[ -f "pyproject.toml" || -f "requirements.txt" ]]; then
  if [[ -f "pyproject.toml" ]]; then
    py_req=$(grep -hE '^[[:space:]]*(requires-python|python_requires)[[:space:]]*=' pyproject.toml 2>/dev/null | head -1 || true)
    kv "Python required" "${py_req:-not specified}"
  else
    kv "Python required" "not specified (requirements.txt only)"
  fi
  kv "Python current" "$(python3 --version 2>/dev/null || echo 'N/A')"
  # Lockfile / pinning signal
  locks=""
  for lf in uv.lock poetry.lock Pipfile.lock requirements.txt; do
    if [[ -f "$lf" ]]; then locks="${locks:+$locks, }$lf"; fi
  done
  kv "Dependency lock/pin files" "${locks:-none found}"
else
  warn "No pyproject.toml/requirements.txt — Python currency N/A"
fi

sub "Go"
if [[ -f "go.mod" ]]; then
  kv "Go version" "$(head -1 go.mod 2>/dev/null)"
  kv "Go current" "$(go version 2>/dev/null || echo 'N/A')"
fi

sub "Rust"
if [[ -f "Cargo.toml" ]]; then
  if grep -qE 'edition\s*=' Cargo.toml 2>/dev/null; then
    kv "Rust edition" "$(grep -hE 'edition\s*=' Cargo.toml 2>/dev/null | head -1)"
  else
    warn "Rust edition not set (defaults to 2015)"
  fi
fi

echo ""
sub "Major Dependency Versions"
if [[ -f "package.json" ]]; then
  jq -r '.dependencies // {} | to_entries[] | select(.value | test("^\\^0\\.|^\\^1\\.[0-9]|^\\^2\\.[0-9]")) | "- \(.key): \(.value)"' package.json 2>/dev/null | head -20 || true
  echo ""
  if has_cmd npm; then
    rc=0
    timeout 60 npm outdated --long 2>/dev/null | head -30 || rc=$?
    [[ "$rc" -ne 0 && "$rc" -ne 124 ]] && warn "npm outdated failed (run npm install first?)"
  fi
else
  warn "No package.json — npm dependency freshness N/A (Python projects: review uv.lock / requirements pins manually)"
fi
