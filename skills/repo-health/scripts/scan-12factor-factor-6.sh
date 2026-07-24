#!/usr/bin/env bash
# scan-12factor-factor-6.sh — Factor 6: Processes
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_6_processes() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for local state / session usage
  local session_usage
  session_usage=$(grep -rn 'session\|\.cache\|localstorage\|\/tmp\/\|\/var\/tmp' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | \
    grep -vE 'test|mock|spec' | head -5 || true)
  if [[ -n "$session_usage" ]]; then
    warnings+=("Local state/session usage detected")
  fi

  # Check for filesystem writes
  local fs_writes
  fs_writes=$(grep -rn 'writeFileSync\|writeFile\|fs\.write\|open.*w' \
    src/ --include='*.js' --include='*.ts' 2>/dev/null | \
    grep -vE 'test|mock|spec|log' | head -5 || true)
  if [[ -n "$fs_writes" ]]; then
    warnings+=("Filesystem writes detected")
  fi

  # Check for sticky sessions
  local sticky
  sticky=$(grep -rn 'sticky\|sticky-session\|cluster.*sticky\|ip_hash' \
    src/ 2>/dev/null | head -5 || true)
  if [[ -n "$sticky" ]]; then
    warnings+=("Sticky session patterns detected — VIOLATION")
    status="FAIL"
  fi

  if [[ ${#warnings[@]} -gt 0 ]]; then
    [[ "$status" = "PASS" ]] && status="WARNING"
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  else
    detail="No local state or sticky sessions detected"
  fi

  echo "FACTOR_6: ${status} - ${detail}"
}

factor_6_processes
exit 0
