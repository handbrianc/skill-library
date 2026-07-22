#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-tech-debt.sh — Top-Down Technical Debt Review (PHASE 3)
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

# Extensions to scan for debt markers and code analysis
TS_EXT="-name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx'"
PY_EXT="-name '*.py'"
GO_EXT="-name '*.go'"
RS_EXT="-name '*.rs'"
JV_EXT="-name '*.java' -o -name '*.kt'"
RB_EXT="-name '*.rb'"
PHP_EXT="-name '*.php'"
CS_EXT="-name '*.cs'"
SWIFT_EXT="-name '*.swift'"
DART_EXT="-name '*.dart'"

ALL_CODE_EXT="-name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.rb' -o -name '*.php' -o -name '*.cs' -o -name '*.kt' -o -name '*.swift' -o -name '*.dart'"
ALL_TS_LIKE="-name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx'"

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

# ---- Helpers --------------------------------------------------------------

# Count debt markers of a given keyword (case-insensitive grep)
count_markers() {
  local marker="$1"
  grep -rni "$marker" "$SRC_DIR" \
    --include='*.js' --include='*.ts' --include='*.tsx' --include='*.jsx' \
    --include='*.py' --include='*.go' --include='*.rs' --include='*.java' \
    --include='*.rb' --include='*.php' --include='*.cs' --include='*.kt' \
    --include='*.swift' --include='*.dart' \
    2>/dev/null \
    | grep -v 'node_modules\|\.git\|/test/\|/tests/\|/spec/' \
    | grep -vi 'nocheck\|eslint-disable\|pragma' \
    | wc -l
  # Return 0 so the pipeline doesn't fail on empty grep
  return 0
}

# Safe bc arithmetic (returns 0 or value)
calc() {
  local expr="$1"
  echo "$expr" | bc 2>/dev/null || echo "0"
}

# ---- MAIN ----------------------------------------------------------------

# Trap to ensure exit 0 always
trap 'exit 0' EXIT
trap '' PIPE

# ===========================================================================
# STEP 3.1 — TODO/FIXME/HACK/XXX Inventory with Aging
# ===========================================================================

section "STEP 3.1 — Technical Debt Marker Inventory"

echo "  Marker Counts:"
total_markers=0
for marker in TODO FIXME HACK XXX WORKAROUND TEMPORARY KLUDGE; do
  cnt=$(count_markers "$marker")
  printf "  %-16s %s\n" "$marker:" "$cnt"
  total_markers=$((total_markers + cnt))
done
kv "Total markers" "$total_markers"

echo ""
sub "Oldest Debt Markers (git blame)"
for marker in TODO FIXME HACK; do
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    git blame "$SRC_DIR" -en -f -w -C 2>/dev/null \
      | grep -i "$marker" | head -10 2>/dev/null || true
  else
    warn "Not a git repository — skipping git blame"
    break
  fi
done

echo ""
sub "Marker Density"
total_lines=$(find "$SRC_DIR" \
  -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.jsx' \
  -o -name '*.py' -o -name '*.go' \
  2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')

if [[ -n "$total_lines" && "$total_lines" -gt 0 ]]; then
  density=$(calc "scale=2; $total_markers * 1000 / $total_lines")
  kv "Marker density" "$density per 1000 LOC ($total_markers markers in $total_lines lines)"
else
  warn "No source files found for density calculation"
fi

# ===========================================================================
# STEP 3.2 — Module Coupling and Dependency Analysis
# ===========================================================================

section "STEP 3.2 — Architectural Analysis"

sub "GitNexus Clusters"
if has_cmd npx; then
  npx gitnexus status 2>/dev/null || npx gitnexus analyze --force 2>/dev/null || true
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

# ===========================================================================
# STEP 3.4 — Test Debt Analysis
# ===========================================================================

section "STEP 3.4 — Test Debt Analysis"

sub "Test-to-Production File Ratio"
prod_files=$(find "$SRC_DIR" \
  -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.go' \
  2>/dev/null | wc -l)
test_files=$(find . -path ./node_modules -prune -o \
  \( -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.go' -o -name 'test_*.py' \) \
  -print 2>/dev/null | wc -l)

if [[ "$prod_files" -gt 0 ]]; then
  ratio=$(calc "scale=2; $test_files / $prod_files")
  kv "Test:Production ratio" "$ratio ($test_files test files : $prod_files production files)"
else
  warn "No production source files found"
fi

echo ""
sub "Slowest Tests"
if [[ -f "$TEST_OUTPUT" ]]; then
  grep -E '✓|✗|PASS|FAIL' "$TEST_OUTPUT" 2>/dev/null \
    | grep -oE '[0-9]+ms|[0-9]+\.[0-9]+s' \
    | sort -rn | head -10 \
    || echo "  No timing data available"
else
  warn "Test output not found at $TEST_OUTPUT — skipping slow test analysis"
fi

echo ""
sub "Test Smell Detection"
smell_count=0
while IFS= read -r -d '' f; do
  sleeps=$(grep -cE 'sleep|setTimeout|wait.*[0-9]' "$f" 2>/dev/null || echo "0")
  if [[ "$sleeps" -gt 0 ]]; then
    echo "  TEST_SMELL_SLEEP: $f ($sleeps sleep calls)"
    smell_count=$((smell_count + 1))
  fi
  mocks=$(grep -cE 'mock|stub|fake|spy' "$f" 2>/dev/null || echo "0")
  if [[ "$mocks" -gt 20 ]]; then
    echo "  TEST_SMELL_OVERMOCKED: $f ($mocks mock/stub/spy references)"
    smell_count=$((smell_count + 1))
  fi
done < <(find . -path ./node_modules -prune -o \
  \( -name '*.test.*' -o -name '*.spec.*' \) -print0 2>/dev/null)
kv "Test smells detected" "$smell_count"

# ===========================================================================
# STEP 3.5 — API Surface and Export Debt
# ===========================================================================

section "STEP 3.5 — API Surface Analysis"

sub "Unused Exports"
if has_cmd npx && [[ -f "tsconfig.json" ]]; then
  npx ts-prune --project tsconfig.json 2>/dev/null \
    && echo "  TS_PRUNE_CHECK: completed (unused exports listed above)" \
    || warn "TS_PRUNE_CHECK: completed with issues" || true
else
  warn "ts-prune not available or no tsconfig.json"
  # Fallback: count barrel files
fi

echo ""
sub "Barrel Files"
barrel_count=$(find "$SRC_DIR" -name 'index.ts' -o -name 'index.js' 2>/dev/null | wc -l)
kv "Barrel file count" "$barrel_count"

echo ""
sub "Frequently Changed Files (hotspots, last 6 months)"
if git rev-parse --is-inside-work-tree &>/dev/null; then
  git log --oneline --since='6 months ago' --name-only 2>/dev/null \
    | sort | uniq -c | sort -rn | head -20 \
    || echo "  No changes in last 6 months or git history unavailable"
else
  warn "Not a git repository — skipping hotspot analysis"
fi

# ===========================================================================
# STEP 3.6 — Error Handling and Resilience Debt
# ===========================================================================

section "STEP 3.6 — Error Handling Debt"

sub "Empty Catch Blocks"
empty_catches=$(grep -rn 'catch\s*(\s*\w*\s*)\s*{\s*}' "$SRC_DIR" \
  --include='*.js' --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
kv "Empty catch blocks" "$empty_catches"

sub "Bare Catch Blocks (silent ignores)"
bare_catches=$(grep -rnE 'catch\s*\(.*\)\s*\{\s*//\s*(TODO|FIXME|ignore|silent)' \
  "$SRC_DIR" --include='*.js' --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
kv "Bare catch blocks" "$bare_catches"

echo ""
sub "Global Error Handlers"
if grep -rn 'process\.on.*uncaught\|process\.on.*unhandled\|@ExceptionHandler' \
  "$SRC_DIR" --include='*.js' --include='*.ts' 2>/dev/null | head -10; then
  :
else
  echo "  No global error handlers found"
fi

echo ""
sub "Error Boundaries (component apps)"
if [[ -d "$SRC_DIR/components" ]]; then
  error_boundaries=$(grep -rn 'componentDidCatch\|ErrorBoundary\|getDerivedStateFromError' \
    "$SRC_DIR/components/" --include='*.tsx' --include='*.jsx' 2>/dev/null | wc -l)
  kv "Error boundaries" "$error_boundaries"
  component_count=$(find "$SRC_DIR/components/" -name '*.tsx' -o -name '*.jsx' 2>/dev/null | wc -l)
  if [[ "$component_count" -gt 0 ]]; then
    boundary_coverage=$(calc "scale=2; $error_boundaries * 100 / $component_count")
    kv "Error boundary coverage" "${boundary_coverage}% of components"
  fi
else
  echo "  No components directory found — skipping error boundary check"
fi

echo ""
sub "Logging Consistency"
console_count=$(grep -rn 'console\.log\|console\.error\|console\.warn' "$SRC_DIR" \
  --include='*.js' --include='*.ts' 2>/dev/null | wc -l)
structured_count=$(grep -rn 'logger\.\|log\.\|logging\.' "$SRC_DIR" \
  --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | wc -l)
kv "Ad-hoc log statements (console.*)" "$console_count"
kv "Structured log statements" "$structured_count"
if [[ "$structured_count" -gt 0 ]]; then
  total_logs=$((console_count + structured_count))
  if [[ "$total_logs" -gt 0 ]]; then
    console_ratio=$(calc "scale=2; $console_count / $total_logs")
    kv "Ad-hoc log ratio" "$console_ratio (% of all log statements that are ad-hoc)"
  fi
fi

# ===========================================================================
# STEP 3.7 — Synthesize Technical Debt Profile
# ===========================================================================

section "STEP 3.7 — Technical Debt Profile"

# Re-count markers for the report table
todo_cnt=$(count_markers "TODO")
fixme_cnt=$(count_markers "FIXME")
hack_cnt=$(count_markers "HACK")
xxx_cnt=$(count_markers "XXX")
workaround_cnt=$(count_markers "WORKAROUND")
temp_cnt=$(count_markers "TEMPORARY")
kludge_cnt=$(count_markers "KLUDGE")
grand_total=$((todo_cnt + fixme_cnt + hack_cnt + xxx_cnt + workaround_cnt + temp_cnt + kludge_cnt))

density_str="N/A"
if [[ -n "$total_lines" && "$total_lines" -gt 0 ]]; then
  density_str=$(calc "scale=2; $grand_total * 1000 / $total_lines")
fi

cat <<PROFILE

## TECHNICAL DEBT PROFILE

### Marker Debt
| Category    | Count | Severity |
|-------------|-------|----------|
| TODO        | $todo_cnt | — |
| FIXME       | $fixme_cnt | — |
| HACK        | $hack_cnt | — |
| XXX         | $xxx_cnt | — |
| WORKAROUND  | $workaround_cnt | — |
| TEMPORARY   | $temp_cnt | — |
| KLUDGE      | $kludge_cnt | — |
| **Total**   | **$grand_total** | — |
| Marker density | $density_str/1000 LOC | — |

### Architecture Debt
| Finding | Severity |
|---------|----------|
| Circular dependencies | (see MADGE/DPDM output above) |
| Layer violations: $violations | — |
| God modules: $god_modules | — |
| Barrel files: $barrel_count | — |

### Technology Debt
| Finding | Severity |
|---------|----------|
| Node required: $node_required | — |
| TypeScript: $(npx tsc --version 2>/dev/null || echo 'N/A') | — |

### Test Debt
| Finding | Severity |
|---------|----------|
| Test:Production ratio: ${ratio:-N/A} | — |
| Test smells: $smell_count | — |

### API Surface Debt
| Finding | Severity |
|---------|----------|
| Barrel files: $barrel_count | — |
| Hotspot files | (see git log output above) |

### Error Handling Debt
| Finding | Severity |
|---------|----------|
| Empty catch blocks: $empty_catches | — |
| Bare catch blocks: $bare_catches | — |
| Ad-hoc console logs: $console_count | — |

### OVERALL TECHNICAL DEBT RATING
- **LOW**: Minor, schedule when convenient
- **MEDIUM**: Plan to address within next quarter
- **HIGH**: Actively causing friction or risk — prioritize
- **CRITICAL**: Blocking velocity or creating production risk — address now

**Overall rating: PENDING** (review findings above and apply severity guide from SKILL.md)
PROFILE

# Done — exit 0 always (findings are data, not failures)
