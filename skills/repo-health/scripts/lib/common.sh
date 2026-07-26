#!/usr/bin/env bash
set -euo pipefail
# lib/common.sh — Shared utilities for repo-health scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # used by consumers that source this library
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC2034 # used by consumers that source this library
TIMEOUT_CMD=""
if command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout"
fi
export TIMEOUT_CMD
has_cmd() { command -v "$1" &>/dev/null; }
has_files() {
  local pat="$1"
  ls $pat 2>/dev/null | head -1 >/dev/null 2>&1
}

# ---- Shared preamble for scan-tech-debt scripts -------------------------------
if [[ -t 1 ]]; then
  COMMON_BOLD='\033[1m'
  COMMON_GREEN='\033[0;32m'
  COMMON_YELLOW='\033[0;33m'
  COMMON_RED='\033[0;31m'
  COMMON_CYAN='\033[0;36m'
  COMMON_NC='\033[0m'
else
  COMMON_BOLD='' COMMON_GREEN='' COMMON_YELLOW='' COMMON_RED='' COMMON_CYAN='' COMMON_NC=''
fi

section() { echo -e "\n${COMMON_BOLD}${COMMON_CYAN}====${COMMON_NC} ${COMMON_BOLD}$*${COMMON_NC}${COMMON_BOLD}${COMMON_CYAN} ====${COMMON_NC}"; }
sub()     { echo -e "  ${COMMON_GREEN}$*${COMMON_NC}"; }
warn()    { echo -e "  ${COMMON_YELLOW}$*${COMMON_NC}"; }
err()     { echo -e "  ${COMMON_RED}$*${COMMON_NC}" >&2; }
kv()      { echo "  $1: $2"; }

# Count debt markers of a given keyword (case-insensitive grep)
count_markers() {
  local marker="$1" srcdir="${2:-src}"
  grep -rni "$marker" "$srcdir" \
    --include='*.js' --include='*.ts' --include='*.tsx' --include='*.jsx' \
    --include='*.py' --include='*.go' --include='*.rs' --include='*.java' \
    --include='*.rb' --include='*.php' --include='*.cs' --include='*.kt' \
    --include='*.swift' --include='*.dart' \
    2>/dev/null \
    | grep -v 'node_modules\|\.git\|/test/\|/tests/\|/spec/' \
    | grep -vic 'nocheck\|eslint-disable\|pragma' \
    | wc -l
}

# Safe bc arithmetic (returns 0 or value)
calc() {
  local expr="$1"
  echo "$expr" | bc 2>/dev/null || echo "0"
}
