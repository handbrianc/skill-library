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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run npm-check-updates to show available major version bumps.
version_advisory() {
  echo "" >&2
  echo "====== VERSION ADVISORY ======" >&2
  echo "(Packages with newer major versions available)" >&2

  if command -v npx &>/dev/null; then
    npx --yes npm-check-updates --target latest --format compact 2>/dev/null \
      | grep -E '# major|major' | head -20 || true
  else
    echo "npx not available — skipping version advisory" >&2
  fi
}

# ---------------------------------------------------------------------------
# Package-manager handlers
# ---------------------------------------------------------------------------

handle_npm() {
  local package_json="package.json"

  if [ ! -f "$package_json" ]; then
    echo "No package.json found — skipping" >&2
    return
  fi

  if ! command -v jq &>/dev/null; then
    echo "jq not available — skipping Node dependency audit (install jq to enable)" >&2
    return
  fi

  local node_modules="./node_modules"
  [ ! -d "$node_modules" ] && echo "No node_modules/ — run npm install first" >&2

  # Parse declared production dependencies
  local dependencies
  dependencies=$(jq -r '.dependencies // {} | keys[]' "$package_json" 2>/dev/null)

  local src_dirs
  src_dirs=$(find . -type d \( -name "src" -o -name "lib" -o -name "app" -o -name "packages" \) \
    ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/dist/*" 2>/dev/null | head -10)

  if [ -z "$src_dirs" ]; then
    echo "No source directories (src/lib/app/packages) found — skipping unused dependency scan" >&2
    return
  fi

  local src_index="$TMPDIR/src_imports.txt"
  touch "$src_index"
  local dir
  for dir in $src_dirs; do
    # Collect import/require usages into a temp file to avoid large in-memory variable
    grep -rh --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
      -E "require\(|import[[:space:]].*from" "$dir" 2>/dev/null >> "$src_index" || true
  done

  echo "" >&2
  echo "====== UNUSED DEPENDENCIES ======" >&2
  echo "(Declared but no import found in source)" >&2
  echo "" >&2

  local depk basename
  for depk in $dependencies; do
    # Dependency keys from package.json are already package names (no version suffix)
    basename="$depk"
    if ! grep -qE "['\"]${basename}(['\"/]|$)" "$src_index" 2>/dev/null; then
      echo -e "DEAD_INSTALL\t$depk" >&2
      # Check if it's actually used dynamically
      find . -type f \( -name "*.ts" -o -name "*.js" -o -name "*.json" -o -name "*.config.*" \) \
        ! -path "*/node_modules/*" ! -path "*/dist/*" \
        -exec grep -lH "$basename" {} + 2>/dev/null | head -3 || true
    fi
  done

  version_advisory
}

handle_pip() {
  local reqs_file="requirements.txt"
  local pyproject_file="pyproject.toml"
  local dependencies=""

  if [ -f "$reqs_file" ]; then
    dependencies=$(awk -F'[=<>]' '{print $1}' "$reqs_file" | xargs)
  elif [ -f "$pyproject_file" ]; then
    dependencies=$(
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

  local installed
  # shellcheck disable=SC2034 # reserved for future unused-package analysis
  installed=$(pip list 2>/dev/null | awk 'NR>2 {print $1}' | head -50)

  # Check if installed packages are actually imported
  local dep base_dep module
  for dep in $dependencies; do
    base_dep="${dep%%[*}"
    base_dep="${base_dep%%;*}"
    module="${base_dep//-/_}"
    if [[ "$module" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && ! python3 -c "import $module" 2>/dev/null; then
      echo -e "POSSIBLY_UNUSED\t$dep" >&2
    fi
  done
}

handle_go() {
  # Go module audit — no-op for now; go.mod detected but no analysis implemented
  :
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=== DEPENDENCY USAGE AUDIT ===" >&2
echo "" >&2

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$PROJECT_ROOT"

# Determine package manager
PKG_MANAGER=""
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

case "$PKG_MANAGER" in
  npm|pnpm|yarn) handle_npm ;;
  pip)          handle_pip ;;
  go)           handle_go ;;
esac

echo "" >&2
echo "=== AUDIT COMPLETE ===" >&2
echo "Dead installs are a maintenance and security risk — remove or investigate." >&2

exit 0
