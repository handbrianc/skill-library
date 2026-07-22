#!/usr/bin/env bash
# scan-12factor-factor-1.sh — Factor 1: Codebase
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_1_codebase() {
  local detail=""
  local status="PASS"

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    detail="No VCS detected — every project should use version control"
    status="FAIL"
  else
    local remote
    remote=$(git remote get-url origin 2>/dev/null || echo "no remote")
    detail="git repo detected (${remote})"

    # Check for monorepo workspaces
    if has_cmd jq && [[ -f "package.json" ]]; then
      local workspaces
      workspaces=$(jq -r '.workspaces // .packages // empty' package.json 2>/dev/null)
      if [[ -n "$workspaces" ]]; then
        detail+=" — monorepo workspaces detected"
      fi
    fi

    local remote_count
    remote_count=$(git remote -v 2>/dev/null | wc -l)
    detail+=" | remotes: ${remote_count}"
  fi

  echo "FACTOR_1: ${status} - ${detail}"
}

factor_1_codebase
exit 0
