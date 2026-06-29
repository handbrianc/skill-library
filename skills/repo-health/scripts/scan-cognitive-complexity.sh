#!/usr/bin/env bash
#
# scan-cognitive-complexity.sh
# Measures both cyclomatic and cognitive complexity.
# Relies on ESLint complexity rule for TS/JS.
#
# Usage: ./scan-cognitive-complexity.sh <target_dir>
# Output: Text report to stderr summarizing:
#   - ESLint complexity-rule violations (cyclomatic complexity)
#   - Heuristic cognitive-complexity red flags (CSV: file,line,pattern,score)
# Note: This script does not currently emit a single unified CSV.
set -euo pipefail

TARGET="${1:-.}"

echo "=== COGNITIVE/CYCLOMATIC COMPLEXITY SCAN ===" >&2
echo "Target: $TARGET" >&2
echo "" >&2

TMPDIR=$(mktemp -d)
OUT="$TMPDIR/complexity_out.csv"

trap "rm -rf $TMPDIR" EXIT

# ------- ESLint-based cyclomatic complexity for TS/JS ----------
if find "$TARGET" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
  ! -path "*/node_modules/*" ! -path "*/dist/*" | grep -q .; then

  echo "Running ESLint complexity analysis..." >&2
  
  # We'll run eslint on each file capturing JSON output
  # Complexity rule will give us cyclomatic complexity
  ESLINT_RULES='"complexity": ["warn", 15]'
  
  npx eslint "$TARGET" \
    --parser @typescript-eslint/parser \
    --plugin @typescript-eslint \
    --rule 'complexity: ["warn", 15]' \
    --format json 2>/dev/null | \
    jq -r '.[]
      | select(.messages != null)
      | .messages[]
      | select(.ruleId and (.ruleId | contains("complexity")))
      | [.filePath, (.line|tostring), (.column|tostring), (.message|gsub("[\t\r\n]+";" ")), .ruleId]
      | @tsv' 2>/dev/null | \
    while IFS=$'\t' read -r filepath line col msg rule; do
      # Cyclomatic complexity threshold here is 15
      echo "$filepath",line=$line,"$msg" >> "$OUT"
    done
  
  if [ -s "$OUT" ]; then
    echo "Cyclomatic Complexity Violations:" >&2
    sort -t, -k2 -n "$OUT" | uniq >&2
    echo "" >&2
  fi
fi

# ------- Cognitive complexity — manual heuristics --------------
# Since there's no standard free cognitive complexity tool,
# we use AST-aware grep to find red-flag patterns:
COGNITIVE_FLAGS="$TMPDIR/cognitive_flags.csv"
echo '"file","line","pattern","score"' > "$COGNITIVE_FLAGS"

find "$TARGET" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" \) \
  ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/build/*" \
  > "$TMPDIR/src_files.txt"

# Red-flag patterns and their cognitive complexity increments:
# Recursion: +3
grep -rnP --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  '\bfunction\s+(\w+)\([^)]*\)\s*\{[^}]*\b\1\s*\(' \
  "$TARGET" 2>/dev/null | head -20 | while IFS=: read -r f l _; do
  echo "\"$f\",\"$l\",\"RECURSIVE_CALL\",3" >> "$COGNITIVE_FLAGS"
done || true

# Ternary nesting (chained ternaries): +2
grep -rn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  -E "\?\s*\w.*\?\s*\w.*\?\s*\w" \
  "$TARGET" 2>/dev/null | head -20 | while IFS=: read -r f l _; do
  echo "\"$f\",\"$l\",\"CHAINED_TERNARY\",2" >> "$COGNITIVE_FLAGS"
done || true

# Arrow function returning arrow function: +2
grep -rn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  -E "=>\s*\(.*\)\s*=>\s*\(|=>\s*\([^)]*\)\s*=>\s*\{[^}]*=>" \
  "$TARGET" 2>/dev/null | head -20 | while IFS=: read -r f l _; do
  echo "\"$f\",\"$l\",\"NESTED_ARROW\",2" >> "$COGNITIVE_FLAGS"
done || true

# Early returns in loops (confusing flow): +1
grep -rn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  -E "for\s*\([^)]+\)[^;]*\{[^}]*return[^}]*\}[^}]*\}\s*;" \
  "$TARGET" 2>/dev/null | head -20 | while IFS=: read -r f l _; do
  echo "\"$f\",\"$l\",\"EARLY_RETURN_LOOP\",1" >> "$COGNITIVE_FLAGS"
done || true

if [ -s "$COGNITIVE_FLAGS" ] && [ "$(wc -l < "$COGNITIVE_FLAGS")" -gt 1 ]; then
  echo "Cognitive Complexity Red Flags (score contribution):" >&2
  tail -n +2 "$COGNITIVE_FLAGS" | sort -t, -k4 -rn | uniq >&2
  echo "" >&2
fi

# ------- Aggregated Summary -------
echo "=== COMPLEXITY SUMMARY ===" >&2
HIGH_COMPLEXITY=$(grep -Ec 'complexity.*(15|20|25|30|999)' "$OUT" 2>/dev/null || echo "0")
echo "Functions exceeding cyclomatic complexity threshold (15): $HIGH_COMPLEXITY" >&2

TOTAL_COGNITIVE=$( awk -F',' 'NR>1 {sum+=$4} END {print sum}' "$COGNITIVE_FLAGS" 2>/dev/null || echo "0")
echo "Total cognitive complexity penalty points found: $TOTAL_COGNITIVE" >&2

echo "" >&2
echo "Flag thresholds:" >&2
echo "  Cyclomatic > 15: MEDIUM risk" >&2
echo "  Cyclomatic > 25: HIGH risk" >&2
echo "  Cyclomatic > 40: CRITICAL" >&2
echo "  Cognitive flags accumulated: review for refactor" >&2

exit 0