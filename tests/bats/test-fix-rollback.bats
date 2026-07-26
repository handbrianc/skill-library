#!/usr/bin/env bats
# ============================================================================
# bats tests for fix-rollback.sh
# ============================================================================

setup() {
  export FIX_REPO_ROOT="${BATS_TEST_TMPDIR}/test-repo"
  mkdir -p "$FIX_REPO_ROOT"
  FIX_COMMON="${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/lib/fix-common.sh"
  echo "original content" > "$FIX_REPO_ROOT/test.txt"
  export SNAPSHOT_DIR="/tmp/repo-health-snapshots-$$"
  rm -rf "$SNAPSHOT_DIR"
}

teardown() {
  rm -rf "$SNAPSHOT_DIR" 2>/dev/null || true
  rm -rf "$FIX_REPO_ROOT" 2>/dev/null || true
}

@test "fix_snapshot creates a snapshot copy" {
  source "$FIX_COMMON"
  fix_snapshot "$FIX_REPO_ROOT/test.txt"
  rel="${FIX_REPO_ROOT#/}"
  [ -f "$SNAPSHOT_DIR/$rel/test.txt" ]
}

@test "fix_snapshot preserves original content" {
  source "$FIX_COMMON"
  fix_snapshot "$FIX_REPO_ROOT/test.txt"
  rel="${FIX_REPO_ROOT#/}"
  result="$(cat "$SNAPSHOT_DIR/$rel/test.txt")"
  [ "$result" = "original content" ]
}

@test "fix_snapshot handles multiple files" {
  echo "file2 content" > "$FIX_REPO_ROOT/file2.txt"
  source "$FIX_COMMON"
  fix_snapshot "$FIX_REPO_ROOT/test.txt" "$FIX_REPO_ROOT/file2.txt"
  rel="${FIX_REPO_ROOT#/}"
  [ -f "$SNAPSHOT_DIR/$rel/test.txt" ]
  [ -f "$SNAPSHOT_DIR/$rel/file2.txt" ]
}

@test "fix_snapshot handles non-existent file gracefully" {
  source "$FIX_COMMON"
  run fix_snapshot "$FIX_REPO_ROOT/nonexistent.txt"
  [ "$status" -eq 0 ]
}

@test "fix_rollback restores file from snapshot" {
  source "$FIX_COMMON"
  fix_snapshot "$FIX_REPO_ROOT/test.txt"
  echo "modified content" > "$FIX_REPO_ROOT/test.txt"
  fix_rollback "$FIX_REPO_ROOT/test.txt"
  result="$(cat "$FIX_REPO_ROOT/test.txt")"
  [ "$result" = "original content" ]
}

@test "fix_rollback with no args restores all" {
  source "$FIX_COMMON"
  fix_snapshot "$FIX_REPO_ROOT/test.txt"
  echo "modified content" > "$FIX_REPO_ROOT/test.txt"
  fix_rollback
  result="$(cat "$FIX_REPO_ROOT/test.txt")"
  [ "$result" = "original content" ]
}

@test "fix_rollback restores deleted file" {
  source "$FIX_COMMON"
  fix_snapshot "$FIX_REPO_ROOT/test.txt"
  rm "$FIX_REPO_ROOT/test.txt"
  [ ! -f "$FIX_REPO_ROOT/test.txt" ]
  fix_rollback "$FIX_REPO_ROOT/test.txt"
  [ -f "$FIX_REPO_ROOT/test.txt" ]
  result="$(cat "$FIX_REPO_ROOT/test.txt")"
  [ "$result" = "original content" ]
}

@test "fix_rollback with no snapshot reports error but returns success" {
  run bash -c "source \"$FIX_COMMON\"; rm -rf \"$SNAPSHOT_DIR\"; fix_rollback \"$FIX_REPO_ROOT/test.txt\" 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no snapshot for"* ]]
}

@test "fix-rollback.sh --list runs" {
  run bash "${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/fix-rollback.sh" --list
  [ "$status" -eq 0 ]
}

@test "fix-rollback.sh --clean succeeds" {
  run bash "${BATS_TEST_DIRNAME}/../../skills/repo-health/scripts/fix-rollback.sh" --clean
  [ "$status" -eq 0 ]
}

@test "fix_verify passes on true" {
  source "$FIX_COMMON"
  run fix_verify "true" true
  [ "$status" -eq 0 ]
}

@test "fix_verify fails on false" {
  source "$FIX_COMMON"
  run fix_verify "false" false
  [ "$status" -ne 0 ]
}

@test "fix_verify_grep finds pattern" {
  source "$FIX_COMMON"
  run fix_verify_grep "find content" "original" "$FIX_REPO_ROOT/test.txt"
  [ "$status" -eq 0 ]
}

@test "fix_verify_grep fails on missing pattern" {
  source "$FIX_COMMON"
  run fix_verify_grep "find missing" "nonexistent_pattern_xyz" "$FIX_REPO_ROOT/test.txt"
  [ "$status" -ne 0 ]
}

@test "fix_apply applies sed expression" {
  source "$FIX_COMMON"
  run fix_apply "$FIX_REPO_ROOT/test.txt" "replace word" 's/original/modified/'
  [ "$status" -eq 0 ]
  result="$(cat "$FIX_REPO_ROOT/test.txt")"
  [ "$result" = "modified content" ]
}

@test "fix_apply enables rollback" {
  source "$FIX_COMMON"
  fix_apply "$FIX_REPO_ROOT/test.txt" "replace word" 's/original/modified/'
  fix_rollback "$FIX_REPO_ROOT/test.txt"
  result="$(cat "$FIX_REPO_ROOT/test.txt")"
  [ "$result" = "original content" ]
}

@test "fix_has_ungit returns 1 for clean repo" {
  git init "$FIX_REPO_ROOT" 2>/dev/null
  cd "$FIX_REPO_ROOT"
  echo "initial" > tracked.txt
  git add tracked.txt 2>/dev/null
  git -c user.name=test -c user.email=test@test commit -m "init" 2>/dev/null || true
  cd - >/dev/null
  source "$FIX_COMMON"
  FIX_REPO_ROOT="$FIX_REPO_ROOT"
  run fix_has_ungit
  [ "$status" -eq 1 ]
}

@test "fix_has_ungit returns 0 for dirty repo" {
  git init "$FIX_REPO_ROOT" 2>/dev/null
  cd "$FIX_REPO_ROOT"
  echo "initial" > tracked.txt
  git add tracked.txt 2>/dev/null
  git -c user.name=test -c user.email=test@test commit -m "init" 2>/dev/null || true
  echo "dirty" > tracked.txt
  cd - >/dev/null
  source "$FIX_COMMON"
  FIX_REPO_ROOT="$FIX_REPO_ROOT"
  run fix_has_ungit
  [ "$status" -eq 0 ]
}
