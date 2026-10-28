#!/usr/bin/env bash
# ============================================================================
# test-install-scripts.sh — Installer integration test: script accessibility
# ============================================================================
#
# Verifies that a copy install produces self-contained skills:
#   1. no repo-relative script references remain in installed SKILL.md files
#      (agents run in the user's project, where ./skills/... cannot resolve),
#   2. full-path and bare ./<script>.sh references point at the destination,
#   3. every bundled script is executable,
#   4. the support scripts actually run from a foreign working directory,
#   5. re-running the installer does not re-rewrite already-rewritten files.
#
# Runs the real installer into a throwaway destination; never touches
# ~/.copilot or ~/.config/opencode.
#
# Usage:
#   ./tests/test-install-scripts.sh        (run by tests/run-tests.sh)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_ROOT/install-skills.sh"

TMP_BASE="${TMPDIR:-/tmp/opencode}"
mkdir -p "$TMP_BASE"
DEST="$(mktemp -d "$TMP_BASE/install-skills-test.XXXXXX")"
FOREIGN_CWD="$(mktemp -d "$TMP_BASE/install-skills-test-cwd.XXXXXX")"
FAILURES=0

cleanup() { rm -rf "$DEST" "$FOREIGN_CWD"; }
trap cleanup EXIT

pass() { echo "    ✓ $*"; }
fail() { echo "    ✖ $*" >&2; FAILURES=$((FAILURES+1)); }

echo "  Destination: $DEST"
echo "  Foreign CWD: $FOREIGN_CWD"
echo ""

# ── 1. Install (copy mode, single throwaway destination, no Copilot flow) ────

"$INSTALLER" --dest "$DEST" > /dev/null

# ── 2. No repo-relative script references remain in installed SKILL.md ──────

LEFTOVER="$(grep -RnE '(^|[^/])(\./)?skills/[a-z0-9-]+/(scripts|SKILL\.md)' \
  --include='*.md' "$DEST" || true)"
if [[ -z "$LEFTOVER" ]]; then
  pass "no repo-relative skill/script references remain in installed SKILL.md files"
else
  fail "relative references remain in installed SKILL.md files:"
  echo "$LEFTOVER" >&2
fi

# ── 3. The reported failure's commands are now absolute and self-consistent ──

P0="$DEST/repo-health--phase-0-environment/SKILL.md"
if grep -Fq "$DEST/repo-health/scripts/install-missing-tools.sh gnu-grep coreutils gnu-date" "$P0"; then
  pass "phase-0 GNU toolchain command points at the installed scripts"
else
  fail "phase-0 GNU toolchain command was not rewritten to the install destination"
fi
if grep -Fq "$DEST/repo-health/scripts/install-missing-tools.sh --filter=test" "$P0"; then
  pass "phase-0 bare table commands (./install-missing-tools.sh) made absolute"
else
  fail "phase-0 bare table command was not rewritten"
fi
if grep -Fq "$DEST/repo-health/scripts/scan-environment.sh --check-tools" "$P0"; then
  pass "phase-0 scan-environment.sh command made absolute"
else
  fail "phase-0 scan-environment.sh command was not rewritten"
fi

# ── 4. Every bundled script is executable ─────────────────────────────────────

NON_EXEC="$(find "$DEST" -type f -name '*.sh' ! -perm -u+x || true)"
if [[ -z "$NON_EXEC" ]]; then
  pass "every installed script is executable"
else
  fail "installed scripts missing the executable bit:"
  echo "$NON_EXEC" >&2
fi

# ── 5. The support scripts run from a foreign working directory ──────────────

if ( cd "$FOREIGN_CWD" && "$DEST/repo-health/scripts/install-missing-tools.sh" --check-only >/dev/null 2>&1 ); then
  pass "install-missing-tools.sh --check-only runs from a foreign working directory"
else
  fail "install-missing-tools.sh --check-only failed from a foreign working directory"
fi
if ( cd "$FOREIGN_CWD" && "$DEST/repo-health/scripts/scan-environment.sh" --check-tools >/dev/null 2>&1 ); then
  pass "scan-environment.sh --check-tools runs from a foreign working directory"
else
  fail "scan-environment.sh --check-tools failed from a foreign working directory"
fi

# ── 6. Rewrite is idempotent (a --skip re-run changes nothing) ───────────────

FILES=(repo-health/SKILL.md repo-health--phase-0-environment/SKILL.md spec-compliance/SKILL.md)
HASH1="$(for f in "${FILES[@]}"; do cat "$DEST/$f"; done | sha256sum)"
"$INSTALLER" --dest "$DEST" --skip > /dev/null
HASH2="$(for f in "${FILES[@]}"; do cat "$DEST/$f"; done | sha256sum)"
if [[ "$HASH1" == "$HASH2" ]]; then
  pass "rewrite is idempotent — --skip re-run left installed SKILL.md files unchanged"
else
  fail "second installer run modified already-rewritten SKILL.md files"
fi

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "  ✅ Installer script-accessibility test passed"
  exit 0
else
  echo "  ❌ $FAILURES installer script-accessibility test failure(s)"
  exit 1
fi
