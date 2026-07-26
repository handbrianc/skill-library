#!/usr/bin/env bats
# ============================================================================
# bats tests for fix-common.sh shared library
# ============================================================================

setup() {
  export FIX_REPO_ROOT="${BATS_TEST_TMPDIR}/test-repo"
  mkdir -p "$FIX_REPO_ROOT"
  echo "hello world" > "$FIX_REPO_ROOT/file.txt"
  export SNAPSHOT_DIR="/tmp/repo-health-snapshots-$$"
  rm -rf "$SNAPSHOT_DIR"
}

teardown() {
  rm -rf "$SNAPSHOT_DIR" 2>/dev/null || true
  rm -rf "$FIX_REPO_ROOT" 2>/dev/null || true
}

# ── Library sourcing ────────────────────────────────────────────────────────

@test "fix-common.sh sources without errors" {
  run bash -c "source ${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/lib/fix-common.sh"
  [ "$status" -eq 0 ]
}

@test "fix-common.sh defines expected functions" {
  source "${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/lib/fix-common.sh"
  [ "$(type -t fix_snapshot)" = "function" ]
  [ "$(type -t fix_rollback)" = "function" ]
  [ "$(type -t fix_verify)" = "function" ]
  [ "$(type -t fix_apply)" = "function" ]
  [ "$(type -t fix_has_ungit)" = "function" ]
  [ "$(type -t fix_section)" = "function" ]
  [ "$(type -t fix_ok)" = "function" ]
  [ "$(type -t fix_warn)" = "function" ]
  [ "$(type -t fix_err)" = "function" ]
}

# ── Output helpers ──────────────────────────────────────────────────────────

@test "fix_section outputs formatted section header" {
  source "${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/lib/fix-common.sh"
  run fix_section "TEST SECTION"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST SECTION"* ]]
}

@test "fix_ok outputs success message" {
  source "${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/lib/fix-common.sh"
  run fix_ok "everything is fine"
  [ "$status" -eq 0 ]
  [[ "$output" == *"everything is fine"* ]]
}

@test "fix_warn outputs warning message" {
  source "${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/lib/fix-common.sh"
  run fix_warn "something suspicious"
  [ "$status" -eq 0 ]
  [[ "$output" == *"something suspicious"* ]]
}

@test "fix_err outputs error message to stderr" {
  run bash -c "source \"${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/lib/fix-common.sh\"; fix_err \"something broke\" 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"something broke"* ]]
}

# ── Environment ─────────────────────────────────────────────────────────────

@test "SNAPSHOT_DIR is set after sourcing" {
  source "${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/lib/fix-common.sh"
  [ -n "$SNAPSHOT_DIR" ]
  [ -d "$SNAPSHOT_DIR" ]
}
