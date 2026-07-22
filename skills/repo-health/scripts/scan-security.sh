#!/usr/bin/env bash
#
# scan-security.sh
# Security review — vulnerability scan, static analysis, secrets, credential exposure.
# Covers PHASE 7 of the repo-health audit.
#
# Usage: ./scan-security.sh [--vuln-scan] [--secrets] [--credential-exposure]
#   No args = runs all checks.
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
    esac
  done
fi

# Step 7.1 — Third-party vulnerability scan
if $DO_VULN; then
  echo "=== VULNERABILITY SCAN ==="
  if [[ -f "package.json" ]]; then
    npm audit --production --audit-level=moderate 2>&1 | tee /tmp/npm-audit.txt || true
  else
    echo "VULN_SCAN: No package.json found (skipping npm audit)"
  fi

  # Semgrep SAST scan
  if command -v semgrep >/dev/null 2>&1; then
    echo ""
    semgrep --config=auto --json src/ 2>/dev/null | jq '[.results[] | {rule: .check_id, file: .path, line: .start.line, severity: .extra.severity}]' || echo "SEMGREP: scan complete (no results or non-JSON output)"
  else
    echo "SEMGREP: not available"
  fi
  echo ""
fi

# Step 7.1b — Static code patterns check (ESLint security plugin)
if $DO_VULN && command -v npx >/dev/null 2>&1; then
  npx eslint src/ --plugin=security --format json 2>/dev/null | jq '.' || true
fi

# Step 7.2 — Secrets scanning
if $DO_SECRETS; then
  echo "=== SECRETS SCAN ==="
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$SCRIPT_DIR/scan-secrets.sh" ]]; then
    "$SCRIPT_DIR/scan-secrets.sh" src/
  else
    echo "scan-secrets.sh: not available"
  fi
  echo ""
fi

# Step 7.3 — Credential exposure
if $DO_CREDENTIALS; then
  echo "=== CREDENTIAL EXPOSURE (git history) ==="
  git log --all --full-history -p \
    -- .env* *.env* secrets.* credentials.* 2>/dev/null | grep -iE "password|secret|apikey|token" \
    | grep -v "^[-+]#\|^#\|Binary" | head -50 || echo "No credential exposure detected in git history"
  echo ""
fi

echo "SECURITY_SCAN_COMPLETE"
exit 0
