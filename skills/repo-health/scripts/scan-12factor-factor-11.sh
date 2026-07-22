#!/usr/bin/env bash
# scan-12factor-factor-11.sh — Factor 11: Logs
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_11_logs() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for stdout-based logging
  local logging
  logging=$(grep -rn 'console\.log\|logger\.info\|logger\.error\|logging\.info\|print(' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -20 || true)
  if [[ -n "$logging" ]]; then
    detail="Logging output detected"
  else
    detail="No logging output found"
  fi

  # Check for logfile management in app code (anti-pattern)
  local logfile_ap
  logfile_ap=$(grep -rn 'fs\.createWriteStream\|fs\.appendFileSync.*log\|logfile\|LogFileName\|FileHandler' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -10 || true)
  if [[ -n "$logfile_ap" ]]; then
    warnings+=("App manages log files directly — VIOLATION")
    status="FAIL"
  fi

  # Check for structured logging libraries
  local structured
  structured=$(grep -rn 'JSON\.stringify.*level\|"level":\|structured\|pino\|winston\|bunyan\|logfmt' \
    package.json src/ 2>/dev/null | head -10 || true)
  if [[ -n "$structured" ]]; then
    warnings+=("Structured logger detected")
  fi

  # Check for log routing config
  if ls logstash* fluent* vector* filebeat* rsyslog* syslog-ng* 2>/dev/null | head -1 >/dev/null 2>&1; then
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
