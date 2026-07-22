#!/usr/bin/env bash
#
# scan-linters-detect.sh
# Detect available linters for the project's language(s) and output availability.
# Designed to be called directly or from scan-linters.sh
#
# Usage: ./scan-linters-detect.sh [target-dir]
#   target-dir: source directory to scan (default: auto-detect src/ lib/ app/ or .)
#

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---- Source directory detection ----
TARGET_DIR="${1:-}"
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="."
  for d in src lib app; do
    if [[ -d "$d" ]]; then TARGET_DIR="$d"; break; fi
  done
fi

# Node.js / TypeScript / JavaScript
if [[ -f "package.json" ]]; then
  if npx eslint --version >/dev/null 2>&1; then
    echo "LINTER_AVAILABLE: eslint ($(npx eslint --version))"
    echo "LINTER_CONFIG_CHECK: $(ls .eslintrc* eslint.config.* .eslintrc.* 2>/dev/null | head -5 || echo 'NO ESLINT CONFIG FOUND')"
  fi
  if npx tsc --noEmit --version >/dev/null 2>&1; then
    echo "TYPE_CHECKER_AVAILABLE: tsc ($(npx tsc --version))"
    echo "TS_CONFIG_CHECK: $(ls tsconfig.json 2>/dev/null || echo 'NO TSCONFIG FOUND')"
  fi
  if command -v prettier >/dev/null 2>&1 || npx prettier --version >/dev/null 2>&1; then
    echo "FORMATTER_AVAILABLE: prettier"
    echo "FORMATTER_CONFIG_CHECK: $(ls .prettierrc* prettier.config.* 2>/dev/null | head -5 || echo 'NO PRETTIER CONFIG FOUND')"
  fi
  jq -r '.scripts | to_entries[] | select(.key | test("lint|format|typecheck|type-check")) | "- \(.key): \(.value)"' package.json 2>/dev/null || true
fi

# Python
if ls ./*.{py,pyw} 2>/dev/null | head -1 >/dev/null 2>&1 || ls "$TARGET_DIR"/*.py 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v pylint >/dev/null 2>&1 && echo "LINTER_AVAILABLE: pylint ($(pylint --version 2>&1 | head -1))"
  command -v flake8 >/dev/null 2>&1 && echo "LINTER_AVAILABLE: flake8 ($(flake8 --version 2>&1 | head -1))"
  command -v ruff   >/dev/null 2>&1 && echo "LINTER_AVAILABLE: ruff ($(ruff --version 2>&1 | head -1))"
  command -v mypy   >/dev/null 2>&1 && echo "TYPE_CHECKER_AVAILABLE: mypy ($(mypy --version 2>&1 | head -1))"
  command -v black  >/dev/null 2>&1 && echo "FORMATTER_AVAILABLE: black ($(black --version 2>&1 | head -1))"
  command -v isort  >/dev/null 2>&1 && echo "FORMATTER_AVAILABLE: isort ($(isort --version 2>&1 | head -1))"
  ls ruff.toml .ruff.toml pyproject.toml .pylintrc .flake8 setup.cfg mypy.ini .isort.cfg 2>/dev/null | head -10 || true
fi

# Go
if ls ./*.go 2>/dev/null | head -1 >/dev/null 2>&1 || ls "$TARGET_DIR"/*.go 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v golangci-lint >/dev/null 2>&1 && echo "LINTER_AVAILABLE: golangci-lint"
  command -v go >/dev/null 2>&1 && echo "GO_VET_AVAILABLE: go vet"
  ls .golangci* .golangci.yml .golangci.yaml 2>/dev/null | head -5 || echo "NO GOLANGCI-LINT CONFIG FOUND" 2>/dev/null || true
fi

# Rust
if [[ -f "Cargo.toml" ]]; then
  if command -v cargo >/dev/null 2>&1; then
    echo "LINTER_AVAILABLE: cargo clippy"
    echo "FORMATTER_AVAILABLE: cargo fmt"
  fi
fi

# Java / JVM
if ls ./*.java 2>/dev/null | head -1 >/dev/null 2>&1 || ls "$TARGET_DIR"/*.java 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v checkstyle >/dev/null 2>&1 && echo "LINTER_AVAILABLE: checkstyle"
  command -v spotbugs   >/dev/null 2>&1 && echo "LINTER_AVAILABLE: spotbugs"
fi

# Ruby
if ls ./*.rb 2>/dev/null | head -1 >/dev/null 2>&1 || ls "$TARGET_DIR"/*.rb 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v rubocop >/dev/null 2>&1 && echo "LINTER_AVAILABLE: rubocop ($(rubocop --version 2>/dev/null))"
fi

# C / C++
if ls ./*.c ./*.cpp ./*.h ./*.hpp 2>/dev/null | head -1 >/dev/null 2>&1 || ls "$TARGET_DIR"/*.c "$TARGET_DIR"/*.cpp 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v clang-tidy >/dev/null 2>&1 && echo "LINTER_AVAILABLE: clang-tidy"
  command -v cppcheck   >/dev/null 2>&1 && echo "LINTER_AVAILABLE: cppcheck"
fi

# PHP
if ls ./*.php 2>/dev/null | head -1 >/dev/null 2>&1 || ls "$TARGET_DIR"/*.php 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v phpcs   >/dev/null 2>&1 && echo "LINTER_AVAILABLE: phpcs ($(phpcs --version 2>/dev/null))"
  command -v phpstan >/dev/null 2>&1 && echo "ANALYZER_AVAILABLE: phpstan"
  command -v psalm   >/dev/null 2>&1 && echo "ANALYZER_AVAILABLE: psalm"
fi

# C# / .NET
if ls ./*.cs 2>/dev/null | head -1 >/dev/null 2>&1 || ls ./*.csproj 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v dotnet >/dev/null 2>&1 && echo "LINTER_AVAILABLE: dotnet format" && echo "ANALYZER_AVAILABLE: dotnet analyze (roslyn)"
fi

# Kotlin
if ls ./*.kt ./*.kts 2>/dev/null | head -1 >/dev/null 2>&1 || ls "$TARGET_DIR"/*.kt 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v ktlint >/dev/null 2>&1 && echo "LINTER_AVAILABLE: ktlint ($(ktlint --version 2>/dev/null))"
  command -v detekt >/dev/null 2>&1 && echo "ANALYZER_AVAILABLE: detekt"
fi

# Swift
if ls ./*.swift 2>/dev/null | head -1 >/dev/null 2>&1 || ls "$TARGET_DIR"/*.swift 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v swiftlint >/dev/null 2>&1 && echo "LINTER_AVAILABLE: swiftlint"
fi

# Dart / Flutter
if ls ./*.dart 2>/dev/null | head -1 >/dev/null 2>&1 || ls "$TARGET_DIR"/*.dart 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v dart >/dev/null 2>&1 && echo "ANALYZER_AVAILABLE: dart analyze"
fi

# Shell scripts
if ls ./*.sh ./*.bash ./*.zsh 2>/dev/null | head -1 >/dev/null 2>&1; then
  command -v shellcheck >/dev/null 2>&1 && echo "LINTER_AVAILABLE: shellcheck ($(shellcheck --version 2>/dev/null | head -1))"
fi
