load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- _wt_cd ---

@test "wt <name> navigates to worktree" {
  _wt_cd feature
  [ "$PWD" = "$TEST_REPO-feature" ]
}

@test "wt cd <name> navigates to worktree" {
  wt cd other
  [ "$PWD" = "$TEST_REPO-other" ]
}

@test "wt <name> returns error for no match" {
  run _wt_cd nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worktree matching"* ]]
}
