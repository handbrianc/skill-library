#!/usr/bin/env bash
#
# fix-lint.sh
# Auto-fix lint issues across the project.
# Runs project-configured linters with --fix where available,
# then reports remaining violations.
#
# Usage: ./fix-lint.sh [--dry-run] [target-dir]
#   target-dir: source directory to scan (default: auto-detect)
#
# Exit codes: 0 = all violations fixed, 1 = remaining violations after fix

set -euo pipefail

FIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX_REPO_ROOT="$(cd "$FIX_DIR/../../.." && pwd)"
source "$FIX_DIR/lib/fix-common.sh"
SCRIPT_DIR="$FIX_DIR"
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true && shift || true

TARGET_DIR="${1:-}"
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$FIX_REPO_ROOT"
  for d in src lib app; do
    if [[ -d "$FIX_REPO_ROOT/$d" ]]; then
      TARGET_DIR="$FIX_REPO_ROOT/$d"
      break
    fi
  done
fi

fix_section "FIX: Lint Auto-Fix"

BEFORE_COUNT=0
AFTER_COUNT=0
FIXED=0
UNABLE=0

# ── ESLint ───────────────────────────────────────────────────────────────────
if command -v npx >/dev/null 2>&1 && npx eslint --version >/dev/null 2>&1; then
  fix_sub "Running ESLint..."

  # Count violations before fix
  BEFORE=$(npx eslint "$TARGET_DIR" --format json --max-warnings -1 2>/dev/null | jq '[.[] | .messages | length] | add // 0' 2>/dev/null || echo "0")
  BEFORE_COUNT=$((BEFORE_COUNT + BEFORE))

  if [[ "$BEFORE" -gt 0 ]]; then
    fix_warn "$BEFORE violations before fix"

    if $DRY_RUN; then
      fix_info "[dry-run] would run eslint --fix"
    else
      npx eslint "$TARGET_DIR" --fix 2>/dev/null || true

      # Count after fix
      AFTER=$(npx eslint "$TARGET_DIR" --format json --max-warnings -1 2>/dev/null | jq '[.[] | .messages | length] | add // 0' 2>/dev/null || echo "0")
      AFTER_COUNT=$((AFTER_COUNT + AFTER))

      if [[ "$AFTER" -lt "$BEFORE" ]]; then
        FIXED=$((FIXED + BEFORE - AFTER))
        fix_ok "ESLint: fixed $((BEFORE - AFTER)) violations, $AFTER remaining"
      else
        UNABLE=$((UNABLE + 1))
        fix_warn "ESLint: $AFTER violations remaining (could not auto-fix)"
      fi
    fi
  else
    fix_ok "ESLint: no violations"
  fi
fi

# ── Ruff (Python) ───────────────────────────────────────────────────────────
if command -v ruff >/dev/null 2>&1; then
  fix_sub "Running Ruff..."

  BEFORE=$(ruff check "$TARGET_DIR" --output-format json 2>/dev/null | jq 'length // 0' 2>/dev/null || echo "0")
  BEFORE_COUNT=$((BEFORE_COUNT + BEFORE))

  if [[ "$BEFORE" -gt 0 ]]; then
    fix_warn "$BEFORE violations before fix"

    if $DRY_RUN; then
      fix_info "[dry-run] would run ruff check --fix"
    else
      ruff check "$TARGET_DIR" --fix 2>/dev/null || true

      AFTER=$(ruff check "$TARGET_DIR" --output-format json 2>/dev/null | jq 'length // 0' 2>/dev/null || echo "0")
      AFTER_COUNT=$((AFTER_COUNT + AFTER))

      if [[ "$AFTER" -lt "$BEFORE" ]]; then
        FIXED=$((FIXED + BEFORE - AFTER))
        fix_ok "Ruff: fixed $((BEFORE - AFTER)) violations, $AFTER remaining"
      else
        UNABLE=$((UNABLE + 1))
        fix_warn "Ruff: $AFTER violations remaining (could not auto-fix)"
      fi
    fi
  else
    fix_ok "Ruff: no violations"
  fi
fi

# ── ShellCheck ───────────────────────────────────────────────────────────────
if command -v shellcheck >/dev/null 2>&1; then
  fix_sub "Running ShellCheck..."

  # Count shell scripts
  SH_FILES=$(find "$TARGET_DIR" -name '*.sh' -type f 2>/dev/null | head -50 | wc -l)
  if [[ "$SH_FILES" -gt 0 ]]; then
    fix_info "Checking $SH_FILES shell scripts"

    if $DRY_RUN; then
      fix_info "[dry-run] would check shell scripts"
    else
      # ShellCheck is advisory-only (no --fix). Report violations.
      SC_VIOLS=$(find "$TARGET_DIR" -name '*.sh' -type f 2>/dev/null \
        | head -50 \
        | xargs shellcheck -f json 2>/dev/null \
        | jq 'length // 0' 2>/dev/null || echo "0")

      if [[ "$SC_VIOLS" -gt 0 ]]; then
        fix_warn "ShellCheck: $SC_VIOLS violations (cannot auto-fix — review manually)"
        UNABLE=$((UNABLE + 1))

        # Report top violations by rule
        find "$TARGET_DIR" -name '*.sh' -type f 2>/dev/null \
          | head -50 \
          | xargs shellcheck -f json 2>/dev/null \
          | jq -r 'group_by(.code) | .[] | "  SC\(.[0].code): \(length) occurrences"' \
          | head -10 || true
      else
        fix_ok "ShellCheck: no violations"
      fi
    fi
  fi
fi

# ── gofmt / go vet ───────────────────────────────────────────────────────────
if command -v go >/dev/null 2>&1 && ls "$TARGET_DIR"/*.go 2>/dev/null | head -1 >/dev/null 2>&1; then
  fix_sub "Running gofmt..."

  if $DRY_RUN; then
    fix_info "[dry-run] would run gofmt -w"
  else
    BEFORE=$(gofmt -l "$TARGET_DIR" 2>/dev/null | wc -l)

    if [[ "$BEFORE" -gt 0 ]]; then
      fix_warn "$BEFORE files need formatting"
      gofmt -w "$TARGET_DIR" 2>/dev/null || true
      AFTER=$(gofmt -l "$TARGET_DIR" 2>/dev/null | wc -l)
      FIXED=$((FIXED + BEFORE - AFTER))
      fix_ok "gofmt: formatted $((BEFORE - AFTER)) files, $AFTER remaining"
    else
      fix_ok "gofmt: all files formatted"
    fi
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
fix_section "Lint Fix — Summary"
fix_info "  Total violations detected: $BEFORE_COUNT"
fix_info "  Auto-fixed: $FIXED"
fix_info "  Remaining: $AFTER_COUNT"
fix_info "  Could not auto-fix: $UNABLE"

if [[ "$FIXED" -gt 0 ]]; then
  fix_ok "Fixed $FIXED lint violations"
fi

if [[ "$AFTER_COUNT" -gt 0 ]]; then
  fix_warn "$AFTER_COUNT violations remain after auto-fix"
  exit 1
fi

if [[ "$BEFORE_COUNT" -eq 0 ]]; then
  fix_ok "No lint issues found"
fi

exit 0
