#!/usr/bin/env bash
# scan-12factor-factor-6.sh — Factor 6: Processes
# Usage: ./scan-12factor-factor-6.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_6: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_6_processes() {
  local detail=""
  local status="PASS"
  local warnings=()
  local src_scanned="no"

  # Check for local state / session usage
  local session_usage=""
  if [[ -d "$TARGET/src" ]]; then
    src_scanned="yes"
    session_usage=$(grep -rn 'session\|\.cache\|localstorage\|\/tmp\/\|\/var\/tmp' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | \
      grep -vE 'test|mock|spec' | head -5 || true)
  fi
  if [[ -n "$session_usage" ]]; then
    warnings+=("Local state/session usage detected")
  fi

  # Check for filesystem writes
  local fs_writes=""
  if [[ "$src_scanned" = "yes" ]]; then
    fs_writes=$(grep -rn 'writeFileSync\|writeFile\|fs\.write\|open.*w' \
      "$TARGET/src" --include='*.js' --include='*.ts' 2>/dev/null | \
      grep -vE 'test|mock|spec|log' | head -5 || true)
  fi
  if [[ -n "$fs_writes" ]]; then
    warnings+=("Filesystem writes detected")
  fi

  # Check for sticky sessions
  local sticky=""
  if [[ "$src_scanned" = "yes" ]]; then
    sticky=$(grep -rn 'sticky\|sticky-session\|cluster.*sticky\|ip_hash' \
      "$TARGET/src" 2>/dev/null | head -5 || true)
  fi
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

  if [[ "$src_scanned" != "yes" ]]; then
    detail+=" | N/A note: no src/ directory found to inspect"
  fi

  echo "FACTOR_6: ${status} - ${detail}"
}

factor_6_processes
exit 0
