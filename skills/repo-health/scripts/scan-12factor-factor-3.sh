#!/usr/bin/env bash
# scan-12factor-factor-3.sh — Factor 3: Config
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_3_config() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for .env.example or config template
  if has_files ".env.example" || has_files ".env.template" || \
     has_files ".env.sample" || has_files "config/.env.example" || \
     has_files "env.example"; then
    detail="Config template found"
  else
    detail="No env var documentation template"
    warnings+=("Missing .env.example")
  fi

  # Check for env var usage in source code
  local env_usage
  env_usage=$(find src/ -type f \( -name '*.js' -o -name '*.ts' -o -name '*.py' \) \
    2>/dev/null | head -20 | xargs grep -l 'process\.env\.\|os\.getenv\|os\.environ\[' 2>/dev/null || true)
  if [[ -n "$env_usage" ]]; then
    warnings+=("Env var reads detected in code")
  else
    warnings+=("No env var reads detected — config may be hardcoded")
  fi

  # Check for hardcoded service addresses
  local hardcoded
  hardcoded=$(grep -rn 'localhost\b.*3306\|localhost\b.*5432\|localhost\b.*6379\|localhost\b.*27017' \
    src/ --include='*.js' --include='*.ts' --include='*.py' --include='*.yaml' --include='*.yml' \
    2>/dev/null | head -5 || true)
  if [[ -n "$hardcoded" ]]; then
    warnings+=("Hardcoded service addresses found")
    status="FAIL"
  fi

  # Check .env tracked in VCS
  if git ls-files --error-unmatch .env &>/dev/null 2>&1; then
    warnings+=(".env tracked in git — secrets may be exposed")
    status="FAIL"
  fi

  if [[ ${#warnings[@]} -eq 0 ]]; then
    detail="Config looks clean"
  else
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    if [[ "$status" = "PASS" ]]; then
      status="WARNING"
    fi
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_3: ${status} - ${detail}"
}

factor_3_config
exit 0
