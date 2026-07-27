#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scan-tech-debt-step-7.sh — Step 3.7: Synthesis report
#
# Re-derives all metrics from the preceding steps and produces the final
# TECHNICAL DEBT PROFILE table.
# Part of the repo-health technical debt scan suite.
#
# Usage:
#   ./skills/repo-health/scripts/scan-tech-debt-step-7.sh [src-dir] [test-output-file]
#
#   src-dir defaults to "src/" if not provided.
#   test-output-file defaults to /tmp/test-output.txt if not provided.
#
# Exits 0 always — findings are data, not failures.
# ---------------------------------------------------------------------------

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---- Config ---------------------------------------------------------------
SRC_DIR="${1:-src}"
TEST_OUTPUT="${2:-/tmp/test-output.txt}"

# Trap to ensure exit 0 always
trap 'exit 0' EXIT
trap '' PIPE

# ===========================================================================
# STEP 3.7 — Synthesize Technical Debt Profile
# ===========================================================================

section "STEP 3.7 — Technical Debt Profile"

# Re-count markers for the report table
todo_cnt=$(count_markers "TODO" "$SRC_DIR")
fixme_cnt=$(count_markers "FIXME" "$SRC_DIR")
hack_cnt=$(count_markers "HACK" "$SRC_DIR")
xxx_cnt=$(count_markers "XXX" "$SRC_DIR")
workaround_cnt=$(count_markers "WORKAROUND" "$SRC_DIR")
temp_cnt=$(count_markers "TEMPORARY" "$SRC_DIR")
kludge_cnt=$(count_markers "KLUDGE" "$SRC_DIR")
grand_total=$((todo_cnt + fixme_cnt + hack_cnt + xxx_cnt + workaround_cnt + temp_cnt + kludge_cnt))

# Re-derive total_lines for density (mirrors step-1)
total_lines=$(find "$SRC_DIR" \
  \( -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.jsx' \
     -o -name '*.py' -o -name '*.go' \) \
  -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')

density_str="N/A"
if [[ -n "$total_lines" && "$total_lines" -gt 0 ]]; then
  density_str=$(calc "scale=2; $grand_total * 1000 / $total_lines")
fi

# Re-derive architecture metrics (mirrors step-2)
violations=0
if [[ -d "$SRC_DIR" ]]; then
  if [[ -d "$SRC_DIR/controllers" && -d "$SRC_DIR/models" ]]; then
    layer_hits=$(grep -rn 'from.*\.\./models\|from.*\.\./repositories' \
      "$SRC_DIR/controllers/" --include='*.ts' --include='*.js' 2>/dev/null | head -10 || true)
    if [[ -n "$layer_hits" ]]; then
      violations=$((violations + 1))
    fi
  fi
  if [[ -d "$SRC_DIR/api" && -d "$SRC_DIR/db" ]]; then
    layer_hits=$(grep -rn 'from.*\.\./db\|require.*\.\./db' \
      "$SRC_DIR/api/" --include='*.ts' --include='*.js' 2>/dev/null | head -10 || true)
    if [[ -n "$layer_hits" ]]; then
      violations=$((violations + 1))
    fi
  fi
  if [[ -d "$SRC_DIR/ui" && -d "$SRC_DIR/api" ]]; then
    layer_hits=$(grep -rn 'from.*\.\./api\|from.*\.\./services' \
      "$SRC_DIR/ui/" --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null | head -10 || true)
    if [[ -n "$layer_hits" ]]; then
      violations=$((violations + 1))
    fi
  fi
fi

god_modules=0
while IFS= read -r -d '' f; do
  imports=$(grep -cE 'import.*from|require\(' "$f" 2>/dev/null || echo "0")
  if [[ "$imports" -ge 20 ]]; then
    god_modules=$((god_modules + 1))
  fi
done < <(find "$SRC_DIR" \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' \) -print0 2>/dev/null)

# Re-derive barrel file count (mirrors step-5)
barrel_count=$(find "$SRC_DIR" -name 'index.ts' -o -name 'index.js' 2>/dev/null | wc -l)

# Re-derive tech currency (mirrors step-3)
node_required="N/A"
if [[ -f "package.json" ]]; then
  node_required=$(jq -r '.engines.node // "not specified"' package.json)
fi

# Re-derive test metrics (mirrors step-4)
prod_files=$(find "$SRC_DIR" \
  -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.go' \
  2>/dev/null | wc -l)
test_files=$(find . -path ./node_modules -prune -o \
  \( -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.go' -o -name 'test_*.py' \) \
  -print 2>/dev/null | wc -l)
ratio="N/A"
if [[ "$prod_files" -gt 0 ]]; then
  ratio=$(calc "scale=2; $test_files / $prod_files")
fi

smell_count=0
while IFS= read -r -d '' f; do
  sleeps=$(grep -cE 'sleep|setTimeout|wait.*[0-9]' "$f" 2>/dev/null || echo "0")
  if [[ "$sleeps" -gt 0 ]]; then
    smell_count=$((smell_count + 1))
  fi
  mocks=$(grep -cE 'mock|stub|fake|spy' "$f" 2>/dev/null || echo "0")
  if [[ "$mocks" -gt 20 ]]; then
    smell_count=$((smell_count + 1))
  fi
done < <(find . -path ./node_modules -prune -o \
  \( -name '*.test.*' -o -name '*.spec.*' \) -print0 2>/dev/null)

# Re-derive error handling metrics (mirrors step-6)
empty_catches=$(grep -rn 'catch\s*(\s*\w*\s*)\s*{\s*}' "$SRC_DIR" \
  --include='*.js' --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
bare_catches=$(grep -rnE 'catch\s*\(.*\)\s*\{\s*//\s*(TODO|FIXME|ignore|silent)' \
  "$SRC_DIR" --include='*.js' --include='*.ts' --include='*.tsx' 2>/dev/null | wc -l)
console_count=$(grep -rn 'console\.log\|console\.error\|console\.warn' "$SRC_DIR" \
  --include='*.js' --include='*.ts' 2>/dev/null | wc -l)

# Get TypeScript version for the Technology Debt table
ts_version=$(npx tsc --version 2>/dev/null || echo 'N/A')

# ---- Profile Report --------------------------------------------------------

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
| TypeScript: $ts_version | — |

### Test Debt
| Finding | Severity |
|---------|----------|
| Test:Production ratio: ${ratio} | — |
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
