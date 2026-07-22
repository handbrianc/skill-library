#!/usr/bin/env bash
# scan-12factor.sh — Twelve-Factor App Compliance Scanner
#
# Evaluates a project's adherence to the 12-Factor App methodology.
# Each factor outputs: FACTOR_[N]: [PASS|FAIL|WARNING] - detail
#
# Usage: ./scan-12factor.sh
# Exit 0 always — findings are data, not script failures.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

echo "=== 12-FACTOR APP COMPLIANCE SCAN ==="
echo "REPO: $REPO_ROOT"
echo ""

# ======================================================
# FACTOR 1: Codebase
# ======================================================
factor_1_codebase() {
  local detail=""
  local status="PASS"

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    detail="No VCS detected — every project should use version control"
    status="FAIL"
  else
    local remote
    remote=$(git remote get-url origin 2>/dev/null || echo "no remote")
    detail="git repo detected (${remote})"

    # Check for monorepo workspaces
    if has_cmd jq && [[ -f "package.json" ]]; then
      local workspaces
      workspaces=$(jq -r '.workspaces // .packages // empty' package.json 2>/dev/null)
      if [[ -n "$workspaces" ]]; then
        detail+=" — monorepo workspaces detected"
      fi
    fi

    local remote_count
    remote_count=$(git remote -v 2>/dev/null | wc -l)
    detail+=" | remotes: ${remote_count}"
  fi

  echo "FACTOR_1: ${status} - ${detail}"
}

# ======================================================
# FACTOR 2: Dependencies
# ======================================================
factor_2_dependencies() {
  local detail=""
  local status="PASS"

  local manifest_found=false
  local lockfile_found=false

  # Check manifest files
  if has_files "package.json" || has_files "yarn.lock" || has_files "pnpm-lock.yaml" || \
     has_files "requirements.txt" || has_files "pyproject.toml" || \
     has_files "Cargo.toml" || has_files "go.mod" || \
     has_files "Gemfile" || has_files "composer.json"; then
    manifest_found=true
    detail="Manifest found"
  else
    detail="No dependency manifest found"
    status="FAIL"
  fi

  # Check lockfiles
  if has_files "package-lock.json" || has_files "yarn.lock" || has_files "pnpm-lock.yaml" || \
     has_files "Cargo.lock" || has_files "Gemfile.lock" || \
     has_files "composer.lock" || has_files "poetry.lock"; then
    lockfile_found=true
    detail+=" | Lockfile present"
  else
    detail+=" | WARNING: No lockfile — dependencies not pinned"
    if [[ "$status" = "PASS" ]]; then
      status="WARNING"
    fi
  fi

  if ! $manifest_found; then
    status="FAIL"
  fi

  echo "FACTOR_2: ${status} - ${detail}"
}

# ======================================================
# FACTOR 3: Config
# ======================================================
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

# ======================================================
# FACTOR 4: Backing services
# ======================================================
factor_4_backing_services() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Detect backing service dependencies
  local backing_deps
  backing_deps=$(grep -rn 'mysql\|postgres\|redis\|mongodb\|rabbitmq\|memcached\|elasticsearch\|s3\|sqs\|kafka\|nats' \
    package.json pyproject.toml Cargo.toml go.mod 2>/dev/null | head -10 || true)
  if [[ -n "$backing_deps" ]]; then
    warnings+=("Backing service dependencies detected")
  fi

  # Check for env var based service URLs
  local url_usage
  url_usage=$(grep -rn 'process\.env\.\w*_URL\|process\.env\.DATABASE_URL\|process\.env\.REDIS_URL\|process\.env\..*_HOST' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -10 || true)
  if [[ -n "$url_usage" ]]; then
    detail="Services accessed via config URL"
  else
    warnings+=("No env var based service URLs found")
  fi

  # Check for hardcoded connection patterns
  local hardcoded_conn
  hardcoded_conn=$(grep -rn 'new\s.*Client\|create.*Connection\|connect(' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | \
    grep -iE 'url|host|port|endpoint' | head -10 || true)
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

# ======================================================
# FACTOR 5: Build, release, run
# ======================================================
factor_5_build_release_run() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for build step
  if has_cmd jq && [[ -f "package.json" ]]; then
    local build_scripts
    build_scripts=$(jq -r '.scripts | to_entries[] | select(.key | test("build|compile|bundle|dist")) | "\(.key): \(.value)"' package.json 2>/dev/null || true)
    if [[ -n "$build_scripts" ]]; then
      detail="Build step defined: ${build_scripts}"
    else
      warnings+=("No build step defined in package.json")
    fi
  fi

  # Check for CI/CD configuration
  if ls .github/workflows/ .circleci/ .gitlab-ci.yml Jenkinsfile 2>/dev/null | head -1 >/dev/null 2>&1; then
    warnings+=("CI/CD detected")
  else
    warnings+=("No CI/CD config found")
  fi

  # Check for release tagging
  local release_tags
  release_tags=$(git tag -l 'v*' --sort=-v:refname 2>/dev/null | head -5 || true)
  if [[ -n "$release_tags" ]]; then
    warnings+=("Release tags found: $(echo "$release_tags" | tr '\n' ' ')")
  else
    warnings+=("No release tags found")
  fi

  # Check for rollback mechanism
  local rollback
  rollback=$(grep -rn 'rollback\|revert\|canary\|blue.green\|v[0-9]\+\.[0-9]' \
    .github/workflows/ .circleci/ 2>/dev/null | head -5 || true)
  if [[ -z "$rollback" ]]; then
    warnings+=("No explicit rollback mechanism detected")
  fi

  if [[ ${#warnings[@]} -gt 0 ]]; then
    status="WARNING"
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_5: ${status} - ${detail}"
}

# ======================================================
# FACTOR 6: Processes
# ======================================================
factor_6_processes() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for local state / session usage
  local session_usage
  session_usage=$(grep -rn 'session\|\.cache\|localstorage\|\/tmp\/\|\/var\/tmp' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | \
    grep -vE 'test|mock|spec' | head -5 || true)
  if [[ -n "$session_usage" ]]; then
    warnings+=("Local state/session usage detected")
  fi

  # Check for filesystem writes
  local fs_writes
  fs_writes=$(grep -rn 'writeFileSync\|writeFile\|fs\.write\|open.*w' \
    src/ --include='*.js' --include='*.ts' 2>/dev/null | \
    grep -vE 'test|mock|spec|log' | head -5 || true)
  if [[ -n "$fs_writes" ]]; then
    warnings+=("Filesystem writes detected")
  fi

  # Check for sticky sessions
  local sticky
  sticky=$(grep -rn 'sticky\|sticky-session\|cluster.*sticky\|ip_hash' \
    src/ 2>/dev/null | head -5 || true)
  if [[ -n "$sticky" ]]; then
    warnings+=("Sticky session patterns detected — VIOLATION")
    status="FAIL"
  fi

  if [[ ${#warnings[@]} -gt 0 ]]; then
    [[ "$status" = "PASS" ]] && status="WARNING"
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  else
    detail="No local state or sticky sessions detected"
  fi

  echo "FACTOR_6: ${status} - ${detail}"
}

# ======================================================
# FACTOR 7: Port binding
# ======================================================
factor_7_port_binding() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for self-contained server
  local server
  server=$(grep -rn 'listen\|\.createServer\|\.run(' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -5 || true)
  if [[ -n "$server" ]]; then
    detail="Self-contained server detected"
  else
    detail="No self-contained server found"
    status="WARNING"
  fi

  # Check for PORT env var
  local port_env
  port_env=$(grep -rn 'PORT\|process\.env\.PORT\|os\.getenv.*PORT' \
    src/ --include='*.ts' --include='*.js' --include='*.py' 2>/dev/null | head -5 || true)
  if [[ -n "$port_env" ]]; then
    warnings+=("Port configurable via env var")
  else
    warnings+=("Port may not be configurable via env var")
  fi

  # Check for hardcoded ports
  local hardcoded_port
  hardcoded_port=$(grep -rn 'port.*=\s*[0-9]\{4,5\}\|listen(:[0-9]\{4,5\})\|\.run([0-9]\{4,5\})' \
    src/ --include='*.ts' --include='*.js' --include='*.py' 2>/dev/null | head -5 || true)
  if [[ -n "$hardcoded_port" ]]; then
    warnings+=("Hardcoded port detected (use PORT env var instead)")
    status="FAIL"
  fi

  if [[ "${#warnings[@]}" -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_7: ${status} - ${detail}"
}

# ======================================================
# FACTOR 8: Concurrency
# ======================================================
factor_8_concurrency() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for process type definitions
  local proc_types
  proc_types=$(grep -rn 'worker\|web_process\|process_type\|EC2\|Procfile\|CLUSTER_MODE\|concurrency' \
    Procfile docker-compose.yml package.json 2>/dev/null | head -10 || true)
  if [[ -n "$proc_types" ]]; then
    detail="Process types defined"
  else
    warnings+=("No process type definitions found")
  fi

  # Check for process manager deps
  if has_cmd jq && [[ -f "package.json" ]]; then
    local pm_deps
    pm_deps=$(jq -r '.dependencies // {} | to_entries[] | select(.key | test("pm2|forever|cluster|concurrently|nodemon|supervisor")) | "\(.key)"' package.json 2>/dev/null || true)
    if [[ -n "$pm_deps" ]]; then
      warnings+=("Process manager dependency: ${pm_deps}")
    fi
  fi

  # Check for scaling config
  local scaling
  scaling=$(grep -rn 'NUM_WORKERS\|WEB_CONCURRENCY\|POOL_SIZE\|worker_count\|WORKERS' \
    .env* .env.example 2>/dev/null | head -5 || true)
  if [[ -n "$scaling" ]]; then
    warnings+=("Scaling env vars found")
  fi

  # Check for daemonization
  local daemon
  daemon=$(grep -rn 'daemon\|fork\|pid.*file\|--daemon' \
    src/ 2>/dev/null | head -5 || true)
  if [[ -n "$daemon" ]]; then
    warnings+=("Daemonization detected — should use process manager")
    status="WARNING"
  fi

  if [[ "${#warnings[@]}" -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_8: ${status} - ${detail}"
}

# ======================================================
# FACTOR 9: Disposability
# ======================================================
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

# ======================================================
# FACTOR 10: Dev/prod parity
# ======================================================
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

# ======================================================
# FACTOR 11: Logs
# ======================================================
factor_11_logs() {
  local detail=""
  local status="PASS"
  local warnings=()

  # Check for stdout-based logging
  local logging
  logging=$(grep -rn 'console\.log\|logger\.info\|logger\.error\|logging\.info\|print(' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -20 || true)
  if [[ -n "$logging" ]]; then
    detail="Logging output detected"
  else
    detail="No logging output found"
  fi

  # Check for logfile management in app code (anti-pattern)
  local logfile_ap
  logfile_ap=$(grep -rn 'fs\.createWriteStream\|fs\.appendFileSync.*log\|logfile\|LogFileName\|FileHandler' \
    src/ --include='*.js' --include='*.ts' --include='*.py' 2>/dev/null | head -10 || true)
  if [[ -n "$logfile_ap" ]]; then
    warnings+=("App manages log files directly — VIOLATION")
    status="FAIL"
  fi

  # Check for structured logging libraries
  local structured
  structured=$(grep -rn 'JSON\.stringify.*level\|"level":\|structured\|pino\|winston\|bunyan\|logfmt' \
    package.json src/ 2>/dev/null | head -10 || true)
  if [[ -n "$structured" ]]; then
    warnings+=("Structured logger detected")
  fi

  # Check for log routing config
  if ls logstash* fluent* vector* filebeat* rsyslog* syslog-ng* 2>/dev/null | head -1 >/dev/null 2>&1; then
    warnings+=("Log routing config found")
  fi

  if [[ "${#warnings[@]}" -gt 0 ]]; then
    local sep=" "
    [[ -n "$detail" ]] && sep=" | "
    detail="${detail}${sep}${warnings[*]}"
  fi

  echo "FACTOR_11: ${status} - ${detail}"
}

# ======================================================
# FACTOR 12: Admin processes
# ======================================================
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

# ======================================================
# FACTOR 13: Report (Step 9.13)
# ======================================================
factor_13_report() {
  echo ""
  echo "=== 12-FACTOR COMPLIANCE SUMMARY ==="
  echo ""
  echo "| Factor | Status | Detail |"
  echo "| ------ | ------ | ------ |"

  # Re-run all factors to capture output
  local results=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^FACTOR_[0-9]+: ]]; then
      results+=("$line")
    fi
  done < <(
    factor_1_codebase
    factor_2_dependencies
    factor_3_config
    factor_4_backing_services
    factor_5_build_release_run
    factor_6_processes
    factor_7_port_binding
    factor_8_concurrency
    factor_9_disposability
    factor_10_dev_prod_parity
    factor_11_logs
    factor_12_admin_processes
  )

  local fail_count=0
  local warn_count=0

  for r in "${results[@]}"; do
    # Extract factor number and status
    local factor_num
    factor_num=$(echo "$r" | sed 's/^FACTOR_\([0-9]*\):.*/\1/')
    local factor_status
    factor_status=$(echo "$r" | sed 's/^FACTOR_[0-9]*: \([A-Z]*\) -.*/\1/')
    local factor_detail
    factor_detail=$(echo "$r" | sed 's/^FACTOR_[0-9]*: [A-Z]* - //')

    local icon
    case "$factor_status" in
      PASS)    icon="✅" ;;
      FAIL)    icon="❌"; fail_count=$((fail_count + 1)) ;;
      WARNING) icon="⚠️"; warn_count=$((warn_count + 1)) ;;
      *)       icon="❓" ;;
    esac

    # Map factor number to name
    local factor_name=""
    case "$factor_num" in
      1)  factor_name="I. Codebase" ;;
      2)  factor_name="II. Dependencies" ;;
      3)  factor_name="III. Config" ;;
      4)  factor_name="IV. Backing services" ;;
      5)  factor_name="V. Build, release, run" ;;
      6)  factor_name="VI. Processes" ;;
      7)  factor_name="VII. Port binding" ;;
      8)  factor_name="VIII. Concurrency" ;;
      9)  factor_name="IX. Disposability" ;;
      10) factor_name="X. Dev/prod parity" ;;
      11) factor_name="XI. Logs" ;;
      12) factor_name="XII. Admin processes" ;;
    esac

    echo "| ${factor_name} | ${icon} ${factor_status} | ${factor_detail} |"
  done

  echo ""
  echo "SUMMARY: ${fail_count} FAIL, ${warn_count} WARNING across 12 factors"
  echo "FACTOR_13: PASS - Compliance report generated"
}

# ======================================================
# Main
# ======================================================

case "${1:-}" in
  --help|-h)
    echo "Usage: $0"
    echo "Evaluates Twelve-Factor App compliance."
    echo "Outputs FACTOR_[N]: [PASS|FAIL|WARNING] - detail for each factor."
    echo "Exit 0 always."
    exit 0
    ;;
esac

# Run all 12 factors + report
factor_1_codebase
factor_2_dependencies
factor_3_config
factor_4_backing_services
factor_5_build_release_run
factor_6_processes
factor_7_port_binding
factor_8_concurrency
factor_9_disposability
factor_10_dev_prod_parity
factor_11_logs
factor_12_admin_processes
factor_13_report

exit 0
