#!/usr/bin/env bash
# scan-12factor-factor-3.sh — Factor 3: Config
# Usage: ./scan-12factor-factor-3.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_3: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_3_config() {
  local detail=""
  local status="PASS"
  local warnings=()
  local notes=()

  # Check for .env.example or config template
  if [[ -f "$TARGET/.env.example" || -f "$TARGET/.env.template" || -f "$TARGET/.env.sample" \
        || -f "$TARGET/config/.env.example" || -f "$TARGET/env.example" ]]; then
    detail="Config template found"
  else
    detail="No env var documentation template"
    warnings+=("Missing .env.example")
  fi

  # Check for env var usage in source code
  local env_usage=""
  if [[ -d "$TARGET/src" ]]; then
    env_usage=$(grep -rlE 'process\.env\.|os\.getenv\(|os\.environ' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -5 || true)
  fi
  if [[ -n "$env_usage" ]]; then
    # 12-factor: config read from environment is the compliant behaviour
    notes+=("Env var reads detected in code (12-factor compliant)")
  else
    warnings+=("No env var reads detected — config may be hardcoded")
  fi

  # Check for hardcoded service addresses
  local hardcoded=""
  if [[ -d "$TARGET/src" ]]; then
    hardcoded=$(grep -rn 'localhost\b.*3306\|localhost\b.*5432\|localhost\b.*6379\|localhost\b.*27017' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' --include='*.yaml' --include='*.yml' \
      2>/dev/null | head -5 || true)
  fi
  if [[ -n "$hardcoded" ]]; then
    warnings+=("Hardcoded service addresses found")
    status="FAIL"
  fi

  # Check .env tracked in VCS
  if git -C "$TARGET" ls-files --error-unmatch .env &>/dev/null 2>&1; then
    warnings+=(".env tracked in git — secrets may be exposed")
    status="FAIL"
  fi

  if [[ ${#warnings[@]} -eq 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    if [[ ${#notes[@]} -gt 0 ]]; then
      detail="${detail}${sep}${notes[*]}"
    else
      detail="Config looks clean"
    fi
  else
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    if [[ "$status" = "PASS" ]]; then
      status="WARNING"
    fi
    detail="${detail}${sep}${warnings[*]}"
    [[ ${#notes[@]} -gt 0 ]] && detail+=" | ${notes[*]}"
  fi

  echo "FACTOR_3: ${status} - ${detail}"
}

factor_3_config
exit 0
