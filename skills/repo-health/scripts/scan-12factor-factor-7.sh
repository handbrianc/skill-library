#!/usr/bin/env bash
# scan-12factor-factor-7.sh — Factor 7: Port binding
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_7_port_binding() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for self-contained server
  local server
  server=$(grep -rn 'listen\|\.createServer\|\.run(' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -5 || true)
  if [[ -n "$server" ]]; then
    detail="Self-contained server detected"
  else
    detail="No self-contained server found"
    status="WARNING"
  fi

  # Check for PORT env var
  local port_env
  port_env=$(grep -rn 'PORT\|process\.env\.PORT\|os\.getenv.*PORT' \
    src/ --include='*.ts' --include='*.js' --include='*.py' 2>/dev/null | head -5 || true)
  if [[ -n "$port_env" ]]; then
    warnings+=("Port configurable via env var")
  else
    warnings+=("Port may not be configurable via env var")
  fi

  # Check for hardcoded ports
  local hardcoded_port
  hardcoded_port=$(grep -rn 'port.*=\s*[0-9]\{4,5\}\|listen(:[0-9]\{4,5\})\|\.run([0-9]\{4,5\})' \
    src/ --include='*.ts' --include='*.js' --include='*.py' 2>/dev/null | head -5 || true)
  if [[ -n "$hardcoded_port" ]]; then
    warnings+=("Hardcoded port detected (use PORT env var instead)")
    status="FAIL"
  fi

  if [[ "${#warnings[@]}" -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_7: ${status} - ${detail}"
}

factor_7_port_binding
exit 0
