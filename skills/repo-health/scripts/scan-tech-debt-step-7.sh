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
#   Vendor directories (.venv, venv, node_modules, __pycache__, site-packages,
#   *.dist-info, .git) are always excluded from every count.
#
# Exits 0 always — findings are data, not failures.
# ---------------------------------------------------------------------------

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---- Config ---------------------------------------------------------------
SRC_DIR="${1:-src}"
# shellcheck disable=SC2034 # accepted as positional arg for interface consistency with other step scripts
TEST_OUTPUT="${2:-/tmp/test-output.txt}"

# Trap to ensure exit 0 always
trap 'exit 0' EXIT
trap '' PIPE

# ---- Helpers ---------------------------------------------------------------
VENDOR_EXCLUDE=( .git .venv venv node_modules __pycache__ site-packages '*.dist-info' '*.egg-info' .tox .mypy_cache .pytest_cache .ruff_cache .hypothesis dist build )

# awk-based arithmetic — bc is not always installed
calc() { awk "BEGIN{printf \"%.2f\", ($1)}" 2>/dev/null || echo 0; }

# count_src_markers MARKER [SRC_DIR] — always prints a single integer
count_src_markers() {
  local marker="$1" srcdir="${2:-src}"
  { grep -rni "$marker" "$srcdir" \
      --include='*.js' --include='*.ts' --include='*.tsx' --include='*.jsx' \
      --include='*.py' --include='*.go' --include='*.rs' --include='*.java' \
      --include='*.rb' --include='*.php' --include='*.cs' --include='*.kt' \
      --include='*.swift' --include='*.dart' \
      "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" \
      2>/dev/null || true; } \
    | { grep -v 'node_modules\|\.git\|/test/\|/tests/\|/spec/' || true; } \
    | { grep -vic 'nocheck\|eslint-disable\|pragma' || true; } \
    | awk '{s+=$1} END{print s+0}'
}

# count_code_lines DIR — total lines across counted source files (single integer)
count_code_lines() {
  local srcdir="$1"
  { grep -rc '' "$srcdir" \
      --include='*.js' --include='*.ts' --include='*.tsx' --include='*.jsx' \
      --include='*.py' --include='*.go' \
      "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" \
      2>/dev/null || true; } \
    | awk -F: '{s+=$NF} END{print s+0}'
}

# match_count GREP-ARGS... — number of matched lines, always a single integer
match_count() {
  { grep -rn "$@" 2>/dev/null || true; } | awk 'END{print NR+0}'
}

# count_imports FILE PATTERN — single integer
count_imports() {
  local file="$1" pat="$2"
  { grep -cE -- "$pat" "$file" 2>/dev/null || true; } | awk '{s+=$1} END{print s+0}'
}

# file_grep_count FILE PATTERN — single integer
file_grep_count() {
  local file="$1" pat="$2"
  { grep -cE -- "$pat" "$file" 2>/dev/null || true; } | awk '{s+=$1} END{print s+0}'
}

npx_has() {
  has_cmd npx || return 1
  npx --no-install "$1" --version &>/dev/null
}

# ===========================================================================
# STEP 3.7 — Synthesize Technical Debt Profile
# ===========================================================================

section "STEP 3.7 — Technical Debt Profile"

# Re-count markers for the report table
todo_cnt=$(count_src_markers "TODO" "$SRC_DIR")
fixme_cnt=$(count_src_markers "FIXME" "$SRC_DIR")
hack_cnt=$(count_src_markers "HACK" "$SRC_DIR")
xxx_cnt=$(count_src_markers "XXX" "$SRC_DIR")
workaround_cnt=$(count_src_markers "WORKAROUND" "$SRC_DIR")
temp_cnt=$(count_src_markers "TEMPORARY" "$SRC_DIR")
kludge_cnt=$(count_src_markers "KLUDGE" "$SRC_DIR")
grand_total=$((todo_cnt + fixme_cnt + hack_cnt + xxx_cnt + workaround_cnt + temp_cnt + kludge_cnt))

# Re-derive total_lines for density (mirrors step-1)
total_lines=$(count_code_lines "$SRC_DIR")

density_str="N/A"
if [[ "$total_lines" -gt 0 ]]; then
  density_str=$(calc "$grand_total * 1000 / $total_lines")
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
  case "$f" in
    *.py) import_pat='^[[:space:]]*(import[[:space:]]|from[[:space:]])' ;;
    *)    import_pat='import.*from|require\(' ;;
  esac
  imports=$(count_imports "$f" "$import_pat")
  if [[ "$imports" -ge 20 ]]; then
    god_modules=$((god_modules + 1))
  fi
done < <(find "$SRC_DIR" \
  \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
       -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
       -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
       -o -name dist -o -name build \) -prune \) \
  -o \( -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' \) -print0 \) 2>/dev/null)

# Re-derive barrel file count (mirrors step-5)
if [[ -d "$SRC_DIR" ]]; then
  barrel_count=$(find "$SRC_DIR" \
    \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
         -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
         -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
         -o -name dist -o -name build \) -prune \) \
    -o \( -type f \( -name 'index.ts' -o -name 'index.js' -o -name '__init__.py' \) -print \) 2>/dev/null | awk 'END{print NR+0}')
else
  barrel_count=0
fi

# Re-derive tech currency (mirrors step-3)
node_required="N/A"
if [[ -f "package.json" ]]; then
  node_required=$(jq -r '.engines.node // "not specified"' package.json 2>/dev/null || echo "not specified")
fi
ts_version="N/A"
if npx_has tsc; then
  ts_version=$(timeout 60 npx --no-install tsc --version 2>/dev/null || echo 'N/A')
fi

# Re-derive test metrics (mirrors step-4)
prod_files=0
test_files=0
if [[ -d "$SRC_DIR" ]]; then
  prod_files=$(find "$SRC_DIR" \
    \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
         -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
         -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
         -o -name dist -o -name build \) -prune \) \
    -o \( -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.go' \) -print \) 2>/dev/null | awk 'END{print NR+0}')
fi
test_files=$(find . \
  \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
       -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
       -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
       -o -name dist -o -name build \) -prune \) \
  -o \( -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.go' -o -name 'test_*.py' -o -name '*_test.py' \) -print \) 2>/dev/null | awk 'END{print NR+0}')
ratio="N/A"
if [[ "$prod_files" -gt 0 ]]; then
  ratio=$(calc "$test_files / $prod_files")
fi

smell_count=0
while IFS= read -r -d '' f; do
  sleeps=$(file_grep_count "$f" 'sleep|setTimeout|wait.*[0-9]')
  if [[ "$sleeps" -gt 0 ]]; then
    smell_count=$((smell_count + 1))
  fi
  mocks=$(file_grep_count "$f" 'mock|stub|fake|spy')
  if [[ "$mocks" -gt 20 ]]; then
    smell_count=$((smell_count + 1))
  fi
done < <(find . \
  \( -type d \( -name .git -o -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \
       -o -name site-packages -o -name '*.dist-info' -o -name '*.egg-info' -o -name .tox \
       -o -name .mypy_cache -o -name .pytest_cache -o -name .ruff_cache -o -name .hypothesis \
       -o -name dist -o -name build \) -prune \) \
  -o \( -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name 'test_*.py' -o -name '*_test.py' \) -print0 \) 2>/dev/null)

# Re-derive error handling metrics (mirrors step-6)
empty_catches=0
bare_catches=0
console_count=0
empty_excepts=0
if [[ -d "$SRC_DIR" ]]; then
  empty_catches=$(match_count 'catch\s*(\s*\w*\s*)\s*{\s*}' "$SRC_DIR" \
    --include='*.js' --include='*.ts' --include='*.tsx' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}")
  bare_catches=$(match_count -E 'catch\s*\(.*\)\s*\{\s*//\s*(TODO|FIXME|ignore|silent)' "$SRC_DIR" \
    --include='*.js' --include='*.ts' --include='*.tsx' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}")
  console_count=$(match_count 'console\.log\|console\.error\|console\.warn' "$SRC_DIR" \
    --include='*.js' --include='*.ts' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}")
  empty_excepts=$({ grep -rnE -A1 'except[^:]*:' "$SRC_DIR" \
    --include='*.py' "${VENDOR_EXCLUDE[@]/#/--exclude-dir=}" 2>/dev/null || true; } \
    | { grep -cE -- '-[0-9]+:[[:space:]]*(pass|\.\.\.)[[:space:]]*$' || true; } \
    | awk '{s+=$1} END{print s+0}')
fi

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
| Barrel files (index.ts/js + Python __init__.py): $barrel_count | — |

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
| Empty except blocks (Python, heuristic): $empty_excepts | — |
| Ad-hoc console logs: $console_count | — |

### OVERALL TECHNICAL DEBT RATING
- **LOW**: Minor, schedule when convenient
- **MEDIUM**: Plan to address within next quarter
- **HIGH**: Actively causing friction or risk — prioritize
- **CRITICAL**: Blocking velocity or creating production risk — address now

**Overall rating: PENDING** (review findings above and apply severity guide from SKILL.md)
PROFILE
