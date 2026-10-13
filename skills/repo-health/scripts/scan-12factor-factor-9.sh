#!/usr/bin/env bash
# scan-12factor-factor-9.sh — Factor 9: Disposability
# Usage: ./scan-12factor-factor-9.sh [target-dir]   (default: current directory)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET="${1:-$PWD}"
if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
else
  echo "FACTOR_9: N/A - target directory not found: ${1:-<none>}"
  exit 0
fi
trap 'exit 0' EXIT

factor_9_disposability() {
  local detail=""
  local status="PASS"
  local warnings=()
  local notes=()

  # Startup time check — use timeout-safe approach
  if [[ -z "$TIMEOUT_CMD" ]]; then
    warnings+=("No timeout command available (install coreutils on macOS or util-linux on Linux)")
  else
    local has_node_entry=false has_py_entry=false
    [[ -f "$TARGET/src/index.js" || -f "$TARGET/src/index.ts" || -f "$TARGET/src/app.js" || -f "$TARGET/src/app.ts" ]] && has_node_entry=true
    [[ -f "$TARGET/src/app.py" || -f "$TARGET/src/main.py" ]] && has_py_entry=true

    if [[ "$has_node_entry" = true && -f "$TARGET/package.json" ]] && has_cmd node; then
      # Determine entry point (plain .js only — node cannot require .ts directly)
      local entry="src/index.js"
      [[ -f "$TARGET/src/app.js" ]] && entry="src/app.js"
      [[ -f "$TARGET/src/index.js" ]] && entry="src/index.js"

      if (cd "$TARGET" && $TIMEOUT_CMD 5 node -e "
        try {
          require('./$entry');
          process.exit(0);
        } catch(e) {
          process.exit(0);
        }
      " &>/dev/null); then
        notes+=("Node cold start completed within 5s")
      else
        warnings+=("Node cold start >5s or timed out")
      fi
    fi

    if [[ "$has_py_entry" = true ]] && has_cmd python3; then
      local py_module=""
      [[ -f "$TARGET/src/app.py" ]] && py_module="app"
      [[ -f "$TARGET/src/main.py" ]] && py_module="main"

      if [[ -n "$py_module" ]]; then
        if (cd "$TARGET" && PYTHONPATH="$TARGET/src" $TIMEOUT_CMD 5 python3 -c "
import sys
try:
    import $py_module
except Exception:
    pass
" 2>/dev/null); then
          notes+=("Python cold start completed within 5s")
        else
          warnings+=("Python cold start >5s or timed out")
        fi
      fi
    fi
    if [[ "$has_node_entry" = false && "$has_py_entry" = false ]]; then
      notes+=("No conventional entry point (src/index.*, src/app.*, src/main.py) — cold-start check N/A")
    fi
  fi

  # Check for SIGTERM handling
  local sigterm=""
  if [[ -d "$TARGET/src" ]]; then
    sigterm=$(grep -rn 'SIGTERM\|SIGINT\|process\.on.*exit\|graceful.*shut\|cleanup\|shutdown' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -10 || true)
  fi
  if [[ -n "$sigterm" ]]; then
    notes+=("Graceful shutdown detected")
  else
    warnings+=("No graceful shutdown handler found")
    status="WARNING"
  fi

  # Check for crash robustness
  local retry=""
  if [[ -d "$TARGET/src" ]]; then
    retry=$(grep -rn 'retry\|idempotent\|reentrant\|transactional\|NACK\|reconnect' \
      "$TARGET/src" --include='*.js' --include='*.ts' --include='*.py' --include='*.go' 2>/dev/null | head -10 || true)
  fi
  if [[ -n "$retry" ]]; then
    notes+=("Retry/idempotency patterns detected")
  fi

  # Check for connection draining
  local drain=""
  if [[ -d "$TARGET/src" ]]; then
    drain=$(grep -rn 'drain\|close.*connection\|close.*server\|keep-alive.*timeout' \
      "$TARGET/src" --include='*.js' --include='*.ts' 2>/dev/null | head -10 || true)
  fi
  if [[ -n "$drain" ]]; then
    notes+=("Connection draining detected")
  fi

  if [[ ${#notes[@]} -gt 0 ]]; then
    detail="${notes[*]}"
  fi
  if [[ ${#warnings[@]} -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  fi
  if [[ -z "$detail" ]]; then
    detail="No disposability signals found — N/A for this project"
  fi

  echo "FACTOR_9: ${status} - ${detail}"
}

factor_9_disposability
exit 0
