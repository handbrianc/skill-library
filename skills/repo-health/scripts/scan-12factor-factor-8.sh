#!/usr/bin/env bash
# scan-12factor-factor-8.sh — Factor 8: Concurrency
# Usage: ./scan-12factor-factor-8.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_8: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_8_concurrency() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for process type definitions
  local proc_files=()
  [[ -f "$TARGET/Procfile" ]] && proc_files+=("$TARGET/Procfile")
  [[ -f "$TARGET/docker-compose.yml" ]] && proc_files+=("$TARGET/docker-compose.yml")
  [[ -f "$TARGET/docker-compose.yaml" ]] && proc_files+=("$TARGET/docker-compose.yaml")
  [[ -f "$TARGET/package.json" ]] && proc_files+=("$TARGET/package.json")

  local proc_types=""
  if [[ ${#proc_files[@]} -gt 0 ]]; then
    proc_types=$(grep -rn 'worker\|web_process\|process_type\|EC2\|Procfile\|CLUSTER_MODE\|concurrency' \
      "${proc_files[@]}" 2>/dev/null | head -10 || true)
  fi
  if [[ -n "$proc_types" ]]; then
    detail="Process types defined"
  else
    warnings+=("No process type definitions found")
  fi

  # Check for process manager deps
  if has_cmd jq && [[ -f "$TARGET/package.json" ]]; then
    local pm_deps
    pm_deps=$(jq -r '.dependencies // {} | to_entries[] | select(.key | test("pm2|forever|cluster|concurrently|nodemon|supervisor")) | "\(.key)"' "$TARGET/package.json" 2>/dev/null || true)
    if [[ -n "$pm_deps" ]]; then
      warnings+=("Process manager dependency: ${pm_deps}")
    fi
  fi

  # Check for scaling config (any .env* file at target root)
  local env_files=()
  shopt -s nullglob
  for ef in "$TARGET"/.env*; do
    [[ -f "$ef" ]] && env_files+=("$ef")
  done
  shopt -u nullglob

  local scaling=""
  if [[ ${#env_files[@]} -gt 0 ]]; then
    scaling=$(grep -rn 'NUM_WORKERS\|WEB_CONCURRENCY\|POOL_SIZE\|worker_count\|WORKERS' \
      "${env_files[@]}" 2>/dev/null | head -5 || true)
  fi
  if [[ -n "$scaling" ]]; then
    warnings+=("Scaling env vars found")
  fi

  # Check for daemonization
  local daemon=""
  if [[ -d "$TARGET/src" ]]; then
    daemon=$(grep -rn 'daemon\|fork\|pid.*file\|--daemon' \
      "$TARGET/src" 2>/dev/null | head -5 || true)
  fi
  if [[ -n "$daemon" ]]; then
    warnings+=("Daemonization detected — should use process manager")
    status="WARNING"
  fi

  if [[ "${#warnings[@]}" -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_8: ${status} - ${detail}"
}

factor_8_concurrency
exit 0
