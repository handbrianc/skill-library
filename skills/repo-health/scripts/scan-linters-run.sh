#!/usr/bin/env bash
#
# scan-linters-run.sh
# Run detected linters against the project and output violation counts.
# Designed to be called directly or from scan-linters.sh
#
# Usage: ./scan-linters-run.sh [target-dir]
#   target-dir: source directory to scan (default: auto-detect src/ lib/ app/ or .)
#
# Outputs violation files to /tmp/ for each detected linter:
#   /tmp/eslint-violations.txt, /tmp/ruff-violations.txt, etc.
#

set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# ---- Source directory detection ----
TARGET_DIR="${1:-}"
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="."
  for d in src lib app; do
    if [[ -d "$d" ]]; then TARGET_DIR="$d"; break; fi
  done
fi

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
