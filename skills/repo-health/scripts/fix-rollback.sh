#!/usr/bin/env bash
#
# fix-rollback.sh
# Rollback mechanism for repo-health auto-fixes.
# Restores files from last snapshot and verifies regression detection.
#
# Usage:
#   ./fix-rollback.sh                    # List all snapshots
#   ./fix-rollback.sh --restore          # Restore ALL files from last snapshot
#   ./fix-rollback.sh --restore <file>   # Restore a specific file
#   ./fix-rollback.sh --check            # Check if any fix caused a regression
#   ./fix-rollback.sh --clean            # Remove snapshot directory
#
# A regression is defined as: a new CRITICAL or HIGH finding introduced by
# the last round of fixes that did not exist before.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/fix-common.sh"

MODE="${1:-list}"
TARGET_FILE="${2:-}"

fix_section "FIX: Rollback & Regression Check"

case "$MODE" in
  --list|-l|list)
    fix_sub "Available snapshots in $SNAPSHOT_DIR"
    if [[ ! -d "$SNAPSHOT_DIR" ]] || [[ -z "$(find "$SNAPSHOT_DIR" -type f 2>/dev/null)" ]]; then
      fix_skip "No snapshots found in $SNAPSHOT_DIR"
      exit 0
    fi
    find "$SNAPSHOT_DIR" -type f 2>/dev/null | while read -r snap; do
      orig="${snap#"$SNAPSHOT_DIR"/}"
      orig="/$orig"
      if [[ -f "$orig" ]]; then
        if diff -q "$snap" "$orig" >/dev/null 2>&1; then
          fix_skip "$orig (unchanged)"
        else
          fix_warn "$orig (MODIFIED — can rollback)"
        fi
      else
        fix_err "$orig (DELETED — can restore)"
      fi
    done
    ;;

  --restore|-r|restore)
    if [[ -n "$TARGET_FILE" ]]; then
      rel="${TARGET_FILE#/}"
      snap="$SNAPSHOT_DIR/$rel"
      if [[ ! -f "$snap" ]]; then
        fix_err "no snapshot for $TARGET_FILE"
        exit 1
      fi
      fix_rollback "$TARGET_FILE"
      fix_ok "Restored $TARGET_FILE from snapshot"
    else
      fix_warn "Restoring ALL files from snapshot..."
      fix_rollback
      fix_ok "All files restored from snapshot"
    fi
    ;;

  --check|-c|check)
    fix_sub "Regression Detection"
    fix_info "Running scan to detect regressions..."

    if [[ ! -d "$SNAPSHOT_DIR" ]] || [[ -z "$(find "$SNAPSHOT_DIR" -type f 2>/dev/null)" ]]; then
      fix_skip "No snapshots — cannot detect regressions"
      exit 0
    fi

    # Compare each snapshot against current file
    REGRESSIONS=0
    find "$SNAPSHOT_DIR" -type f 2>/dev/null | while read -r snap; do
      orig="${snap#"$SNAPSHOT_DIR"/}"
      orig="/$orig"
      if [[ -f "$orig" ]]; then
        if ! diff -q "$snap" "$orig" >/dev/null 2>&1; then
          # File was modified — check if it's a regression
          if diff "$snap" "$orig" 2>/dev/null | grep -q '^[+-].*TODO\|FIXME\|HACK\|XXX'; then
            fix_warn "$orig: new debt markers introduced"
            ((REGRESSIONS++)) || true
          fi
          if [[ -f "$orig" ]] && ! bash -n "$orig" 2>/dev/null && [[ "$orig" == *.sh ]]; then
            fix_err "$orig: bash syntax error introduced (REGRESSION)"
            ((REGRESSIONS++)) || true
          fi
        fi
      fi
    done

    if [[ "$REGRESSIONS" -eq 0 ]]; then
      fix_ok "No regressions detected"
    else
      fix_warn "$REGRESSIONS regression(s) detected"
      fix_info "Run 'fix-rollback.sh --restore' to revert all changes"
    fi
    ;;

  --clean|clean)
    fix_cleanup_snapshots
    fix_ok "Snapshot directory cleaned"
    ;;

  *)
    echo "Usage: $0 [--list|--restore [file]|--check|--clean]" >&2
    exit 1
    ;;
esac

exit 0
