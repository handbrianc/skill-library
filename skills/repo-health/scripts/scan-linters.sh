#!/usr/bin/env bash
#
# scan-linters.sh
# Detect available linters for the project's language(s), run them,
# and output violation counts for use by the repo-health audit.
#
# Usage: ./scan-linters.sh [target-dir]
#   target-dir: source directory to scan (default: auto-detect src/ lib/ app/ or .)
#
# Outputs violation files to /tmp/ for each detected linter:
#   /tmp/eslint-violations.txt, /tmp/ruff-violations.txt, etc.
#
# Returns: 0 always (non-zero exits from linters are captured as violations, not failures)
#

set -euo pipefail

# ---- Source directory detection ----
TARGET_DIR="${1:-}"
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="."
  for d in src lib app; do
    if [[ -d "$d" ]]; then TARGET_DIR="$d"; break; fi
  done
fi

echo "SCAN_LINTERS_TARGET: $TARGET_DIR"

# ---- Step 1: Detect ----
echo ""
echo "=== LINTER DETECTION ==="

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

# ---- Step 2: Run linters ----
echo ""
echo "=== LINTER RUN ==="

# ESLint (JavaScript/TypeScript)
if npx eslint --version >/dev/null 2>&1; then
  npx eslint "$TARGET_DIR" --format json --max-warnings 0 2>/dev/null > /tmp/eslint-output.json || true
  if [[ -s /tmp/eslint-output.json ]]; then
    jq '[.[] | .messageCount] | add // 0' /tmp/eslint-output.json > /tmp/eslint-violations.txt
    jq '[.[] | .messages[] | select(.severity == 2) | {file: .filePath, line: .line, rule: .ruleId, message: .message}]' /tmp/eslint-output.json > /tmp/eslint-errors.json 2>/dev/null
    echo "ESLINT_RESULT: $(cat /tmp/eslint-violations.txt) violations"
  else
    echo "ESLINT_RESULT: 0 violations (no output)"
  fi
fi

# Python linters
if command -v ruff >/dev/null 2>&1; then
  ruff check "$TARGET_DIR" --output-format json 2>/dev/null | jq 'length // 0' > /tmp/ruff-violations.txt
  echo "RUFF_RESULT: $(cat /tmp/ruff-violations.txt) violations"
fi
if command -v flake8 >/dev/null 2>&1; then
  flake8 "$TARGET_DIR" --count --statistics 2>&1 | tail -1 | tee /tmp/flake8-violations.txt
fi
if command -v pylint >/dev/null 2>&1; then
  pylint "$TARGET_DIR" --output-format json 2>/dev/null | jq 'length // 0' > /tmp/pylint-violations.txt 2>/dev/null || true
  echo "PYLINT_RESULT: $(cat /tmp/pylint-violations.txt 2>/dev/null || echo '0') violations"
fi
if command -v mypy >/dev/null 2>&1; then
  mypy "$TARGET_DIR" --strict 2>&1 | tail -5 | tee /tmp/mypy-violations.txt
fi

# Go
if command -v golangci-lint >/dev/null 2>&1; then
  golangci-lint run ./... --out-format json 2>/dev/null > /tmp/golangci-output.json
  jq '.Issues | length // 0' /tmp/golangci-output.json 2>/dev/null > /tmp/golangci-violations.txt || echo "0" > /tmp/golangci-violations.txt
  echo "GOLANGCI_RESULT: $(cat /tmp/golangci-violations.txt) violations"
fi
if command -v go >/dev/null 2>&1; then
  go vet ./... 2>&1 | tee /tmp/govet-violations.txt || true
fi

# Rust
if command -v cargo >/dev/null 2>&1 && [[ -f "Cargo.toml" ]]; then
  cargo clippy -- -D warnings 2>&1 | tee /tmp/clippy-violations.txt
fi

# Ruby
if command -v rubocop >/dev/null 2>&1; then
  rubocop --format json 2>/dev/null | jq '.summary | {offense_count, target_file_count}' > /tmp/rubocop-violations.json
  echo "RUBOCOP_RESULT: $(jq -r '.offense_count // "unknown"' /tmp/rubocop-violations.json) violations"
fi

# PHP
if command -v phpcs >/dev/null 2>&1; then
  phpcs "$TARGET_DIR" --report=json 2>/dev/null | jq '.totals | {errors: .errors, warnings: .warnings}' > /tmp/phpcs-violations.json
  echo "PHPCS_RESULT: $(jq -r '.errors' /tmp/phpcs-violations.json 2>/dev/null || echo 'unknown') errors"
fi
if command -v phpstan >/dev/null 2>&1; then
  phpstan analyse "$TARGET_DIR" --error-format=json 2>/dev/null | jq 'length' > /tmp/phpstan-violations.txt || true
  echo "PHPSTAN_RESULT: $(cat /tmp/phpstan-violations.txt 2>/dev/null || echo '0') violations"
fi

# C# / .NET
if command -v dotnet >/dev/null 2>&1 && ls ./*.csproj 2>/dev/null | head -1 >/dev/null 2>&1; then
  dotnet format --verify-no-changes 2>&1 | tail -3 | tee /tmp/dotnet-format-violations.txt
fi

# Kotlin
if command -v ktlint >/dev/null 2>&1; then
  ktlint "$TARGET_DIR"/**/*.kt 2>&1 | tee /tmp/ktlint-violations.txt
fi

# Swift
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --reporter json 2>/dev/null | jq 'length' > /tmp/swiftlint-violations.txt
  echo "SWIFTLINT_RESULT: $(cat /tmp/swiftlint-violations.txt 2>/dev/null || echo '0') violations"
fi

# Dart
if command -v dart >/dev/null 2>&1; then
  dart analyze --fatal-infos 2>&1 | tail -10 | tee /tmp/dart-analyze-violations.txt
fi

# Shell
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck ./*.sh scripts/*.sh 2>/dev/null | tee /tmp/shellcheck-violations.txt || true
fi

echo ""
echo "=== LINTER SCAN COMPLETE ==="
