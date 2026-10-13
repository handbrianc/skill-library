#!/usr/bin/env bash
# scan-12factor-factor-10.sh — Factor 10: Dev/prod parity
# Usage: ./scan-12factor-factor-10.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_10: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_10_dev_prod_parity() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for sqlite in dev (disparity flag)
  local manifests=()
  [[ -f "$TARGET/package.json" ]] && manifests+=("$TARGET/package.json")
  [[ -f "$TARGET/requirements.txt" ]] && manifests+=("$TARGET/requirements.txt")
  [[ -f "$TARGET/pyproject.toml" ]] && manifests+=("$TARGET/pyproject.toml")

  local sqlite=""
  if [[ ${#manifests[@]} -gt 0 ]]; then
    sqlite=$(grep -rn 'sqlite\|SQLite\|sqlite3' "${manifests[@]}" 2>/dev/null | head -5 || true)
  fi
  if [[ -n "$sqlite" ]]; then
    warnings+=("SQLite detected — verify production uses same DB type")
    status="WARNING"
  fi

  # Check for dev environment tooling
  if [[ -f "$TARGET/Dockerfile" || -f "$TARGET/docker-compose.yml" || -f "$TARGET/docker-compose.yaml" \
       || -f "$TARGET/Vagrantfile" || -d "$TARGET/.devcontainer" ]]; then
    warnings+=("Dev environment tooling found")
  else
    warnings+=("No Docker/Vagrant/DevContainer for environment parity")
  fi

  # Recent commit signal
  local commits_7d commits_30d
  commits_7d=$({ git -C "$TARGET" log --since='7 days ago' --oneline 2>/dev/null || true; } | awk 'END{print NR+0}')
  commits_30d=$({ git -C "$TARGET" log --since='30 days ago' --oneline 2>/dev/null || true; } | awk 'END{print NR+0}')
  warnings+=("${commits_7d} commits in 7d, ${commits_30d} commits in 30d")

  # Check for env-specific config
  local env_files=()
  shopt -s nullglob
  for ef in "$TARGET"/.env*; do
    [[ -f "$ef" ]] && env_files+=("$ef")
  done
  shopt -u nullglob

  local env_sep=""
  if [[ ${#env_files[@]} -gt 0 ]]; then
    env_sep=$(grep -rn 'NODE_ENV\|DJANGO_SETTINGS_MODULE\|APP_ENV\|RAILS_ENV\|GO_ENV' \
      "${env_files[@]}" 2>/dev/null | head -10 || true)
  fi
  if [[ -z "$env_sep" && -d "$TARGET/src" ]]; then
    env_sep=$(grep -rn 'NODE_ENV\|DJANGO_SETTINGS_MODULE\|APP_ENV\|RAILS_ENV\|GO_ENV' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -10 || true)
  fi
  if [[ -z "$env_sep" ]]; then
    warnings+=("No env-specific config patterns found")
  fi

  detail="${warnings[*]}"

  echo "FACTOR_10: ${status} - ${detail}"
}

factor_10_dev_prod_parity
exit 0
