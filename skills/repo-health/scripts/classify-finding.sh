#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# classify-finding.sh — Automated finding classification (NITPICK rubric)
#
# Reads a JSON findings list and applies the NITPICK rubric to each LOW
# severity finding. CRITICAL/HIGH/MEDIUM are always ACTIONABLE per rubric.
# Also applies the Non-Negotiable CRITICAL rules from the helpers subskill.
#
# Usage:
#   ./classify-finding.sh --findings findings.json
#   cat findings.json | ./classify-finding.sh
#
# Input: Same findings JSON format as compute-grade.sh.
# Output: Same JSON with each finding annotated with a "classification" field
#   ("ACTIONABLE" or "NITPICK") and a "classificationReason" field.
#
# NITPICK rubric (LOW severity only):
#   A LOW finding is NITPICK if ANY is true:
#     1. Cosmetic — purely cosmetic (formatting, minor doc wording)
#     2. Negligible — negligible impact on correctness/security/maintainability
#     3. Quick-manual — fixing requires manual judgment, not a scripted change
#
# Non-Negotiable CRITICAL (always actionable, never downgrade):
#   - Any package with a known CVE
#   - Insecure code patterns (SQL injection, XSS, command injection, etc.)
#   - Committed secrets/credentials
#   - Dependency with known CVE (any severity)
#   - Dependency outdated by major version
#   - Runtime/dependency outdated by major version
#
# These findings are ALWAYS ACTIONABLE regardless of severity assignment.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY_SCRIPT_DIR="$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/common.sh"
SCRIPT_DIR="$CLASSIFY_SCRIPT_DIR"

# ---- Parse args ----
INPUT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --findings) INPUT_FILE="$2"; shift 2 ;;
    --help|-h) echo "Usage: $0 [--findings file.json]"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

JSON=""
if [[ -n "$INPUT_FILE" ]]; then
  if [[ ! -f "$INPUT_FILE" ]]; then
    err "File not found: $INPUT_FILE"
    exit 1
  fi
  JSON=$(cat "$INPUT_FILE")
elif [[ ! -t 0 ]]; then
  JSON=$(cat)
else
  err "Usage: $0 --findings file.json or pipe JSON to stdin"
  exit 1
fi

if ! echo "$JSON" | jq empty 2>/dev/null; then
  err "Invalid JSON input"
  exit 1
fi

# ---- Auto-classification rules (as jq filters) ----

# Severity-based: CRITICAL, HIGH, MEDIUM are always ACTIONABLE
# Non-negotiable patterns (always actionable regardless of severity):
NON_NEGOTIABLE_KEYWORDS=(
  "CVE"
  "known CVE"
  "credential exposure"
  "hardcoded"
  "committed secret"
  "password"
  "SQL injection"
  "XSS"
  "command injection"
  "innerHTML without sanitize"
  "JWT none algorithm"
  "path traversal"
  "XXE"
  "deserialization"
  "insecure cookie"
  "CSRF"
  "outdated by a major version"
  "outdated major"
  "blocking velocity"
  "runtime outdated"
)

# Build combined non-negotiable regex pattern for jq
NN_PATTERN=""
for kw in "${NON_NEGOTIABLE_KEYWORDS[@]}"; do
  if [[ -n "$NN_PATTERN" ]]; then
    NN_PATTERN="${NN_PATTERN}|"
  fi
  NN_PATTERN="${NN_PATTERN}${kw}"
done

# Apply classification in a single jq invocation:
# 1. Severity-based: CRITICAL/HIGH/MEDIUM → ACTIONABLE
# 2. LOW → apply NITPICK test (cosmetic, negligible, quick-manual patterns)
# 3. All findings matching non-negotiable keywords → override to ACTIONABLE
CLASSIFIED=$(echo "$JSON" | jq \
  --arg nn_pattern "$NN_PATTERN" \
  '
  .findings |= map(
    # Step 1: Severity-based default
    if .severity == "CRITICAL" or .severity == "HIGH" or .severity == "MEDIUM" then
      .classification = "ACTIONABLE"
    | .classificationReason = "severity-" + (.severity | ascii_downcase) + "-always-actionable"
    elif .severity == "LOW" then
      .classification = "ACTIONABLE"
    | .classificationReason = "low-actionable-default"
    else
      .
    end
    # Step 2: NITPICK test for LOW findings
    | if .severity == "LOW" and .classification == "ACTIONABLE" and
         ((.description // "") | test("(?i)formatting|whitespace|trailing space|missing blank|minor doc|cosmetic|naming preference|spelling|typo")) then
      .classification = "NITPICK"
    | .classificationReason = "cosmetic"
    elif .severity == "LOW" and .classification == "ACTIONABLE" and
         ((.description // "") | test("(?i)low-confidence|vulture|negligible|marginal|insignificant|trivial")) then
      .classification = "NITPICK"
    | .classificationReason = "negligible-impact"
    elif .severity == "LOW" and .classification == "ACTIONABLE" and
         ((.description // "") | test("(?i)TODO marker|development marker|manual judgment|requires user|requires manual")) then
      .classification = "NITPICK"
    | .classificationReason = "quick-manual-judgment"
    elif .severity == "LOW" and .classification == "ACTIONABLE" and
         ((.description // "") | test("(?i)NOASSERTION|license.*unknown|lockfile|pip-compile|lockfile strategy")) then
      .classification = "NITPICK"
    | .classificationReason = "quick-manual-judgment"
    elif .severity == "LOW" and .classification == "ACTIONABLE" and
         ((.description // "") | test("(?i)architectural debt|god module|hotspot|high import count|change frequency")) then
      .classification = "NITPICK"
    | .classificationReason = "quick-manual-judgment"
    else
      .
    end
    # Step 3: Non-negotiable override — always ACTIONABLE
    | if ((.description // "") | test("(?i)" + $nn_pattern)) then
      .classification = "ACTIONABLE"
    | .classificationReason = "non-negotiable-" + (.severity | ascii_downcase)
    else
      .
    end
  )
  ')

# ---- Summary (stderr) ----
ACT_COUNT=$(echo "$CLASSIFIED" | jq '[.findings[] | select(.classification == "ACTIONABLE")] | length')
NIT_COUNT=$(echo "$CLASSIFIED" | jq '[.findings[] | select(.classification == "NITPICK")] | length')

section "Classification Summary" >&2
sub "Total findings: $(echo "$CLASSIFIED" | jq '.findings | length')" >&2
sub "ACTIONABLE: $ACT_COUNT" >&2
sub "NITPICK: $NIT_COUNT" >&2

echo "$CLASSIFIED"
