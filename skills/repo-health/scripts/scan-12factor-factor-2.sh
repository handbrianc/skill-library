#!/usr/bin/env bash
# scan-12factor-factor-2.sh — Factor 2: Dependencies
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_2_dependencies() {
  local detail=""
  local status="PASS"

  local manifest_found=false
  local lockfile_found=false

  # Check manifest files
  if has_files "package.json" || has_files "yarn.lock" || has_files "pnpm-lock.yaml" || \
     has_files "requirements.txt" || has_files "pyproject.toml" || \
     has_files "Cargo.toml" || has_files "go.mod" || \
     has_files "Gemfile" || has_files "composer.json"; then
    manifest_found=true
    detail="Manifest found"
  else
    detail="No dependency manifest found"
    status="FAIL"
  fi

  # Check lockfiles
  if has_files "package-lock.json" || has_files "yarn.lock" || has_files "pnpm-lock.yaml" || \
     has_files "Cargo.lock" || has_files "Gemfile.lock" || \
     has_files "composer.lock" || has_files "poetry.lock"; then
    lockfile_found=true
    detail+=" | Lockfile present"
  else
    detail+=" | WARNING: No lockfile — dependencies not pinned"
    if [[ "$status" = "PASS" ]]; then
      status="WARNING"
    fi
  fi

  if ! $manifest_found; then
    status="FAIL"
  fi

  echo "FACTOR_2: ${status} - ${detail}"
}

factor_2_dependencies
exit 0
