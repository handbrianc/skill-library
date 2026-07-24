#!/usr/bin/env bash
# lib/fix-common.sh — Shared utilities for repo-health fix scripts
#
# Provides:
#   - FIX_LOG / FIX_WARN / FIX_ERR / FIX_OK output helpers
#   - fix_snapshot()   — snapshot files before modification for rollback
#   - fix_rollback()   — restore files from snapshot
#   - fix_verify()     — run a verification command and report pass/fail
#   - fix_apply()      — apply a sed expression with snapshot + rollback on failure
#   - fix_replace_block() — replace a delimited block in a file (e.g. gitnexus:start..end)
#   - fix_has_ungit()  — detect uncommitted changes to abort early
#   - SNAPSHOT_DIR     — where snapshots live

set -euo pipefail

# ---- Paths -------------------------------------------------------------------
FIX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX_REPO_ROOT="${FIX_REPO_ROOT:-$(cd "$FIX_SCRIPT_DIR/../../../.." && pwd)}"
SNAPSHOT_DIR="/tmp/repo-health-snapshots-$$"
mkdir -p "$SNAPSHOT_DIR"

# ---- Colours (disabled if not a terminal) -----------------------------------
if [[ -t 1 ]]; then
  FBOLD='\033[1m'
  FGREEN='\033[0;32m'
  FYELLOW='\033[0;33m'
  FRED='\033[0;31m'
  FCYAN='\033[0;36m'
  FGREY='\033[0;90m'
  FNC='\033[0m'
else
  FBOLD='' FGREEN='' FYELLOW='' FRED='' FCYAN='' FGREY='' FNC=''
fi

fix_section() { echo -e "\n${FBOLD}${FCYAN}====${FNC} ${FBOLD}$*${FNC}${FBOLD}${FCYAN} ====${FNC}"; }
fix_sub()     { echo -e "  ${FGREEN}$*${FNC}"; }
fix_warn()    { echo -e "  ${FYELLOW}⚠ $*${FNC}"; }
fix_err()     { echo -e "  ${FRED}✖ $*${FNC}" >&2; }
fix_ok()      { echo -e "  ${FGREEN}✓ $*${FNC}"; }
fix_skip()    { echo -e "  ${FGREY}— $*${FNC}"; }
fix_info()    { echo -e "  ${FGREY}$*${FNC}"; }
fix_log()     { echo "[$(date '+%H:%M:%S')] $*" >&2; }

# ---- Snapshot / Rollback -----------------------------------------------------

# fix_snapshot file1 [file2 ...]
#   Save a copy of each file to SNAPSHOT_DIR before modifying.
fix_snapshot() {
  local f
  for f in "$@"; do
    if [[ -f "$f" ]]; then
      local rel="${f#/}"  # strip leading slash for snapshot path
      local dst="$SNAPSHOT_DIR/$rel"
      mkdir -p "$(dirname "$dst")"
      cp "$f" "$dst"
      fix_info "snapshot: $f → $dst"
    fi
  done
}

# fix_rollback [file1 file2 ...]
#   Restore files from snapshot. If no files given, restore ALL snapshots.
fix_rollback() {
  if [[ $# -eq 0 ]]; then
    # Restore everything
    fix_section "ROLLBACK — restoring all files from snapshot"
    find "$SNAPSHOT_DIR" -type f 2>/dev/null | while read -r snap; do
      local orig="${snap#"$SNAPSHOT_DIR"/}"
      orig="/$orig"
      if [[ -f "$snap" ]]; then
        cp "$snap" "$orig"
        fix_warn "restored: $orig"
      fi
    done
    return 0
  fi
  local f
  for f in "$@"; do
    local rel="${f#/}"
    local snap="$SNAPSHOT_DIR/$rel"
    if [[ -f "$snap" ]]; then
      cp "$snap" "$f"
      fix_warn "restored: $f"
    else
      fix_err "no snapshot for: $f"
    fi
  done
}

# fix_cleanup_snapshots
#   Remove the snapshot directory.
fix_cleanup_snapshots() {
  rm -rf "$SNAPSHOT_DIR" 2>/dev/null || true
}

# ---- Verification -----------------------------------------------------------

# fix_verify "description" command [args...]
#   Run a command. Print ✓ if exit 0, ✖ if non-zero.
#   Returns the exit code of the command.
fix_verify() {
  local desc="$1"
  shift
  fix_info "verify: $desc"
  if "$@" 2>&1; then
    fix_ok "verification passed: $desc"
    return 0
  else
    local rc=$?
    fix_err "verification FAILED: $desc (exit $rc)"
    return $rc
  fi
}

# fix_verify_grep "description" pattern file
#   Check that a pattern exists in a file.
fix_verify_grep() {
  local desc="$1" pat="$2" file="$3"
  if grep -q "$pat" "$file" 2>/dev/null; then
    fix_ok "$desc"
    return 0
  else
    fix_err "$desc — pattern not found: $pat in $file"
    return 1
  fi
}

# ---- Safe Application -------------------------------------------------------

# fix_apply file description sed_expression
#   Snapshot a file, apply a sed expression, verify file still valid.
#   On failure, rollback the file.
fix_apply() {
  local file="$1" desc="$2" expr="$3"
  fix_snapshot "$file"
  fix_info "applying: $desc"
  if sed -i.bak "$expr" "$file" 2>/dev/null; then
    rm -f "${file}.bak" 2>/dev/null || true
    fix_ok "$desc"
    return 0
  else
    fix_err "sed failed: $desc"
    fix_rollback "$file"
    return 1
  fi
}

# fix_replace_block file open_delim close_delim new_content
#   Replace everything between open_delim and close_delim (inclusive) with
#   new_content. open_delim and close_delim are literal strings.
fix_replace_block() {
  local file="$1" open_delim="$2" close_delim="$3" new_content="$4"

  if [[ ! -f "$file" ]]; then
    fix_err "file not found: $file"
    return 1
  fi

  fix_snapshot "$file"

  # Create temp file with new content
  local tmpf
  tmpf=$(mktemp)

  # Write the new content between delimiters
  awk -v open="$open_delim" -v close="$close_delim" \
    'BEGIN { skip=0 }
     index($0, open) { skip=1; print; next }
     index($0, close) { print; skip=0; next }
     skip { next }
     { print }' "$file" > "$tmpf"

  # Insert new content after the opening delimiter
  awk -v open="$open_delim" -v content="$new_content" \
    'index($0, open) { print; print content; next }
     { print }' "$tmpf" > "${tmpf}2"

  mv "${tmpf}2" "$file"
  rm -f "$tmpf"
  fix_ok "replaced block in $file"
}

# ---- Pre-flight -------------------------------------------------------------

# fix_has_ungit
#   Check for uncommitted changes in the repo. Returns 0 if clean, 1 if dirty.
fix_has_ungit() {
  if ! git -C "$FIX_REPO_ROOT" diff --quiet 2>/dev/null; then
    fix_warn "uncommitted changes detected in $FIX_REPO_ROOT"
    return 0
  fi
  if ! git -C "$FIX_REPO_ROOT" diff --cached --quiet 2>/dev/null; then
    fix_warn "staged but uncommitted changes detected"
    return 0
  fi
  return 1
}

export -f fix_snapshot fix_rollback fix_cleanup_snapshots
export -f fix_verify fix_verify_grep fix_apply fix_replace_block
export -f fix_has_ungit
export FIX_REPO_ROOT SNAPSHOT_DIR
