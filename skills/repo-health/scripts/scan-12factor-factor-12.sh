#!/usr/bin/env bash
# scan-12factor-factor-12.sh — Factor 12: Admin processes
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_12_admin_processes() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for admin/management scripts
  if ls manage.py artisan rake bin/console Makefile script/ 2>/dev/null | head -1 >/dev/null 2>&1; then
    detail="Admin/management scripts found"
  else
    warnings+=("No admin/management scripts found")
  fi

  # Check for migration tooling
  local migrations
  migrations=$(grep -rn 'migrate\|migration\|schema\|db:migrate\|alembic\|prisma.*migrate\|typeorm.*migrate' \
    package.json pyproject.toml scripts/ Makefile 2>/dev/null | head -10 || true)
  if [[ -n "$migrations" ]]; then
    warnings+=("Database migration tooling found")
  fi

  # Check for npm script admin commands
  if has_cmd jq && [[ -f "package.json" ]]; then
    local admin_scripts
    admin_scripts=$(jq -r '.scripts | to_entries[] | select(.key | test("migrate|seed|console|shell|admin")) | "\(.key): \(.value)"' package.json 2>/dev/null || true)
    if [[ -n "$admin_scripts" ]]; then
      warnings+=("Admin scripts: ${admin_scripts}")
    fi
  fi

  if [[ "${#warnings[@]}" -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_12: ${status} - ${detail}"
}

factor_12_admin_processes
exit 0
