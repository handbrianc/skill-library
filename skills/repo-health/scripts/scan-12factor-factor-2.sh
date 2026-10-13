#!/usr/bin/env bash
# scan-12factor-factor-2.sh — Factor 2: Dependencies
# Usage: ./scan-12factor-factor-2.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_2: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_2_dependencies() {
  local detail=""
  local status="PASS"

  local manifest="none"
  local m
  for m in package.json pyproject.toml requirements.txt Cargo.toml go.mod Gemfile composer.json Pipfile; do
    if [[ -f "$TARGET/$m" ]]; then
      manifest="$m"
      break
    fi
  done

  if [[ "$manifest" != "none" ]]; then
    detail="Manifest found ($manifest)"
  else
    detail="No dependency manifest found"
    status="FAIL"
  fi

  # Check lockfiles
  local lockfile="none"
  local l
  for l in package-lock.json yarn.lock pnpm-lock.yaml Cargo.lock Gemfile.lock composer.lock poetry.lock uv.lock Pipfile.lock; do
    if [[ -f "$TARGET/$l" ]]; then
      lockfile="$l"
      break
    fi
  done

  if [[ "$lockfile" != "none" ]]; then
    detail+=" | Lockfile present ($lockfile)"
  else
    detail+=" | WARNING: No lockfile — dependencies not pinned"
    if [[ "$status" = "PASS" ]]; then
      status="WARNING"
    fi
  fi

  if [[ "$manifest" = "none" ]]; then
    status="FAIL"
  fi

  echo "FACTOR_2: ${status} - ${detail}"
}

factor_2_dependencies
exit 0
