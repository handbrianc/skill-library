#!/usr/bin/env bash
# scan-12factor-factor-12.sh — Factor 12: Admin processes
# Usage: ./scan-12factor-factor-12.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_12: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_12_admin_processes() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for admin/management scripts (guarded file tests on the target dir)
  local admin_entry=""
  if [[ -f "$TARGET/manage.py" ]]; then
    admin_entry="manage.py"
  elif [[ -f "$TARGET/artisan" ]]; then
    admin_entry="artisan"
  elif [[ -f "$TARGET/Rakefile" ]]; then
    admin_entry="Rakefile"
  elif [[ -f "$TARGET/bin/console" ]]; then
    admin_entry="bin/console"
  elif [[ -f "$TARGET/Makefile" ]]; then
    admin_entry="Makefile"
  elif [[ -d "$TARGET/script" || -d "$TARGET/scripts" ]]; then
    admin_entry="script(s)/ directory"
  fi

  if [[ -n "$admin_entry" ]]; then
    detail="Admin/management scripts found ($admin_entry)"
  else
    warnings+=("No admin/management scripts found")
  fi

  # Check for migration tooling
  local migration_files=()
  [[ -f "$TARGET/package.json" ]] && migration_files+=("$TARGET/package.json")
  [[ -f "$TARGET/pyproject.toml" ]] && migration_files+=("$TARGET/pyproject.toml")
  [[ -f "$TARGET/Makefile" ]] && migration_files+=("$TARGET/Makefile")
  local migrations=""
  if [[ ${#migration_files[@]} -gt 0 ]]; then
    migrations=$(grep -rn 'migrate\|migration\|schema\|db:migrate\|alembic\|prisma.*migrate\|typeorm.*migrate' \
      "${migration_files[@]}" 2>/dev/null | head -10 || true)
  fi
  if [[ -z "$migrations" && -d "$TARGET/scripts" ]]; then
    migrations=$(grep -rn 'migrate\|migration\|schema\|alembic' \
      "$TARGET/scripts" --include='*.sh' --include='*.py' 2>/dev/null | head -5 || true)
  fi
  if [[ -n "$migrations" ]]; then
    warnings+=("Database migration tooling found")
  fi

  # Check for npm script admin commands
  if has_cmd jq && [[ -f "$TARGET/package.json" ]]; then
    local admin_scripts
    admin_scripts=$(jq -r '.scripts | to_entries[] | select(.key | test("migrate|seed|console|shell|admin")) | "\(.key): \(.value)"' "$TARGET/package.json" 2>/dev/null || true)
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
