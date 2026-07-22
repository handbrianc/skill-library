#!/usr/bin/env bash
# lib/common.sh — Shared utilities for repo-health scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMEOUT_CMD=""
if command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout"
fi
has_cmd() { command -v "$1" &>/dev/null; }
has_files() {
  local pat="$1"
  ls $pat 2>/dev/null | head -1 >/dev/null 2>&1
}
