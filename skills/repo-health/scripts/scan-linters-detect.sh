#!/usr/bin/env bash
#
# scan-linters-detect.sh
# Detect available linters for the project's language(s) and output availability.
# Designed to be called directly or from scan-linters.sh
#
# Usage: ./scan-linters-detect.sh [target-dir]
#   target-dir: source directory to scan (default: $REPO_HEALTH_TARGET_DIR, then
#   auto-detect src/ lib/ app/ or .)
#
# Tools that are absent for the project's stack are reported as LINTER_NA with
# a rationale — absence is never treated as a failure.
#

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---- Source directory detection ----
TARGET_DIR="${1:-${REPO_HEALTH_TARGET_DIR:-}}"
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="."
  for d in src lib app; do
    if [[ -d "$d" ]]; then TARGET_DIR="$d"; break; fi
  done
fi

# ---- Repo root hint (manifests live at the root, target may be src/) ----
ROOT_HINT="$PWD"
if [[ -d "$TARGET_DIR" && "$TARGET_DIR" != "." ]]; then
  d="$(cd "$TARGET_DIR" 2>/dev/null && pwd || true)"
  while [[ -n "$d" && "$d" != "/" ]]; do
    if [[ -f "$d/pyproject.toml" || -f "$d/package.json" || -f "$d/go.mod" || -f "$d/Cargo.toml" ]]; then
      ROOT_HINT="$d"
      break
    fi
    d="$(dirname "$d")"
  done
fi
echo "SCAN_LINTERS_TARGET: $TARGET_DIR"
echo "LINTERS_ROOT_HINT: $ROOT_HINT"

# Project-local virtualenv tools win over PATH shims (they match project config)
find_venv_tool() {
  local name="$1" cand
  for cand in "$ROOT_HINT/.venv/bin/$name" "$ROOT_HINT/venv/bin/$name"; do
    if [[ -x "$cand" ]]; then echo "$cand"; return 0; fi
  done
  command -v "$name" 2>/dev/null || return 1
}

has_source_files() { # dir ext [maxdepth]
  local dir="$1" ext="$2" maxdepth="${3:-2}"
  find "$dir" -maxdepth "$maxdepth" -name "*.$ext" \
    -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/venv/*" \
    -not -path "*/__pycache__/*" -not -path "*/site-packages/*" -not -path "*/.git/*" \
    -print -quit 2>/dev/null | grep -q .
}

IS_PYTHON=false
if [[ -f "$ROOT_HINT/pyproject.toml" || -f "$ROOT_HINT/setup.py" || -f "$ROOT_HINT/setup.cfg" ]] \
   || compgen -G "$ROOT_HINT/requirements*.txt" >/dev/null 2>&1 \
   || has_source_files "$TARGET_DIR" py; then
  IS_PYTHON=true
fi

# Node.js / TypeScript / JavaScript
if [[ -f "package.json" ]]; then
  if npx --no-install eslint --version >/dev/null 2>&1 || command -v eslint >/dev/null 2>&1; then
    echo "LINTER_AVAILABLE: eslint ($(npx --no-install eslint --version 2>/dev/null || eslint --version 2>/dev/null))"
    echo "LINTER_CONFIG_CHECK: $(ls .eslintrc* eslint.config.* .eslintrc.* 2>/dev/null | head -5 || echo 'NO ESLINT CONFIG FOUND')"
  else
    echo "LINTER_NA: eslint (package.json present but eslint not installed locally)"
  fi
  if npx --no-install tsc --version >/dev/null 2>&1 || command -v tsc >/dev/null 2>&1; then
    echo "TYPE_CHECKER_AVAILABLE: tsc ($(npx --no-install tsc --version 2>/dev/null || tsc --version 2>/dev/null))"
    echo "TS_CONFIG_CHECK: $(ls tsconfig.json 2>/dev/null || echo 'NO TSCONFIG FOUND')"
  fi
  if command -v prettier >/dev/null 2>&1 || npx --no-install prettier --version >/dev/null 2>&1; then
    echo "FORMATTER_AVAILABLE: prettier"
    echo "FORMATTER_CONFIG_CHECK: $(ls .prettierrc* prettier.config.* 2>/dev/null | head -5 || echo 'NO PRETTIER CONFIG FOUND')"
  fi
  jq -r '.scripts | to_entries[] | select(.key | test("lint|format|typecheck|type-check")) | "- \(.key): \(.value)"' package.json 2>/dev/null || true
else
  echo "STACK_NA: node (no package.json — Node linters skipped)"
fi

# Python
if $IS_PYTHON; then
  if RUFF_BIN=$(find_venv_tool ruff); then
    echo "LINTER_AVAILABLE: ruff ($("$RUFF_BIN" --version 2>&1 | head -1))"
    echo "FORMATTER_AVAILABLE: ruff format (bundled with ruff $("$RUFF_BIN" --version 2>&1 | head -1 | grep -oE '[0-9][0-9.]*'))"
  else
    echo "LINTER_NA: ruff (not installed — install with: pip install ruff)"
  fi
  if MYPY_BIN=$(find_venv_tool mypy); then
    echo "TYPE_CHECKER_AVAILABLE: mypy ($("$MYPY_BIN" --version 2>&1 | head -1))"
  else
    echo "LINTER_NA: mypy (not installed — install with: pip install mypy)"
  fi
  if BANDIT_BIN=$(find_venv_tool bandit); then
    echo "SECURITY_LINTER_AVAILABLE: bandit ($("$BANDIT_BIN" --version 2>&1 | head -1))"
  elif [[ -f "$ROOT_HINT/pyproject.toml" ]] && grep -qE '^\[tool\.bandit' "$ROOT_HINT/pyproject.toml" 2>/dev/null; then
    echo "LINTER_NA: bandit (pyproject.toml configures [tool.bandit] but the bandit CLI is not installed)"
  fi
  command -v pylint >/dev/null 2>&1 && echo "LINTER_AVAILABLE: pylint ($(pylint --version 2>&1 | head -1))"
  command -v flake8 >/dev/null 2>&1 && echo "LINTER_AVAILABLE: flake8 ($(flake8 --version 2>&1 | head -1))"
  command -v black >/dev/null 2>&1 && echo "FORMATTER_AVAILABLE: black ($(black --version 2>&1 | head -1))"
  command -v isort >/dev/null 2>&1 && echo "FORMATTER_AVAILABLE: isort ($(isort --version 2>&1 | head -1))"
  echo "PYTHON_CONFIG_CHECK: $(ls ruff.toml .ruff.toml pyproject.toml .pylintrc .flake8 setup.cfg mypy.ini .isort.cfg 2>/dev/null | head -10 || true)"
  if [[ -f "$ROOT_HINT/pyproject.toml" ]]; then
    for tool in ruff mypy bandit coverage pytest; do
      if grep -qE "^\\[tool\\.$tool" "$ROOT_HINT/pyproject.toml" 2>/dev/null; then
        echo "TOOL_CONFIGURED: $tool ([tool.$tool] in pyproject.toml)"
      fi
    done
  fi
else
  echo "STACK_NA: python (no pyproject.toml/setup.cfg/requirements*.txt/*.py)"
fi

# Go
if has_source_files . go 3 || [[ -f "go.mod" ]]; then
  command -v golangci-lint >/dev/null 2>&1 && echo "LINTER_AVAILABLE: golangci-lint"
  if command -v go >/dev/null 2>&1; then
    echo "GO_VET_AVAILABLE: go vet"
  else
    echo "LINTER_NA: go vet (go toolchain not on PATH)"
  fi
  echo "GO_CONFIG_CHECK: $(ls .golangci.yml .golangci.yaml .golangci.toml 2>/dev/null | head -5 || echo 'NO GOLANGCI-LINT CONFIG FOUND')"
fi

# Rust
if [[ -f "Cargo.toml" ]]; then
  if command -v cargo >/dev/null 2>&1; then
    echo "LINTER_AVAILABLE: cargo clippy"
    echo "FORMATTER_AVAILABLE: cargo fmt"
  else
    echo "LINTER_NA: cargo clippy/fmt (cargo not on PATH)"
  fi
fi

# Java / JVM
if has_source_files . java 3 || [[ -f "pom.xml" || -f "build.gradle" ]]; then
  command -v checkstyle >/dev/null 2>&1 && echo "LINTER_AVAILABLE: checkstyle"
  command -v spotbugs   >/dev/null 2>&1 && echo "LINTER_AVAILABLE: spotbugs"
fi

# Ruby
if has_source_files . rb 3; then
  command -v rubocop >/dev/null 2>&1 && echo "LINTER_AVAILABLE: rubocop ($(rubocop --version 2>/dev/null))"
fi

# C / C++
if has_source_files . c 3 || has_source_files . cpp 3; then
  command -v clang-tidy >/dev/null 2>&1 && echo "LINTER_AVAILABLE: clang-tidy"
  command -v cppcheck   >/dev/null 2>&1 && echo "LINTER_AVAILABLE: cppcheck"
fi

# PHP
if has_source_files . php 3; then
  command -v phpcs   >/dev/null 2>&1 && echo "LINTER_AVAILABLE: phpcs ($(phpcs --version 2>/dev/null))"
  command -v phpstan >/dev/null 2>&1 && echo "ANALYZER_AVAILABLE: phpstan"
  command -v psalm   >/dev/null 2>&1 && echo "ANALYZER_AVAILABLE: psalm"
fi

# C# / .NET
if has_source_files . cs 3 || compgen -G './*.csproj' >/dev/null 2>&1; then
  command -v dotnet >/dev/null 2>&1 && echo "LINTER_AVAILABLE: dotnet format" && echo "ANALYZER_AVAILABLE: dotnet analyze (roslyn)"
fi

# Kotlin
if has_source_files . kt 3 || has_source_files . kts 3; then
  command -v ktlint >/dev/null 2>&1 && echo "LINTER_AVAILABLE: ktlint ($(ktlint --version 2>/dev/null))"
  command -v detekt >/dev/null 2>&1 && echo "ANALYZER_AVAILABLE: detekt"
fi

# Swift
if has_source_files . swift 3; then
  command -v swiftlint >/dev/null 2>&1 && echo "LINTER_AVAILABLE: swiftlint"
fi

# Dart / Flutter
if has_source_files . dart 3; then
  command -v dart >/dev/null 2>&1 && echo "ANALYZER_AVAILABLE: dart analyze"
fi

# Shell scripts — anywhere in the repo (not just the root), vendor dirs excluded
if has_source_files . sh 6 || has_source_files "$TARGET_DIR" sh 6; then
  if command -v shellcheck >/dev/null 2>&1; then
    echo "LINTER_AVAILABLE: shellcheck ($(shellcheck --version 2>/dev/null | grep -m1 'version:'))"
  else
    echo "LINTER_NA: shellcheck (shell scripts present but shellcheck is not installed)"
  fi
fi

# Markdown docs
if has_source_files . md 5; then
  if command -v markdownlint >/dev/null 2>&1 || command -v markdownlint-cli2 >/dev/null 2>&1; then
    echo "LINTER_AVAILABLE: markdownlint ($(markdownlint --version 2>/dev/null || markdownlint-cli2 --version 2>/dev/null))"
  else
    echo "LINTER_NA: markdownlint (markdown files present but markdownlint is not installed)"
  fi
fi

exit 0
