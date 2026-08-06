load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- _wt_resolve ---

@test "_wt_resolve finds worktree by branch name" {
  result=$(_wt_resolve feature)
  [ "$result" = "$TEST_REPO-feature" ]
}

@test "_wt_resolve finds worktree by directory basename" {
  result=$(_wt_resolve "$(basename "$TEST_REPO-other")")
  [ "$result" = "$TEST_REPO-other" ]
}

@test "_wt_resolve returns empty string for no match" {
  result=$(_wt_resolve nonexistent)
  [ -z "$result" ]
}
