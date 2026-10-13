#!/usr/bin/env bash
# scan-12factor-factor-4.sh — Factor 4: Backing services
# Usage: ./scan-12factor-factor-4.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_4: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_4_backing_services() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Detect backing service dependencies (only in manifests that exist)
  local manifests=()
  local m
  for m in package.json pyproject.toml Cargo.toml go.mod requirements.txt; do
    [[ -f "$TARGET/$m" ]] && manifests+=("$TARGET/$m")
  done
  local backing_deps=""
  if [[ ${#manifests[@]} -gt 0 ]]; then
    backing_deps=$(grep -rn 'mysql\|postgres\|redis\|mongodb\|rabbitmq\|memcached\|elasticsearch\|s3\|sqs\|kafka\|nats' \
      "${manifests[@]}" 2>/dev/null | head -10 || true)
  fi
  if [[ -n "$backing_deps" ]]; then
    warnings+=("Backing service dependencies detected")
  fi

  # Check for env var based service URLs
  local url_usage=""
  if [[ -d "$TARGET/src" ]]; then
    url_usage=$(grep -rn 'process\.env\.\w*_URL\|process\.env\.DATABASE_URL\|process\.env\.REDIS_URL\|process\.env\..*_HOST\|os\.getenv.*_URL\|os\.environ\[.*_URL\|os\.getenv.*_HOST' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -10 || true)
  fi
  if [[ -n "$url_usage" ]]; then
    detail="Services accessed via config URL"
  else
    warnings+=("No env var based service URLs found")
  fi

  # Check for hardcoded connection patterns
  local hardcoded_conn=""
  if [[ -d "$TARGET/src" ]]; then
    hardcoded_conn=$(grep -rn 'new\s.*Client\|create.*Connection\|connect(' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | \
      grep -iE 'url|host|port|endpoint' | head -10 || true)
  fi
  if [[ -n "$hardcoded_conn" ]]; then
    warnings+=("Connection patterns found — verify env var usage")
  fi

  if [[ ${#warnings[@]} -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    [[ "$status" = "PASS" ]] && status="WARNING"
    detail="${detail}${sep}${warnings[*]}"
  fi

  # If nothing at all found, mark as N/A
  if [[ -z "$detail" ]]; then
    detail="No backing service references found — N/A for this project"
  fi

  echo "FACTOR_4: ${status} - ${detail}"
}

factor_4_backing_services
exit 0
