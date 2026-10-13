#!/usr/bin/env bash
# scan-12factor-factor-11.sh — Factor 11: Logs
# Usage: ./scan-12factor-factor-11.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_11: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_11_logs() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for stdout-based logging
  local logging=""
  if [[ -d "$TARGET/src" ]]; then
    logging=$(grep -rn 'console\.log\|logger\.info\|logger\.error\|logging\.info\|print(' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -20 || true)
  fi
  if [[ -n "$logging" ]]; then
    detail="Logging output detected"
  else
    detail="No logging output found"
  fi

  # Check for logfile management in app code (anti-pattern)
  local logfile_ap=""
  if [[ -d "$TARGET/src" ]]; then
    logfile_ap=$(grep -rn 'fs\.createWriteStream\|fs\.appendFileSync.*log\|logfile\|LogFileName\|FileHandler' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -10 || true)
  fi
  if [[ -n "$logfile_ap" ]]; then
    warnings+=("App manages log files directly — VIOLATION")
    status="FAIL"
  fi

  # Check for structured logging libraries
  local structured_files=()
  [[ -f "$TARGET/package.json" ]] && structured_files+=("$TARGET/package.json")
  local structured=""
  if [[ -d "$TARGET/src" ]]; then
    structured=$(grep -rn 'JSON\.stringify.*level\|"level":\|structured\|pino\|winston\|bunyan\|logfmt' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -10 || true)
  fi
  if [[ ${#structured_files[@]} -gt 0 ]]; then
    structured+=$(grep -rn 'pino\|winston\|bunyan\|logfmt' "${structured_files[@]}" 2>/dev/null | head -5 || true)
  fi
  if [[ -n "$structured" ]]; then
    warnings+=("Structured logger detected")
  fi

  # Check for log routing config files at the target root
  local routing_found=false
  local pat
  for pat in 'logstash*' 'fluent*' 'vector*' 'filebeat*' 'rsyslog*' 'syslog-ng*'; do
    if compgen -G "$TARGET/$pat" >/dev/null; then
      routing_found=true
      break
    fi
  done
  if [[ "$routing_found" = true ]]; then
    warnings+=("Log routing config found")
  fi

  if [[ "${#warnings[@]}" -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_11: ${status} - ${detail}"
}

factor_11_logs
exit 0
