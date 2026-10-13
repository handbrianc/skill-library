#!/usr/bin/env bash
#
# audit-dependency-usage.sh
# Audits declared dependencies vs import/require usage to find:
#   - Dead installs (declared but never imported)
#   - Imported-but-undeclared packages (stdlib + first-party excluded)
#
# Usage: ./audit-dependency-usage.sh [target-dir]
#   target-dir: project directory to audit (default: git toplevel of the
#   current directory, or the current directory when not in a git repo).
#
# Output: Tab-separated sections: DECLARED_NOT_IMPORTED | IMPORTED_NOT_DECLARED
#         (plus PLATFORM_CONDITIONAL for marker-gated deps)
# Python analysis is a heuristic: import names are matched to declared
# packages via PEP-503 normalization plus a small alias table — verify
# findings manually before removing dependencies.
#
# Note: DevDependency classification and optionalDependencies are not currently analyzed for Node projects.

set -euo pipefail

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"; exit 0' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run npm-check-updates to show available major version bumps.
# Never triggers a network install: gated on a local (npx --no-install)
# npm-check-updates and bounded with timeout, per the message below.
version_advisory() {
  echo "" >&2
  echo "====== VERSION ADVISORY ======" >&2
  echo "(Packages with newer major versions available)" >&2

  if ! command -v npx &>/dev/null; then
    echo "npx not available — skipping version advisory" >&2
    return 0
  fi
  if ! timeout 30 npx --no-install npm-check-updates --version &>/dev/null; then
    echo "npm-check-updates not installed locally (npx --no-install) — version advisory N/A" >&2
    return 0
  fi
  echo "(bounded to 120s; npx --no-install, no network installs)" >&2
  timeout 120 npx --no-install npm-check-updates --target latest --format compact 2>/dev/null \
    | grep -E '# major|major' | head -20 || true
}

# ---------------------------------------------------------------------------
# Python dependency cross-check (declared vs imported)
# ---------------------------------------------------------------------------

# grep-based fallback used only when python3 is unavailable.
python_fallback_grep() {
  local target="$1"
  echo "python3 unavailable — falling back to a crude grep-based check (low confidence)" >&2
  local declared_file="$TMPDIR/declared.txt"
  : > "$declared_file"
  if [[ -f "$target/requirements.txt" ]]; then
    grep -hE '^[A-Za-z0-9]' "$target/requirements.txt" 2>/dev/null \
      | sed -E 's/[<>=!~;[].*//; s/[-_.]+/-/g; s/.*/\L&/' >> "$declared_file" || true
  fi
  local src_dir="$target/src"
  [[ -d "$src_dir" ]] || src_dir="$target"
  local imports
  imports=$({ grep -rhoE '^[[:space:]]*(import|from)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
    "$src_dir" --include='*.py' \
    --exclude-dir=.venv --exclude-dir=venv --exclude-dir=node_modules \
    --exclude-dir=__pycache__ --exclude-dir=site-packages --exclude-dir='*.dist-info' \
    --exclude-dir=.git 2>/dev/null || true; } \
    | awk '{print $2}' | sort -u)
  local d i
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    i=$(echo "$d" | tr '-' '_')
    if ! echo "$imports" | grep -qx "$i"; then
      echo -e "DECLARED_NOT_IMPORTED\t$d" >&2
    fi
  done < "$declared_file"
}

python_crosscheck() {
  local target="$1"

  if ! command -v python3 &>/dev/null; then
    python_fallback_grep "$target"
    return 0
  fi

  # The heavy lifting runs in one python3 pass (stdlib-only: tomllib + ast).
  # Prints TSV sections to stderr; a non-zero exit falls back to grep.
  local py_rc=0
  python3 - "$target" <<'PY' >&2 || py_rc=$?
import ast, os, re, sys

target = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()

def canon(name):
    return re.sub(r"[-_.]+", "-", name).lower()

declared = {}            # canonical name -> source file
conditional = {}         # canonical name -> environment marker
optional_groups = []

pyproject = os.path.join(target, "pyproject.toml")
data = None
try:
    import tomllib
    with open(pyproject, "rb") as f:
        data = tomllib.load(f)
except FileNotFoundError:
    data = None
except Exception:
    data = None

if data is not None:
    proj = data.get("project", {}) or {}
    for spec in (proj.get("dependencies") or []):
        spec = spec.strip()
        name = re.split(r"[<>=!~;\[\s]", spec, maxsplit=1)[0]
        if not name:
            continue
        marker = ""
        if ";" in spec:
            marker = spec.split(";", 1)[1].strip()
        if marker and ("sys_platform" in marker or "platform_python" in marker or "python_version" in marker):
            conditional[canon(name)] = marker
        else:
            declared[canon(name)] = "pyproject.toml"
    optional_groups = sorted((proj.get("optional-dependencies") or {}).keys())

    poetry_deps = (((data.get("tool", {}) or {}).get("poetry", {}) or {}).get("dependencies", {}) or {})
    for name in poetry_deps:
        if name.lower() in ("python",):
            continue
        declared.setdefault(canon(name), "pyproject.toml (poetry)")
else:
    # tomllib unavailable or unreadable: regex fallback for a flat dependencies array
    try:
        text = open(pyproject, encoding="utf-8", errors="ignore").read()
        m = re.search(r"^dependencies\s*=\s*\[(.*?)^\]", text, re.S | re.M)
        if m:
            for spec in re.findall(r'"([^"]+)"', m.group(1)):
                name = re.split(r"[<>=!~;\[\s]", spec.strip(), 1)[0]
                if name:
                    marker = spec.split(";", 1)[1].strip() if ";" in spec else ""
                    if marker and ("sys_platform" in marker or "platform_python" in marker or "python_version" in marker):
                        conditional[canon(name)] = marker
                    else:
                        declared[canon(name)] = "pyproject.toml (regex)"
    except OSError:
        pass

req = os.path.join(target, "requirements.txt")
if os.path.isfile(req):
    try:
        for line in open(req, encoding="utf-8", errors="ignore"):
            line = line.strip()
            if not line or line.startswith(("#", "-")):
                continue
            name = re.split(r"[<>=!~;\[\s]", line, maxsplit=1)[0]
            if name:
                declared.setdefault(canon(name), "requirements.txt")
    except OSError:
        pass

# Import roots: src/ layout preferred, else the whole target (vendor dirs pruned)
src = os.path.join(target, "src")
roots = [src] if os.path.isdir(src) else [target]

VENDOR = {".git", ".venv", "venv", "node_modules", "__pycache__", "site-packages",
          ".tox", ".mypy_cache", ".pytest_cache", ".ruff_cache", ".hypothesis", "dist", "build"}

def is_vendor(d):
    return d in VENDOR or d.endswith(".dist-info") or d.endswith(".egg-info")

# First-party top-level import names: packages living in the import roots,
# plus the project's own declared name.
first_party = set()
for root in roots:
    try:
        for entry in os.listdir(root):
            p = os.path.join(root, entry)
            if os.path.isdir(p) and os.path.exists(os.path.join(p, "__init__.py")):
                first_party.add(entry.replace("-", "_"))
    except OSError:
        pass
try:
    import tomllib as _t
    with open(pyproject, "rb") as f:
        pname = (_t.load(f).get("project", {}) or {}).get("name")
    if pname:
        first_party.add(canon(pname).replace("-", "_"))
except Exception:
    pass

stdlib = set()
try:
    stdlib = set(sys.stdlib_module_names)
except AttributeError:
    stdlib = set()

ALIAS = {
    "python-docx": {"docx"},
    "python-pptx": {"pptx"},
    "python-oxmsg": {"oxmsg"},
    "python-dotenv": {"dotenv"},
    "python-dateutil": {"dateutil"},
    "python-snappy": {"snappy"},
    "pillow": {"PIL"},
    "pyyaml": {"yaml"},
    "beautifulsoup4": {"bs4"},
    "opencv-python": {"cv2"},
    "scikit-learn": {"sklearn"},
    "scikit-image": {"skimage"},
    "pyobjc-core": {"objc"},
    "pyobjc-framework-cocoa": {"Cocoa"},
    "pyobjc-framework-quartz": {"Quartz"},
    "pyobjc-framework-coreml": {"CoreML"},
    "pyobjc-framework-vision": {"Vision"},
}

import_names = {}
for d in declared:
    names = {d.replace("-", "_")}
    if d in ALIAS:
        names |= ALIAS[d]
    import_names[d] = names

imported = set()
files_scanned = 0
for root in roots:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not is_vendor(d)]
        for fn in filenames:
            if not fn.endswith(".py"):
                continue
            path = os.path.join(dirpath, fn)
            try:
                tree = ast.parse(open(path, encoding="utf-8", errors="ignore").read())
            except Exception:
                continue
            files_scanned += 1
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    for a in node.names:
                        imported.add(a.name.split(".")[0])
                elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                    imported.add(node.module.split(".")[0])

own = set(first_party)
if stdlib:
    imported -= stdlib
imported -= own

# Declared-but-unimported and imported-but-undeclared, with family-prefix
# matching: an import root `opentelemetry` counts as usage of any declared
# `opentelemetry-*` distribution (the AST only records the top-level root of
# dotted imports), and vice versa — without this, namespace-package families
# show up as false positives on both sides of the report.
def imp_canonical(imp):
    return imp.replace("_", "-")

def declared_used(d):
    names = import_names[d]  # underscored canonical + alias import names
    if any(n in imported for n in names):
        return True
    return any(d.startswith(imp_canonical(i) + "-") for i in imported)

def root_is_declared(i):
    # Exact match first: raw import root (underscored) vs alias names, then
    # the hyphenated canonical form, then the family-prefix rule.
    if any(i in names for names in import_names.values()):
        return True
    ic = imp_canonical(i)
    if ic in import_names:
        return True
    return any(d.startswith(ic + "-") for d in import_names)

unused = [d for d in import_names if d not in conditional and not declared_used(d)]

undeclared = sorted(i for i in imported if not root_is_declared(i))

out = sys.stderr
print("", file=out)
print("====== PYTHON DEPENDENCY CROSS-CHECK (heuristic) ======", file=out)
print("(declared deps vs actual imports; PEP-503 name normalization + common alias", file=out)
print(" table; verify manually before removing — e.g. entry points/plugins load lazily)", file=out)
print("(requirements.txt counts as declared; if it is a resolved lockfile, its entries", file=out)
print(" may be transitive — the source column shows where each declared dep came from)", file=out)
print("", file=out)
print("Scope: declared runtime deps vs imports under %s (%d .py files parsed)" % (
    roots[0], files_scanned), file=out)
if optional_groups:
    print("Note: dependency-groups/optional-dependencies NOT cross-checked (dev-only): %s" %
          ", ".join(optional_groups), file=out)
print("", file=out)
print("====== DECLARED-BUT-UNIMPORTED ======", file=out)
print("(Declared but no import found in source — candidate dead installs)", file=out)
for d in sorted(unused):
    print("DECLARED_NOT_IMPORTED\t%s\t%s" % (d, declared.get(d, "?")), file=out)
print("", file=out)
print("====== IMPORTED-BUT-NOT-DECLARED ======", file=out)
print("(Imported in source but absent from declared runtime deps; stdlib and", file=out)
print(" first-party packages excluded)", file=out)
for m in undeclared:
    print("IMPORTED_NOT_DECLARED\t%s" % m, file=out)
if conditional:
    print("", file=out)
    print("====== PLATFORM-CONDITIONAL DEPS (not counted as dead) ======", file=out)
    for d, mk in sorted(conditional.items()):
        print("PLATFORM_CONDITIONAL\t%s\tmarker: %s" % (d, mk), file=out)
print("", file=out)
n_pyproject = sum(1 for v in declared.values() if "pyproject" in v)
n_requirements = sum(1 for v in declared.values() if "requirements" in v)
print("Cross-check complete: %d declared (%d from pyproject, %d from requirements.txt) + %d platform-conditional, %d unimported, %d undeclared" % (
    len(declared), n_pyproject, n_requirements,
    len(conditional), len(unused), len(undeclared)), file=out)
PY
  if [[ "$py_rc" -ne 0 ]]; then
    echo "Python cross-check script failed — trying grep fallback" >&2
    python_fallback_grep "$target"
  fi
}

# ---------------------------------------------------------------------------
# Package-manager handlers
# ---------------------------------------------------------------------------

handle_npm() {
  local package_json="package.json"

  if [ ! -f "$package_json" ]; then
    echo "No package.json found — skipping" >&2
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    echo "jq not available — skipping Node dependency audit (install jq to enable)" >&2
    return 0
  fi

  local node_modules="./node_modules"
  [ ! -d "$node_modules" ] && echo "No node_modules/ — run npm install first" >&2

  # Parse declared production dependencies
  local dependencies
  dependencies=$(jq -r '.dependencies // {} | keys[]' "$package_json" 2>/dev/null)

  local src_dirs
  src_dirs=$(find . -type d \( -name "src" -o -name "lib" -o -name "app" -o -name "packages" \) \
    ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/dist/*" ! -path "*/.venv/*" 2>/dev/null | head -10)

  if [ -z "$src_dirs" ]; then
    echo "No source directories (src/lib/app/packages) found — skipping unused dependency scan" >&2
    return 0
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
      # Check if it's actually used dynamically (config files etc.). The
      # declaration itself (package.json / package-lock.json) is excluded so
      # it can't masquerade as usage evidence.
      find . -type f \( -name "*.ts" -o -name "*.js" -o -name "*.json" -o -name "*.config.*" \) \
        ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/.venv/*" \
        ! -name 'package.json' ! -name 'package-lock.json' \
        -exec grep -lH "$basename" {} + 2>/dev/null | head -3 || true
    fi
  done

  version_advisory
}

handle_pip() {
  python_crosscheck "$1"
}

handle_go() {
  # Go module audit — no-op for now; go.mod detected but no analysis implemented
  echo "Go module audit not implemented — N/A" >&2
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=== DEPENDENCY USAGE AUDIT ===" >&2
echo ""

# Resolve the audit target: optional $1, else git toplevel / CWD (legacy behavior)
TARGET_DIR="${1:-}"
if [[ -n "$TARGET_DIR" ]]; then
  if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Target directory not found: $TARGET_DIR — dependency usage audit N/A" >&2
    exit 0
  fi
  PROJECT_ROOT="$(cd "$TARGET_DIR" && pwd)"
else
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
cd "$PROJECT_ROOT"

# Determine package manager
PKG_MANAGER=""
if [ -f "pnpm-lock.yaml" ]; then
  PKG_MANAGER="pnpm"
elif [ -f "yarn.lock" ]; then
  PKG_MANAGER="yarn"
elif [ -f "package-lock.json" ]; then
  PKG_MANAGER="npm"
elif [ -f "package.json" ]; then
  PKG_MANAGER="npm"
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
  PKG_MANAGER="pip"
elif [ -f "go.mod" ]; then
  PKG_MANAGER="go"
else
  echo "Cannot detect package manager — exiting" >&2
  exit 0
fi
echo "Detected package manager: $PKG_MANAGER (target: $PROJECT_ROOT)" >&2

case "$PKG_MANAGER" in
  npm|pnpm|yarn) handle_npm ;;
  pip)           handle_pip "$PROJECT_ROOT" ;;
  go)            handle_go ;;
esac

echo "" >&2
echo "=== AUDIT COMPLETE ===" >&2
echo "Dead installs are a maintenance and security risk — remove or investigate." >&2

exit 0
