#!/usr/bin/env bash
#
# audit-dependency-usage.sh
# Audits package.json dependencies vs import/require usage to find:
#   - Dead installs (declared but never imported)
#   - Out-of-date versions (via npm-check-updates)
# Note: DevDependency/prodDependency classification and optionalDependencies are not currently analyzed.
#
# Usage: ./audit-dependency-usage.sh
# Output: Tab-separated sections: UNUSED | VERSION_ADVICE
#

set -euo pipefail

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== DEPENDENCY USAGE AUDIT ===" >&2
echo "" >&2

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$PROJECT_ROOT"

# Determine package manager
if [ -f "pnpm-lock.yaml" ]; then
  PKG_MANAGER="pnpm"
elif [ -f "yarn.lock" ]; then
  PKG_MANAGER="yarn"
elif [ -f "package-lock.json" ]; then
  PKG_MANAGER="npm"
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
  PKG_MANAGER="pip"
elif [ -f "go.mod" ]; then
  PKG_MANAGER="go"
else
  echo "Cannot detect package manager — exiting" >&2
  exit 0
fi
echo "Detected package manager: $PKG_MANAGER" >&2

# ------ Node.js/npm ------
if [ "$PKG_MANAGER" == "npm" ] || [ "$PKG_MANAGER" == "pnpm" ] || [ "$PKG_MANAGER" == "yarn" ]; then
  PACKAGE_JSON="package.json"
  
  if [ ! -f "$PACKAGE_JSON" ]; then
    echo "No package.json found — skipping" >&2
    exit 0
  fi

  if ! command -v jq &>/dev/null; then
    echo "jq not available — skipping Node dependency audit (install jq to enable)" >&2
    exit 0
  fi
  
  NODE_MODULES="./node_modules"
  [ ! -d "$NODE_MODULES" ] && echo "No node_modules/ — run npm install first" >&2
  
  # Parse declared production dependencies
  DEPENDENCIES=$(jq -r '.dependencies // {} | keys[]' "$PACKAGE_JSON" 2>/dev/null)
  SRC_DIRS=$(find . -type d \( -name "src" -o -name "lib" -o -name "app" -o -name "packages" \) \
    ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/dist/*" 2>/dev/null | head -10)
  
  SRC_INDEX="$TMPDIR/src_imports.txt"
  touch "$SRC_INDEX"
  for DIR in $SRC_DIRS; do
    # Collect import/require usages into a temp file to avoid large in-memory variable
    grep -rh --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
      -E "require\(|import[[:space:]].*from" "$DIR" 2>/dev/null >> "$SRC_INDEX" || true
  done
  
  echo "" >&2
  echo "====== UNUSED DEPENDENCIES ======" >&2
  echo "(Declared but no import found in source)" >&2
  echo "" >&2
  
  for DEPK in $DEPENDENCIES; do
    # Dependency keys from package.json are already package names (no version suffix)
    BASENAME="$DEPK"
    if ! grep -qF "$BASENAME" "$SRC_INDEX" 2>/dev/null; then
      echo -e "DEAD_INSTALL\t$DEPK" >&2
      
      # Check if it's actually used dynamically
      find . -type f \( -name "*.ts" -o -name "*.js" -o -name "*.json" -o -name "*.config.*" \) \
        ! -path "*/node_modules/*" ! -path "*/dist/*" \
        -exec grep -lH "$BASENAME" {} + 2>/dev/null | head -3 || true
    fi
  done
  
  echo "" >&2
  echo "====== VERSION ADVISORY ======" >&2
  echo "(Packages with newer major versions available)" >&2
  
  # Check for majors
  npx --yes npm-check-updates --target latest --format compact 2>/dev/null \
    | grep -E '# major|major' | head -20 || true
  
  # ------ Python/pip ------
elif [ "$PKG_MANAGER" == "pip" ]; then
  REQS_FILE="requirements.txt"
  PYPROJECT_FILE="pyproject.toml"
  
  if [ -f "$REQS_FILE" ]; then
    DEPENDENCIES=$(awk -F'[=<>]' '{print $1}' "$REQS_FILE" | xargs)
  elif [ -f "$PYPROJECT_FILE" ]; then
    DEPENDENCIES=$(
      python3 - <<'PY' 2>/dev/null
import re, sys
try:
    import tomllib  # py>=3.11
except Exception:
    sys.exit(0)

with open("pyproject.toml", "rb") as f:
    data = tomllib.load(f)

deps = []
for spec in (data.get("project", {}) or {}).get("dependencies", []) or []:
    name = re.split(r"[<>=!~ ]", spec.strip(), 1)[0]
    if name:
        deps.append(name)

poetry = (((data.get("tool", {}) or {}).get("poetry", {}) or {}).get("dependencies", {}) or {})
for name in poetry.keys():
    if name.lower() != "python":
        deps.append(name)

print(" ".join(sorted(set(deps))))
PY
    ) || true
  fi
  
  INSTALLED=$(pip list 2>/dev/null | awk 'NR>2 {print $1}' | head -50)
  
  # Check if installed packages are actually imported
  for DEP in $DEPENDENCIES; do
    PEP517_NAME=$(echo "$DEP" | tr '_' '-' | tr 'A-Z' 'a-z')
    if ! python3 -c "import ${PEP517_NAME//-/_}" 2>/dev/null; then
      echo -e "POSSIBLY_UNUSED\t$DEP" >&2
    fi
  done
fi

echo "" >&2
echo "=== AUDIT COMPLETE ===" >&2
echo "Dead installs are a maintenance and security risk — remove or investigate." >&2

exit 0