#!/usr/bin/env bash
# scan-12factor-factor-10.sh — Factor 10: Dev/prod parity
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_10_dev_prod_parity() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for sqlite in dev (disparity flag)
  local sqlite
  sqlite=$(grep -rn 'sqlite\|SQLite\|sqlite3' package.json requirements.txt 2>/dev/null | head -5 || true)
  if [[ -n "$sqlite" ]]; then
    warnings+=("SQLite detected — verify production uses same DB type")
    status="WARNING"
  fi

  # Check for dev environment tooling
  if ls Dockerfile docker-compose.yml Vagrantfile .devcontainer/ 2>/dev/null | head -1 >/dev/null 2>&1; then
    warnings+=("Dev environment tooling found")
  else
    warnings+=("No Docker/Vagrant/DevContainer for environment parity")
  fi

  # Recent commit signal
  local commits_7d commits_30d
  commits_7d=$(git log --since='7 days ago' --oneline 2>/dev/null | wc -l)
  commits_30d=$(git log --since='30 days ago' --oneline 2>/dev/null | wc -l)
  warnings+=("${commits_7d} commits in 7d, ${commits_30d} commits in 30d")

  # Check for env-specific config
  local env_sep
  env_sep=$(grep -rn 'NODE_ENV\|DJANGO_SETTINGS_MODULE\|APP_ENV\|RAILS_ENV\|GO_ENV' \
    .env* src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -10 || true)
  if [[ -z "$env_sep" ]]; then
    warnings+=("No env-specific config patterns found")
  fi

  detail="${warnings[*]}"

  echo "FACTOR_10: ${status} - ${detail}"
}

factor_10_dev_prod_parity
exit 0
