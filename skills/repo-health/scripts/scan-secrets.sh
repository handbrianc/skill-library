#!/usr/bin/env bash
#
# scan-secrets.sh
# Scans source code for leaked credentials, API keys, tokens, and secrets.
# Checks git history AND current tree.
#
# Usage: ./scan-secrets.sh <target_dir>
# Output: TSV: SECRET_TYPE | FILE | LINE | EVIDENCE_MASKED | SEVERITY
#
set -euo pipefail

TARGET="${1:-.}"

echo "=== SECRET/CREDENTIAL SCAN ===" >&2
echo "Target: $TARGET" >&2
echo "" >&2

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ---- Pattern Definitions ----
# Each pattern maps to a (SEVERITY, REGEX) tuple.
# High-confidence secrets get HIGH/CRITICAL; common placeholders get LOW.
declare -a PATTERNS=(
  "AWS_ACCESS_KEY_ID:HIGH:AKIA[0-9A-Z]{16}"
  "AWS_SECRET_KEY:HIGH:aws_secret(_access_key|_key)?.*=.*['\"][A-Za-z0-9/+=]{40}"
  "GITHUB_TOKEN:HIGH:ghp_[A-Za-z0-9]{36}"
  "GITHUB_TOKEN:HIGH:github_pat_[A-Za-z0-9_]{22,}"
  "STRIPE_SECRET_KEY:HIGH:sk_live_[0-9a-zA-Z]{24,}"
  "STRIPE_SECRET_KEY:HIGH:sk_test_[0-9a-zA-Z]{24,}"
  "STRIPE_PUBLISHABLE:MEDIUM:pk_live_[0-9a-zA-Z]{24,}"
  "STRIPE_PUBLISHABLE:MEDIUM:pk_test_[0-9a-zA-Z]{24,}"
  "JWT_SECRET:HIGH:(jwt|JsonWebToken).*(secret|key).*=.*['\"][^'\"]{8,}"
  "DATABASE_URL_WITH_CREDS:CRITICAL:mysql://[^:]+:[^@]+@|postgres://[^:]+:[^@]+@|mongodb://[^:]+:[^@]+@|redis://[^:]+:[^@]+@"
  "PRIVATE_KEY_BLOCK:CRITICAL:-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----"
  "API_KEY_GENERIC:HIGH:api[_-]?key.*=.*['\"][A-Za-z0-9_\-]{20,}"
  "BEARER_TOKEN:MEDIUM:Bearer [A-Za-z0-9_\-\.]{20,}"
  "BASIC_AUTH_URL:HIGH:https?://[^:]+:[^@]+@[a-zA-Z0-9.-]+"
  "GENERIC_PASSWORD:LOW:password.*=.*['\"][^'\"]{3,}[\"']"
  "GENERIC_SECRET:LOW:secret.*=.*['\"][^'\"]{6,}[\"']"
  "SLACK_TOKEN:HIGH:xox[baprs]-[0-9]{10,}-[0-9]{10,}-[0-9a-zA-Z]{24,}"
  "SENDGRID_KEY:HIGH:SG\\.[a-zA-Z0-9_-]{22}\\.[a-zA-Z0-9_-]{43}"
  "MAILGUN_API:MEDIUM:MG[a-zA-Z0-9]{32}"
  "TWILIO_ACCOUNT:MEDIUM:AC[a-z0-9]{32}"
  "OPENAI_KEY:HIGH:sk-[A-Za-z0-9]{48}"
)

# ---- SCAN FUNCTION ----
do_scan() {
  local file_glob="$1"
  local secret_type="$2"
  local sev="$3"
  local pattern="$4"

  {
    find "$TARGET" -type f -name "$file_glob" \
      ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/dist/*" \
      ! -path "*/build/*" ! -path "*/vendor/*" \
      -exec grep -Hn -E "$pattern" {} + 2>/dev/null || true
  } | while IFS= read -r hit; do
    file=${hit%%:*}
    rest=${hit#*:}; line=${rest%%:*}; match=${rest#*:}
    masked=$(printf '%s' "$match" | sed -E 's/([A-Za-z0-9._\/=:+-]{4})[A-Za-z0-9._\/=:+-]{8,}/\1*REDACTED*/g')
    printf '%s\t%s\t%s\t%s\t%s\n' "$secret_type" "$file" "$line" "$masked" "$sev"
  done || true
}

for entry in "${PATTERNS[@]}"; do
  SECRET_TYPE="${entry%%:*}"; rest="${entry#*:}"; SEV="${rest%%:*}"; PATTERN="${rest#*:}"
  
  do_scan "*.ts" "$SECRET_TYPE" "$SEV" "$PATTERN"
  do_scan "*.tsx" "$SECRET_TYPE" "$SEV" "$PATTERN"
  do_scan "*.js" "$SECRET_TYPE" "$SEV" "$PATTERN"
  do_scan "*.jsx" "$SECRET_TYPE" "$SEV" "$PATTERN"
  do_scan "*.py" "$SECRET_TYPE" "$SEV" "$PATTERN"
  do_scan "*.go" "$SECRET_TYPE" "$SEV" "$PATTERN"
  do_scan "*.json" "$SECRET_TYPE" "$SEV" "$PATTERN"
  do_scan "*.yaml" "$SECRET_TYPE" "$SEV" "$PATTERN"
  do_scan "*.yml" "$SECRET_TYPE" "$SEV" "$PATTERN"
  do_scan "*.toml" "$SECRET_TYPE" "$SEV" "$PATTERN"
done

# ---- ENV FILES GET HIGHER SENSITIVITY ----
echo "" >&2
echo "=== ENV/CONFIG FILE SWEEP (CRITICAL SEVERITY) ===" >&2

for entry in "${PATTERNS[@]}"; do
  SECRET_TYPE="${entry%%:*}"; rest="${entry#*:}"; SEV="${rest%%:*}"; PATTERN="${rest#*:}"

  # Env/config files are higher-signal; treat matches as CRITICAL regardless of base severity.
  do_scan ".env" "$SECRET_TYPE" "CRITICAL" "$PATTERN"
  do_scan ".env.*" "$SECRET_TYPE" "CRITICAL" "$PATTERN"
  do_scan "*.env*" "$SECRET_TYPE" "CRITICAL" "$PATTERN"
  do_scan "*.env" "$SECRET_TYPE" "CRITICAL" "$PATTERN"
done

# ---- GIT HISTORY SCAN (proxy via -S string search) ----
echo "" >&2
echo "=== GIT HISTORY SWEEP ===" >&2
echo "(Detects secrets ever committed — even if subsequently removed)" >&2

# Keys worth searching history for
HISTORY_PATTERNS="AKIA[A-Z0-9]\{16\}|sk_live_[a-z0-9]\{24\}|-----BEGIN PRIVATE KEY-----"
# Emit only commit metadata and affected filenames — never print patch lines that contain the secret value.
git log --all --full-history --format="COMMIT:%H %as %s" --name-only -G "$HISTORY_PATTERNS" --pickaxe-regex \
  -- "*.js" "*.ts" "*.json" "*.yaml" "*.env*" 2>/dev/null | \
while IFS= read -r histline; do
  if [[ "$histline" == COMMIT:* ]]; then
    _COMMIT_INFO="${histline#COMMIT:}"
  elif [ -n "$histline" ]; then
    printf 'HISTORY_SECRET\t%s\t(git-history)\t[SECRET FOUND IN HISTORY — review commit: %s]\tHIGH\n' \
      "$histline" "${_COMMIT_INFO:-unknown}"
  fi
done || true

# ---- NETWORK-PROXIMATE SECRETS (higher exploitability) ----
echo "" >&2
echo "=== NETWORK-PROXIMATE SECRET SWEEP ===" >&2
echo "(Secrets in files that make HTTP/-network calls — easier to exfiltrate)" >&2

readarray -t NETWORK_FILES < <(find "$TARGET" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" \) \
  ! -path "*/node_modules/*" ! -path "*/dist/*" \
  -exec grep -lE "fetch\(|axios\.|requests?\.|\.get\(|\.post\(|\.put\(|\.delete\(|http\.|urllib\.|net/http|RPC|gRPC|graphql" {} \; 2>/dev/null)

HIGH_VALUE_TYPES="AKIA[A-Z0-9]{16}|sk_live_|-----BEGIN PRIVATE KEY-----|mongodb://|postgres://|mysql://|redis://"

for FILE in "${NETWORK_FILES[@]}"; do
  if grep -qE "$HIGH_VALUE_TYPES" "$FILE" 2>/dev/null; then
    grep -nE "$HIGH_VALUE_TYPES" "$FILE" 2>/dev/null | head -5 | while IFS=: read -r LN MATCH; do
      masked=$(printf '%s' "$MATCH" | sed -E 's/([A-Za-z0-9._\/=:+-]{4})[A-Za-z0-9._\/=:+-]{8,}/\1*REDACTED*/g')
      printf 'NETWORK_PROXIMATE_CRITICAL\t%s\t%s\t%s\tCRITICAL\n' "$FILE" "$LN" "$masked"
    done || true
  fi
done

echo "" >&2
echo "=== SCAN COMPLETE ===" >&2
echo "Action required for CRITICAL/HIGH findings regardless of quantity." >&2
echo "Rotate ALL exposed secrets immediately — do not assume only one key matters." >&2
echo "Use 'git filter-branch' or 'bfg' to purge secret-containing commits from history." >&2

exit 0