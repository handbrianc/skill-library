#!/usr/bin/env bash
# scan-12factor-factor-9.sh — Factor 9: Disposability
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

factor_9_disposability() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Startup time check — use timeout-safe approach
  if [[ -z "$TIMEOUT_CMD" ]]; then
    warnings+=("No timeout command available (install coreutils on macOS or util-linux on Linux)")
  else
    if has_files "src/index.ts" || has_files "src/index.js" || has_files "src/app.ts" || has_files "src/app.py"; then
      warnings+=("Entry point found")

      if has_cmd node && (has_files "src/index.ts" || has_files "src/index.js" || has_files "src/app.ts"); then
        # Determine entry point
        local entry="src/index.js"
        [[ -f "src/index.ts" ]] && entry="src/index.ts"
        [[ -f "src/app.ts" ]] && entry="src/app.ts"
        [[ -f "src/index.js" ]] && entry="src/index.js"

        if $TIMEOUT_CMD 5 node -e "
          try {
            require('./$entry');
            process.exit(0);
          } catch(e) {
            process.exit(0);
          }
        " &>/dev/null; then
          warnings+=("Node cold start completed within 5s")
        else
          warnings+=("Node cold start >5s or timed out")
        fi
      fi

      if has_cmd python3 && ls src/*.py 2>/dev/null | head -1 >/dev/null 2>&1; then
        local py_module=""
        [[ -f "src/app.py" ]] && py_module="app"
        [[ -f "src/main.py" ]] && py_module="main"

        if [[ -n "$py_module" ]]; then
          if $TIMEOUT_CMD 5 python3 -c "
import sys
sys.path.insert(0, 'src')
try:
    import $py_module
except Exception:
    pass
" 2>/dev/null; then
            warnings+=("Python cold start completed within 5s")
          else
            warnings+=("Python cold start >5s or timed out")
          fi
        fi
      fi
    fi
  fi

  # Check for SIGTERM handling
  local sigterm
  sigterm=$(grep -rn 'SIGTERM\|SIGINT\|process\.on.*exit\|graceful.*shut\|cleanup\|shutdown' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -10 || true)
  if [[ -n "$sigterm" ]]; then
    warnings+=("Graceful shutdown detected")
  else
    warnings+=("No graceful shutdown handler found")
    status="WARNING"
  fi

  # Check for crash robustness
  local retry
  retry=$(grep -rn 'retry\|idempotent\|reentrant\|transactional\|NACK\|reconnect' \
    src/ --include='*.js' --include='*.ts' --include='*.py' --include='*.go' 2>/dev/null | head -10 || true)
  if [[ -n "$retry" ]]; then
    warnings+=("Retry/idempotency patterns detected")
  fi

  # Check for connection draining
  local drain
  drain=$(grep -rn 'drain\|close.*connection\|close.*server\|keep-alive.*timeout' \
    src/ --include='*.js' --include='*.ts' 2>/dev/null | head -10 || true)
  if [[ -n "$drain" ]]; then
    warnings+=("Connection draining detected")
  fi

  detail="${warnings[*]}"

  echo "FACTOR_9: ${status} - ${detail}"
}

factor_9_disposability
exit 0
