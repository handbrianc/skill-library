#!/usr/bin/env bash
# scan-12factor-factor-1.sh — Factor 1: Codebase
# Usage: ./scan-12factor-factor-1.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_1: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_1_codebase() {
  local detail=""
  local status="PASS"

  if ! git -C "$TARGET" rev-parse --is-inside-work-tree &>/dev/null; then
    detail="No VCS detected — every project should use version control"
    status="FAIL"
  else
    local remote
    remote=$(git -C "$TARGET" remote get-url origin 2>/dev/null || echo "no remote")
    detail="git repo detected (${remote})"

    # Check for monorepo workspaces
    if has_cmd jq && [[ -f "$TARGET/package.json" ]]; then
      local workspaces
      workspaces=$(jq -r '.workspaces // .packages // empty' "$TARGET/package.json" 2>/dev/null)
      if [[ -n "$workspaces" ]]; then
        detail+=" — monorepo workspaces detected"
      fi
    fi

    local remote_count
    remote_count=$(git -C "$TARGET" remote -v 2>/dev/null | awk 'END{print NR+0}')
    detail+=" | remotes: ${remote_count}"
  fi

  echo "FACTOR_1: ${status} - ${detail}"
}

factor_1_codebase
exit 0
