#!/usr/bin/env bash
# scan-12factor-factor-8.sh — Factor 8: Concurrency
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_8_concurrency() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for process type definitions
  local proc_types
  proc_types=$(grep -rn 'worker\|web_process\|process_type\|EC2\|Procfile\|CLUSTER_MODE\|concurrency' \
    Procfile docker-compose.yml package.json 2>/dev/null | head -10 || true)
  if [[ -n "$proc_types" ]]; then
    detail="Process types defined"
  else
    warnings+=("No process type definitions found")
  fi

  # Check for process manager deps
  if has_cmd jq && [[ -f "package.json" ]]; then
    local pm_deps
    pm_deps=$(jq -r '.dependencies // {} | to_entries[] | select(.key | test("pm2|forever|cluster|concurrently|nodemon|supervisor")) | "\(.key)"' package.json 2>/dev/null || true)
    if [[ -n "$pm_deps" ]]; then
      warnings+=("Process manager dependency: ${pm_deps}")
    fi
  fi

  # Check for scaling config
  local scaling
  scaling=$(grep -rn 'NUM_WORKERS\|WEB_CONCURRENCY\|POOL_SIZE\|worker_count\|WORKERS' \
    .env* .env.example 2>/dev/null | head -5 || true)
  if [[ -n "$scaling" ]]; then
    warnings+=("Scaling env vars found")
  fi

  # Check for daemonization
  local daemon
  daemon=$(grep -rn 'daemon\|fork\|pid.*file\|--daemon' \
    src/ 2>/dev/null | head -5 || true)
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
