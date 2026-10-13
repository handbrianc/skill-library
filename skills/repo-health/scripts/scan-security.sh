#!/usr/bin/env bash
#
# scan-security.sh
# Security review — vulnerability scan, static analysis, secrets, credential exposure.
# Covers PHASE 7 of the repo-health audit.
#
# Usage: ./scan-security.sh [--vuln-scan] [--secrets] [--credential-exposure]
#   No args = runs all checks.
#
# Target directory: $REPO_HEALTH_TARGET_DIR env override, else the current
# working directory.
#
# Multi-stack aware: Node projects get npm audit + ESLint security; Python
# projects get pip-audit + bandit; missing tools are reported as N/A with a
# rationale instead of silently skipping. A missing package.json no longer
# bails the whole scan.
#

set -euo pipefail

DO_VULN=false
DO_SECRETS=false
DO_CREDENTIALS=false

if [[ $# -eq 0 ]]; then
  DO_VULN=true
  DO_SECRETS=true
  DO_CREDENTIALS=true
else
  for arg in "$@"; do
    case "$arg" in
      --vuln-scan) DO_VULN=true ;;
      --secrets) DO_SECRETS=true ;;
      --credential-exposure) DO_CREDENTIALS=true ;;
      *) echo "Unknown option: $arg (ignored)" ;;
    esac
  done
fi

TARGET_DIR="${REPO_HEALTH_TARGET_DIR:-$PWD}"
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "SCAN_SECURITY_ERROR: target directory not found: $TARGET_DIR" >&2
  exit 1
fi
cd "$TARGET_DIR"
shopt -s nullglob

RUN_TIMEOUT="${REPO_HEALTH_TOOL_TIMEOUT:-600}"
run_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$RUN_TIMEOUT" "$@"
  else
    "$@"
  fi
}

# Project-local virtualenv python wins over PATH (matches project deps)
VENV_PY=""
for venv_dir in .venv venv; do
  if [[ -x "$venv_dir/bin/python" ]]; then VENV_PY="$venv_dir/bin/python"; break; fi
done
# venv-preferred tool resolution
find_tool() {
  local name="$1" cand
  for cand in .venv/bin/"$name" venv/bin/"$name"; do
    if [[ -x "$cand" ]]; then echo "$PWD/$cand"; return 0; fi
  done
  command -v "$name" 2>/dev/null || return 1
}

# Stack detection
HAS_NODE=false
HAS_PYTHON=false
if [[ -f package.json ]]; then HAS_NODE=true; fi
if [[ -f pyproject.toml || -f setup.py || -f setup.cfg ]]; then HAS_PYTHON=true; fi
if compgen -G 'requirements*.txt' >/dev/null 2>&1; then HAS_PYTHON=true; fi
echo "STACK: node=$HAS_NODE python=$HAS_PYTHON"

# Project-code target: src/ or lib/ or app/ if present, else repo root.
# Vendor/dependency trees (.venv, node_modules, site-packages, ...) are NEVER
# scanned as project code.
SRC_DIR="."
for d in src lib app; do
  if [[ -d "$d" ]]; then SRC_DIR="$d"; break; fi
done
echo "PROJECT_CODE_TARGET: $SRC_DIR"

# Step 7.1 — Third-party vulnerability scan
if $DO_VULN; then
  echo "=== VULNERABILITY SCAN ==="
  if $HAS_NODE; then
    npm audit --production --audit-level=moderate 2>&1 | tee /tmp/npm-audit.txt || true
  else
    echo "NPM_AUDIT: N/A (no package.json — not a Node project)"
  fi

  if $HAS_PYTHON; then
    PY_AUDIT_MODE=""
    if [[ -n "$VENV_PY" ]] && "$VENV_PY" -c "import pip_audit" >/dev/null 2>&1; then
      PY_AUDIT_MODE="venv-module"
    elif command -v pip-audit >/dev/null 2>&1 && compgen -G 'requirements*.txt' >/dev/null 2>&1; then
      PY_AUDIT_MODE="requirements"
    fi
    if [[ -n "$PY_AUDIT_MODE" ]]; then
      echo "PIP_AUDIT: running (mode=$PY_AUDIT_MODE)"
      if [[ "$PY_AUDIT_MODE" == "venv-module" ]]; then
        run_timeout "$VENV_PY" -m pip_audit --progress-spinner off 2>&1 | head -50 || true
      else
        REQ_FILE=""
        for f in requirements*.txt; do REQ_FILE="$f"; break; done
        run_timeout pip-audit -r "$REQ_FILE" --progress-spinner off 2>&1 | head -50 || true
      fi
      echo "PIP_AUDIT: done (see above; exit status captured in scan log)"
    else
      echo "PIP_AUDIT: N/A (pip-audit not available for this project env — install with: pip install pip-audit)"
    fi
  else
    echo "PIP_AUDIT: N/A (no Python manifests)"
  fi

  # Semgrep SAST scan (cross-language)
  if command -v semgrep >/dev/null 2>&1; then
    echo ""
    echo "SEMGREP: running against $SRC_DIR (auto rules; may fetch from registry)"
    run_timeout semgrep --config=auto --json --exclude=".venv/" --exclude="node_modules/" \
      --exclude="dist/" --exclude="build/" "$SRC_DIR" 2>/dev/null \
      | jq '[.results[] | {rule: .check_id, file: .path, line: .start.line, severity: .extra.severity}]' \
      || echo "SEMGREP: scan complete (no results, non-JSON output, timeout, or registry unreachable)"
  else
    echo "SEMGREP: not available (N/A — install with: pip install semgrep)"
  fi

  # Bandit static analysis (Python SAST)
  if $HAS_PYTHON; then
    if BANDIT_BIN=$(find_tool bandit); then
      echo ""
      echo "BANDIT: running against $SRC_DIR"
      if grep -qE '^\[tool\.bandit' pyproject.toml 2>/dev/null; then
        echo "BANDIT_CONFIG: [tool.bandit] in pyproject.toml (picked up automatically)"
      fi
      run_timeout "$BANDIT_BIN" -r "$SRC_DIR" -q -f json 2>/dev/null > /tmp/bandit-raw.json || true
      jq '[.results[] | {file: .filename, line: .line_number, test: .test_id, severity: .issue_severity}]' \
        /tmp/bandit-raw.json > /tmp/bandit-findings.json 2>/dev/null \
        || echo "[]" > /tmp/bandit-findings.json
      BANDIT_COUNT=$(jq 'length' /tmp/bandit-findings.json 2>/dev/null || echo 0)
      echo "BANDIT_RESULT: ${BANDIT_COUNT:-0} issue(s) (details: /tmp/bandit-findings.json)"
    else
      echo "BANDIT: N/A (bandit not installed in project env or PATH — install with: pip install bandit)"
    fi
  fi
  echo ""
fi

# Step 7.1b — Static code patterns check (ESLint security plugin, Node only)
if $DO_VULN && $HAS_NODE && command -v npx >/dev/null 2>&1; then
  if npx --no-install eslint --version >/dev/null 2>&1; then
    npx eslint src/ --plugin=security --format json 2>/dev/null | jq '.' || true
  else
    echo "ESLINT_SECURITY: N/A (eslint not installed locally; npx --no-install found nothing)"
  fi
fi

# Step 7.2 — Secrets scanning
if $DO_SECRETS; then
  echo "=== SECRETS SCAN ==="
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$SCRIPT_DIR/scan-secrets.sh" ]]; then
    if [[ "$SRC_DIR" != "." ]]; then
      echo "SECRETS_TARGET: $SRC_DIR"
      bash "$SCRIPT_DIR/scan-secrets.sh" "$SRC_DIR" || true
    else
      # Flat layout: stage the project's source/config files in a temp copy so
      # scan-secrets.sh (which walks its target recursively) can never crawl
      # .venv / node_modules / site-packages at the repo root.
      STAGE=""
      STAGE=$(mktemp -d "${TMPDIR:-/tmp}/repo-health-secrets.XXXXXX")
      find . -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.jsx' \
        -o -name '*.tsx' -o -name '*.go' -o -name '*.rb' -o -name '*.php' \
        -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.toml' \
        -o -name '*.env*' \) \
        -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.venv/*" \
        -not -path "./venv/*" -not -path "./__pycache__/*" -not -path "./site-packages/*" \
        -not -path "*.dist-info/*" -not -path "./.tox/*" -not -path "./dist/*" \
        -not -path "./build/*" -not -path "./target/*" -print0 2>/dev/null |
      while IFS= read -r -d '' f; do
        mkdir -p "$STAGE/$(dirname "$f")"
        cp "$f" "$STAGE/$f" 2>/dev/null || true
      done
      echo "SECRETS_TARGET: . (staged copy without vendor/build trees: $STAGE)"
      bash "$SCRIPT_DIR/scan-secrets.sh" "$STAGE" || true
      rm -rf "$STAGE"
    fi
  else
    echo "scan-secrets.sh: not available"
  fi
  echo ""
fi

# Step 7.3 — Credential exposure
if $DO_CREDENTIALS; then
  echo "=== CREDENTIAL EXPOSURE (git history) ==="
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git log --all --full-history -p \
      -- '.env*' '*.env*' 'secrets.*' 'credentials.*' 2>/dev/null | grep -iE "password|secret|apikey|token" \
      | grep -v "^[-+]#\|^#\|Binary" | head -50 || echo "No credential exposure detected in git history"
  else
    echo "CREDENTIAL_HISTORY: N/A (not a git repository)"
  fi
  echo ""
fi

echo "SECURITY_SCAN_COMPLETE"
exit 0
