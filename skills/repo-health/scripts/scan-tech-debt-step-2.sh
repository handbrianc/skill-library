#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-tech-debt-step-2.sh — Step 3.2: Module coupling & architecture
#
# Analyses circular dependencies, layer violations, and god modules.
# Part of the repo-health technical debt scan suite.
#
# Usage:
#   ./skills/repo-health/scripts/scan-tech-debt-step-2.sh [src-dir]
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
# STEP 3.2 — Module Coupling and Dependency Analysis
# ===========================================================================

section "STEP 3.2 — Architectural Analysis"

sub "GitNexus Clusters"
if has_cmd npx; then
  npx gitnexus status 2>/dev/null || npx gitnexus analyze --force --skip-agents-md 2>/dev/null || true
  npx gitnexus cypher \
    "MATCH (c:Community) RETURN c.heuristicLabel, c.symbolCount, c.cohesion, c.keywords ORDER BY c.symbolCount DESC" \
    2>/dev/null \
    | head -30 \
    || warn "GitNexus: not available or no clusters for this repo"
else
  warn "npx not available — skipping GitNexus queries"
fi

echo ""
sub "Circular Dependency Check"
if has_cmd npx; then
  # madge for JS/TS
  if npx madge --circular "$SRC_DIR" --extensions ts,tsx,js,jsx 2>/dev/null; then
    echo "  MADGE_CHECK: no circular dependencies detected"
  else
    warn "MADGE_CHECK: circular dependencies found (see above)"
  fi
  # dpdm for TS (best-effort, may fail gracefully)
  npx dpdm --circular "$SRC_DIR" --exit-code circular 2>/dev/null \
    && echo "  DPDM_CHECK: no circular deps" \
    || warn "DPDM_CHECK: circular dependencies found (check output)" || true
else
  warn "npx not available — skipping circular dependency checks"
fi

echo ""
sub "Layer Violation Check"
violations=0
if [[ -d "$SRC_DIR" ]]; then
  if [[ -d "$SRC_DIR/controllers" && -d "$SRC_DIR/models" ]]; then
    layer_hits=$(grep -rn 'from.*\.\./models\|from.*\.\./repositories' \
      "$SRC_DIR/controllers/" --include='*.ts' --include='*.js' 2>/dev/null | head -10 || true)
    if [[ -n "$layer_hits" ]]; then
      echo "$layer_hits"
      violations=$((violations + 1))
    fi
  fi
  if [[ -d "$SRC_DIR/api" && -d "$SRC_DIR/db" ]]; then
    layer_hits=$(grep -rn 'from.*\.\./db\|require.*\.\./db' \
      "$SRC_DIR/api/" --include='*.ts' --include='*.js' 2>/dev/null | head -10 || true)
    if [[ -n "$layer_hits" ]]; then
      echo "$layer_hits"
      violations=$((violations + 1))
    fi
  fi
  if [[ -d "$SRC_DIR/ui" && -d "$SRC_DIR/api" ]]; then
    layer_hits=$(grep -rn 'from.*\.\./api\|from.*\.\./services' \
      "$SRC_DIR/ui/" --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null | head -10 || true)
    if [[ -n "$layer_hits" ]]; then
      echo "$layer_hits"
      violations=$((violations + 1))
    fi
  fi
  if [[ "$violations" -eq 0 ]]; then
    echo "  LAYER_CHECK: no obvious layer violations detected"
  fi
  kv "Layer violations" "$violations potential violations found"
fi

echo ""
sub "God Module Detection"
god_modules=0
while IFS= read -r -d '' f; do
  imports=$(grep -cE 'import.*from|require\(' "$f" 2>/dev/null || echo "0")
  if [[ "$imports" -ge 20 ]]; then
    echo "  GOD_MODULE: $f ($imports imports)"
    god_modules=$((god_modules + 1))
  fi
done < <(find "$SRC_DIR" \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' \) -print0 2>/dev/null)
kv "God modules (>=20 imports)" "$god_modules"
