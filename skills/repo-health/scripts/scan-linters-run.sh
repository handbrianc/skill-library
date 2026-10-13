#!/usr/bin/env bash
#
# scan-linters-run.sh
# Run detected linters against the project and output violation counts.
# Designed to be called directly or from scan-linters.sh
#
# Usage: ./scan-linters-run.sh [target-dir]
#   target-dir: source directory to scan (default: $REPO_HEALTH_TARGET_DIR, then
#   auto-detect src/ lib/ app/ or .)
#
# Outputs violation files to /tmp/ for each detected linter:
#   /tmp/eslint-violations.txt, /tmp/ruff-violations.txt,
#   /tmp/ruff-format-violations.txt, /tmp/mypy-violations.txt,
#   /tmp/bandit-violations.txt, /tmp/shellcheck-violations.txt,
#   /tmp/markdownlint-violations.txt, etc.
#
# Tools absent for the project's stack are reported as *_NA with a rationale.
# Project-local virtualenv binaries (.venv/bin, venv/bin) are preferred over
# PATH so the linter versions match the project's configuration. Type-checkers
# and SAST tools never scan vendor trees (.venv, node_modules, site-packages).
#

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
set +e
# ---- Source directory detection ----
TARGET_DIR="${1:-${REPO_HEALTH_TARGET_DIR:-}}"
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="."
  for d in src lib app; do
    if [[ -d "$d" ]]; then TARGET_DIR="$d"; break; fi
  done
fi

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
echo "SCAN_LINTERS_RUN_TARGET: $TARGET_DIR"

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

run_timeout() { # secs cmd...
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  else
    "$@"
  fi
}

IS_PYTHON=false
if [[ -f "$ROOT_HINT/pyproject.toml" || -f "$ROOT_HINT/setup.py" || -f "$ROOT_HINT/setup.cfg" ]] \
   || compgen -G "$ROOT_HINT/requirements*.txt" >/dev/null 2>&1 \
   || has_source_files "$TARGET_DIR" py; then
  IS_PYTHON=true
fi

# When pointed at the repo root, type-checkers/SAST must not crawl vendor trees
PY_TARGET="$TARGET_DIR"
if [[ "$TARGET_DIR" == "." && -d src ]]; then
  PY_TARGET="src"
  echo "PYTHON_SCOPE: src (repo root would include venv/caches)"
fi

# ESLint (JavaScript/TypeScript)
if [[ -f "package.json" ]]; then
  if npx --no-install eslint --version >/dev/null 2>&1 || command -v eslint >/dev/null 2>&1; then
    npx --no-install eslint "$TARGET_DIR" --format json --max-warnings 0 2>/dev/null > /tmp/eslint-output.json || true
    if [[ -s /tmp/eslint-output.json ]]; then
      jq '[.[] | .messageCount] | add // 0' /tmp/eslint-output.json > /tmp/eslint-violations.txt
      jq '[.[] | .messages[] | select(.severity == 2) | {file: .filePath, line: .line, rule: .ruleId, message: .message}]' /tmp/eslint-output.json > /tmp/eslint-errors.json 2>/dev/null
      echo "ESLINT_RESULT: $(cat /tmp/eslint-violations.txt) violations"
    else
      echo "ESLINT_RESULT: 0 violations (no output)"
    fi
  else
    echo "ESLINT_NA: eslint not installed locally (npx --no-install found nothing)"
  fi
fi

# Python linters
if $IS_PYTHON; then
  if RUFF_BIN=$(find_venv_tool ruff); then
    "$RUFF_BIN" check "$TARGET_DIR" --output-format json --no-cache 2>/dev/null > /tmp/ruff-output.json || true
    if [[ -s /tmp/ruff-output.json ]]; then
      jq 'length // 0' /tmp/ruff-output.json > /tmp/ruff-violations.txt 2>/dev/null || echo 0 > /tmp/ruff-violations.txt
    else
      echo 0 > /tmp/ruff-violations.txt
    fi
    echo "RUFF_RESULT: $(cat /tmp/ruff-violations.txt 2>/dev/null || echo 0) violations (details: /tmp/ruff-output.json)"

    "$RUFF_BIN" format --check --no-cache "$TARGET_DIR" > /tmp/ruff-format-check.txt 2>&1 || true
    RF_N=$(grep -oE '[0-9]+ files? would be reformatted' /tmp/ruff-format-check.txt 2>/dev/null | tail -1 | grep -oE '^[0-9]+' || true)
    : "${RF_N:=0}"
    echo "$RF_N" > /tmp/ruff-format-violations.txt
    echo "RUFF_FORMAT_RESULT: $RF_N file(s) would be reformatted (details: /tmp/ruff-format-check.txt)"
  else
    echo "RUFF_NA: ruff not installed (check + format checks skipped — install with: pip install ruff)"
  fi

  if command -v flake8 >/dev/null 2>&1; then
    flake8 "$TARGET_DIR" --count --statistics 2>&1 | tail -1 | tee /tmp/flake8-violations.txt
  fi
  if command -v pylint >/dev/null 2>&1; then
    pylint "$TARGET_DIR" --output-format json 2>/dev/null | jq 'length // 0' > /tmp/pylint-violations.txt 2>/dev/null || true
    echo "PYLINT_RESULT: $(cat /tmp/pylint-violations.txt 2>/dev/null || echo '0') violations"
  fi
  if MYPY_BIN=$(find_venv_tool mypy); then
    MYPY_TIMEOUT="${REPO_HEALTH_MYPY_TIMEOUT:-900}"
    echo "MYPY: running ($("$MYPY_BIN" --version 2>&1 | head -1)) against $PY_TARGET (config: pyproject.toml/mypy.ini if present)"
    run_timeout "$MYPY_TIMEOUT" "$MYPY_BIN" "$PY_TARGET" --cache-dir="/tmp/repo-health-mypy-cache-$(basename "$PWD")" \
      > /tmp/mypy-output.txt 2>&1 || true
    grep 'error:' /tmp/mypy-output.txt 2>/dev/null | head -20 > /tmp/mypy-violations.txt || true
    MYPY_ERRS=$(grep -c 'error:' /tmp/mypy-output.txt 2>/dev/null || true)
    : "${MYPY_ERRS:=0}"
    echo "MYPY_RESULT: $MYPY_ERRS type error(s) (summary: $(tail -1 /tmp/mypy-output.txt 2>/dev/null))"
  else
    echo "MYPY_NA: mypy not installed (install with: pip install mypy)"
  fi
  if BANDIT_BIN=$(find_venv_tool bandit); then
    run_timeout 300 "$BANDIT_BIN" -r "$PY_TARGET" -q -f json 2>/dev/null > /tmp/bandit-raw.json || true
    if [[ -s /tmp/bandit-raw.json ]]; then
      BANDIT_N=$(jq '.results | length // 0' /tmp/bandit-raw.json 2>/dev/null || echo 0)
    else
      BANDIT_N=0
    fi
    echo "$BANDIT_N" > /tmp/bandit-violations.txt
    echo "BANDIT_RESULT: $BANDIT_N issue(s) (details: /tmp/bandit-raw.json)"
  fi
fi

# Go
if command -v golangci-lint >/dev/null 2>&1; then
  golangci-lint run ./... --out-format json 2>/dev/null > /tmp/golangci-output.json || true
  jq '.Issues | length // 0' /tmp/golangci-output.json 2>/dev/null > /tmp/golangci-violations.txt || echo "0" > /tmp/golangci-violations.txt
  echo "GOLANGCI_RESULT: $(cat /tmp/golangci-violations.txt) violations"
fi
if command -v go >/dev/null 2>&1; then
  go vet ./... 2>&1 | tee /tmp/govet-violations.txt || true
fi

# Rust
if command -v cargo >/dev/null 2>&1 && [[ -f "Cargo.toml" ]]; then
  cargo clippy -- -D warnings 2>&1 | tee /tmp/clippy-violations.txt || true
fi

# Ruby
if command -v rubocop >/dev/null 2>&1; then
  rubocop --format json 2>/dev/null | jq '.summary | {offense_count, target_file_count}' > /tmp/rubocop-violations.json || true
  echo "RUBOCOP_RESULT: $(jq -r '.offense_count // "unknown"' /tmp/rubocop-violations.json 2>/dev/null) violations"
fi

# PHP
if command -v phpcs >/dev/null 2>&1; then
  phpcs "$TARGET_DIR" --report=json 2>/dev/null | jq '.totals | {errors: .errors, warnings: .warnings}' > /tmp/phpcs-violations.json || true
  echo "PHPCS_RESULT: $(jq -r '.errors' /tmp/phpcs-violations.json 2>/dev/null || echo 'unknown') errors"
fi
if command -v phpstan >/dev/null 2>&1; then
  phpstan analyse "$TARGET_DIR" --error-format=json 2>/dev/null | jq 'length' > /tmp/phpstan-violations.txt || true
  echo "PHPSTAN_RESULT: $(cat /tmp/phpstan-violations.txt 2>/dev/null || echo '0') violations"
fi

# C# / .NET
if command -v dotnet >/dev/null 2>&1 && compgen -G './*.csproj' >/dev/null 2>&1; then
  dotnet format --verify-no-changes 2>&1 | tail -3 | tee /tmp/dotnet-format-violations.txt || true
fi

# Kotlin
if command -v ktlint >/dev/null 2>&1; then
  ktlint "$TARGET_DIR"/**/*.kt 2>&1 | tee /tmp/ktlint-violations.txt || true
fi

# Swift
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --reporter json 2>/dev/null | jq 'length' > /tmp/swiftlint-violations.txt || true
  echo "SWIFTLINT_RESULT: $(cat /tmp/swiftlint-violations.txt 2>/dev/null || echo '0') violations"
fi

# Dart
if command -v dart >/dev/null 2>&1; then
  dart analyze --fatal-infos 2>&1 | tail -10 | tee /tmp/dart-analyze-violations.txt || true
fi

# Shell — every .sh in the repo (vendor dirs excluded), not just the root
if command -v shellcheck >/dev/null 2>&1; then
  mapfile -d '' SH_FILES < <(find . -maxdepth 6 -name '*.sh' \
    -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/venv/*" \
    -not -path "*/.git/*" -not -path "*/__pycache__/*" -print0 2>/dev/null)
  if (( ${#SH_FILES[@]} > 0 )); then
    shellcheck "${SH_FILES[@]}" > /tmp/shellcheck-violations.txt 2>&1 || true
    SC_N=$(grep -c '^In ' /tmp/shellcheck-violations.txt 2>/dev/null || true)
    : "${SC_N:=0}"
    echo "SHELLCHECK_RESULT: $SC_N issue(s) in ${#SH_FILES[@]} script(s) (details: /tmp/shellcheck-violations.txt)"
  else
    echo "SHELLCHECK_NA: no .sh files in repo"
  fi
else
  if has_source_files . sh 6; then
    echo "SHELLCHECK_NA: shell scripts present but shellcheck is not installed"
  fi
fi

# Markdown — every .md in the repo (vendor dirs excluded)
MDL_BIN=$(command -v markdownlint 2>/dev/null || command -v markdownlint-cli2 2>/dev/null || true)
if [[ -n "$MDL_BIN" ]]; then
  mapfile -d '' MD_FILES < <(find . -maxdepth 5 -name '*.md' \
    -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/venv/*" \
    -not -path "*/.git/*" -not -path "*/__pycache__/*" -not -path "*/site-packages/*" \
    -not -path "*.dist-info/*" -print0 2>/dev/null)
  if (( ${#MD_FILES[@]} > 0 )); then
    xargs -0 -n 100 "$MDL_BIN" < <(printf '%s\0' "${MD_FILES[@]}") \
      > /tmp/markdownlint-violations.txt 2>&1 || true
    MD_N=$(grep -cE ' MD[0-9]+' /tmp/markdownlint-violations.txt 2>/dev/null || true)
    : "${MD_N:=0}"
    echo "MARKDOWNLINT_RESULT: $MD_N violation(s) in ${#MD_FILES[@]} file(s) (details: /tmp/markdownlint-violations.txt)"
  else
    echo "MARKDOWNLINT_NA: no .md files in repo"
  fi
else
  if has_source_files . md 5; then
    echo "MARKDOWNLINT_NA: markdown files present but markdownlint is not installed"
  fi
fi

echo "LINTER_RUN_COMPLETE"
exit 0
