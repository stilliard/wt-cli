load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- _wt_ls ---

@test "wt ls lists worktrees" {
  run _wt_ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_REPO "* ]]
  [[ "$output" == *"feature"* ]]
  [[ "$output" == *"other"* ]]
}

@test "wt with no args lists worktrees" {
  run wt
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
}

@test "wt list alias works" {
  run wt list
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
}

@test "wt ls alias works" {
  run wt ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
}

@test "wt ls errors on unknown flag" {
  run wt ls --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}
