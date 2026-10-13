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
#   src-dir defaults to "src/" if not provided. Vendor directories
#   (.venv, venv, node_modules, __pycache__, site-packages, *.dist-info, .git)
#   are always excluded.
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

# ---- Helpers ---------------------------------------------------------------

# npx tool available offline? (never trigger a network install)
npx_has() {
  has_cmd npx || return 1
  npx --no-install "$1" --version &>/dev/null
}

# Count imports in one file — always a single integer
count_imports() {
  local file="$1" pat="$2"
  { grep -cE -- "$pat" "$file" 2>/dev/null || true; } | awk '{s+=$1} END{print s+0}'
}

# ===========================================================================
# STEP 3.2 — Module Coupling and Dependency Analysis
# ===========================================================================

section "STEP 3.2 — Architectural Analysis"

if [[ ! -d "$SRC_DIR" ]]; then
  warn "Source directory not found: $SRC_DIR — architectural analysis N/A"
  exit 0
fi
echo "  Target: $SRC_DIR"

echo ""
sub "Circular Dependency Check"
if [[ -f "package.json" ]]; then
  if npx_has madge; then
    rc=0
    timeout 120 npx --no-install madge --circular "$SRC_DIR" --extensions ts,tsx,js,jsx 2>/dev/null || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      echo "  MADGE_CHECK: no circular dependencies detected"
    elif [[ "$rc" -eq 124 ]]; then
      warn "MADGE_CHECK: timed out after 120s — N/A"
    else
      warn "MADGE_CHECK: circular dependencies found (see above)"
    fi
  else
    warn "madge not installed — JS/TS circular dependency check N/A (npm i -g madge to enable)"
  fi
  if npx_has dpdm; then
    rc=0
    timeout 120 npx --no-install dpdm --circular "$SRC_DIR" --exit-code circular 2>/dev/null || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      echo "  DPDM_CHECK: no circular deps"
    else
      warn "DPDM_CHECK: circular dependencies found (check output)"
    fi
  else
    warn "dpdm not installed — DPDM circular check N/A"
  fi
else
  warn "No package.json — JS/TS circular dependency checks N/A"
  warn "Python circular imports: not detected by this scan (consider import-linter) — N/A"
fi

echo ""
sub "Layer Violation Check"
violations=0

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
if [[ ! -d "$SRC_DIR/controllers" && ( -f "pyproject.toml" || -f "requirements.txt" ) ]]; then
  warn "NOTE: layer-violation heuristics cover TS/JS layouts (controllers/models/api/db/ui) — N/A for Python layering"
fi

echo ""
sub "God Module Detection"
god_modules=0
while IFS= read -r -d '' f; do
  case "$f" in
    *.py) import_pat='^[[:space:]]*(import[[:space:]]|from[[:space:]])' ;;
    *)    import_pat='import.*from|require\(' ;;
  esac
  imports=$(count_imports "$f" "$import_pat")
  if [[ "$imports" -ge 20 ]]; then
    echo "  GOD_MODULE: $f ($imports imports)"
    god_modules=$((god_modules + 1))
  fi
done < <(find "$SRC_DIR" \
  \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
       -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
       -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
       -o -name dist -o -name build \) -prune \) \
  -o \( -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' \) -print0 \) 2>/dev/null)
kv "God modules (>=20 imports)" "$god_modules"
