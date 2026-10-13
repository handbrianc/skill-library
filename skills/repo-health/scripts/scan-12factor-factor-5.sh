#!/usr/bin/env bash
# scan-12factor-factor-5.sh — Factor 5: Build, release, run
# Usage: ./scan-12factor-factor-5.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_5: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_5_build_release_run() {
  local detail=""
  local status="PASS"
  local warnings=()
  local notes=()

  # Check for build step
  if has_cmd jq && [[ -f "$TARGET/package.json" ]]; then
    local build_scripts
    build_scripts=$(jq -r '.scripts | to_entries[] | select(.key | test("build|compile|bundle|dist")) | "\(.key): \(.value)"' "$TARGET/package.json" 2>/dev/null || true)
    if [[ -n "$build_scripts" ]]; then
      notes+=("Build step defined: ${build_scripts}")
    else
      warnings+=("No build step defined in package.json")
    fi
  elif [[ -f "$TARGET/pyproject.toml" ]]; then
    notes+=("Python build backend declared in pyproject.toml")
  fi

  # Check for CI/CD configuration — CI presence is a POSITIVE signal, not a warning
  local ci_files=()
  if [[ -d "$TARGET/.github/workflows" ]]; then
    while IFS= read -r wf; do
      ci_files+=("$(basename "$wf")")
    done < <(find "$TARGET/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | head -3)
  fi
  if [[ ${#ci_files[@]} -gt 0 ]]; then
    notes+=("CI/CD detected (.github/workflows: ${ci_files[*]})")
  elif [[ -f "$TARGET/.gitlab-ci.yml" || -f "$TARGET/.circleci/config.yml" \
       || -f "$TARGET/Jenkinsfile" || -f "$TARGET/.travis.yml" || -f "$TARGET/bitbucket-pipelines.yml" ]]; then
    notes+=("CI/CD detected")
  else
    warnings+=("No CI/CD config found")
  fi

  # Check for release tagging
  local release_tags
  release_tags=$(git -C "$TARGET" tag -l 'v*' --sort=-v:refname 2>/dev/null | head -5 || true)
  if [[ -n "$release_tags" ]]; then
    warnings+=("Release tags found: $(echo "$release_tags" | tr '\n' ' ')")
  else
    warnings+=("No release tags found")
  fi

  # Check for rollback mechanism
  if [[ -d "$TARGET/.github/workflows" ]]; then
    local rollback
    rollback=$(grep -rn 'rollback\|revert\|canary\|blue.green\|v[0-9]\+\.[0-9]' \
      "$TARGET/.github/workflows/" 2>/dev/null | head -5 || true)
    if [[ -z "$rollback" ]]; then
      warnings+=("No explicit rollback mechanism detected")
    fi
  else
    warnings+=("No CI workflows to inspect for rollback mechanisms")
  fi

  if [[ ${#notes[@]} -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${notes[*]}"
  fi
  if [[ ${#warnings[@]} -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    [[ "$status" = "PASS" ]] && status="WARNING"
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_5: ${status} - ${detail}"
}

factor_5_build_release_run
exit 0
