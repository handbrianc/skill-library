#!/usr/bin/env bash
#
# run-scan-suite.sh
# Master script — runs all deterministic scans in sequence.
# Produces a combined artifact bundle.
#
# Usage: ./run-scan-suite.sh [--skip-network-checks]
# Output: /tmp/repo-health-{timestamp}.zip containing all scan outputs
#

set -euo pipefail

SKIP_SECRETS=false

for arg in "$@"; do
  case "$arg" in
    --skip-secrets-scan) SKIP_SECRETS=true ;;
  esac
done

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUT_ZIP="/tmp/repo-health-${TIMESTAMP}.zip"
WORKDIR=$(pwd)
PROJECT_NAME=$(basename "$WORKDIR")
# ---- SETUP ARTIFACT DIR ----
ARTIFACT_DIR="/tmp/repo-health-${TIMESTAMP}"
mkdir -p "$ARTIFACT_DIR"

# Capture environment for reproducibility
echo "Capturing environment..." >&2
{
  echo "# Environment captured at $(date)"
  echo "Node: $(node --version 2>/dev/null || echo 'N/A')"
  echo "NPM: $(npm --version 2>/dev/null || echo 'N/A')"
  echo "Python: $(python3 --version 2>/dev/null || echo 'N/A')"
  echo "Go: $(go version 2>/dev/null || echo 'N/A')"
  echo "Git commit: $(git rev-parse HEAD 2>/dev/null || echo 'N/A')"
  echo "GitNexus: $(npx gitnexus --version 2>/dev/null || echo 'N/A')"
  echo ""
  echo "Package manager:"
  [ -f package-lock.json ] && echo "  npm (package-lock.json found)"
  [ -f pnpm-lock.yaml ] && echo "  pnpm (pnpm-lock.yaml found)"
  [ -f yarn.lock ] && echo "  yarn (yarn.lock found)"
  [ -f go.mod ] && echo "  Go (go.mod found)"
  [ -f pyproject.toml ] && echo "  Python (pyproject.toml found)"
} > "$ARTIFACT_DIR/environment.txt"

# ---- DISPATCH TO SCRIPTS ----
LOG() { echo "[$1] $2" >&2; }

dispatch() {
  local SCRIPT="$1"
  local LABEL="$2"
  local OUTFILE="$3"
  shift 3

  LOG "$LABEL" "Starting..."
  if [ ! -f "$SCRIPT" ]; then
    LOG "$LABEL" "SKIPPED (script not found: $SCRIPT)"
    return
  fi

  local START=$(date +%s.%N)
  if bash "$SCRIPT" "$@" 2>&1 | tee "$ARTIFACT_DIR/$OUTFILE"; then
    LOG "$LABEL" "Done."
  else
    LOG "$LABEL" "Warning: exited non-zero."
  fi
  local ELAPSED=$(echo "$(date +%s.%N) - $START" | bc 2>/dev/null || echo "N/A")
  LOG "$LABEL" "Elapsed: ${ELAPSED}s"
}

SCRIPT_BASE="$(dirname "$0")"
echo "" >&2

LOG "MAIN" "=== Code Quality Scans ===" 
dispatch "$SCRIPT_BASE/detect-dead-code.sh" "DEAD_CODE" "scan-01-dead-code.log" "$WORKDIR"
dispatch "$SCRIPT_BASE/scan-cognitive-complexity.sh" "COMPLEXITY" "scan-02-complexity.log" "$WORKDIR"
dispatch "$SCRIPT_BASE/find-duplicates.sh" "DUPLICATES" "scan-03-duplicates.log" "$WORKDIR"
dispatch "$SCRIPT_BASE/audit-dependency-usage.sh" "DEPS_USAGE" "scan-04-deps-usage.log"
echo "" >&2
LOG "MAIN" "=== Documentation Scans ==="
dispatch "$SCRIPT_BASE/check-doc-links.sh" "DOC_LINKS" "scan-05-doc-links.log"

echo "" >&2
LOG "MAIN" "=== Specification Scans ==="
if [ -d "specs" ]; then
  dispatch "$SCRIPT_BASE/compare-specs.sh" "SPEC_ALIGN" "scan-06-spec-align.log" "specs" "specs/archive"
else
  LOG "SPEC_ALIGN" "SKIPPED (no specs/ directory)"
fi

echo "" >&2
if ! $SKIP_SECRETS; then
  LOG "MAIN" "=== Security Scans ==="
  dispatch "$SCRIPT_BASE/scan-secrets.sh" "SECRETS" "scan-07-secrets.log"
else
  LOG "SECRETS" "SKIPPED (--skip-secrets-scan specified)"
fi

echo "" >&2
LOG "MAIN" "=== License Scans ==="
# Generate SBOM first if we have syft
if command -v syft &>/dev/null; then
  LOG "SBOM" "Generating SBOM with syft..."
  syft . -o spdx-json > "$ARTIFACT_DIR/sbom.spdx.json" 2>&1 && LOG "SBOM" "Generated." || LOG "SBOM" "Warning: syft failed."
  dispatch "$SCRIPT_BASE/scan-licenses.sh" "LICENSES" "scan-08-licenses.log" "$ARTIFACT_DIR/sbom.spdx.json"
else
  LOG "SBOM+LICENSE" "SKIPPED (syft not available)"
fi

# ---- GitNexus contextual analysis (if available) ----
echo "" >&2
LOG "MAIN" "=== GitNexus Knowledge Graph Analysis ==="
if npx gitnexus status &>/dev/null; then
  {
    echo "# GitNexus Context Snapshot"
    echo "# Generated: $(date)"
    npx gitnexus status 2>&1 || true
    echo ""
    echo "# Clusters:"
    # We'll call gitnexus context via a subshell placeholder comment
    echo "# NOTE: For full cluster data, run in a Claude Code session with GitNexus MCP."
    echo "# Tool: READ gitnexus://repo/{name}/clusters"
    echo "# Tool: READ gitnexus://repo/{name}/processes"
  } > "$ARTIFACT_DIR/gitnexus-context.txt"
  LOG "GitNexus" "Context snapshot saved."
else
  LOG "GitNexus" "SKIPPED (not indexed or gitnexus not available)"
fi

# ---- Bundle Artifacts ----
echo "" >&2
LOG "MAIN" "Bundling artifacts..."
ARCHIVE_PATH=""
pushd /tmp >/dev/null
if zip -r "$OUT_ZIP" "repo-health-${TIMESTAMP}/" -q 2>/dev/null; then
  ARCHIVE_PATH="$OUT_ZIP"
elif tar czf "${OUT_ZIP%.zip}.tgz" "repo-health-${TIMESTAMP}/" 2>/dev/null; then
  ARCHIVE_PATH="${OUT_ZIP%.zip}.tgz"
fi
popd >/dev/null

ARTIFACT_COUNT=$(ls "$ARTIFACT_DIR" 2>/dev/null | wc -l)
echo "" >&2
echo "==============================================" >&2
echo "  SCAN SUITE COMPLETE" >&2
echo "  Artifacts: $ARTIFACT_COUNT files in $ARTIFACT_DIR" >&2
echo "  Archive:   ${ARCHIVE_PATH:-N/A}" >&2
echo "  Project:   $PROJECT_NAME" >&2
echo "  Date:      $(date)" >&2
echo "==============================================" >&2
echo "" >&2
echo "Next: Load the output files into Claude Code and run the repo-health skill" >&2
echo "for consolidated analysis and action plan creation." >&2

exit 0