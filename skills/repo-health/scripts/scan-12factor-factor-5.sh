#!/usr/bin/env bash
# scan-12factor-factor-5.sh — Factor 5: Build, release, run
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_5_build_release_run() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for build step
  if has_cmd jq && [[ -f "package.json" ]]; then
    local build_scripts
    build_scripts=$(jq -r '.scripts | to_entries[] | select(.key | test("build|compile|bundle|dist")) | "\(.key): \(.value)"' package.json 2>/dev/null || true)
    if [[ -n "$build_scripts" ]]; then
      detail="Build step defined: ${build_scripts}"
    else
      warnings+=("No build step defined in package.json")
    fi
  fi

  # Check for CI/CD configuration
  if ls .github/workflows/ .circleci/ .gitlab-ci.yml Jenkinsfile 2>/dev/null | head -1 >/dev/null 2>&1; then
    warnings+=("CI/CD detected")
  else
    warnings+=("No CI/CD config found")
  fi

  # Check for release tagging
  local release_tags
  release_tags=$(git tag -l 'v*' --sort=-v:refname 2>/dev/null | head -5 || true)
  if [[ -n "$release_tags" ]]; then
    warnings+=("Release tags found: $(echo "$release_tags" | tr '\n' ' ')")
  else
    warnings+=("No release tags found")
  fi

  # Check for rollback mechanism
  local rollback
  rollback=$(grep -rn 'rollback\|revert\|canary\|blue.green\|v[0-9]\+\.[0-9]' \
    .github/workflows/ .circleci/ 2>/dev/null | head -5 || true)
  if [[ -z "$rollback" ]]; then
    warnings+=("No explicit rollback mechanism detected")
  fi

  if [[ ${#warnings[@]} -gt 0 ]]; then
    status="WARNING"
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_5: ${status} - ${detail}"
}

factor_5_build_release_run
exit 0
