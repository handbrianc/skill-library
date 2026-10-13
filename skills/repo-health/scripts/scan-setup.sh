#!/usr/bin/env bash
# scan-setup.sh — PHASE 1 (Setup & Discovery) and PHASE 5 (OpenSpec Specifications)
#
# Usage:
#   ./scan-setup.sh                  # Run both discovery and specs
#   ./scan-setup.sh --mode=discovery # Tech stack, package manager, entry points, docs
#   ./scan-setup.sh --mode=specs     # Spec discovery, archive scan, alignment stub
#
# Target directory: $REPO_HEALTH_TARGET_DIR env override, else the current
# working directory (run-scan-suite.sh runs this from the project root).
#
# Multi-stack aware: Node, Python, Go, Rust, JVM. Every probe of an optional
# manifest is guarded ([[ -f ]] / lsx / || true) so a missing file can never
# abort the scan under `set -euo pipefail`.
#
# Exits 0 for a successful scan; exit 1 only if the target directory is not
# a directory.

set -euo pipefail

MODE="${1:-}"
DISCOVERY=false
SPECS=false

case "$MODE" in
  --mode=discovery) DISCOVERY=true ;;
  --mode=specs)     SPECS=true     ;;
  "")               DISCOVERY=true; SPECS=true ;;
  *)
    echo "Unknown mode: $MODE"
    echo "Usage: $0 [--mode=discovery|--mode=specs]"
    exit 0
    ;;
esac

TARGET_DIR="${REPO_HEALTH_TARGET_DIR:-$PWD}"
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "SCAN_SETUP_ERROR: target directory not found: $TARGET_DIR" >&2
  exit 1
fi
cd "$TARGET_DIR"
shopt -s nullglob

# List only the operands that actually exist. A bare `ls` with one missing
# operand exits 2, which kills the whole scan under set -e AND (with an
# `|| echo "nothing found"` fallback) contradicts its own output when other
# operands do exist.
lsx() {
  local -a hits=()
  local p
  for p in "$@"; do
    if [[ -e "$p" ]]; then hits+=("$p"); fi
  done
  if (( ${#hits[@]} > 0 )); then
    ls -d -- "${hits[@]}"
  fi
  return 0
}

# find ... | head can die by SIGPIPE (exit 141) under pipefail; safe_head
# swallows that without hiding real find errors.
safe_head() { head -"$1" 2>/dev/null || true; }

HAS_NODE=false
HAS_PYTHON=false
HAS_GO=false
HAS_RUST=false
HAS_JVM=false

if [[ -f package.json ]]; then HAS_NODE=true; fi
if [[ -f pyproject.toml || -f setup.py || -f setup.cfg ]]; then HAS_PYTHON=true; fi
if compgen -G 'requirements*.txt' >/dev/null 2>&1; then HAS_PYTHON=true; fi
if [[ -f go.mod ]]; then HAS_GO=true; fi
if [[ -f Cargo.toml ]]; then HAS_RUST=true; fi
if [[ -f pom.xml || -f build.gradle || -f build.gradle.kts || -f settings.gradle || -f settings.gradle.kts ]]; then HAS_JVM=true; fi

# ────────────────────────────────────────────────────────────
# PHASE 1 — Setup & Discovery
# ────────────────────────────────────────────────────────────
if "$DISCOVERY"; then
  echo "=== PHASE 1: SETUP & DISCOVERY ==="

  # -- Tech stack identification
  echo ""
  echo "--- Tech Stack ---"

  if $HAS_NODE; then
    echo "STACK_DETECTED: node (package.json)"
    jq '{name, version, private, engines, scripts}' package.json 2>/dev/null || echo "{}"
  else
    echo "STACK_NA: node (no package.json)"
  fi

  if $HAS_PYTHON; then
    if [[ -f pyproject.toml ]]; then
      echo "STACK_DETECTED: python (pyproject.toml)"
      grep -E '^(name|version|description|requires-python) *=' pyproject.toml 2>/dev/null | head -6 || true
      for tool in ruff mypy bandit coverage pytest black isort pylint flake8; do
        if grep -qE "^\\[tool\\.$tool" pyproject.toml 2>/dev/null; then
          echo "TOOL_CONFIGURED: $tool ([tool.$tool] in pyproject.toml)"
        fi
      done
      awk '/^\[project\.scripts\]/{f=1; next} /^\[/{f=0} f && NF {print "ENTRY_POINT: " $0}' pyproject.toml 2>/dev/null || true
    else
      echo "STACK_DETECTED: python (setup.py/setup.cfg)"
    fi
  else
    echo "STACK_NA: python (no pyproject.toml/setup.py/setup.cfg/requirements*.txt)"
  fi

  if $HAS_GO; then
    echo "STACK_DETECTED: go (go.mod)"
    grep -m1 '^module ' go.mod 2>/dev/null || true
    grep -m1 '^go ' go.mod 2>/dev/null || true
  else
    echo "STACK_NA: go (no go.mod)"
  fi

  if $HAS_RUST; then
    echo "STACK_DETECTED: rust (Cargo.toml)"
    grep -E '^(name|version) *=' Cargo.toml 2>/dev/null | head -2 || true
  else
    echo "STACK_NA: rust (no Cargo.toml)"
  fi

  if $HAS_JVM; then
    echo "STACK_DETECTED: jvm (pom.xml/build.gradle)"
  else
    echo "STACK_NA: jvm (no pom.xml/build.gradle)"
  fi

  # -- Config & lock artifacts (only the ones that exist; never a failing ls)
  echo ""
  echo "--- Config & Lock Artifacts ---"
  lsx package.json tsconfig.json tsconfig.*.json jsconfig.json \
      pyproject.toml setup.cfg setup.py requirements*.txt \
      go.mod go.sum Cargo.toml Cargo.lock \
      pom.xml build.gradle build.gradle.kts settings.gradle settings.gradle.kts \
      uv.lock poetry.lock Pipfile Pipfile.lock \
      package-lock.json pnpm-lock.yaml yarn.lock \
      Makefile Justfile Taskfile.yml CMakeLists.txt .tool-versions
  if ! $HAS_NODE && ! $HAS_PYTHON && ! $HAS_GO && ! $HAS_RUST && ! $HAS_JVM; then
    echo "NO_MANIFESTS: no recognized project manifests found at repo root"
  fi

  # -- Git history sample
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git log --oneline -5 2>/dev/null || true
  else
    echo "GIT: not a git repository"
  fi

  # -- Package manager artifacts
  echo ""
  echo "--- Package Manager Artifacts ---"
  if $HAS_NODE; then
    if [[ -d node_modules ]]; then
      npm ls --depth=0 2>/dev/null | safe_head 40 || true
      pnpm list --depth=0 2>/dev/null | safe_head 40 || true
      yarn list --depth=0 2>/dev/null | safe_head 40 || true
    else
      echo "  (node_modules not installed — skipping npm/pnpm/yarn ls)"
    fi
  else
    echo "  N/A: node (no package.json)"
  fi

  if $HAS_PYTHON; then
    VENV_PY=""
    for venv_dir in .venv venv; do
      if [[ -x "$venv_dir/bin/python" ]]; then VENV_PY="$venv_dir/bin/python"; break; fi
    done
    if [[ -n "$VENV_PY" ]]; then
      echo "VENV: $VENV_PY"
      "$VENV_PY" -m pip list 2>/dev/null | safe_head 30 || true
    else
      echo "  (no project virtualenv found — global pip list follows)"
      pip list 2>/dev/null | safe_head 30 || true
    fi
    if [[ -f uv.lock ]]; then echo "LOCK: uv.lock (uv)"; fi
    if [[ -f poetry.lock ]]; then echo "LOCK: poetry.lock (poetry)"; fi
    if [[ -f Pipfile.lock ]]; then echo "LOCK: Pipfile.lock (pipenv)"; fi
    if compgen -G 'requirements*.txt' >/dev/null 2>&1; then
      echo "LOCK: pinned via requirements*.txt"
    fi
  else
    echo "  N/A: python (no Python project manifests)"
  fi

  if $HAS_GO && [[ -f go.sum ]]; then echo "LOCK: go.sum"; fi
  if $HAS_RUST && [[ -f Cargo.lock ]]; then echo "LOCK: Cargo.lock"; fi

  # -- Entry points
  echo ""
  echo "--- Entry Points ---"
  for d in src lib app cmd main; do
    if [[ -d "$d" ]]; then
      echo "SOURCE_DIR: $d/"
      ls "$d" 2>/dev/null | safe_head 20 || true
    fi
  done
  for f in main.py main.go main.rb main.rs index.js index.ts; do
    if [[ -f "$f" ]]; then echo "ENTRY_FILE: $f"; fi
  done
  if $HAS_NODE; then
    jq -r '"ENTRY_FIELD: main=" + (.main // "-"), "ENTRY_FIELD: bin=" + ((.bin // "-") | tostring)' package.json 2>/dev/null || true
  fi
  if $HAS_PYTHON && [[ -f pyproject.toml ]]; then
    if grep -qE '^\[project\.scripts\]' pyproject.toml 2>/dev/null; then
      echo "ENTRY_TABLE: [project.scripts] (see ENTRY_POINT lines above)"
    fi
  fi
  find . -maxdepth 4 \( -name "__main__.py" -o -name "main.py" -o -name "main.go" \) \
    -not -path "*/.git/*" -not -path "*/node_modules/*" -not -path "*/.venv/*" \
    -not -path "*/venv/*" -not -path "*/__pycache__/*" -not -path "*/site-packages/*" \
    -not -path "*/.tox/*" -not -path "*/.mypy_cache/*" -not -path "*/.ruff_cache/*" \
    -not -path "*/dist/*" -not -path "*/build/*" -not -path "*/target/*" \
    -type f -print 2>/dev/null | safe_head 20 || true

  # -- Documentation locations
  echo ""
  echo "--- Documentation Locations ---"
  lsx ./*.md ./*.rst ./*.txt LICENSE* LICENCE* COPYING* NOTICE* README* CHANGELOG* CONTRIBUTING* INSTALL* AUTHORS* SECURITY* CODE_OF_CONDUCT*
  for d in docs doc wiki .github; do
    if [[ -d "$d" ]]; then echo "DOC_DIR: $d/"; fi
  done

  # -- Specification locations
  echo ""
  echo "--- Specification Locations ---"
  lsx ./SPEC.md ./OPENSPEC* ./openspec*
  for d in specs openspec .spec spec arch; do
    if [[ -d "$d" ]]; then echo "SPEC_DIR: $d/"; fi
  done
  if [[ ! -d specs && ! -d openspec && ! -d .spec && ! -d spec && ! -d arch && ! -f SPEC.md ]]; then
    echo "NO_SPECS: no specs/ or openspec/ style spec directories found"
  fi

  echo ""
fi

# ────────────────────────────────────────────────────────────
# PHASE 5 — OpenSpec Specifications
# ────────────────────────────────────────────────────────────
if "$SPECS"; then
  echo "=== PHASE 5: OPENSPEC SPECIFICATIONS ==="

  # -- Step 5.1: Locate specs
  echo ""
  echo "--- Step 5.1: Locate Specs ---"
  for d in specs openspec .spec spec arch; do
    if [[ -d "$d" ]]; then
      echo "SPEC_DIR: $d/"
      ls -la "$d" 2>/dev/null | safe_head 30 || true
    fi
  done
  lsx ./SPEC.md ./OPENSPEC* ./openspec*
  find . -maxdepth 4 \( -name "*spec*" -o -name "*SPEC*" -o -name "*requirement*" \) \
    -not -path "./node_modules/*" -not -path "./.git/*" -not -path "./.venv/*" \
    -not -path "./venv/*" -not -path "./__pycache__/*" -not -path "./site-packages/*" \
    -not -path "./.tox/*" -not -path "./dist/*" -not -path "./build/*" -not -path "./target/*" \
    -type f -print 2>/dev/null | safe_head 40 || true

  # -- Step 5.2: Archive scan
  echo ""
  echo "--- Step 5.2: Archive Scan ---"
  for d in specs/archive openspec/changes/archive openspec/archive specs/old specs/v0.*; do
    if [[ -d "$d" ]]; then
      echo "ARCHIVE_DIR: $d/"
      ls -lt "$d" 2>/dev/null | safe_head 20 || true
    fi
  done

  # -- Step 5.3: Alignment stub
  echo ""
  echo "--- Step 5.3: Alignment Check (STUB) ---"
  echo "Spec alignment not yet automated."
  echo "Manual steps:"
  echo "  1. Read each spec's requirements (Given/When/Then or plain requirements)"
  echo "  2. Cross-reference with code — does implementation exist?"
  echo "  3. Flag: spec requires X but code has no evidence of X implementation"

  echo ""
fi

exit 0
