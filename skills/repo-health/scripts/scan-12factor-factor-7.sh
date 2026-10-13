#!/usr/bin/env bash
# scan-12factor-factor-7.sh — Factor 7: Port binding
# Usage: ./scan-12factor-factor-7.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_7: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_7_port_binding() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for self-contained server
  local server=""
  if [[ -d "$TARGET/src" ]]; then
    server=$(grep -rn 'listen\|\.createServer\|\.run(' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -5 || true)
  fi
  if [[ -n "$server" ]]; then
    detail="Self-contained server detected"
  else
    detail="No self-contained server found"
    status="WARNING"
  fi

  # Check for PORT env var (word-bounded to avoid matching "import"/"report")
  local port_env=""
  if [[ -d "$TARGET/src" ]]; then
    port_env=$(grep -rnE '\bPORT\b|process\.env\.PORT|os\.getenv.*PORT' \
      "$TARGET/src" --include='*.ts' --include='*.js' --include='*.py' 2>/dev/null | head -5 || true)
  fi
  if [[ -n "$port_env" ]]; then
    warnings+=("Port configurable via env var")
  else
    warnings+=("Port may not be configurable via env var")
  fi

  # Check for hardcoded ports
  local hardcoded_port=""
  if [[ -d "$TARGET/src" ]]; then
    hardcoded_port=$(grep -rnE 'port.*=\s*[0-9]\{4,5\}|listen\(:[0-9]\{4,5\}\)|\.run\([0-9]\{4,5\}\)' \
      "$TARGET/src" --include='*.ts' --include='*.js' --include='*.py' 2>/dev/null | head -5 || true)
  fi
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
